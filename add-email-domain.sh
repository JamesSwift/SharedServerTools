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
echo "ADD AN EMAIL DOMAIN TO EXIM"
echo "============================="
echo

echo "This script let's you easily add a new domain to exim. If you have already added a domain, you can see the DKIM settings for it by running this script again."
echo 
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
	chmod -R 660 /etc/exim4/dkim/${domain}/
	echo
	echo "DKIM is a way of proving which servers have permission to send email for a domain."
	echo "Email clients check for a DKIM DNS record when determining if a message is spam."
	echo
	echo "Please consider adding the following entires to your DNS record for" ${domain}
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
echo "Type:     TXT"
echo "Name:     _dmarc."${domain}
echo "Value:    v=DMARC1; p=reject; ruf=mailto:postmaster@${domain}; adkim=s; aspf=s"
echo


//Create the virtual domain file
if [ ! -f "/etc/exim4/dkim/${domain}/dkim.public" ]
then
	touch "/etc/exim4/virtual/${domain}"
	chown root:Debian-exim /etc/exim4/virtual/${domain}
	chmod 660 /etc/exim4/virtual/${domain}
	service exim4 reload
fi

echo
echo "To setup routing from addresses at this domain to local users edit the file: /etc/exim4/virtual/${domain}"
echo
echo "For example to send info@${domain} to local user james add the following:"
echo
echo "info : james@localhost"