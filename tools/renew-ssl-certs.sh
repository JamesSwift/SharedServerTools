#!/bin/bash

FQN=$(hostname -f)
echo $(date +%F_%T) "Renewing $FQN"

# Ubuntu packages install certbot to /usr/bin; older copies used /usr/local/sbin.
if command -v certbot >/dev/null 2>&1; then
	certbot renew --quiet
elif [[ -x /usr/local/sbin/certbot ]]; then
	/usr/local/sbin/certbot renew --quiet
else
	echo "certbot not found" >&2
	exit 1
fi