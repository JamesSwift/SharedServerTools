#!/bin/bash

#First, check we are root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." 2>&1
  exit 1
fi

########################################################################
# Helper functions

replace_config_param(){
	#args: file, key, new_value, (old_value to match against)

	if [ -z "$1" ]
	then
		echo "-Parameter #1 is zero length.-"
		return 1
	fi
		if [ -z "$2" ]
	then
				echo "-Parameter #2 is zero length.-"
				return 1
		fi

	CONFIG_FILE=$1
	TARGET_KEY=$2
	REPLACEMENT_VALUE=$3
	SEARCH_KEY=${4:-".*"}

	if grep -q "^[ ^I]*$TARGET_KEY[ ^I]*" "$CONFIG_FILE"; then
		sed -re 's/^('"$TARGET_KEY"')([[:space:]]+)'"$SEARCH_KEY"'/\1\2'"$REPLACEMENT_VALUE"'/' -i $CONFIG_FILE
	else
	   echo "$TARGET_KEY $REPLACEMENT_VALUE" >> "$CONFIG_FILE"
	fi
	return 0
}

#args: destination_file, config-templates file,
apply_template(){
	rm $1".backup" 2> /dev/null
	cp ${SCRIPT_DIR}/config-templates/$2 $1"~"

	#Apply sed filters for all known variables
	sed -i "s/__HOSTNAME_FULL__/${HOSTNAME_FULL}/g" $1"~"
	sed -i "s/__HOSTNAME_SHORT__/${HOSTNAME_SHORT}/g" $1"~"
	sed -i "s/__PRIMARY_IP__/${PRIMARY_IP}/g" $1"~"

	mv $1 $1".backup" 2> /dev/null
	mv $1"~" $1
	return 0;
}


#############################################################################
# Variables used throughout

SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname $SCRIPT_PATH`
HOSTNAME_SHORT=`hostname`
HOSTNAME_FULL=`hostname -f`
PRIMARY_IP=`hostname -I`

#clear


#############################################################################
# Begin user interaction

echo "================="
echo "SharedServerTools"
echo "================="
echo
echo "This script is designed to turn a clean ubuntu 22.04 installation into a working, secured, web, file, & mail server (with spam checking)."
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
	apt update
	apt upgrade -y

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
	adduser $new_username
	echo
	usermod -aG adm,dialout,cdrom,floppy,sudo,audio,dip,video,plugdev,netdev,lxd $new_username
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
echo "Current primary IP: "$PRIMARY_IP" (This should be a single ip address, if more listed please correct)"
echo "Current full hostname: "$HOSTNAME_FULL
echo "Current short hostname: "$HOSTNAME_SHORT
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
	echo "Primary IP: "$TEMP_PIP
	echo "Full hostname: "$TEMP_HN_FULL
	echo "Short hostname: "$TEMP_HN_SHORT
	echo
	read -p "Would you like to save these settings? [y/N]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		PRIMARY_IP=$TEMP_PIP

		#Sort out short hostname
		hostname $TEMP_HN_SHORT
		HOSTNAME_SHORT=$TEMP_HN_SHORT
		echo $TEMP_HN_SHORT > /etc/hostname

		#Save full hostname in host file
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
read -p "Press enter to continue"
echo 

apt install -y git nginx php8.1-fpm php8.1-mysql mariadb-server fail2ban certbot

######################################################################################################
# Configure software

#clear
echo "========================="
echo "Configure Server Software"
echo "========================="
echo
echo "Enabling relevant jails in fail2ban:"
apply_template /etc/fail2ban/jail.local jail.local
service fail2ban restart
echo "Done"
echo
echo
echo "Setting up php:"
apply_template /etc/php/8.1/fpm/conf.d/php.ini php.ini
service php8.1-fpm restart
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

if grep -q "#__SharedServerTools__" "/etc/nginx/sites-available/default"
then
	read -p "The nginx config file for the default domain already exists, do you want to overwrite it? [y/N]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		apply_template /etc/nginx/sites-available/default default
	fi
else
	apply_template /etc/nginx/sites-available/default default
fi


service nginx restart
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
			sed -i "s/#__COMMENT__//g" /etc/nginx/sites-available/default
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
	sed -i 's/#__COMMENT_LINE__/#__COMMENT__&/g' /etc/nginx/sites-available/default
	service nginx reload
	echo
	certbot certonly --agree-tos --webroot --webroot-path /var/www/html -d ${HOSTNAME_FULL}
	echo
	echo "Installing certificate:"
	sed -i "s/#__COMMENT__//g" /etc/nginx/sites-available/default
	service nginx restart
	echo "Done"
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
echo "If your server came with the default 'ubuntu' user, don't forget you may wish to remove it or change it's password."
