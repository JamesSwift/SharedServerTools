#!/bin/bash

echo "Enter the username of the website you wish to delete:"
read username
echo "Enter the domain of the website you wish to delete:"
read domain

rm /etc/nginx/sites-enabled/$domain
rm /etc/nginx/sites-available/$domain
rm /etc/php/7.*/fpm/pool.d/${username}.conf
service php7.2-fpm restart
service nginx restart
deluser www-data $username
deluser $username
rm -rf /home/$username

