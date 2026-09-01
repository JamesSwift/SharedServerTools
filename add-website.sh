#!/bin/bash
# Interactive: do not use set -e here — a failed grep or optional command
# would abort in the middle of a prompt.

. "$(dirname "$(realpath "$0")")/tools/sst-lib.sh"
sst_require_root
sst_init_vars

echo "==========================="
echo "Creating/Altering A Website"
echo "==========================="
echo
echo "Each website is owned by a Unix user. PHP and (if mail is enabled) ~/Maildir"
echo "run as that user so site owners cannot read each other's files by default."
echo
echo "Please enter the domain name of the website (excluding www):"
read -r domain

domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
if [[ -z "$domain" ]]; then
	sst_die "No domain entered."
fi

DOMAIN_IP=$(getent hosts "$domain" | awk '{ print $1 ; exit }')
DOMAIN_IP="${DOMAIN_IP%% }"

if [[ "$DOMAIN_IP" != "$PRIMARY_IP" && "$DOMAIN_IP" != "127.0.0.1" ]]; then
	echo
	echo "WARNING! $domain ($DOMAIN_IP) doesn't point to this server's IP address ($PRIMARY_IP)."
	echo "This server must be reachable at ${domain}:80 to be able to obtain an SSL certificate."
	echo "If this server is behind a proxy and you are sure it is reachable then continue. Otherwise alter your DNS settings then try again."
	echo
	read -p "Continue adding the website? [y/N]" -n 1 -r
	echo
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		echo "Canceled."
		exit 1
	fi
	echo "Continuing..."
fi

if [[ -f "${SST_NGINX_AVAILABLE}/${domain}" ]]; then
	echo
	username=$(grep --only-matching --perl-regex "(?<=\#__OWNER__\=).*" "${SST_NGINX_AVAILABLE}/${domain}" || true)
	DOC_ROOT=$(grep --only-matching --perl-regex "(?<=\#__DIR__\=).*" "${SST_NGINX_AVAILABLE}/${domain}" || true)
	if [[ -z "$username" ]]; then
		sst_die "Could not read owner from ${SST_NGINX_AVAILABLE}/${domain} (#__OWNER__= line missing)."
	fi
	if [[ -d "/home/${username}" ]]; then
		chmod 0750 "/home/${username}" || true
	fi

	echo "$domain is already configured on this system. It belongs to: $username"
	read -p "Do you wish to reset the nginx config for it to the default state? [N/y]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		read -p "Do you want to use www.${domain} as the primary domain? [Y/n]" -n 1 -r
		echo
		if [[ $REPLY =~ ^[Nn]$ ]]; then
			template="${SCRIPT_DIR}/templates/nginx-website.template"
		else
			echo "Setting up redirect to www."
			template="${SCRIPT_DIR}/templates/nginx-website-www.template"
		fi

		echo "Resetting config. By default SSL is DISABLED, so you may wish to re-enable it later when asked."
		echo
		rm -f "${SST_NGINX_AVAILABLE}/${domain}"
		cp "$template" "${SST_NGINX_AVAILABLE}/${domain}"
		sed -i "s/__USERNAME__/${username}/g" "${SST_NGINX_AVAILABLE}/${domain}"
		sed -i "s#__DOC_ROOT__#${DOC_ROOT}#g" "${SST_NGINX_AVAILABLE}/${domain}"
		sed -i "s/__DOMAIN__/${domain}/g" "${SST_NGINX_AVAILABLE}/${domain}"
		service "$(sst_php_fpm_service)" reload || sst_die "php-fpm reload failed."
	fi
	echo
else
	echo "Which user should own this new website (will be created if doesn't exist):"
	read -r username
	if [[ -z "$username" ]]; then
		sst_die "No username entered."
	fi
	sst_ensure_site_user "$username"

	DOC_ROOT="/home/${username}/www/${domain}/"

	echo
	read -p "Where should the document root be? (It will be created if it does not exist) [${DOC_ROOT}]:" TEMP_DOC_ROOT
	DOC_ROOT=${TEMP_DOC_ROOT:-${DOC_ROOT}}

	if [[ ! -d "$DOC_ROOT" ]]; then
		mkdir -p "$DOC_ROOT" || sst_die "Could not create ${DOC_ROOT}."
	fi
	echo "Document root will be: $DOC_ROOT"
	echo
	cd "$DOC_ROOT" || sst_die "Could not enter ${DOC_ROOT}."

	# nginx (www-data) needs group read on this user's files.
	usermod -aG "${username}" www-data

	read -p "Do you want to set up a git repo in the document root which auto-checks out any commits you push to it? [Y/n]" -n 1 -r
	echo
	if ! [[ $REPLY =~ ^[Nn]$ ]]; then
		echo "Setting up git repo in www directory"
		git init
		git config --local receive.denyCurrentBranch ignore
		echo
		echo "Adding git hook to auto checkout pushed commits:"
		cp "${SCRIPT_DIR}/templates/git-hook.template" .git/hooks/post-receive
		sed -i "s/__USERNAME__/${username}/g" .git/hooks/post-receive
		sed -i "s#__DOC_ROOT__#${DOC_ROOT}#g" .git/hooks/post-receive
		chmod +x .git/hooks/post-receive
	fi

	read -p "Do you want to use www.${domain} as the primary domain? [Y/n]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Nn]$ ]]; then
		template="${SCRIPT_DIR}/templates/nginx-website.template"
	else
		echo "Setting up redirect to www."
		template="${SCRIPT_DIR}/templates/nginx-website-www.template"
	fi

	cp "$template" "${SST_NGINX_AVAILABLE}/${domain}"
	sed -i "s/__USERNAME__/${username}/g" "${SST_NGINX_AVAILABLE}/${domain}"
	sed -i "s#__DOC_ROOT__#${DOC_ROOT}#g" "${SST_NGINX_AVAILABLE}/${domain}"
	sed -i "s/__DOMAIN__/${domain}/g" "${SST_NGINX_AVAILABLE}/${domain}"

	mkdir -p "/home/${username}/www"
	chown -R "${username}:${username}" "/home/${username}/www"

	ln -s "${SST_NGINX_AVAILABLE}/${domain}" "${SST_NGINX_ENABLED}/${domain}"

	echo "Creating php-fpm pool config file in $(sst_php_fpm_pool_dir)/${username}.conf"
	cp "${SCRIPT_DIR}/templates/fpm-pool.template" "$(sst_php_fpm_pool_dir)/${username}.conf"
	sed -i "s/__USERNAME__/${username}/g" "$(sst_php_fpm_pool_dir)/${username}.conf"

	echo "Reloading php-fpm configuration:"
	service "$(sst_php_fpm_service)" reload || sst_die "php-fpm reload failed."
	echo "Reloading nginx configuration:"
	service nginx reload || sst_die "nginx reload failed. Check: nginx -t"
fi

read -p "Do you wish to enable SSL for this domain? [Y/n]" -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
	echo "Turning off SSL:"
	sed -i '/#__COMMENT_LINE__/s/^/#__COMMENT__/g' "${SST_NGINX_AVAILABLE}/${domain}"
	service nginx reload || sst_die "nginx reload failed."
else
	echo "Turning off SSL while obtaining certificate:"
	sed -i '/#__COMMENT_LINE__/s/^/#__COMMENT__/g' "${SST_NGINX_AVAILABLE}/${domain}"
	service nginx reload || sst_die "nginx reload failed."

	echo "Obtaining ssl certificate:"
	read -p "Do you want to obtain an ssl certificate for www.${domain} as well as ${domain}? [Y/n]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Nn]$ ]]; then
		certbot certonly --webroot --webroot-path "${DOC_ROOT}" -d "${domain}" || sst_die "certbot failed for ${domain}."
	else
		echo "Acquiring cert for www subdomain."
		certbot certonly --webroot --webroot-path "${DOC_ROOT}" -d "${domain}" -d "www.${domain}" || sst_die "certbot failed for ${domain}."
	fi

	echo "Installing certificate:"
	sed -i "s/__SSL_DOMAIN__/${domain}/g" "${SST_NGINX_AVAILABLE}/${domain}"
	sed -i "s/#__COMMENT__//g" "${SST_NGINX_AVAILABLE}/${domain}"

	echo "Reloading nginx:"
	service nginx reload || sst_die "nginx reload failed after installing the certificate."
fi

if sst_mail_enabled; then
	echo
	sst_ensure_dkim "$domain"
	sst_ensure_virtual_domain "$domain" "$username"

	echo
	echo "Mail for this domain is delivered to Unix user '${username}' (~ /home/${username}/Maildir)."
	echo "IMAP/POP3 login is that username and password — not a shared mailbox account."
	echo
	echo "To add more addresses, edit: ${SST_EXIM_VIRTUAL}/${domain}"
	echo "Example:"
	echo "  info : ${username}@localhost"
	echo
else
	echo
	echo "Mail is not enabled on this server. Run ${SCRIPT_DIR}/setup-mail.sh to turn Exim/Dovecot on, then ${SCRIPT_DIR}/add-email-domain.sh for this domain."
	echo
fi

echo "The website has been configured. You can run this script again to reconfigure it or see these details again, if you wish."
