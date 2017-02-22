#!/bin/bash

FQN=`hostname -f`
echo $(date +%F_%T) "Renewing $FQN"

#Check if certificates need updating
/usr/local/sbin/certbot-auto renew --quiet

#Copy certificate to exim directory
cp /etc/letsencrypt/live/${FQN}/fullchain.pem /etc/exim
cp /etc/letsencrypt/live/${FQN}/privkey.pem /etc/exim

