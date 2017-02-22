#!/bin/bash
if [[ $# -eq 0 ]] ; then
    echo 'Error: Please specify the backup location as the first argument to this script.'
    exit 0
fi

backup_location=$1

echo Starting restore complete filesystem backup
echo
echo WARNING! This will complpetely destroy the current filesytem, and replace it with files from:
echo
echo $backup_location
echo
read -p "Are you absolutely sure? " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]
then
     
	rsync -aAXHzv --rsync-path="rsync --fake-super" --delete --exclude={"/etc/network/interfaces","/var/lib/lxcfs/*","/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/lost+found"} $backup_location /
	echo 
	echo "Don't forget, if you have restored from another server's backup:"
	echo - Make sure any backup scripts are pointing to the right destination (not overwriting the original server)
	echo - Configure this server's hostname
	echo
	echo Restore Complete
fi
