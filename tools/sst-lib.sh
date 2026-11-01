#!/bin/bash
# Shared helpers. Source this file; do not execute it.
: "${SST_EXIM_VIRTUAL:=/etc/exim4/virtual}"
: "${SST_EXIM_DKIM:=/etc/exim4/dkim}"
: "${SST_NGINX_AVAILABLE:=/etc/nginx/sites-available}"
: "${SST_NGINX_ENABLED:=/etc/nginx/sites-enabled}"

sst_die() {
	echo "ERROR: $*" >&2
	exit 1
}

sst_require_root() {
	if [[ $EUID -ne 0 ]]; then
		sst_die "This script must be run as root (sudo $0)."
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

# Installed php-fpm version (fallback 8.5).
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

# Write this owner's pool into the installed php-fpm pool.d (drops older-version copies).
sst_install_php_fpm_pool() {
	local username=$1
	local dest old
	if [[ -z "${SCRIPT_DIR:-}" ]]; then
		sst_die "sst_install_php_fpm_pool: SCRIPT_DIR is not set."
	fi
	mkdir -p "$(sst_php_fpm_pool_dir)" || sst_die "Could not create $(sst_php_fpm_pool_dir)."
	dest="$(sst_php_fpm_pool_dir)/${username}.conf"
	echo "Writing php-fpm pool ${dest}"
	cp "${SCRIPT_DIR}/templates/fpm-pool.template" "$dest" || sst_die "Could not write ${dest}."
	sed -i "s/__USERNAME__/${username}/g" "$dest"
	if [[ -d /etc/php ]]; then
		for old in /etc/php/*/fpm/pool.d/"${username}.conf"; do
			[[ -f "$old" ]] || continue
			if [[ "$old" != "$dest" ]]; then
				rm -f "$old"
			fi
		done
	fi
}

# Skip groups that do not exist on this install.
sst_add_admin_groups() {
	local username=$1
	local group
	for group in adm dialout cdrom sudo audio dip video plugdev netdev lxd; do
		if getent group "$group" >/dev/null 2>&1; then
			usermod -aG "$group" "$username"
		fi
	done
}

# Letters, digits, _ and - only. Not system account names.
sst_valid_site_user() {
	local username=$1
	[[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1
	case "$username" in
		root|www-data|Debian-exim|dovecot|debian-spamd|nobody|sync) return 1 ;;
	esac
	return 0
}

# Create the account if needed; home mode 0750.
sst_ensure_site_user() {
	local username=$1
	if ! sst_valid_site_user "$username"; then
		sst_die "Refusing username '${username}'. Use a simple name like 'alice' (not root/www-data)."
	fi
	if ! getent passwd "$username" >/dev/null; then
		echo "Creating system user '${username}' (home will be mode 0750)."
		adduser "$username" || sst_die "adduser ${username} failed."
	fi
	if [[ -d "/home/${username}" ]]; then
		chmod 0750 "/home/${username}" || true
	fi
}

# Interactive: ask which hostname visitors should land on. Sets globals
# SST_CANONICAL_HOST and SST_OTHER_HOST. No default — the operator must pick.
sst_prompt_canonical_hostname() {
	local domain=$1
	local reply
	while true; do
		echo
		echo "Which hostname should visitors land on for ${domain}?"
		echo "  W = www.${domain}  (bare ${domain} will 301 to www.${domain})"
		echo "  B = ${domain}      (www.${domain} will 301 to ${domain})"
		read -p "Enter W or B: " -n 1 -r reply
		echo
		case "$reply" in
			[Ww])
				SST_CANONICAL_HOST="www.${domain}"
				SST_OTHER_HOST="${domain}"
				return 0
				;;
			[Bb])
				SST_CANONICAL_HOST="${domain}"
				SST_OTHER_HOST="www.${domain}"
				return 0
				;;
			*) echo "Please answer W or B." ;;
		esac
	done
}

# Interactive: ask whether plain HTTP should be 301'd to HTTPS on the canonical
# hostname. Default Yes. Sets global SST_FORCE_HTTPS to 1 or 0.
sst_prompt_force_https() {
	local reply
	read -p "Redirect all HTTP traffic on the canonical hostname to HTTPS? [Y/n] " -n 1 -r reply
	echo
	if [[ $reply =~ ^[Nn]$ ]]; then
		SST_FORCE_HTTPS=0
	else
		SST_FORCE_HTTPS=1
	fi
}

# Materialise nginx-website.template into ${SST_NGINX_AVAILABLE}/${domain}.
# Args: domain username doc_root canonical_host other_host force_https(0|1)
sst_write_site_config() {
	local domain=$1
	local username=$2
	local doc_root=$3
	local canonical=$4
	local other=$5
	local force_https=$6
	local dest="${SST_NGINX_AVAILABLE}/${domain}"
	if [[ -z "${SCRIPT_DIR:-}" ]]; then
		sst_die "sst_write_site_config: SCRIPT_DIR is not set."
	fi
	cp "${SCRIPT_DIR}/templates/nginx-website.template" "$dest" \
		|| sst_die "Could not write ${dest}."
	sed -i "s/__USERNAME__/${username}/g" "$dest"
	sed -i "s#__DOC_ROOT__#${doc_root}#g" "$dest"
	sed -i "s/__DOMAIN__/${domain}/g" "$dest"
	sed -i "s/__CANONICAL_HOST__/${canonical}/g" "$dest"
	sed -i "s/__OTHER_HOST__/${other}/g" "$dest"
	if [[ "$force_https" == "1" ]]; then
		# Keep the force-HTTPS line (strip only the toggle prefix); the SSL
		# #__COMMENT__ switch continues to gate it until a cert is installed.
		sed -i 's/#__FORCE_HTTPS__ //g' "$dest"
	else
		sed -i '/#__FORCE_HTTPS__/d' "$dest"
	fi
}

# nginx (www-data) needs group read on this user's ~/www.
sst_nginx_join_owner_group() {
	local username=$1
	usermod -aG "$username" www-data
}

# fail2ban inotify does not pick up newly created log files matching a glob.
sst_fail2ban_reload_nginx() {
	if ! command -v fail2ban-client >/dev/null 2>&1; then
		return 0
	fi
	fail2ban-client reload nginx-botsearch nginx-http-auth nginx-forbidden 2>/dev/null \
		|| systemctl reload fail2ban 2>/dev/null \
		|| service fail2ban reload 2>/dev/null \
		|| true
}

# nginx creates per-site logs as root:root; let the site owner read them
# (same ownership the logrotate postrotate step applies).
sst_fix_site_log_perms() {
	local f
	for f in /home/*/www/*.log; do
		[[ -f "$f" ]] || continue
		chgrp "$(stat -c %G "$(dirname "$f")")" "$f" && chmod 0640 "$f"
	done
}

# Reverse sst_nginx_join_owner_group so userdel can remove the group.
sst_nginx_leave_owner_group() {
	local username=$1
	if getent group "$username" >/dev/null 2>&1; then
		gpasswd -d www-data "$username" 2>/dev/null || true
	fi
}

# True if any nginx site config is still owned by this user.
sst_owner_has_remaining_sites() {
	local username=$1
	local f
	[[ -d "${SST_NGINX_AVAILABLE}" ]] || return 1
	for f in "${SST_NGINX_AVAILABLE}"/*; do
		[[ -f "$f" ]] || continue
		if grep -qE "^#__OWNER__=${username}[[:space:]]*$" "$f"; then
			return 0
		fi
	done
	return 1
}

# Drop www-data from the group, userdel -r, then remove any leftover group.
sst_delete_site_user() {
	local username=$1
	if ! sst_valid_site_user "$username"; then
		sst_die "Refusing to delete '${username}'."
	fi
	sst_nginx_leave_owner_group "$username"
	if getent passwd "$username" >/dev/null; then
		userdel -r "$username" || true
		if getent passwd "$username" >/dev/null; then
			sst_die "userdel ${username} failed."
		fi
	fi
	if [[ -d "/home/${username}" ]]; then
		rm -rf "/home/${username}"
	fi
	if getent group "$username" >/dev/null 2>&1 && ! getent passwd "$username" >/dev/null; then
		sst_nginx_leave_owner_group "$username"
		groupdel "$username" 2>/dev/null || true
	fi
}

# If this owner has no sites left, drop nginx's extra group membership.
# If the unix user is already gone, remove a leftover namesake group.
sst_cleanup_owner_if_no_sites() {
	local username=$1
	if ! sst_valid_site_user "$username"; then
		return 0
	fi
	if sst_owner_has_remaining_sites "$username"; then
		return 0
	fi
	sst_nginx_leave_owner_group "$username"
	if ! getent passwd "$username" >/dev/null && getent group "$username" >/dev/null 2>&1; then
		groupdel "$username" 2>/dev/null || true
	fi
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

# Multi-user hosts: narrow the default umask and new-home mode so one account
# cannot drive-by read another's files. Picks umask 027 (files 640 / dirs 750)
# which still lets www-data read site files via the per-user group that
# sst_nginx_join_owner_group joins. USERGROUPS_ENAB is disabled so pam_umask
# does not relax the group bits for user-private-group accounts.
sst_apply_umask_defaults() {
	if [[ -f /etc/login.defs ]]; then
		replace_config_param /etc/login.defs UMASK 027
		replace_config_param /etc/login.defs HOME_MODE 0750
		replace_config_param /etc/login.defs USERGROUPS_ENAB no
	fi
	if [[ -f /etc/adduser.conf ]]; then
		# adduser.conf uses KEY=VALUE, so replace_config_param can't drive it.
		if grep -qE '^[[:space:]]*#?[[:space:]]*DIR_MODE=' /etc/adduser.conf; then
			sed -i -E 's|^[[:space:]]*#?[[:space:]]*DIR_MODE=.*$|DIR_MODE=0750|' /etc/adduser.conf
		else
			echo "DIR_MODE=0750" >> /etc/adduser.conf
		fi
	fi
}

# Offer to chmod existing /home/* directories to 0750. Idempotent — anything
# already 0750 or stricter is left alone. Pre-existing accounts created before
# HOME_MODE/DIR_MODE were tightened often end up at 0755.
sst_tighten_existing_homes() {
	local entry name current
	local -a candidates=()
	for entry in /home/*; do
		[[ -d "$entry" ]] || continue
		name=$(basename "$entry")
		case "$name" in
			lost+found|.*) continue ;;
		esac
		current=$(stat -c '%a' "$entry")
		# Anything that grants "other" or extra "group" bits beyond rx is a candidate.
		case "$current" in
			700|750|500|550|000) ;;
			*) candidates+=("${entry}|${current}") ;;
		esac
	done
	if [[ ${#candidates[@]} -eq 0 ]]; then
		return 0
	fi
	echo
	echo "These home directories are more permissive than 0750:"
	local item path mode
	for item in "${candidates[@]}"; do
		path=${item%|*}
		mode=${item##*|}
		printf '  %s  (currently %s)\n' "$path" "$mode"
	done
	echo
	read -p "Chmod them to 0750 so other users cannot read them? [y/N]" -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		for item in "${candidates[@]}"; do
			path=${item%|*}
			chmod 0750 "$path" || true
		done
	fi
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

	if [[ -f "$dest" ]] && [[ -n "${SST_BACKUP_DIR:-}" ]]; then
		mkdir -p "$SST_BACKUP_DIR"
		cp -a "$dest" "$SST_BACKUP_DIR/$(echo "$dest" | sed 's#^/##; s#/#_#g')"
	fi

	mv "$dest" "${dest}.backup" 2>/dev/null || true
	mv "${dest}~" "$dest"
	return 0
}

sst_os_version_id() {
	if [[ -f /etc/os-release ]]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		echo "${VERSION_ID:-unknown}"
	else
		echo "unknown"
	fi
}

sst_dovecot_major_minor() {
	local ver=""
	if command -v dovecot >/dev/null 2>&1; then
		ver=$(dovecot --version 2>/dev/null | awk '{print $1}')
	fi
	echo "${ver:-}"
}

sst_dovecot_conf_has_23_names() {
	local f=$1
	[[ -f "$f" ]] && grep -qE '^\s*(mail_location|ssl_cert|ssl_key)\s*=' "$f"
}

# Move SST's old Dovecot 2.3 10-*.conf aside so distro files + 99-sharedservertools.conf run.
sst_quarantine_dovecot_23_files() {
	local confd=${SST_DOVECOT_CONF_D:-/etc/dovecot/conf.d}
	local stamp f path dest
	stamp=$(date +%Y%m%d%H%M%S)
	for f in 10-ssl.conf 10-mail.conf 10-master.conf 10-auth.conf; do
		path="${confd}/${f}"
		if ! sst_dovecot_conf_has_23_names "$path"; then
			continue
		fi
		dest="${path}.sst-pre24-${stamp}"
		echo "Moving Dovecot 2.3 ${path} aside (${dest})."
		mv "$path" "$dest"
		if [[ -f "${path}.dpkg-dist" ]]; then
			cp -a "${path}.dpkg-dist" "$path"
		elif [[ -f "/usr/share/dovecot/conf.d/${f}" ]]; then
			cp -a "/usr/share/dovecot/conf.d/${f}" "$path"
		elif [[ -f "/usr/share/doc/dovecot-core/example-config/conf.d/${f}" ]]; then
			cp -a "/usr/share/doc/dovecot-core/example-config/conf.d/${f}" "$path"
		fi
	done
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
	[[ -f /etc/exim4/update-exim4.conf.conf ]] && [[ -d "${SST_EXIM_VIRTUAL}" ]]
}

# Print the DKIM/SPF/DMARC records for an existing key directory.
sst_print_mail_dns() {
	local domain=$1
	local selector=${2:-$(hostname)}
	local pubkey=""

	if [[ -f "${SST_EXIM_DKIM}/${domain}/dkim.public" ]]; then
		pubkey=$(sed '1d;$d' "${SST_EXIM_DKIM}/${domain}/dkim.public" | tr -d '\n')
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

	mkdir -p "${SST_EXIM_DKIM}/${domain}"

	# If a leftover <domain>.private sits next to <domain>/, move it in.
	if [[ -f "${SST_EXIM_DKIM}/${domain}.private" ]] && [[ ! -f "${SST_EXIM_DKIM}/${domain}/dkim.private" ]]; then
		echo "Migrating flat DKIM key ${SST_EXIM_DKIM}/${domain}.private into ${domain}/dkim.private"
		cp -a "${SST_EXIM_DKIM}/${domain}.private" "${SST_EXIM_DKIM}/${domain}/dkim.private"
		if [[ -f "${SST_EXIM_DKIM}/${domain}.public" ]]; then
			cp -a "${SST_EXIM_DKIM}/${domain}.public" "${SST_EXIM_DKIM}/${domain}/dkim.public"
		fi
	fi

	if [[ -f "${SST_EXIM_DKIM}/${domain}/dkim.public" ]]; then
		echo "DKIM keys were previously generated for this domain."
		echo
		echo "If you experience issues sending mail, please ensure the following entries are in your DNS record for ${domain}"
	else
		echo "Generating a DKIM key for sending emails for this domain from this server."
		echo
		openssl genrsa -out "${SST_EXIM_DKIM}/${domain}/dkim.private" 2048 >/dev/null 2>&1
		openssl rsa -in "${SST_EXIM_DKIM}/${domain}/dkim.private" -out "${SST_EXIM_DKIM}/${domain}/dkim.public" -pubout -outform PEM
		echo
		echo "DKIM is a way of proving which servers have permission to send email for a domain."
		echo "Email clients check for a DKIM DNS record when determining if a message is spam."
		echo
		echo "Please add the following entries to your DNS record for ${domain}"
	fi

	chown -R root:Debian-exim "${SST_EXIM_DKIM}/${domain}"
	chmod 750 "${SST_EXIM_DKIM}" "${SST_EXIM_DKIM}/${domain}"
	chmod 640 "${SST_EXIM_DKIM}/${domain}/dkim.private"
	chmod 644 "${SST_EXIM_DKIM}/${domain}/dkim.public" 2>/dev/null || true

	sst_print_mail_dns "$domain" "$selector"
}

# Create /etc/exim4/virtual/<domain> if missing.
# Optional second arg: local username to seed a postmaster alias.
sst_ensure_virtual_domain() {
	local domain=$1
	local username=${2:-}

	mkdir -p "${SST_EXIM_VIRTUAL}"
	chown root:Debian-exim "${SST_EXIM_VIRTUAL}"
	chmod 750 "${SST_EXIM_VIRTUAL}"

	if [[ ! -f "${SST_EXIM_VIRTUAL}/${domain}" ]]; then
		if [[ -n "$username" ]]; then
			echo "postmaster : ${username}@localhost" > "${SST_EXIM_VIRTUAL}/${domain}"
		else
			touch "${SST_EXIM_VIRTUAL}/${domain}"
		fi
		chown root:Debian-exim "${SST_EXIM_VIRTUAL}/${domain}"
		chmod 640 "${SST_EXIM_VIRTUAL}/${domain}"
		if command -v systemctl >/dev/null 2>&1; then
			systemctl reload exim4 2>/dev/null || service exim4 reload 2>/dev/null || true
		fi
	fi
}
