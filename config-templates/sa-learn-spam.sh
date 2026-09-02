#!/bin/sh
# Train the shared Bayes DB as spam. Message body on stdin (imap-sieve pipe).
# --dbpath is bayes_path form (matches 99_sst.cf). Run as root: debian-spamd
# cannot read user Maildirs, and the IMAP user cannot write the shared DB.
dbpath=/var/lib/spamassassin/.spamassassin/bayes
if [ "$(id -u)" -eq 0 ]; then
	exec /usr/bin/sa-learn --dbpath "$dbpath" --spam
fi
exec /usr/bin/sudo -n /usr/bin/sa-learn --dbpath "$dbpath" --spam
