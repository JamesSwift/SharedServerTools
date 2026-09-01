#!/bin/bash
# Full-filesystem restore. Interactive confirmation — do not use set -e until after "yes".
set -u

if [[ $# -lt 1 || -z "${1:-}" ]]; then
	echo "ERROR: Please specify the backup location as the first argument." >&2
	echo "Usage: $0 /path/to/backup/" >&2
	exit 1
fi

backup_location=$1

echo "Starting complete filesystem restore"
echo
echo "WARNING! This will completely destroy the current filesystem, and replace it with files from:"
echo
echo "${backup_location}"
echo
read -p "Are you absolutely sure? " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	set -eo pipefail
	rsync -aAXHv --rsync-path="rsync --fake-super" --delete \
		--exclude={"/etc/network/interfaces","/var/lib/lxcfs/*","/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
		"${backup_location}" /
	echo
	echo "Don't forget, if you have restored from another server's backup:"
	echo "- Make sure any backup scripts are pointing to the right destination (not overwriting the original server)"
	echo "- Configure this server's hostname"
	echo
	echo "Restore Complete"
else
	echo "Canceled."
	exit 1
fi
