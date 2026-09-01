#!/bin/bash
# Install and configure Exim4 + Dovecot + SpamAssassin for Ubuntu 26.04 LTS.
# Safe to re-run. Called from initial-setup.sh after the hostname SSL cert exists,
# or on its own to turn mail back on for an existing web server.

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
echo "This configures Ubuntu's split Exim4 config (/etc/exim4/conf.d + update-exim4.conf),"
echo "Dovecot 2.4 IMAP/POP3, and SpamAssassin (spamd)."
echo
echo "Target: Ubuntu 26.04 LTS, Exim 4.99, Dovecot 2.4, PHP ${PHP_VERSION}."
echo "This host reports Ubuntu ${OS_ID}."
echo "From-version for existing SST mail boxes is Ubuntu 20.04 (Exim 4.93, Dovecot 2.3, PHP 7.4)."
echo "Read docs/upgrade-from-ubuntu-20.04.md before overwriting a drifted host."
echo

if [[ "$OS_ID" == "20.04" ]]; then
	echo "Refusing to install the 26.04 mail templates on Ubuntu 20.04."
	echo "The live 20.04 stack still works because Exim 4.93 does not reject tainted"
	echo "path expansions. Running this script here would replace working files with"
	echo "Dovecot 2.4 settings that this release cannot parse."
	echo
	echo "On this box run:  sudo ${SCRIPT_DIR}/tools/audit-mail-upgrade.sh"
	echo "Then upgrade Ubuntu to 26.04 and re-run setup-mail.sh."
	exit 1
fi

if [[ "$OS_ID" == "22.04" || "$OS_ID" == "24.04" ]]; then
	echo "WARNING: Ubuntu ${OS_ID} can load the taint-safe Exim snippets, but Dovecot is"
	echo "still 2.3. The 99-sharedservertools.conf drop-in is Dovecot 2.4 syntax and"
	echo "will not start imap/pop3 on this release. Prefer finishing the upgrade to 26.04."
	echo
	read -p "Install Exim snippets anyway (Dovecot drop-in will still be written)? [y/N]" -n 1 -r
	echo
	if ! [[ $REPLY =~ ^[Yy]$ ]]; then
		echo "Canceled."
		exit 1
	fi
fi

DOVECOT_VER=$(sst_dovecot_major_minor)
if [[ -n "$DOVECOT_VER" && "$DOVECOT_VER" == 2.3* ]]; then
	echo "Installed Dovecot ${DOVECOT_VER}: after this script, check that 10-ssl.conf /"
	echo "10-mail.conf do not still use mail_location or ssl_cert = <  (2.3 SST copies)."
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
# 20.04 SST replaced 10-*.conf with 2.3 syntax. 26.04 Dovecot will not start if those remain.
for f in /etc/dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-mail.conf \
	/etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-auth.conf; do
	if [[ -f "$f" ]] && grep -qE '^\s*(mail_location|ssl_cert|ssl_key)\s*=' "$f"; then
		echo "NOTE: $f still has Dovecot 2.3 settings. After 26.04, move it aside and"
		echo "      use the distro file plus 99-sharedservertools.conf. See docs/upgrade-from-ubuntu-20.04.md"
	fi
done
apply_template /etc/dovecot/conf.d/99-sharedservertools.conf 99-sharedservertools-dovecot.conf
# Do not replace Ubuntu's 2.4 10-*.conf files; only the drop-in above is ours.
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
mkdir -p /etc/exim4/virtual /etc/exim4/dkim /etc/exim4/conf.d/main /etc/exim4/conf.d/acl /etc/exim4/conf.d/router /etc/exim4/conf.d/auth
chown -R root:Debian-exim /etc/exim4/dkim /etc/exim4/virtual
chmod -R 770 /etc/exim4/dkim /etc/exim4/virtual

sst_ensure_virtual_domain "${HOSTNAME_FULL}"

apply_template /etc/exim4/check_data_acl check_data_acl
apply_template /etc/exim4/conf.d/acl/01_acl_check_sender 01_acl_check_sender
apply_template /etc/exim4/conf.d/router/350_exim4-config_vdom_aliases 350_exim4-config_vdom_aliases
apply_template /etc/exim4/conf.d/auth/40_dovecot 40_dovecot
apply_template /etc/exim4/update-exim4.conf.conf update-exim4.conf.conf
apply_template /etc/exim4/conf.d/main/00_local_macros 00_local_macros

# DKIM signing uses Debian's stock remote_smtp transport (DKIM_* macros).
# Do not replace 30_exim4-config_remote_smtp_smarthost; internet sites use remote_smtp.

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
	chmod 640 /etc/letsencrypt/archive/${HOSTNAME_FULL}/privkey*.pem 2>/dev/null || true
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
echo "IMAP/POP3: Dovecot on 993/995 (TLS required), system user accounts."
echo "SMTP submission: Exim on 587 (STARTTLS) and 465 (implicit TLS)."
echo "Virtual aliases: /etc/exim4/virtual/<domain>  (see add-email-domain.sh)"
echo
echo "To add another mail domain without a website, run add-email-domain.sh"
echo
echo "Replaced files were copied to ${SST_BACKUP_DIR} (and to *.backup beside each file)."
echo "Merge any local 20.04 tweaks from that backup; do not restore tainted \$domain paths."
echo
