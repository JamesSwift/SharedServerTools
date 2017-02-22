#!/bin/bash
if [[ $# -eq 0 ]] ; then
    echo 'Error: Please specify the backup location as the first argument to this script.'
    exit 0
fi

backup_location=$1

echo Starting rsync backup task
echo
echo Backing up to: $backup_location
echo 
rsync -aAXHzv --rsync-path="rsync --fake-super" --ignore-errors --numeric-ids --delete --exclude={"/var/lib/lxcfs/*","/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/lost+found"} / $backup_location
echo 
echo Backup Complete
