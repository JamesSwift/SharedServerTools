#!/bin/bash
# Keep eight daily snapshots under /root/mysql-backups/{01..08}. 01 is newest.
set -euo pipefail

BACKUP_DIR="/root/mysql-backups"
mkdir -p "$BACKUP_DIR"

echo "$(date +%F_%T) Backup and rotate all mysql databases in: ${BACKUP_DIR}"

rm -rf "${BACKUP_DIR}/08"
for i in 07 06 05 04 03 02 01; do
	next=$(printf '%02d' $((10#$i + 1)))
	if [[ -e "${BACKUP_DIR}/${i}" ]]; then
		mv "${BACKUP_DIR}/${i}" "${BACKUP_DIR}/${next}"
	fi
done
mkdir -p "${BACKUP_DIR}/01"

DUMP_FILE="${BACKUP_DIR}/01/mysql-$(date +%F_%T).bz2"
if ! mysqldump --all-databases | bzip2 > "$DUMP_FILE"; then
	echo "ERROR: mysqldump failed. Partial file left at ${DUMP_FILE}" >&2
	exit 1
fi

echo "$(date +%F_%T) Done"
