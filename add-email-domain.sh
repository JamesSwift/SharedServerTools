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

echo "This script lets you easily add a new domain to exim. If you have already added a domain, you can see the DKIM settings for it by running this script again."
echo
echo "Please enter the domain name (excluding www):"
read -r domain

domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
if [[ -z "$domain" ]]; then
	sst_die "No domain entered."
fi

echo
echo "Which local user should receive mail for this domain?"
echo "Reuse an existing system user if this domain belongs with their other sites."
echo "(Leave blank only if you will edit ${SST_EXIM_VIRTUAL}/${domain} yourself.)"
read -r mail_user

if [[ -n "$mail_user" ]]; then
	if ! getent passwd "$mail_user" >/dev/null; then
		sst_die "User '${mail_user}' does not exist. Create them with add-website.sh or adduser first."
	fi
	if ! sst_valid_site_user "$mail_user"; then
		echo "WARNING: '${mail_user}' looks like a system account name."
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
	echo "postmaster@${domain} -> ${mail_user}@localhost"
	echo "Add extra addresses like:  info : ${mail_user}@localhost"
else
	echo "The file is empty. Example to deliver to a local user:"
	echo "  info : user@localhost"
fi
echo
