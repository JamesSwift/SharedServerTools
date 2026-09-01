#!/bin/bash
# Full-filesystem rsync backup. Not interactive; fail loudly on bad args.
set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
	echo "ERROR: Please specify the backup destination as the first argument." >&2
	echo "Usage: $0 /path/to/backup/" >&2
	exit 1
fi

backup_location=$1

echo "Starting rsync backup task"
echo
echo "Backing up to: ${backup_location}"
echo
rsync -aAxXHzv --rsync-path="rsync --fake-super" --ignore-errors --numeric-ids --delete \
	--exclude={"/var/lib/lxcfs/*","/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/lost+found"} \
	/ "${backup_location}"
echo
echo "Backup Complete"
