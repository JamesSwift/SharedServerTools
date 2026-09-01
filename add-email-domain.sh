#!/bin/bash
# Interactive: do not use set -e (prompts + optional lookups).

. "$(dirname "$(realpath "$0")")/tools/sst-lib.sh"
sst_require_root
sst_init_vars

echo "============================="
echo "ADD AN EMAIL DOMAIN TO EXIM"
echo "============================="
echo

if ! sst_mail_enabled; then
	sst_die "Mail is not configured yet. Run ${SCRIPT_DIR}/setup-mail.sh first (or initial-setup.sh and enable mail)."
fi

echo "This adds a domain to Exim (virtual aliases + DKIM)."
echo "Pick the Unix user who already owns this person's sites (or will)."
echo "All of that group's domains and mail aliases land in that user's ~/Maildir."
echo "If you already added this domain, run this again to reprint DNS records."
echo
echo "Please enter the domain name (excluding www):"
read -r domain

domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
if [[ -z "$domain" ]]; then
	sst_die "No domain entered."
fi

echo
echo "Which local Unix user owns this group (sites + mail)?"
echo "Reuse the same user for several domains. IMAP login = that user."
echo "(Leave blank only if you will edit ${SST_EXIM_VIRTUAL}/${domain} yourself.)"
read -r mail_user

if [[ -n "$mail_user" ]]; then
	if ! getent passwd "$mail_user" >/dev/null; then
		sst_die "User '${mail_user}' does not exist. Create them with add-website.sh or adduser first."
	fi
	if ! sst_valid_site_user "$mail_user"; then
		echo "WARNING: '${mail_user}' is a special/system name. Continuing, but prefer an owner-group account."
	fi
	if [[ -d "/home/${mail_user}" ]]; then
		chmod 0750 "/home/${mail_user}" || true
	fi
fi

sst_ensure_dkim "$domain"
sst_ensure_virtual_domain "$domain" "${mail_user:-}"

echo
echo "Alias file: ${SST_EXIM_VIRTUAL}/${domain}"
if [[ -n "$mail_user" ]]; then
	echo "postmaster@${domain} -> ${mail_user}@localhost  (~${mail_user}/Maildir)"
	echo "Same Unix user can own other domains too. Add more mailboxes/aliases:"
	echo "  info : ${mail_user}@localhost"
else
	echo "The file is empty. Example to deliver to local user james:"
	echo "  info : james@localhost"
fi
echo
