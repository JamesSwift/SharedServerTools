require ["vnd.dovecot.pipe", "copy", "imapsieve", "environment", "variables"];

if environment :matches "imap.user" "*" {
  set "username" "${1}";
}

# sa-learn-spam.sh MUST live in sieve_pipe_bin_dir (/usr/lib/dovecot/sieve).
pipe :copy "sa-learn-spam.sh" [ "${username}" ];
