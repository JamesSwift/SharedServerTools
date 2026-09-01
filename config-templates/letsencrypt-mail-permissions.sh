#!/bin/bash
# Certbot deploy hook: keep Let's Encrypt keys readable by Exim and reload mail.
# Installed as /etc/letsencrypt/renewal-hooks/deploy/sharedservertools-mail.sh

set -euo pipefail

HOSTNAME_FULL=$(hostname -f)

if [[ -d /etc/letsencrypt/live ]]; then
	chown root:Debian-exim /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
	chmod 750 /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
	chmod g+s /etc/letsencrypt/live /etc/letsencrypt/archive 2>/dev/null || true
fi

if [[ -d "/etc/letsencrypt/archive/${HOSTNAME_FULL}" ]]; then
	chown -R root:Debian-exim "/etc/letsencrypt/archive/${HOSTNAME_FULL}"
	chmod g+s "/etc/letsencrypt/archive/${HOSTNAME_FULL}"
	chmod 640 /etc/letsencrypt/archive/${HOSTNAME_FULL}/privkey*.pem 2>/dev/null || true
fi

if [[ -d "/etc/letsencrypt/live/${HOSTNAME_FULL}" ]]; then
	chown -R root:Debian-exim "/etc/letsencrypt/live/${HOSTNAME_FULL}"
	chmod g+s "/etc/letsencrypt/live/${HOSTNAME_FULL}"
fi

if systemctl is-active --quiet exim4 2>/dev/null; then
	systemctl reload exim4 || true
fi
if systemctl is-active --quiet dovecot 2>/dev/null; then
	systemctl reload dovecot || true
fi
