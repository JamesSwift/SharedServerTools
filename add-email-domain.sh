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


echo "============================="
echo "ADD/VIEW DOMAIN DKIM SETTINGS"
echo "============================="

echo ""
echo "Please enter the domain name (excluding www):"
read domain

domain=`echo "$domain" | tr '[:upper:]' '[:lower:]'`


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

	#Make sure files have proper owner
	chown -R root:Debian-exim /etc/exim4/dkim/${domain}/

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

