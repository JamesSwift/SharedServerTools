#!/bin/bash
# Read-only inventory of this machine's mail config.

set -u

_sst_here=$(dirname "$(realpath "$0")")
if [[ -f "${_sst_here}/sst-lib.sh" ]]; then
	. "${_sst_here}/sst-lib.sh"
elif [[ -f "${_sst_here}/tools/sst-lib.sh" ]]; then
	. "${_sst_here}/tools/sst-lib.sh"
else
	echo "ERROR: cannot find sst-lib.sh (run this as ./tools/audit-mail.sh from the repo)." >&2
	exit 1
fi
sst_init_vars

echo "SharedServerTools mail inventory"
echo "================================"
echo "Date: $(date -Is)"
echo "Host: ${HOSTNAME_FULL} (${HOSTNAME_SHORT})"
echo "Primary IP (first hostname -I): ${PRIMARY_IP}"
echo

if [[ -f /etc/os-release ]]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	echo "OS: ${PRETTY_NAME:-?}  VERSION_ID=${VERSION_ID:-?}"
fi
echo "Kernel: $(uname -r)"
echo

echo "-- package versions --"
for cmd in exim4 dovecot php nginx spamassassin spamd; do
	if command -v "$cmd" >/dev/null 2>&1; then
		case "$cmd" in
			php) php -v 2>/dev/null | head -n 1 ;;
			exim4) exim4 -bV 2>/dev/null | head -n 1 ;;
			dovecot) dovecot --version 2>/dev/null ;;
			*) "$cmd" -v 2>/dev/null | head -n 1 || true ;;
		esac
	else
		echo "$cmd: not in PATH"
	fi
done
echo "php-fpm pools detected:"
if [[ -d /etc/php ]]; then
	find /etc/php -path '*/fpm/pool.d/*.conf' 2>/dev/null | sort || true
fi
echo

echo "-- Exim layout --"
echo "update-exim4.conf.conf:"
if [[ -f /etc/exim4/update-exim4.conf.conf ]]; then
	grep -E '^dc_' /etc/exim4/update-exim4.conf.conf || true
else
	echo "  (missing)"
fi
echo
echo "virtual domains (filenames only):"
if [[ -d /etc/exim4/virtual ]]; then
	ls -la /etc/exim4/virtual 2>/dev/null || echo "  (cannot list; try sudo)"
else
	echo "  (no /etc/exim4/virtual)"
fi
echo
echo "DKIM layout:"
if [[ -d /etc/exim4/dkim ]]; then
	ls -la /etc/exim4/dkim 2>/dev/null || echo "  (cannot list; try sudo)"
	flat=$(find /etc/exim4/dkim -maxdepth 1 -type f -name '*.private' 2>/dev/null | wc -l)
	dirs=$(find /etc/exim4/dkim -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
	echo "  flat *.private files: ${flat}   per-domain directories: ${dirs}"
else
	echo "  (no /etc/exim4/dkim)"
fi
echo

echo "-- Exim paths that splice \$domain / \$local_part (Exim 4.94+ will reject these) --"
hits=0
if [[ -d /etc/exim4 ]]; then
	while IFS= read -r line; do
		echo "  $line"
		hits=$((hits + 1))
	done < <(grep -RIn --exclude='*.backup' \
		-e '/virtual/\$domain[^_]' \
		-e '/dkim/\${' \
		-e 'DKIM_FILE.*\$' \
		-e 'exists{/etc/exim4/virtual/\${' \
		-e 'lsearch{/etc/exim4/virtual/\$domain}' \
		/etc/exim4 2>/dev/null || true)
fi
if [[ "$hits" -eq 0 ]]; then
	echo "  (none matched)"
fi
echo

echo "-- Dovecot settings --"
for f in /etc/dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-mail.conf \
	/etc/dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-auth.conf; do
	if [[ -f "$f" ]]; then
		old=$(grep -E '^\s*(mail_location|ssl_cert|ssl_key|ssl_dh|disable_plaintext_auth)\s*=' "$f" 2>/dev/null || true)
		if [[ -n "$old" ]]; then
			echo "$f:"
			echo "$old" | sed 's/^/  /'
		else
			echo "$f: present"
		fi
	else
		echo "$f: missing"
	fi
done
if [[ -f /etc/dovecot/conf.d/99-sharedservertools.conf ]]; then
	echo "99-sharedservertools.conf: installed"
fi
echo

echo "-- mail-related files --"
for f in \
	/etc/exim4/conf.d/main/00_local_macros \
	/etc/exim4/conf.d/acl/01_acl_check_sender \
	/etc/exim4/check_data_acl \
	/etc/exim4/conf.d/router/350_exim4-config_vdom_aliases \
	/etc/exim4/conf.d/auth/40_dovecot \
	/etc/exim4/conf.d/transport/30_exim4-config_remote_smtp_smarthost \
	/etc/exim4/update-exim4.conf.conf \
	/etc/default/spamassassin \
	/etc/default/spamd \
	/etc/email-addresses
do
	if [[ -e "$f" ]]; then
		ls -l "$f"
	else
		echo "(absent) $f"
	fi
done
echo

echo "-- extra Exim conf.d files --"
if [[ -d /etc/exim4/conf.d ]]; then
	found=0
	while read -r f; do
		base=$(basename "$f")
		case "$base" in
			00_local_macros|01_acl_check_sender|350_exim4-config_vdom_aliases|40_dovecot)
				continue
				;;
		esac
		if [[ "$base" == *exim4-config* ]] || [[ "$base" == mmm_* ]]; then
			continue
		fi
		echo "  $f"
		found=1
	done < <(find /etc/exim4/conf.d -type f 2>/dev/null | sort)
	if [[ "$found" -eq 0 ]]; then
		echo "  (none)"
	fi
fi
echo
