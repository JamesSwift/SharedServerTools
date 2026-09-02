require ["vnd.dovecot.pipe", "copy", "imapsieve", "environment", "variables"];

if environment :matches "imap.mailbox" "*" {
  set "mailbox" "${1}";
}

# Not-spam is a MOVE out of Junk/Spam. Trash (and copies into another
# spam folder) are not ham.
if string :is :comparator "i;ascii-casemap" "${mailbox}" ["Trash", "Junk", "Spam", "my spam"] {
  stop;
}

if environment :matches "imap.user" "*" {
  set "username" "${1}";
}

# sa-learn-ham.sh MUST live in sieve_pipe_bin_dir (/usr/lib/dovecot/sieve).
pipe :copy "sa-learn-ham.sh" [ "${username}" ];
