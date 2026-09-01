#!/bin/bash
# Interactive: do not use set -e.

. "$(dirname "$(realpath "$0")")/tools/sst-lib.sh"
sst_require_root
sst_init_vars

echo "Enter the domain of the website you wish to delete (excluding www):"
read -r domain
if [[ -z "$domain" ]]; then
	sst_die "No domain entered."
fi

if [[ ! -f "${SST_NGINX_AVAILABLE}/${domain}" ]]; then
	sst_die "Domain ${domain} doesn't exist on this system."
fi

username=$(grep --only-matching --perl-regex "(?<=\#__OWNER__\=).*" "${SST_NGINX_AVAILABLE}/${domain}" || true)
DOC_ROOT=$(grep --only-matching --perl-regex "(?<=\#__DIR__\=).*" "${SST_NGINX_AVAILABLE}/${domain}" || true)

if [[ -z "$username" ]] || ! getent passwd "$username" >/dev/null || [[ ! -d "/home/${username}" ]]; then
	sst_die "The owner of the domain could not be found (username='${username}')."
fi

rm -f "${SST_NGINX_ENABLED}/${domain}"
rm -f "${SST_NGINX_AVAILABLE}/${domain}"
rm -rf "/etc/letsencrypt/live/${domain}/"
rm -f "/etc/letsencrypt/renewal/${domain}.conf"
rm -rf "/etc/letsencrypt/archive/${domain}/"
rm -f "/home/${username}/www/${domain}".*

read -p "Do you wish to delete the document root folder? (${DOC_ROOT}) [N/y]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	rm -rf "${DOC_ROOT}"
fi

service nginx restart || sst_die "nginx restart failed."

echo "Domain deleted. Mail aliases in ${SST_EXIM_VIRTUAL}/${domain} (if any) were left in place."
echo

read -p "Do you wish to delete user '$username' who owns this domain? (WARNING: they may have other active domains!) [N/y]" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	rm -f "$(sst_php_fpm_pool_dir)/${username}.conf"
	service "$(sst_php_fpm_service)" restart || true
	sst_delete_site_user "$username"
else
	sst_cleanup_owner_if_no_sites "$username"
fi
