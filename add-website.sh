#!/bin/bash

#First, check we are root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." 2>&1
  exit 1
fi

#vars
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname $SCRIPT_PATH`
PRIMARY_IP=`hostname -I`
PRIMARY_IP="${PRIMARY_IP%% }"


echo "==========================="
echo "Creating/Altering A Website"
echo "==========================="

echo ""
echo "Please enter the domain name of the website (excluding www):"
read domain

domain=`echo "$domain" | tr '[:upper:]' '[:lower:]'`

DOMAIN_IP=`getent hosts $domain | awk '{ print $1 ; exit }'`
DOMAIN_IP="${DOMAIN_IP%% }"

if [ "$DOMAIN_IP" != "$PRIMARY_IP" ] && [ "$DOMAIN_IP" != "127.0.0.1" ]
then
	echo
	echo "WARNING! $domain ($DOMAIN_IP) doesn't point to this server's IP address ($PRIMARY_IP)."
	echo "This server must be reachable at ${domain}:80 to be able to obtain an SSL certificate."
	echo "If this server is behind a proxy and you are sure it is reachable then continue. Otherwise alter your DNS settings then try again."
	echo
	read -p "Continue adding the website? [y/N]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		#Never mind
		echo
		echo "Continuing..."
		echo
	else
		echo "Canceled."
		exit
	fi
fi


#Check if already added
if [ -f "/etc/nginx/sites-available/${domain}" ]
then
	echo

	#Find vars
	username=`grep --only-matching --perl-regex "(?<=\#__OWNER__\=).*" /etc/nginx/sites-available/${domain}`
	DOC_ROOT=`grep --only-matching --perl-regex "(?<=\#__DIR__\=).*" /etc/nginx/sites-available/${domain}`


	echo "$domain is already configured on this system. It belongs to: $username"
	read -p "Do you wish to reset the nginx config for it to the default state? [N/y]" -n 1 -r

	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
	then

		read -p "Do you want to use www.${domain} as the primary domain? [Y/n]" -n 1 -r
		echo
		if [[ $REPLY =~ ^[Nn]$ ]]
		then
			template=${SCRIPT_DIR}/templates/nginx-website.template
		else
			echo "Setting up redirect to www."
			template=${SCRIPT_DIR}/templates/nginx-website-www.template
		fi

		echo "Resetting config. By default SSL is DISABLED, so you may wish to re-enable it later when asked."
		echo
		rm /etc/nginx/sites-available/${domain}
		cp ${template} /etc/nginx/sites-available/${domain}
		sed -i "s/__USERNAME__/${username}/g" /etc/nginx/sites-available/${domain}
		sed -i "s#__DOC_ROOT__#${DOC_ROOT}#g" /etc/nginx/sites-available/${domain}
		sed -i "s/__DOMAIN__/${domain}/g" /etc/nginx/sites-available/${domain}
		service php8.1-fpm reload
	fi
	echo
else

	echo "Which user should own this new website (will be created if doesn't exist):"
	read username

	if [[ ! $(getent passwd $username) ]] ; then
		echo
		echo "Creating new user: $username"
		adduser ${username}
	fi

	DOC_ROOT="/home/${username}/www/${domain}/"


	echo
	read -p "Where should the document root be? (It will be created if it does not exist) [${DOC_ROOT}]:" TEMP_DOC_ROOT
	DOC_ROOT=${TEMP_DOC_ROOT:-${DOC_ROOT}}

	if [ ! -d "$DOC_ROOT" ]; then
		mkdir -p "$DOC_ROOT"
	fi
	echo Document root will be: $DOC_ROOT
	echo
	cd "$DOC_ROOT"

	#echo
	#echo "Adding www-data to group $username (to allow nginx to read the static files)"
	usermod -aG ${username} www-data

	read -p "Do you want to set up a git repo in the document root which auto-checks out any commits you push to it? [Y/n]" -n 1 -r
	echo
	if ! [[ $REPLY =~ ^[Nn]$ ]]
	then
		echo "Setting up  git repo in www directory"
		git init
		git config --local receive.denyCurrentBranch ignore
		echo


		echo "Adding git hook to auto checkout pushed commits:"
		cp ${SCRIPT_DIR}/templates/git-hook.template .git/hooks/post-receive
		sed -i "s/__USERNAME__/${username}/g" .git/hooks/post-receive
		sed -i "s#__DOC_ROOT__#${DOC_ROOT}#g" .git/hooks/post-receive
		chmod +x .git/hooks/post-receive
	fi

	read -p "Do you want to use www.${domain} as the primary domain? [Y/n]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Nn]$ ]]
	then
		template=${SCRIPT_DIR}/templates/nginx-website.template
	else
		echo "Setting up redirect to www."
		template=${SCRIPT_DIR}/templates/nginx-website-www.template
	fi

	#echo "Creating nginx website config file in /etc/nginx/sites-available/${domain}"
	cp ${template} /etc/nginx/sites-available/${domain}
	sed -i "s/__USERNAME__/${username}/g" /etc/nginx/sites-available/${domain}
	sed -i "s#__DOC_ROOT__#${DOC_ROOT}#g" /etc/nginx/sites-available/${domain}
	sed -i "s/__DOMAIN__/${domain}/g" /etc/nginx/sites-available/${domain}

	#Make dir for storing logs
	if [ ! -d "/home/${username}/www" ]; then
		mkdir -p /home/${username}/www
	fi
	chown -R ${username}.${username} /home/${username}/www


	#echo "Linking nginx website config to /etc/nginx/sites-enabled/${domain}"
	ln -s /etc/nginx/sites-available/${domain} /etc/nginx/sites-enabled/${domain}


	echo "Creating php-fpm pool config file in /etc/php/8.1/pfm/pool.d/${username}.conf"
	cp ${SCRIPT_DIR}/templates/fpm-pool.template /etc/php/8.1/fpm/pool.d/${username}.conf
	sed -i "s/__USERNAME__/${username}/g" /etc/php/8.1/fpm/pool.d/${username}.conf


	echo "Reloading php-fpm configuration:"
	service php8.1-fpm reload
	echo "Reloading nginx configuration:"
	service nginx reload

fi


read -p "Do you wish to enable SSL for this domain? [Y/n]" -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]
then
	echo "Turning off SSL:"
	sed -i '/#__COMMENT_LINE__/s/^/#__COMMENT__/g' "/etc/nginx/sites-available/${domain}"
	service nginx reload
else
	echo "Turning off SSL while obtaining certificate:"
	sed -i '/#__COMMENT_LINE__/s/^/#__COMMENT__/g' "/etc/nginx/sites-available/${domain}"
	service nginx reload

	echo "Obtaining ssl certificate:"
	read -p "Do you want to obtain an ssl certificate for www.${domain} as well as ${domain}? [Y/n]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Nn]$ ]]
	then
		certbot certonly --webroot --webroot-path "${DOC_ROOT}" -d "${domain}"
	else
		echo "Aquiring cert for www subdomain."
		certbot certonly --webroot --webroot-path "${DOC_ROOT}" -d "${domain}" -d "www.${domain}"
	fi


	echo "Installing certificate:"
	sed -i "s/__SSL_DOMAIN__/${domain}/g" "/etc/nginx/sites-available/${domain}"
	sed -i "s/#__COMMENT__//g" "/etc/nginx/sites-available/${domain}"

	echo "Reloading nginx:"
	service nginx reload
fi


echo "The website has been configured. You can run this script again to reconfigure it or see these details again, if you wish."
