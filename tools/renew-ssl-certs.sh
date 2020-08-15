#!/bin/bash

FQN=`hostname -f`
echo $(date +%F_%T) "Renewing $FQN"

#Check if certificates need updating
/usr/local/sbin/certbot renew --quiet