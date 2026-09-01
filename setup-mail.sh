#!/bin/bash
# Install Exim4, Dovecot, and SpamAssassin. Safe to re-run.
# Called from initial-setup.sh after the hostname SSL cert exists.

set -euo pipefail

. "$(dirname "$(realpath "$0")")/tools/sst-lib.sh"
sst_require_root
sst_init_vars

OS_ID=$(sst_os_version_id)
SST_BACKUP_DIR="/root/sharedservertools-backup-$(date +%Y%m%d%H%M%S)"
export SST_BACKUP_DIR

echo "===================="
echo "Mail server (Exim4)"
echo "===================="
echo
echo "This installs Exim4, Dovecot (IMAP/POP3), and SpamAssassin."
echo "This host reports Ubuntu ${OS_ID}."
echo

if [[ "$OS_ID" == "20.04" || "$OS_ID" == "18.04" ]]; then
	echo "ERROR: This script requires Ubuntu 26.04 (this host reports ${OS_ID})."
	exit 1
fi

if [[ "$OS_ID" != "26.04" ]]; then
	echo "WARNING: Mail config is written for Ubuntu 26.04. Dovecot on ${OS_ID} may not start."
	echo
	read -p "Continue anyway? [y/N]" -n 1 -r
	echo
	if ! [[ $REPLY =~ ^[Yy]$ ]]; then
		echo "Canceled."
		exit 1
	fi
fi

DOVECOT_VER=$(sst_dovecot_major_minor)
if [[ -n "$DOVECOT_VER" && "$DOVECOT_VER" == 2.3* ]]; then
	echo "Installed Dovecot ${DOVECOT_VER}: if IMAP fails to start, check 10-ssl.conf / 10-mail.conf"
	echo "for old setting names (mail_location, ssl_cert = <)."
	echo
fi

if [[ ! -f "/etc/letsencrypt/live/${HOSTNAME_FULL}/fullchain.pem" ]]; then
	echo "WARNING: No Let's Encrypt certificate found for ${HOSTNAME_FULL}."
	echo "Exim and Dovecot templates point at /etc/letsencrypt/live/${HOSTNAME_FULL}/."
	echo "Obtain a cert first (re-run initial-setup.sh) or edit the installed TLS paths."
	echo
	read -p "Continue anyway? [y/N]" -n 1 -r
	echo
	if ! [[ $REPLY =~ ^[Yy]$ ]]; then
		echo "Canceled."
		exit 1
	fi
fi

echo "Installing mail packages:"
echo "- exim4-daemon-heavy (content scanning / spam ACL)"
echo "- dovecot-imapd dovecot-pop3d dovecot-sieve"
echo "- spamassassin spamd spamc"
echo
read -p "Press enter to continue"

export DEBIAN_FRONTEND=noninteractive
apt-get update
# Avoid the exim4-config debconf wizard; we install update-exim4.conf.conf ourselves.
echo "exim4-config exim4/dc_eximconfig_configtype select internet" | debconf-set-selections
echo "exim4-config exim4/dc_other_hostnames string " | debconf-set-selections
echo "exim4-config exim4/dc_local_interfaces string " | debconf-set-selections
echo "exim4-config exim4/dc_minimaldns boolean false" | debconf-set-selections
echo "exim4-config exim4/dc_relay_domains string " | debconf-set-selections
echo "exim4-config exim4/dc_relay_nets string " | debconf-set-selections
echo "exim4-config exim4/dc_smarthost string " | debconf-set-selections
echo "exim4-config exim4/dc_use_split_config boolean true" | debconf-set-selections
echo "exim4-config exim4/dc_mailname_in_oh boolean true" | debconf-set-selections
echo "exim4-config exim4/dc_localdelivery select maildir_home" | debconf-set-selections

apt-get install -y exim4-daemon-heavy dovecot-imapd dovecot-pop3d dovecot-sieve spamassassin spamd spamc

echo
echo "Setting up Dovecot:"
for f in /etc/dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-mail.conf \
	/etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-auth.conf; do
	if [[ -f "$f" ]] && grep -qE '^\s*(mail_location|ssl_cert|ssl_key)\s*=' "$f"; then
		echo "NOTE: $f still has old Dovecot settings. IMAP may not start until you use the"
		echo "      distro file plus 99-sharedservertools.conf."
	fi
done
apply_template /etc/dovecot/conf.d/99-sharedservertools.conf 99-sharedservertools-dovecot.conf
chmod 644 /var/www 2>/dev/null || true
echo "Done"
echo

echo "Setting up SpamAssassin (spamd):"
if [[ -f /etc/default/spamd ]]; then
	apply_template /etc/default/spamd spamd
fi
if [[ -f /usr/lib/systemd/system/spamd.service ]] || [[ -f /lib/systemd/system/spamd.service ]]; then
	systemctl enable --now spamd.service
elif [[ -f /usr/lib/systemd/system/spamassassin.service ]] || [[ -f /lib/systemd/system/spamassassin.service ]]; then
	systemctl enable --now spamassassin.service
fi
if [[ -f /usr/lib/systemd/system/spamassassin-maintenance.timer ]] || [[ -f /lib/systemd/system/spamassassin-maintenance.timer ]]; then
	systemctl enable --now spamassassin-maintenance.timer
fi
echo "Done"
echo

echo "Setting up Exim4 (split config):"
mkdir -p "${SST_EXIM_VIRTUAL}" "${SST_EXIM_DKIM}" /etc/exim4/conf.d/main /etc/exim4/conf.d/acl /etc/exim4/conf.d/router /etc/exim4/conf.d/auth
chown root:Debian-exim "${SST_EXIM_DKIM}" "${SST_EXIM_VIRTUAL}"
chmod 750 "${SST_EXIM_DKIM}" "${SST_EXIM_VIRTUAL}"

sst_ensure_virtual_domain "${HOSTNAME_FULL}"

apply_template /etc/exim4/check_data_acl check_data_acl
apply_template /etc/exim4/conf.d/acl/01_acl_check_sender 01_acl_check_sender
apply_template /etc/exim4/conf.d/router/350_exim4-config_vdom_aliases 350_exim4-config_vdom_aliases
apply_template /etc/exim4/conf.d/auth/40_dovecot 40_dovecot
apply_template /etc/exim4/update-exim4.conf.conf update-exim4.conf.conf
apply_template /etc/exim4/conf.d/main/00_local_macros 00_local_macros

update-exim4.conf
echo "Done"
echo

echo "TLS key permissions for Exim (Dovecot reads certs as root):"
if getent group Debian-exim >/dev/null 2>&1 && getent passwd dovecot >/dev/null 2>&1; then
	usermod -aG Debian-exim dovecot 2>/dev/null || true
fi

if [[ -d /etc/letsencrypt/live ]]; then
	chown root:Debian-exim /etc/letsencrypt/live /etc/letsencrypt/archive
	chmod 750 /etc/letsencrypt/live /etc/letsencrypt/archive
	chmod g+s /etc/letsencrypt/live /etc/letsencrypt/archive
fi
if [[ -d "/etc/letsencrypt/archive/${HOSTNAME_FULL}" ]]; then
	chown -R root:Debian-exim "/etc/letsencrypt/archive/${HOSTNAME_FULL}"
	chmod g+s "/etc/letsencrypt/archive/${HOSTNAME_FULL}"
	chmod 640 "/etc/letsencrypt/archive/${HOSTNAME_FULL}"/privkey*.pem 2>/dev/null || true
fi
if [[ -d "/etc/letsencrypt/live/${HOSTNAME_FULL}" ]]; then
	chown -R root:Debian-exim "/etc/letsencrypt/live/${HOSTNAME_FULL}"
	chmod g+s "/etc/letsencrypt/live/${HOSTNAME_FULL}"
fi

mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cp "${SCRIPT_DIR}/config-templates/letsencrypt-mail-permissions.sh" \
	/etc/letsencrypt/renewal-hooks/deploy/sharedservertools-mail.sh
chmod 755 /etc/letsencrypt/renewal-hooks/deploy/sharedservertools-mail.sh

if [[ -f /etc/fail2ban/jail.local ]]; then
	if ! grep -q '^\[exim\]' /etc/fail2ban/jail.local; then
		cat >> /etc/fail2ban/jail.local <<'EOF'

[exim]
enabled = true
bantime  = 1h
maxretry = 3

[dovecot]
enabled = true
EOF
		systemctl reload fail2ban 2>/dev/null || service fail2ban reload 2>/dev/null || true
	fi
fi

systemctl restart dovecot
systemctl restart exim4

echo
echo "Checking Exim configuration:"
if ! update-exim4.conf; then
	echo "ERROR: update-exim4.conf failed. See messages above." >&2
	exit 1
fi
# Avoid SIGPIPE/pipefail from `head` closing the pipe early.
exim4 -bV 2>/dev/null | sed -n '1,8p' || true
echo

sst_ensure_dkim "${HOSTNAME_FULL}" "${HOSTNAME_SHORT}"

echo "Mail setup is complete."
echo
echo "IMAP/POP3: Dovecot on 993/995 (TLS required)."
echo "SMTP submission: Exim on 587 (STARTTLS) and 465 (implicit TLS)."
echo "Virtual aliases: /etc/exim4/virtual/<domain>  (see add-email-domain.sh)"
echo
echo "To add another mail domain without a website, run add-email-domain.sh"
echo
echo "Replaced files were copied to ${SST_BACKUP_DIR} (and to *.backup beside each file)."
echo
