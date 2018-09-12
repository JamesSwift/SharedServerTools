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

echo "======================"
echo "Creating A New Website"
echo "======================"

echo ""
echo "Please enter the (sub-)domain name of the new website (excluding www):"
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
	username=`grep --only-matching --perl-regex "(?<=\#__OWNER__\=).*" /etc/nginx/sites-available/${domain}`
	echo "$domain is already configured on this system. It belongs to: $username"
	read -p "Do you wish to reset the nginx config for it? [N/y]" -n 1 -r 

	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
		echo "Resetting config. By default SSL is DISABLED, you may wish to re-enable it."
		echo
		rm /etc/nginx/sites-available/${domain}
		cp ${SCRIPT_DIR}/templates/nginx-website.template /etc/nginx/sites-available/${domain}
		sed -i "s/__USERNAME__/${username}/g" /etc/nginx/sites-available/${domain}
		sed -i "s/__DOMAIN__/${domain}/g" /etc/nginx/sites-available/${domain}
		service php7.2-fpm reload
	fi
	echo
else 

	echo "Which user should own this new website (will be created if doesn't exist):"
	read username

	if [ ! $(getent passwd $username) ] ; then
		echo
		echo "Creating new user: $username"
		adduser ${username}
		echo
	fi
	
	
	mkdir /home/${username}/www 2> /dev/null
	mkdir /home/${username}/www/$domain
	cd /home/${username}/www/$domain
	
	#echo 
	#echo "Adding www-data to group $username (to allow nginx to read the static files)"
	usermod -aG ${username} www-data	


	#echo "Setting up blank git repo in www directory:"
	git init
	git config --local receive.denyCurrentBranch ignore


	echo "Adding git hook to auto checkout pushed commits:"
	cp ${SCRIPT_DIR}/templates/git-hook.template .git/hooks/post-receive
	sed -i "s/__USERNAME__/${username}/g" .git/hooks/post-receive
	chmod +x .git/hooks/post-receive
	

	#echo "Creating nginx website config file in /etc/nginx/sites-available/${domain}"
	cp ${SCRIPT_DIR}/templates/nginx-website.template /etc/nginx/sites-available/${domain}
	sed -i "s/__USERNAME__/${username}/g" /etc/nginx/sites-available/${domain}
	sed -i "s/__DOMAIN__/${domain}/g" /etc/nginx/sites-available/${domain}

	chown -R ${username}.${username} /home/${username}/www


	#echo "Linking nginx website config to /etc/nginx/sites-enabled/${domain}"
	ln -s /etc/nginx/sites-available/${domain} /etc/nginx/sites-enabled/${domain}


	echo "Creating php-fpm pool config file in /etc/php/7.2/pfm/pool.d/${username}.conf"
	cp ${SCRIPT_DIR}/templates/fpm-pool.template /etc/php/7.2/fpm/pool.d/${username}.conf
	sed -i "s/__USERNAME__/${username}/g" /etc/php/7.2/fpm/pool.d/${username}.conf


	echo "Reloading php-fpm configuration:"
	service php7.2-fpm reload
	echo "Reloading nginx configuration:"
	service nginx reload

fi


read -p "Do you wish to enable SSL for this domain? [Y/n]" -n 1 -r 
echo
if [[ $REPLY =~ ^[Nn]$ ]]
then
	echo "Turning off SSL:"
	sed -i 's/#__COMMENT_LINE__/#__COMMENT__&/g' "/etc/nginx/sites-available/${domain}"
	service nginx reload	
else
	echo "Turning off SSL while obtaining certificate:"
	sed -i 's/#__COMMENT_LINE__/#__COMMENT__&/g' "/etc/nginx/sites-available/${domain}"
	service nginx reload
	
	echo "Obtaining ssl certificate:"
	certbot-auto certonly --webroot --webroot-path "/home/${username}/www/${domain}/" -d "${domain}" -d "www.${domain}"

	echo "Installing certificate:"
	sed -i "s/__SSL_DOMAIN__/${domain}/g" "/etc/nginx/sites-available/${domain}"
	sed -i "s/#__COMMENT__//g" "/etc/nginx/sites-available/${domain}"

	echo "Reloading nginx:"
	service nginx reload
fi

echo
if [ -f "/etc/exim4/dkim/${domain}/dkim.public" ]
then
	echo "DKIM keys were previously generated for this domain."
	echo
	echo "If you experience issues sending mail, please ensure the following entires are in your DNS record for" ${domain}
else
	echo "Generating a DKIM key for sending emails for this domain from this server."
	echo
	mkdir /etc/exim4/dkim/${domain}/
	openssl genrsa -out /etc/exim4/dkim/${domain}/dkim.private 2048 > /dev/null 2>&1
	openssl rsa -in /etc/exim4/dkim/${domain}/dkim.private -out /etc/exim4/dkim/${domain}/dkim.public -pubout -outform PEM
	echo
	echo "DKIM is a way of proving which servers have permission to send email for a domain."
	echo "Email clients check for a DKIM DNS record when determining if a message is spam."
	echo 
	echo "Please add the following entires to your DNS record for" ${domain}
fi

echo
echo "Type:     TXT"
echo "Name:     "$(hostname)"._domainkey"
echo "Value:    v=DKIM1; p="$(cat /etc/exim4/dkim/${domain}/dkim.public | sed '1,1d' | sed '$d' | tr -d '\n')
echo
echo "Type:     TXT"
echo "Name:     "${domain}
echo "Value:    v=spf1 a mx -all"
echo




echo "The website has been configured. You can run this script again to reconfigure it or see these details again, if you wish."
