#!/bin/bash
# Shared helpers for SharedServerTools scripts. Source this file; do not execute it.

sst_require_root() {
	if [[ $EUID -ne 0 ]]; then
		echo "This script must be run as root." >&2
		exit 1
	fi
}

sst_script_dir() {
	local source_path
	source_path=$(realpath "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")
	dirname "$source_path"
}

# First IPv4/IPv6 address from hostname -I (ignores extra addresses and trailing space).
sst_primary_ip() {
	hostname -I 2>/dev/null | awk '{print $1}'
}

# Ubuntu 26.04 LTS default is PHP 8.5; detect whatever php-fpm is actually installed.
sst_detect_php_version() {
	local version=""
	if [[ -n "${SST_PHP_VERSION:-}" ]]; then
		echo "$SST_PHP_VERSION"
		return 0
	fi
	if command -v php >/dev/null 2>&1; then
		version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)
	fi
	if [[ -z "$version" ]] && [[ -d /etc/php ]]; then
		version=$(find /etc/php -mindepth 2 -maxdepth 2 -type d -name fpm -printf '%h\n' 2>/dev/null | sed 's|.*/||' | sort -V | tail -1)
	fi
	if [[ -z "$version" ]]; then
		version="8.5"
	fi
	echo "$version"
}

sst_php_fpm_service() {
	echo "php$(sst_detect_php_version)-fpm"
}

sst_php_fpm_pool_dir() {
	echo "/etc/php/$(sst_detect_php_version)/fpm/pool.d"
}

sst_php_fpm_conf_d() {
	echo "/etc/php/$(sst_detect_php_version)/fpm/conf.d"
}

sst_php_default_sock() {
	echo "/run/php/php$(sst_detect_php_version)-fpm.sock"
}

# Existing groups only: Ubuntu 26.04 no longer has floppy, and may not have lxd.
sst_add_admin_groups() {
	local username=$1
	local group
	for group in adm dialout cdrom sudo audio dip video plugdev netdev lxd; do
		if getent group "$group" >/dev/null 2>&1; then
			usermod -aG "$group" "$username"
		fi
	done
}

replace_config_param() {
	# args: file, key, new_value, (old_value to match against)
	if [ -z "$1" ]; then
		echo "-Parameter #1 is zero length.-"
		return 1
	fi
	if [ -z "$2" ]; then
		echo "-Parameter #2 is zero length.-"
		return 1
	fi

	local CONFIG_FILE=$1
	local TARGET_KEY=$2
	local REPLACEMENT_VALUE=$3
	local SEARCH_KEY=${4:-".*"}

	if grep -q "^[ ^I]*$TARGET_KEY[ ^I]*" "$CONFIG_FILE"; then
		sed -re 's/^('"$TARGET_KEY"')([[:space:]]+)'"$SEARCH_KEY"'/\1\2'"$REPLACEMENT_VALUE"'/' -i "$CONFIG_FILE"
	else
		echo "$TARGET_KEY $REPLACEMENT_VALUE" >> "$CONFIG_FILE"
	fi
	return 0
}

# args: destination_file, config-templates file
apply_template() {
	local dest=$1
	local template=$2
	rm -f "${dest}.backup"
	cp "${SCRIPT_DIR}/config-templates/${template}" "${dest}~"

	sed -i "s/__HOSTNAME_FULL__/${HOSTNAME_FULL}/g" "${dest}~"
	sed -i "s/__HOSTNAME_SHORT__/${HOSTNAME_SHORT}/g" "${dest}~"
	sed -i "s/__PRIMARY_IP__/${PRIMARY_IP}/g" "${dest}~"
	sed -i "s/__PHP_VERSION__/${PHP_VERSION}/g" "${dest}~"
	sed -i "s#__PHP_FPM_SOCK__#${PHP_FPM_SOCK}#g" "${dest}~"

	mv "$dest" "${dest}.backup" 2>/dev/null || true
	mv "${dest}~" "$dest"
	return 0
}

sst_init_vars() {
	SCRIPT_PATH=$(realpath "$0")
	SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
	HOSTNAME_SHORT=$(hostname)
	HOSTNAME_FULL=$(hostname -f)
	PRIMARY_IP=$(sst_primary_ip)
	PHP_VERSION=$(sst_detect_php_version)
	PHP_FPM_SOCK=$(sst_php_default_sock)
}

sst_mail_enabled() {
	[[ -f /etc/exim4/update-exim4.conf.conf ]] && [[ -d /etc/exim4/virtual ]]
}

# Print the DKIM/SPF/DMARC records for an existing key directory.
sst_print_mail_dns() {
	local domain=$1
	local selector=${2:-$(hostname)}
	local pubkey=""

	if [[ -f "/etc/exim4/dkim/${domain}/dkim.public" ]]; then
		pubkey=$(sed '1d;$d' "/etc/exim4/dkim/${domain}/dkim.public" | tr -d '\n')
	fi

	echo
	echo "Type:     TXT"
	echo "Name:     ${selector}._domainkey.${domain}"
	echo "Value:    v=DKIM1; k=rsa; p=${pubkey}"
	echo
	echo "Type:     TXT"
	echo "Name:     ${domain}"
	echo "Value:    v=spf1 a mx -all"
	echo
	echo "Type:     TXT"
	echo "Name:     _dmarc.${domain}"
	echo "Value:    v=DMARC1; p=reject; ruf=mailto:postmaster@${domain}; adkim=s; aspf=s"
	echo
}

# Create DKIM key material for a domain if missing. Prints DNS records either way.
sst_ensure_dkim() {
	local domain=$1
	local selector=${2:-$(hostname)}

	mkdir -p "/etc/exim4/dkim/${domain}"

	if [[ -f "/etc/exim4/dkim/${domain}/dkim.public" ]]; then
		echo "DKIM keys were previously generated for this domain."
		echo
		echo "If you experience issues sending mail, please ensure the following entries are in your DNS record for ${domain}"
	else
		echo "Generating a DKIM key for sending emails for this domain from this server."
		echo
		openssl genrsa -out "/etc/exim4/dkim/${domain}/dkim.private" 2048 >/dev/null 2>&1
		openssl rsa -in "/etc/exim4/dkim/${domain}/dkim.private" -out "/etc/exim4/dkim/${domain}/dkim.public" -pubout -outform PEM
		echo
		echo "DKIM is a way of proving which servers have permission to send email for a domain."
		echo "Email clients check for a DKIM DNS record when determining if a message is spam."
		echo
		echo "Please add the following entries to your DNS record for ${domain}"
	fi

	chown -R root:Debian-exim "/etc/exim4/dkim/${domain}"
	chmod -R 770 "/etc/exim4/dkim/${domain}"
	chmod 640 "/etc/exim4/dkim/${domain}/dkim.private"

	sst_print_mail_dns "$domain" "$selector"
}

# Create /etc/exim4/virtual/<domain> if missing.
# Optional second arg: local username to seed a postmaster alias.
sst_ensure_virtual_domain() {
	local domain=$1
	local username=${2:-}

	mkdir -p /etc/exim4/virtual
	chown root:Debian-exim /etc/exim4/virtual
	chmod 770 /etc/exim4/virtual

	if [[ ! -f "/etc/exim4/virtual/${domain}" ]]; then
		if [[ -n "$username" ]]; then
			echo "postmaster : ${username}@localhost" > "/etc/exim4/virtual/${domain}"
		else
			touch "/etc/exim4/virtual/${domain}"
		fi
		chown root:Debian-exim "/etc/exim4/virtual/${domain}"
		chmod 770 "/etc/exim4/virtual/${domain}"
		if command -v systemctl >/dev/null 2>&1; then
			systemctl reload exim4 2>/dev/null || service exim4 reload 2>/dev/null || true
		fi
	fi
}
