#!/bin/bash
# Interactive: do not use set -e here. A failed optional command would abort
# mid-prompt. Fail loudly on the steps that must succeed (apt, nginx, certbot).

. "$(dirname "$(realpath "$0")")/tools/sst-lib.sh"
sst_require_root
sst_init_vars

#clear


#############################################################################
# Begin user interaction

echo "================="
echo "SharedServerTools"
echo "================="
echo
echo "This script is designed to turn a clean Ubuntu 26.04 LTS installation into a working, secured, multi-domain web server, with optional Exim/Dovecot mail."
echo "Ideally this script should be run as the very first thing you do with your new install. It will alter config files with no regard for their current state."
echo
echo "The process is quite simple, but you will need to answer some questions first:"
echo
echo


#############################################
# Check for updates

echo "================"
echo "Security Updates"
echo "================"
echo
echo "Before we start, it is advisable to check for and install any pending updates."
read -p "Would you like to do this now? [y/N]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo
	echo
	apt update || sst_die "apt update failed."
	apt upgrade -y || sst_die "apt upgrade failed."

	echo
	echo
	echo "It is best to restart you server after significant updates."
	read -p "Would you like to do this now? [y/N]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		#clear
		echo "After rebooting, run this script again to continue setup."
		echo
		reboot
	fi
fi

############################################
# Secure root account

#clear

echo "================"
echo "Account Security"
echo "================"
echo
echo "If your installation of ubuntu came with a default root password, it should be changed."
read -p "Would you like to do this now? [y/N]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo
	echo
	passwd root
	echo
	echo
fi

echo "It is bad practice to log into the root account to do work. It is better to create a personal account with sudo access."
read -p "Would you like to do this now? [y/N]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo
	echo
	read -p "Desired username:" new_username
	if [[ -z "${new_username}" ]]; then
		echo "No username entered; skipping personal account."
	else
		adduser "$new_username" || sst_die "adduser ${new_username} failed."
		echo
		sst_add_admin_groups "$new_username"
	fi
	echo
	echo
fi


echo "It is also bad practice to allow root ssh access (as this is the most common point of attack)."
read -p "Would you disable root ssh login capabilities now? [y/N]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
	replace_config_param /etc/ssh/sshd_config PermitRootLogin no
	#Leave sshd restart until next reboot
fi



echo "Some VPS providers install ssh public certificates in /root/.ssh/authorized_keys"
echo "Generally this is to allow them to provide support, but it might be considered a security risk."
read -p "Would you like to reset the authorized_keys file now?? [y/N]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
	mv /root/.ssh/authorized_keys /root/.ssh/authorized_keys.backup
	touch /root/.ssh/authorized_keys
fi




#################################################
# Setup hostname

#clear

echo "==============="
echo "Server Hostname"
echo "==============="

echo "It is important that the server (and this script) know the fully qualified domain name that refers to this server."
echo "Here are the current settings:"
echo
echo "Current primary IP: ${PRIMARY_IP} (first address from hostname -I; correct it if that is not the public address)"
echo "Current full hostname: ${HOSTNAME_FULL}"
echo "Current short hostname: ${HOSTNAME_SHORT}"
echo
echo "This script needs to know the domain that points to this server so it can obtain SSL certificates."
echo
read -p "Would you like to change these settings now? [y/N]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then

	read -p "Please enter the primary IP [${PRIMARY_IP}]:" TEMP_PIP
	read -p "Please enter the new full host name [$HOSTNAME_FULL]:" TEMP_HN_FULL
	read -p "Please enter the new short host name [$HOSTNAME_SHORT]:" TEMP_HN_SHORT
	echo

	TEMP_PIP=${TEMP_PIP:-${PRIMARY_IP}}
	TEMP_HN_FULL=${TEMP_HN_FULL:-${HOSTNAME_FULL}}
	TEMP_HN_SHORT=${TEMP_HN_SHORT:-${HOSTNAME_SHORT}}

	echo "The settings you entered were:"
	echo "Primary IP: ${TEMP_PIP}"
	echo "Full hostname: ${TEMP_HN_FULL}"
	echo "Short hostname: ${TEMP_HN_SHORT}"
	echo
	read -p "Would you like to save these settings? [y/N]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		PRIMARY_IP=$TEMP_PIP

		# Sort out short hostname
		hostname "$TEMP_HN_SHORT" || sst_die "Could not set hostname to ${TEMP_HN_SHORT}."
		HOSTNAME_SHORT=$TEMP_HN_SHORT
		echo "$TEMP_HN_SHORT" > /etc/hostname

		# Save full hostname in host file
		HOSTNAME_FULL=$TEMP_HN_FULL
		apply_template /etc/hosts hosts
	else
		echo "Changes abandoned"
	fi
fi

apply_template /etc/mailname mailname


############################################################################
# Install software

#clear
echo "======================"
echo "Install Server Software"
echo "======================"
echo
echo "The script will now install the software needed for the server's operation from apt. Namely:"
echo "- git"
echo "- nginx"
echo "- php-fpm"
echo "- mariadb-server"
echo "- fail2ban"
echo "- certbot"
echo
echo "Mail (Exim, Dovecot, SpamAssassin) is optional and offered after SSL is in place."
echo
read -p "Press enter to continue"
echo 

apt install -y git nginx php-fpm php-mysql mariadb-server fail2ban certbot \
	|| sst_die "apt install of web stack packages failed."

# Re-detect after packages are installed (metapackage php-fpm follows the distro default).
PHP_VERSION=$(sst_detect_php_version)
PHP_FPM_SOCK=$(sst_php_default_sock)

######################################################################################################
# Configure software

#clear
echo "========================="
echo "Configure Server Software"
echo "========================="
echo
echo "Enabling relevant jails in fail2ban:"
apply_template /etc/fail2ban/jail.local jail.local
service fail2ban restart || sst_die "fail2ban restart failed."
echo "Done"
echo
echo
echo "Setting up php:"
apply_template "$(sst_php_fpm_conf_d)/99-sharedservertools.ini" php.ini
service "$(sst_php_fpm_service)" restart || sst_die "php-fpm restart failed."
echo "Done"
echo
echo
echo "Setting up nginx:"
chmod 770 -R /var/www
chown -R root.www-data /var/www

#Generate new dhparam
if [ -f "/etc/ssl/certs/dhparam.pem" ]
then
	echo "It seems you already have a dhparam.pem file (which strengthens SSL security)."
	read -p "Would you like to generate a new one anyway (warning: it will take a long time!)? [y/N]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
		then
		openssl dhparam -out /etc/ssl/certs/dhparam.pem 4096
	fi
else
	#File not found, generate a new one
	echo "You need to generate a strong DHE parameter to secure SSL requests. This will take quite a while."
	openssl dhparam -out /etc/ssl/certs/dhparam.pem 4096
fi

apply_template /etc/nginx/snippets/ssl-params.conf ssl-params.conf
apply_template /etc/nginx/nginx.conf nginx.conf

if grep -q "#__SharedServerTools__" "${SST_NGINX_AVAILABLE}/default"
then
	read -p "The nginx config file for the default domain already exists, do you want to overwrite it? [y/N]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		apply_template "${SST_NGINX_AVAILABLE}/default" default
	fi
else
	apply_template "${SST_NGINX_AVAILABLE}/default" default
fi


service nginx restart || sst_die "nginx restart failed. Check: nginx -t"
echo "Done"
echo


########################################################################
# SSL Certificate

if [ -f "/etc/letsencrypt/live/${HOSTNAME_FULL}/fullchain.pem" ]
then
	read -p "Would you like to obtain a fresh SSL certificate?[y/N]" -n 1 -r
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		echo
		#Do this in the next block below
	else
		#If a valid cert exists, make sure it is being used
		if [ -f "/etc/letsencrypt/live/${HOSTNAME_FULL}/fullchain.pem" ]
		then
			sed -i "s/#__COMMENT__//g" "${SST_NGINX_AVAILABLE}/default"
		fi
	fi
fi

if [ ! -f "/etc/letsencrypt/live/${HOSTNAME_FULL}/fullchain.pem" ] || [[ $REPLY =~ ^[Yy]$ ]]
then
	#clear
	echo "=============="
	echo "SSL Certifcate"
	echo "=============="
	echo
	sed -i 's/#__COMMENT_LINE__/#__COMMENT__&/g' "${SST_NGINX_AVAILABLE}/default"
	service nginx reload || sst_die "nginx reload failed before certbot."
	echo
	certbot certonly --agree-tos --webroot --webroot-path /var/www/html -d "${HOSTNAME_FULL}" \
		|| sst_die "certbot failed for ${HOSTNAME_FULL}."
	echo
	echo "Installing certificate:"
	sed -i "s/#__COMMENT__//g" "${SST_NGINX_AVAILABLE}/default"
	service nginx restart || sst_die "nginx restart failed after installing the certificate."
	echo "Done"
fi


########################################################################
# Optional mail stack (after the hostname certificate exists)

echo
echo "===="
echo "Mail"
echo "===="
echo
echo "Exim4, Dovecot, and SpamAssassin can be installed next."
echo "You can also run ./setup-mail.sh later if you skip this now."
echo
read -p "Would you like to set up email on this server now? [Y/n]" -n 1 -r
echo
if ! [[ $REPLY =~ ^[Nn]$ ]]
then
	"${SCRIPT_DIR}/setup-mail.sh"
else
	echo "Skipping mail. Run ${SCRIPT_DIR}/setup-mail.sh when you are ready."
fi


echo
echo "====================="
echo "Installation complete"
echo "====================="
echo
echo "The script has finished setting up your new server."
echo
echo "Next steps:"
echo
echo "Single-Site Server"
echo "  If this server will host only one domain, you can store your files in /var/www/html"
echo
echo "Multi-Site Server"
echo "  If you plan to host multiple websites, from multiple users, run the add-website.sh file for each domain."
echo
echo
echo "You can re-run this setup file at any time to alter your configuration."
echo
echo "If you enabled mail, add more domains with add-email-domain.sh (or add-website.sh)."
echo
echo "If your server came with the default 'ubuntu' user, don't forget you may wish to remove it or change it's password."
