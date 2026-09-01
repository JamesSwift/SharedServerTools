# Upgrading a Ubuntu 20.04 SharedServerTools host to 26.04 (with mail)

The live production server this project was written for is still on **Ubuntu 20.04**, with a working 20.04-era Exim/Dovecot stack and **local modifications on top of SharedServerTools**. This document is the upgrade-aware companion to a greenfield 26.04 install. It does not log into that box; run `tools/audit-mail-upgrade.sh` there later.

Do **not** run `setup-mail.sh` or `initial-setup.sh` as a “fix” while still on 20.04. Those scripts target 26.04 and will overwrite files you have drifted.

## Why 20.04 still works, and 22.04+ did not

| Ubuntu | Exim | Tainted filenames | Dovecot | PHP (SST default then) |
| --- | --- | --- | --- | --- |
| 20.04 LTS (from) | 4.93 | Not enforced the way 4.94+ is. `$domain` in a path still works. | 2.3 | 7.4 |
| 22.04 LTS | 4.95 | **Breaks** 20.04-era SST mail templates | 2.3 | 8.1 |
| 24.04 LTS | 4.97 | Same taint rules | 2.3 | 8.3 |
| 26.04 LTS (to) | 4.99 | Same taint rules; configs in this repo are written for this | **2.4** (new syntax) | 8.5 |

SST mail was removed in May 2022 (`3a5a388`) after hours of fighting 22.04 Exim. The production host stayed on 20.04 instead. This restore keeps Ubuntu’s split Exim config and de-taints with `dsearch`. Dovecot 2.4 is a **drop-in**, not a restore of the old `10-*.conf` copies.

Suggested release path: 20.04 → 22.04 → 24.04 → 26.04 (do-release-upgrade). Mail may break at the 22.04 step until the new Exim snippets are in place. Plan a maintenance window; do not expect `setup-mail.sh` on 20.04 to “prepare” the box.

## What to copy off the 20.04 box first

Operator data (SST did not generate these from scratch every run, or you edited them by hand):

| Path | What it is |
| --- | --- |
| `/etc/exim4/virtual/*` | Per-domain aliases (`info : james@localhost`). **Keep.** Same path on 26.04. |
| `/etc/exim4/dkim/` | DKIM keys. 20.04 SST after Aug 2020 uses `<domain>/dkim.private`. Older SST used flat `<domain>.private`. **Keep both layouts**; `setup-mail.sh` migrates flat files into directories. |
| `/etc/email-addresses` | Default From: rewrite per Unix user. **Keep.** |
| `/etc/aliases` | System aliases. **Keep.** |
| `/etc/exim4/passwd.client` | Smarthost client auth, if you use it. **Keep.** |
| `~/.forward` on each mail user | Exim filter / spam filing. **Keep.** Maildir path is `$home/Maildir` (SST since 55619e2). |
| `/etc/nginx/sites-available/*` | Per-site nginx. **Keep.** Per-user PHP sockets (`/run/php/<user>.sock`) are version-agnostic. The **default** site used to hardcode `php7.4-fpm.sock`. |
| `/etc/php/7.4/fpm/pool.d/*.conf` | Per-user FPM pools. **Move** to `/etc/php/8.5/fpm/pool.d/` on 26.04 (or whatever `php-fpm` installs). |
| Let’s Encrypt `live/` + `archive/` | Certs. **Keep.** |

## Files SST will replace on 26.04 (`setup-mail.sh`)

Each existing file is copied to a timestamped directory under `/root/sharedservertools-backup/` **and** to `*.backup` next to the original. Diff those against this repo before discarding local tweaks.

| Installed path | Template | Notes |
| --- | --- | --- |
| `/etc/exim4/conf.d/main/00_local_macros` | `config-templates/00_local_macros` | TLS, DKIM `dsearch`, ports, `MAIN_LOCAL_DOMAINS`. |
| `/etc/exim4/conf.d/acl/01_acl_check_sender` | `01_acl_check_sender` | SMTP AUTH From: check, taint-safe. |
| `/etc/exim4/conf.d/router/350_exim4-config_vdom_aliases` | `350_exim4-config_vdom_aliases` | Virtual domains via `dsearch` + `$domain_data`. |
| `/etc/exim4/conf.d/auth/40_dovecot` | `40_dovecot` | Socket path is `/run/dovecot/auth-client`. |
| `/etc/exim4/check_data_acl` | `check_data_acl` | Sender ACL + SpamAssassin. |
| `/etc/exim4/update-exim4.conf.conf` | `update-exim4.conf.conf` | Split config, `internet`, `maildir_home`. |
| `/etc/dovecot/conf.d/99-sharedservertools.conf` | `99-sharedservertools-dovecot.conf` | **New.** Dovecot 2.4 only. |
| `/etc/default/spamd` | `spamd` | Ubuntu 24.04+ unit is `spamd`, not `spamassassin`. |

`apply_template` has no regard for “I edited three lines.” Merge by hand from the backup.

## Files 20.04 SST used to overwrite — this tree no longer touches them

If you customized these, **merge yourself**. After `do-release-upgrade` to 26.04, Dovecot 2.3 syntax in the first four will prevent Dovecot from starting.

| Path | 20.04 SST behaviour | 26.04 |
| --- | --- | --- |
| `/etc/dovecot/conf.d/10-ssl.conf` | Replaced (`ssl_cert = </etc/letsencrypt/...`) | Distro 2.4 file + drop-in `ssl_server_cert_file` (no `<`). |
| `/etc/dovecot/conf.d/10-mail.conf` | Replaced (`mail_location = maildir:~/Maildir`) | Distro 2.4: `mail_driver` / `mail_path`. Drop-in sets Maildir. |
| `/etc/dovecot/conf.d/10-master.conf` | Replaced (`unix_listener auth-client`) | Distro 2.4 + drop-in `auth-client`. |
| `/etc/dovecot/conf.d/10-auth.conf` | Replaced (`auth_mechanisms = plain login`) | Distro 2.4 file; drop-in sets mechanisms. |
| `/etc/exim4/conf.d/transport/30_exim4-config_remote_smtp_smarthost` | Replaced to add `DKIM_*` | **Not replaced.** `internet` uses stock `remote_smtp`, which already honours `DKIM_*`. If you actually use a smarthost, keep your file and add the same macros Debian uses on `remote_smtp`. |
| `/etc/default/spamassassin` | `ENABLED`/`CRON`/`OPTIONS` | Package `spamd` uses `/etc/default/spamd`. `sa-exim` is **not** in 26.04. |

If `10-ssl.conf` still contains `ssl_cert = <` after upgrade, move the SST copies aside and restore Ubuntu’s 2.4 examples, then rely on `99-sharedservertools.conf`.

## Breaking behaviour changes (not just file names)

1. **Exim taint.** Anything that builds a filename from `$domain`, `$local_part`, or `$h_from:` without a `dsearch`/`lsearch` that de-taints will fail at 22.04+. Grep your extras: `tools/audit-mail-upgrade.sh` looks for the old SST patterns.
2. **Port 587.** 20.04 SST set `tls_on_connect_ports = 465 : 587`. That is wrong for submission; 587 is STARTTLS. This restore uses `tls_on_connect_ports = 465` only. Clients using implicit TLS on 587 need to switch to 465 or STARTTLS on 587.
3. **`MAIN_FORCE_SENDER = yes`.** 20.04 templates defined this, which (Debian’s `.ifndef`) *disables* `untrusted_set_sender=*`. PHP/`sendmail` From: rewriting then behaves like classic Exim. This restore **leaves it unset** so website users can set envelope sender. SMTP AUTH is still limited by `acl_check_sender`. If you relied on forced Sender: headers, put `MAIN_FORCE_SENDER = yes` back in `00_local_macros` after comparing backups.
4. **Dovecot 2.4.** `mail_location`, `ssl_cert`, `ssl_key`, `ssl_dh`, and `disable_plaintext_auth` are gone or renamed. `dovecot_config_version = 2.4.0` is required in `dovecot.conf` (distro file).
5. **PHP 7.4 → 8.5.** Pools and any hardcoded `php7.4-fpm.sock` in nginx. `add-website.sh` now detects the installed FPM version.
6. **SpamAssassin 3.4 → 4.x.** Service name `spamassassin` → `spamd`. Content scan is Exim ACL `spam = nobody:true`, not `sa-exim`.
7. **`dovecot-antispam`.** Not in the 2.4 Ubuntu package set; IMAP-train-spam is gone unless you replace it.
8. **Auth socket.** Templates now use `/run/dovecot/auth-client` (`/var/run` is a symlink; old SST used `/var/run/dovecot/auth-client`).

## Procedure (once you are ready to move the 20.04 host)

1. On **20.04**, as root: copy this repo and run `sudo ./tools/audit-mail-upgrade.sh | tee /root/sst-mail-audit-$(date +%F).txt`. Keep the log with the backups below.
2. Tarball operator data: `virtual/`, `dkim/`, `email-addresses`, nginx sites, php 7.4 pools, Let’s Encrypt, `/etc/dovecot/conf.d`, `/etc/exim4/conf.d`.
3. `do-release-upgrade` through to **26.04**. Expect Dovecot/Exim to be unhappy at 22.04 until step 4.
4. On 26.04: `sudo ./setup-mail.sh`. It refuses to run on 20.04, warns on 22.04/24.04 (Exim snippets OK, Dovecot 2.4 drop-in is not), backs up files it replaces, leaves `virtual/` and `dkim/` in place, migrates flat DKIM files.
5. Diff `/root/sharedservertools-backup-*` against anything you know you edited. Re-apply local tweaks using `dsearch` / Dovecot 2.4 names — do not paste 20.04 path expansions back.
6. Move PHP pools 7.4 → 8.5; reload FPM and nginx.
7. If Dovecot fails to start, look for leftover `mail_location` / `ssl_cert` in `10-*.conf`.
8. `update-exim4.conf && exim4 -bt you@your-virtual-domain` and `doveconf -n`.
9. Re-print DNS with `add-email-domain.sh` (selector is still the short hostname). MX/SPF/DKIM should stay valid if keys were copied.

`initial-setup.sh` on a host that already has years of nginx/php/mail drift will still rewrite nginx, php, fail2ban, and hosts from templates. Prefer `setup-mail.sh` plus manual web-stack fixes over a full `initial-setup.sh` replay.
