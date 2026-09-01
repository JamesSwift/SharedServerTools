#!/bin/bash
# Non-destructive checks for SharedServerTools mail templates and (if installed) Exim.
set -euo pipefail

ROOT=$(dirname "$(dirname "$(realpath "$0")")")
fail=0

echo "== bash syntax =="
for f in "$ROOT"/initial-setup.sh "$ROOT"/setup-mail.sh "$ROOT"/add-email-domain.sh \
	"$ROOT"/add-website.sh "$ROOT"/remove-website.sh "$ROOT"/tools/*.sh; do
	if ! bash -n "$f"; then
		echo "FAIL: bash -n $f"
		fail=1
	else
		echo "OK   $f"
	fi
done

echo
echo "== templates: no leftover 2.3 Dovecot names in 2.4 drop-in =="
dovecot_dropin="$ROOT/config-templates/99-sharedservertools-dovecot.conf"
for bad in mail_location ssl_cert ssl_key ssl_dh; do
	if grep -E "^[[:space:]]*${bad}[[:space:]]*=" "$dovecot_dropin"; then
		echo "FAIL: Dovecot 2.3 setting '$bad' in $dovecot_dropin"
		fail=1
	fi
done
for need in ssl_server_cert_file ssl_server_key_file mail_driver mail_path; do
	if ! grep -q "$need" "$dovecot_dropin"; then
		echo "FAIL: missing $need in Dovecot drop-in"
		fail=1
	fi
done
echo "OK   Dovecot 2.4 drop-in setting names"

echo
echo "== templates: Exim dsearch lookups =="
if grep -E 'virtual/\$domain[^-_]' "$ROOT"/config-templates/350_exim4-config_vdom_aliases \
	|| grep -E 'virtual/\$domain"' "$ROOT"/config-templates/350_exim4-config_vdom_aliases; then
	echo "FAIL: router still uses \$domain in a path"
	fail=1
fi
if ! grep -q 'dsearch' "$ROOT"/config-templates/350_exim4-config_vdom_aliases; then
	echo "FAIL: virtual router missing dsearch"
	fail=1
fi
if ! grep -q 'dsearch' "$ROOT"/config-templates/00_local_macros; then
	echo "FAIL: DKIM macros missing dsearch"
	fail=1
fi
if grep -q 'tls_on_connect_ports = 465 : 587' "$ROOT"/config-templates/00_local_macros; then
	echo "FAIL: port 587 must not be TLS-on-connect"
	fail=1
fi
echo "OK   Exim templates use dsearch / \$domain_data"

echo
echo "== templates: Maildir modes =="
if ! grep -q 'MAILDIR_HOME_DIRECTORY_MODE = 0700' "$ROOT"/config-templates/00_local_macros; then
	echo "FAIL: Maildir directory mode should be 0700"
	fail=1
else
	echo "OK   MAILDIR_HOME_DIRECTORY_MODE = 0700"
fi

echo
echo "== placeholders =="
if grep -R '__[A-Z0-9_]*__' "$ROOT"/config-templates/00_local_macros \
	"$ROOT"/config-templates/99-sharedservertools-dovecot.conf \
	"$ROOT"/config-templates/default | grep -v '__HOSTNAME_\|__PHP_\|__PRIMARY_'; then
	echo "(info) leftover placeholders shown above if any unexpected"
fi

echo
echo "== site user: www-data group is reversed before userdel =="
if grep -q 'usermod -aG "$username" www-data' "$ROOT"/tools/sst-lib.sh \
	&& grep -q 'sst_nginx_join_owner_group' "$ROOT"/add-website.sh; then
	echo "OK   add-website still adds www-data to the owner group"
else
	echo "FAIL: live sites must still run usermod -aG USER www-data"
	fail=1
fi
if grep -q 'gpasswd -d www-data' "$ROOT"/tools/sst-lib.sh \
	&& grep -q 'userdel -r' "$ROOT"/tools/sst-lib.sh \
	&& grep -q 'sst_delete_site_user' "$ROOT"/remove-website.sh; then
	echo "OK   remove-website deletes users via gpasswd then userdel -r"
else
	echo "FAIL: site/user removal must drop www-data from the group then userdel -r"
	fail=1
fi

# Remaining-site detection (no root needed).
# shellcheck source=/dev/null
. "$ROOT/tools/sst-lib.sh"
site_tmp=$(mktemp -d)
SST_NGINX_AVAILABLE=$site_tmp
printf '%s\n' "#__OWNER__=alice" > "$site_tmp/alice.com"
printf '%s\n' "#__OWNER__=alice2" > "$site_tmp/other.com"
if sst_owner_has_remaining_sites alice && sst_owner_has_remaining_sites alice2 \
	&& ! sst_owner_has_remaining_sites bob; then
	echo "OK   sst_owner_has_remaining_sites matches whole owner names"
else
	echo "FAIL: sst_owner_has_remaining_sites matching"
	fail=1
fi
rm -rf "$site_tmp"

if [[ $EUID -eq 0 ]] && getent passwd www-data >/dev/null && command -v userdel >/dev/null; then
	live_u=ssttmpusr
	userdel -r "$live_u" >/dev/null 2>&1 || true
	groupdel "$live_u" >/dev/null 2>&1 || true
	adduser --disabled-password --gecos "" "$live_u" >/dev/null
	sst_nginx_join_owner_group "$live_u"
	if id -nG www-data | grep -qw "$live_u"; then
		echo "OK   sst_nginx_join_owner_group adds www-data"
	else
		echo "FAIL: www-data was not added to ${live_u}"
		fail=1
	fi
	SST_NGINX_AVAILABLE=$(mktemp -d)
	sst_delete_site_user "$live_u"
	if getent passwd "$live_u" >/dev/null || getent group "$live_u" >/dev/null; then
		echo "FAIL: user/group ${live_u} left behind after sst_delete_site_user"
		fail=1
	elif id -nG www-data | grep -qw "$live_u"; then
		echo "FAIL: www-data still in leftover ${live_u} group"
		fail=1
	else
		echo "OK   sst_delete_site_user removes user and group"
	fi
	rm -rf "$SST_NGINX_AVAILABLE"

	# Last site gone but the unix user is kept: drop www-data, keep the account.
	adduser --disabled-password --gecos "" "$live_u" >/dev/null
	sst_nginx_join_owner_group "$live_u"
	SST_NGINX_AVAILABLE=$(mktemp -d)
	sst_cleanup_owner_if_no_sites "$live_u"
	if ! getent passwd "$live_u" >/dev/null; then
		echo "FAIL: cleanup without remaining sites must not delete the unix user"
		fail=1
	elif id -nG www-data | grep -qw "$live_u"; then
		echo "FAIL: www-data still in ${live_u} after last site removed"
		fail=1
	else
		echo "OK   last site gone: www-data leaves the group, user kept"
	fi
	rm -rf "$SST_NGINX_AVAILABLE"
	sst_delete_site_user "$live_u"

	# Owner still has another site: leave www-data in the group.
	adduser --disabled-password --gecos "" "$live_u" >/dev/null
	sst_nginx_join_owner_group "$live_u"
	SST_NGINX_AVAILABLE=$(mktemp -d)
	printf '%s\n' "#__OWNER__=${live_u}" > "$SST_NGINX_AVAILABLE/still-live.example"
	sst_cleanup_owner_if_no_sites "$live_u"
	if id -nG www-data | grep -qw "$live_u" && getent passwd "$live_u" >/dev/null; then
		echo "OK   remaining sites keep www-data in the owner group"
	else
		echo "FAIL: www-data was removed while a site still exists"
		fail=1
	fi
	rm -rf "$SST_NGINX_AVAILABLE"
	sst_delete_site_user "$live_u"

	# Leftover group from userdel -r without gpasswd first.
	adduser --disabled-password --gecos "" "$live_u" >/dev/null
	sst_nginx_join_owner_group "$live_u"
	userdel -r "$live_u" >/dev/null 2>&1 || true
	SST_NGINX_AVAILABLE=$(mktemp -d)
	sst_cleanup_owner_if_no_sites "$live_u"
	if getent group "$live_u" >/dev/null; then
		echo "FAIL: leftover group ${live_u} not cleaned"
		fail=1
	else
		echo "OK   leftover group with no sites is removed"
	fi
	rm -rf "$SST_NGINX_AVAILABLE"
	userdel -r "$live_u" >/dev/null 2>&1 || true
	groupdel "$live_u" >/dev/null 2>&1 || true
else
	echo "(not root; skipped live userdel group checks)"
fi
unset SST_NGINX_AVAILABLE || true

if command -v exim4 >/dev/null 2>&1; then
	echo
	echo "== installed Exim =="
	exim4 -bV | head -n 8
	if [[ -f /var/lib/exim4/config.autogenerated ]]; then
		if grep -n 'Tainted' /var/log/exim4/mainlog 2>/dev/null | tail -n 5; then
			true
		fi
		echo "OK   exim4 binary present"
	fi
else
	echo
	echo "(exim4 not installed here; skipped live binary checks)"
fi

if [[ "$fail" -ne 0 ]]; then
	echo
	echo "Some checks failed."
	exit 1
fi
echo
echo "All checks passed."
