#!/bin/sh
# Train the shared Bayes DB as ham. Message body on stdin (imap-sieve pipe).
# Last classification wins (sa-learn reclassifies via bayes_seen; no --forget).
dbpath=/var/lib/spamassassin/.spamassassin/bayes
if [ "$(id -u)" -eq 0 ]; then
	exec /usr/bin/sa-learn --dbpath "$dbpath" --ham
fi
exec /usr/bin/sudo -n /usr/bin/sa-learn --dbpath "$dbpath" --ham
