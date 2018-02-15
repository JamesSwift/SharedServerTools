#!/bin/bash

#vars
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname $SCRIPT_PATH`

echo "Creating a new website."
echo "Before starting, ensure that the domain you are about to setup points to the current server."
read -rsp $"Press any key to continue..." -n 1 key
echo ""
echo "Please enter the domain name for this new website:"
read domain

echo "Please enter the a username to use for the new website:"
read username

adduser ${username}
mkdir /home/${username}/www
cd /home/${username}/www

echo ""

echo "Adding www-data to group $username (to allow nginx to read the static files)"
usermod -aG ${username} www-data

echo "Setting up blank git repo in www directory:"
git init
git config --local receive.denyCurrentBranch ignore


echo "Adding hook to auto checkout pushed commits:"
cp ${SCRIPT_DIR}/templates/git-hook.template .git/hooks/post-receive
sed -i "s/__USERNAME__/${username}/g" .git/hooks/post-receive
chmod +x .git/hooks/post-receive
chown -R ${username}.${username} ./

echo "Creating nginx website config file in /etc/nginx/sites-available/${domain}"
cp ${SCRIPT_DIR}/templates/nginx-website.template /etc/nginx/sites-available/${domain}
sed -i "s/__USERNAME__/${username}/g" /etc/nginx/sites-available/${domain}
sed -i "s/__DOMAIN__/${domain}/g" /etc/nginx/sites-available/${domain}


echo "Linking nginx website config to /etc/nginx/sites-enabled/${domain}"
ln -s /etc/nginx/sites-available/${domain} /etc/nginx/sites-enabled/${domain}


echo "Creating php-fpm pool config file in /etc/php/7.0/pfm/pool.d/${username}.conf"
cp ${SCRIPT_DIR}/templates/fpm-pool.template /etc/php/7.0/fpm/pool.d/${username}.conf
sed -i "s/__USERNAME__/${username}/g" /etc/php/7.0/fpm/pool.d/${username}.conf


echo "Reloading php-fpm configuration:"
service php7.0-fpm reload
echo "Reloading nginx configuration:"
service nginx reload


echo "Obtaining ssl certificate:"
#certbot-auto --nginx --no-redirect -d ${domain} -d www.${domain}
certbot-auto certonly --webroot --webroot-path /home/${username}/www -d ${domain} -d www.${domain}

echo "Installing certificate:"
sed -i "s/__SSL_DOMAIN__/${domain}/g" /etc/nginx/sites-available/${domain}
sed -i "s/#__COMMENT__//g" /etc/nginx/sites-available/${domain}


echo "Reloading nginx:"
service nginx reload


echo "New website has been added."
