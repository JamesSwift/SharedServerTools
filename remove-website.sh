#!/bin/bash

#First, check we are root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." 2>&1
  exit 1
fi

echo "Enter the domain of the website you wish to delete (excluding www):"
read domain

#Check if already added
if [ ! -f "/etc/nginx/sites-available/${domain}" ]
then
	echo "Domain $domain doesn't exist on this system."
	exit
fi

#Find the owner before deleting
username=`grep --only-matching --perl-regex "(?<=\#__OWNER__\=).*" /etc/nginx/sites-available/${domain}`
DOC_ROOT=`grep --only-matching --perl-regex "(?<=\#__DIR__\=).*" /etc/nginx/sites-available/${domain}`

if [[ ! $(getent passwd $username) ]] || [ ! -d /home/$username ] || [ "$username" == "" ] ; then
	echo "An error occured and the owner of the domain could not be found."
	exit
fi

rm /etc/nginx/sites-enabled/$domain
rm /etc/nginx/sites-available/$domain
rm -rf /etc/letsencrypt/live/$domain/
rm -rf /etc/letsencrypt/renewal/${domain}.conf
rm -rf /etc/letsencrypt/archive/${domain}.conf
rm -f /home/$username/www/${domain}.*

read -p "Do you wish to delete the document root folder? (${DOC_ROOT}) [N/y]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
	rm -rf "${DOC_ROOT}"
fi

service nginx restart

echo "Domain deleted."
echo


read -p "Do you wish to delete user '$username' who owns this domain? (WARNING: they may have other active domains!) [N/y]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then


	rm /etc/php/7.4/fpm/pool.d/${username}.conf
	service php7.4-fpm restart
	deluser www-data $username
	deluser $username
	rm -rf /home/$username
fi