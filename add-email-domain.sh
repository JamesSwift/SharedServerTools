#!/bin/bash

. "$(dirname "$(realpath "$0")")/tools/sst-lib.sh"
sst_require_root
sst_init_vars

echo "============================="
echo "ADD AN EMAIL DOMAIN TO EXIM"
echo "============================="
echo

if ! sst_mail_enabled; then
	echo "Mail is not configured on this server yet."
	echo "Run ./setup-mail.sh (or re-run initial-setup.sh and enable mail) first."
	exit 1
fi

echo "This script lets you add a new domain to Exim. If you have already added a domain, you can see the DKIM settings for it by running this script again."
echo
echo "Please enter the domain name (excluding www):"
read -r domain

domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')

if [[ -z "$domain" ]]; then
	echo "No domain entered."
	exit 1
fi

sst_ensure_dkim "$domain"
sst_ensure_virtual_domain "$domain"

echo
echo "To setup routing from addresses at this domain to local users edit the file: /etc/exim4/virtual/${domain}"
echo
echo "For example to send info@${domain} to local user james add the following:"
echo
echo "info : james@localhost"
echo
