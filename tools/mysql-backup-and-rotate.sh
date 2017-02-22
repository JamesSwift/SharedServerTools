#!/bin/bash

export DB_BACKUP="/root/mysql-backups"

echo $(date +%F_%T) " Backup and rotate all mysql databases in: $DB_BACKUP"


rm -rf $DB_BACKUP/08
mv $DB_BACKUP/07 $DB_BACKUP/08
mv $DB_BACKUP/06 $DB_BACKUP/07
mv $DB_BACKUP/05 $DB_BACKUP/06
mv $DB_BACKUP/04 $DB_BACKUP/05
mv $DB_BACKUP/03 $DB_BACKUP/04
mv $DB_BACKUP/02 $DB_BACKUP/03
mv $DB_BACKUP/01 $DB_BACKUP/02
mkdir $DB_BACKUP/01

mysqldump --all-databases | bzip2 > $DB_BACKUP/01/mysql-$(date +%F_%T).bz2

echo $(date +%F_%T) " Done"
exit 0
