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
echo "== templates: From: restriction on submission, not inbound MX =="
sender_acl="$ROOT/config-templates/check_data_acl"
acl_calls=$(grep -c 'acl_check_sender' "$sender_acl" || true)
if grep -q 'authenticated = \*' "$sender_acl" \
	&& grep -q 'acl_check_sender \${authenticated_id}' "$sender_acl" \
	&& [[ "$acl_calls" -eq 1 ]]; then
	echo "OK   check_data_acl AUTH uses acl_check_sender \${authenticated_id}"
else
	echo "FAIL: AUTH must call acl_check_sender once with \${authenticated_id}"
	fail=1
fi
if grep -q 'relay_from_hosts' "$sender_acl" \
	&& grep -q '!authenticated = \*' "$sender_acl" \
	&& grep -q 'Authentication required to submit mail from this host' "$sender_acl"; then
	echo "OK   unauthenticated localhost SMTP is a hard AUTH-required deny"
else
	echo "FAIL: +relay_from_hosts without AUTH must hard-deny (no empty nested ACL)"
	fail=1
fi
if grep -q 'received_protocol' "$sender_acl" \
	|| grep -q 'sender_ident' "$sender_acl" \
	|| awk '/hosts = \+relay_from_hosts/,/^$/' "$sender_acl" | grep -q 'acl_check_sender'; then
	echo "FAIL: DATA ACL must not use received_protocol or empty nested ACL"
	fail=1
else
	echo "OK   DATA ACL has no local/notsmtp rule and no empty nested ACL"
fi
if grep -q 'acl_not_smtp = acl_check_local_sender' "$ROOT"/config-templates/00_local_macros \
	&& grep -q 'acl_check_local_sender:' "$ROOT"/config-templates/01_acl_check_sender \
	&& grep -q 'acl_check_sender \${sender_ident}' "$ROOT"/config-templates/01_acl_check_sender; then
	echo "OK   local sendmail is hooked via acl_not_smtp / sender_ident"
else
	echo "FAIL: local sendmail must run acl_check_sender with sender_ident"
	fail=1
fi
if grep -q 'dsearch,filter=file,ret=full {/etc/exim4/virtual}' "$ROOT"/config-templates/01_acl_check_sender \
	&& ! grep -E 'virtual/\$\{?domain' "$ROOT"/config-templates/01_acl_check_sender; then
	echo "OK   acl_check_sender still uses tainted-safe dsearch"
else
	echo "FAIL: do not weaken acl_check_sender dsearch"
	fail=1
fi

echo
echo "== templates: SA junk router / transport / tag threshold =="
sa_router="$ROOT/config-templates/550_exim4-config_sa_junk"
sa_transport="$ROOT/config-templates/30_exim4-config_maildir_junk"
if [[ -f "$sa_router" ]] && grep -q 'driver = accept' "$sa_router" \
	&& grep -q 'domains = +local_domains' "$sa_router" \
	&& grep -q 'check_local_user' "$sa_router" \
	&& grep -q 'local_parts = ! root' "$sa_router" \
	&& grep -q 'eqi' "$sa_router" \
	&& grep -q 'X-SA-Status' "$sa_router" \
	&& grep -q 'transport = maildir_junk' "$sa_router"; then
	echo "OK   sa_junk router files X-SA-Status Yes via maildir_junk"
else
	echo "FAIL: 550_exim4-config_sa_junk must accept local users (not root) when X-SA-Status is Yes"
	fail=1
fi
if [[ -f "$sa_transport" ]] && grep -q 'driver = appendfile' "$sa_transport" \
	&& grep -q 'maildir_format' "$sa_transport" \
	&& grep -q 'create_directory' "$sa_transport" \
	&& grep -q 'directory = $home/Maildir/.Junk' "$sa_transport" \
	&& grep -q 'MAILDIR_HOME_DIRECTORY_MODE' "$sa_transport" \
	&& grep -q 'MAILDIR_HOME_MODE' "$sa_transport" \
	&& grep -q 'mode_fail_narrower = false' "$sa_transport"; then
	echo "OK   maildir_junk delivers to \$home/Maildir/.Junk"
else
	echo "FAIL: maildir_junk transport must clone maildir_home into Maildir/.Junk"
	fail=1
fi
if grep -q 'spam_score_int}{30}' "$ROOT"/config-templates/check_data_acl \
	&& grep -q 'X-SA-Status: Yes' "$ROOT"/config-templates/check_data_acl \
	&& grep -q 'spam_score_int}{70}' "$ROOT"/config-templates/check_data_acl \
	&& ! grep -q 'spam_score_int}{50}' "$ROOT"/config-templates/check_data_acl; then
	echo "OK   check_data_acl tags at 3.0 and rejects at 7.0"
else
	echo "FAIL: X-SA-Status Yes at 30 (3.0); reject still at 70 (7.0)"
	fail=1
fi
if grep -q '550_exim4-config_sa_junk' "$ROOT"/setup-mail.sh \
	&& grep -q '30_exim4-config_maildir_junk' "$ROOT"/setup-mail.sh \
	&& grep -q 'conf.d/transport' "$ROOT"/setup-mail.sh; then
	echo "OK   setup-mail.sh installs sa_junk router and transport"
else
	echo "FAIL: setup-mail.sh must apply_template the junk router and transport"
	fail=1
fi
if grep -q '[.]forward' "$ROOT"/README.md || grep -q 'Maildir/.Spam' "$ROOT"/README.md; then
	echo "FAIL: README must not require ~/.forward or Maildir/.Spam"
	fail=1
elif grep -q 'Maildir/.Junk' "$ROOT"/README.md; then
	echo "OK   README files tagged spam into Maildir/.Junk (no ~/.forward)"
else
	echo "FAIL: README should mention Maildir/.Junk"
	fail=1
fi

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

echo
echo "== audit-mail.sh finds sst-lib.sh =="
if bash "$ROOT/tools/audit-mail.sh" >/dev/null; then
	echo "OK   ./tools/audit-mail.sh runs from the repo"
else
	echo "FAIL: ./tools/audit-mail.sh exited non-zero"
	fail=1
fi
audit_copy=$(mktemp -d)
cp "$ROOT/tools/audit-mail.sh" "$audit_copy/audit-mail.sh"
audit_err=$(mktemp)
if bash "$audit_copy/audit-mail.sh" >/dev/null 2>"$audit_err"; then
	echo "FAIL: audit-mail.sh without sst-lib.sh should exit"
	fail=1
elif grep -q 'sst-lib.sh' "$audit_err" && ! grep -q 'sst_init_vars: command not found' "$audit_err"; then
	echo "OK   missing sst-lib.sh is a clear error (not sst_init_vars)"
else
	echo "FAIL: expected a sst-lib.sh error, got:"
	sed 's/^/  /' "$audit_err"
	fail=1
fi
rm -rf "$audit_copy" "$audit_err"

echo
echo "== add-website refreshes the current php-fpm pool on existing sites =="
pool_calls=$(grep -c 'sst_install_php_fpm_pool' "$ROOT"/add-website.sh || true)
if [[ "$pool_calls" -ge 2 ]]; then
	echo "OK   existing-site path rewrites the php-fpm pool"
else
	echo "FAIL: existing-site branch must call sst_install_php_fpm_pool"
	fail=1
fi
if grep -q 'sst_php_fpm_pool_dir' "$ROOT"/tools/sst-lib.sh \
	&& grep -q 'sst_install_php_fpm_pool' "$ROOT"/add-website.sh; then
	echo "OK   pool path comes from sst_php_fpm_pool_dir (installed php-fpm)"
else
	echo "FAIL: php-fpm pool must use sst_php_fpm_pool_dir, not a hardcoded 8.1/7.4 path"
	fail=1
fi
if grep -E 'php[0-9]+\.[0-9]+/fpm/pool' "$ROOT"/add-website.sh "$ROOT"/remove-website.sh; then
	echo "FAIL: website scripts still hardcode a php-fpm pool path"
	fail=1
else
	echo "OK   no hardcoded phpX.Y pool paths in add/remove-website"
fi

echo
echo "== setup-mail: 26.04 Dovecot 2.3 leftovers / 20.04 refuse / internet mode =="
if grep -q '20.04' "$ROOT"/setup-mail.sh && grep -q 'exit 1' "$ROOT"/setup-mail.sh; then
	echo "OK   setup-mail still refuses Ubuntu 20.04"
else
	echo "FAIL: setup-mail.sh must refuse to run on 20.04"
	fail=1
fi
if grep -q 'sst_quarantine_dovecot_23_files' "$ROOT"/setup-mail.sh; then
	echo "OK   setup-mail quarantines Dovecot 2.3 10-*.conf on 2.4"
else
	echo "FAIL: setup-mail.sh must move old Dovecot 2.3 10-*.conf aside"
	fail=1
fi
if grep -q "dc_eximconfig_configtype='internet'" "$ROOT"/config-templates/update-exim4.conf.conf \
	&& grep -q "dc_smarthost=''" "$ROOT"/config-templates/update-exim4.conf.conf; then
	echo "OK   Exim template is internet mode (no smarthost)"
else
	echo "FAIL: Exim must stay internet mode, not smarthost"
	fail=1
fi

dov_tmp=$(mktemp -d)
printf '%s\n' 'mail_location = maildir:~/Maildir' > "$dov_tmp/10-mail.conf"
printf '%s\n' '# distro 2.4 mail' > "$dov_tmp/10-mail.conf.dpkg-dist"
printf '%s\n' 'ssl_cert = </etc/dovecot/private/dovecot.pem' > "$dov_tmp/10-ssl.conf"
printf '%s\n' 'mail_path = ~/Maildir' > "$dov_tmp/10-auth.conf"
SST_DOVECOT_CONF_D=$dov_tmp
sst_quarantine_dovecot_23_files
if [[ -f "$dov_tmp/10-mail.conf" ]] && grep -q 'distro 2.4 mail' "$dov_tmp/10-mail.conf" \
	&& ls "$dov_tmp"/10-mail.conf.sst-pre24-* >/dev/null 2>&1 \
	&& ls "$dov_tmp"/10-ssl.conf.sst-pre24-* >/dev/null 2>&1 \
	&& [[ ! -f "$dov_tmp/10-ssl.conf" ]] \
	&& [[ -f "$dov_tmp/10-auth.conf" ]]; then
	echo "OK   sst_quarantine_dovecot_23_files moves 2.3 files and restores dpkg-dist"
else
	echo "FAIL: Dovecot 2.3 quarantine behaviour"
	ls -la "$dov_tmp"
	fail=1
fi
rm -rf "$dov_tmp"
unset SST_DOVECOT_CONF_D || true

if grep -q 'initial-setup.sh, add-website.sh, and setup-mail.sh' "$ROOT"/README.md; then
	echo "OK   README Upgrading names the scripts to re-run"
else
	echo "FAIL: README Upgrading should say to re-run initial-setup.sh / add-website.sh / setup-mail.sh"
	fail=1
fi

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
