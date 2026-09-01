# SharedServerTools v0.4.0

Interactive scripts to turn a fresh **Ubuntu 26.04 LTS** install into a manageable, secured, multi-domain web and email server.

These scripts perform common setup steps, including:

- setting up hostname and IP addresses
- installing fail2ban to monitor and block attacks
- running each website as a specified system user
- acquiring and installing SSL certificates for each domain
- hardening SSL parameters
- optional mail: Exim4 (MTA), Dovecot (IMAP/POP3), SpamAssassin
- creating DKIM key pairs to authenticate emails sent from the server
- easily adding email aliases per domain
- defining which addresses an SMTP-authenticated user can send `From:`

Don't worry, the scripts walk you through each change before it is made, nothing should break. After the initial setup, you should be able to install other software and modify configuration files without causing issues.

The scripts assume a basic knowledge of server configurations, and they assume you won't intentionally be trying to break anything. They are not meant to be exposed to end-users, and are not hardened for input sanitization.

Interactive scripts (`initial-setup.sh`, `add-website.sh`, `add-email-domain.sh`, `remove-website.sh`) do **not** use `set -e`: a failed optional command would abort in the middle of a prompt. They still exit with a clear `ERROR:` on empty input and on nginx/php/certbot failures. Non-interactive tools (`setup-mail.sh`, backup scripts) use `set -euo pipefail`.

## Isolation (cheap, not multi-tenant)

Everyone on the box is trusted (you / your own businesses). There are no containers, VMs, or SELinux policies. Isolation is ordinary Unix ownership:

- One system user per site owner. PHP-FPM runs as that user. `add-website.sh` creates the account if needed.
- Mail is that user's `~/Maildir` (directory 0700, files 0600). Virtual domains are alias files (`info : james@localhost`), not a second identity system and not a shared `vmail` Unix user.
- Site-owner homes are mode **0750**. nginx (`www-data`) is added to the site user's group so it can read `~/www`. Other site users cannot browse `~/Maildir`.
- `/etc/exim4/virtual/` and `/etc/exim4/dkim/` are `root:Debian-exim` with directory 750 / private keys 640.

Remaining gaps (accepted for now; decide later if they matter):

- Exim and Dovecot remain **shared daemons**. Per-user data is isolated; the processes are not.
- PHP `mail()` / `/usr/sbin/sendmail` is not covered by the SMTP AUTH `From:` ACL (`acl_check_sender`). A site user can set an arbitrary envelope sender on local injection.
- `www-data` is in every site user's group (required for nginx). Group-readable files in any site home are readable by the web server.
- Editing `/etc/exim4/virtual/<domain>` as root can alias mail to any local user.
- No mailbox quotas.

## Version assumptions (September 2026)

| | From (production SST boxes) | To (this repo) |
| --- | --- | --- |
| OS | **Ubuntu 20.04 LTS** (Focal), often with local edits on top of SST | **Ubuntu 26.04 LTS** (Resolute) |
| Exim | 4.93 — tainted path expansions still work | 4.99 split config + `dsearch` de-taint |
| Dovecot | 2.3 (`mail_location`, `ssl_cert = <…`) | **2.4** (new setting names; old `10-*.conf` copies will not parse) |
| PHP | 7.4 (`php7.4-fpm`) | distro `php-fpm` (**8.5** on 26.04) |
| SpamAssassin | 3.4, `spamassassin.service`, optional `sa-exim` | 4.x **`spamd`**, Exim `spam =` ACL |

Ubuntu 24.04 can load the **Exim** snippets (4.97, same taint rules). Dovecot 2.4 drop-in settings will not run on 24.04’s Dovecot 2.3. `setup-mail.sh` **refuses to run on 20.04** so it cannot clobber a working 4.93 stack with 2.4 Dovecot files.

Greenfield: install 26.04 and run `initial-setup.sh`. Existing 20.04 host: **`docs/upgrade-from-ubuntu-20.04.md`** — that is the real path for a box with years of local drift.

# Installation

    sudo apt install -y git
    git clone https://github.com/JamesSwift/SharedServerTools.git
    sudo ./SharedServerTools/initial-setup.sh

`initial-setup.sh` asks whether to enable mail after the hostname TLS certificate exists. To add mail later on a web-only server:

    sudo ./SharedServerTools/setup-mail.sh

# Enabling mail / moving off Ubuntu 20.04

Mail still works on 20.04 because Focal’s Exim 4.93 does not reject tainted filenames. Ubuntu 22.04 shipped Exim 4.95, which **does**. That is why SST mail was deleted on 2022-05-02 (`3a5a388`) after same-day `_data` experiments failed, and why a production host stayed on 20.04 with local tweaks.

This restore is built for **26.04 after that upgrade**, not as a patch you apply on 20.04:

1. On the 20.04 box: `sudo ./tools/audit-mail-upgrade.sh | tee /root/sst-mail-audit.txt`
2. Read **[docs/upgrade-from-ubuntu-20.04.md](docs/upgrade-from-ubuntu-20.04.md)** — what to copy, which files SST will replace, which old `10-*.conf` / smarthost / `spamassassin` files you must merge by hand, and behaviour changes (`tls_on_connect` on 587, `MAIN_FORCE_SENDER`, PHP pools).
3. Upgrade Ubuntu to 26.04 LTS (20.04 → 22.04 → 24.04 → 26.04). Expect mail to break at 22.04 until the next step.
4. `sudo ./setup-mail.sh` (or `initial-setup.sh` only on a **clean** 26.04 disk). Replaced files go to `/root/sharedservertools-backup-<timestamp>/`. `/etc/exim4/virtual/` and `/etc/exim4/dkim/` are left in place.
5. Re-apply local diffs from the backup using `dsearch` / Dovecot 2.4 names. Do not paste 20.04 `$domain` paths back.
6. Reprint DKIM/SPF/DMARC with `add-email-domain.sh`. Submission: 587 STARTTLS, 465 implicit TLS. IMAP/POP3: 993/995.

What we did **not** bring back:

- Replacing Dovecot’s entire `10-*.conf` files (20.04/22.04 SST copies). Overrides live in `conf.d/99-sharedservertools.conf`.
- Replacing Debian’s `remote_smtp_smarthost` transport. `internet` uses stock `remote_smtp`, which already honours `DKIM_*`.
- `sa-exim` (not in Ubuntu 26.04). Spam is Exim’s `spam =` ACL against `spamd`.
- `dovecot-antispam` (not in the 2.4 package set).

# Email addresses

Exim delivers to local Unix accounts in the usual way (`james@server.example.com` → user `james`). Extra domains are mapped in `/etc/exim4/virtual/<domain>`:

`/etc/exim4/virtual/mysite.com`

    info : james@localhost

If the file does not exist, run `add-email-domain.sh` (or `add-website.sh` when mail is enabled). That also creates DKIM keys.

# Spam filtering

Each message under 500k is scored by SpamAssassin. High-confidence spam is rejected at SMTP time (`X-SA-Status` is added from score 5.0; reject at 7.0). To file remaining spam into a Maildir folder, put this in `~/.forward`:

    #   Exim filter   <<== do not edit or remove this line!
    if $h_X-SA-Status: matches "^Yes" then
        save $home/Maildir/.Spam
        finish
    endif

# DKIM / DMARC

When you create a website (mail enabled) or add an email domain, a DKIM key is created under `/etc/exim4/dkim/<domain>/`. The selector is the server's short hostname. Re-run `add-email-domain.sh` to print the TXT records again.

# Default `From:` header

Local submissions (PHP `mail()`, `/usr/sbin/sendmail`) may set their own envelope sender. To change the default rewrite for a Unix user, edit `/etc/email-addresses`:

    user: me@myothersite.com

SMTP AUTH users may only send as addresses listed for them in `/etc/exim4/virtual/` (see `acl_check_sender`).

# Upgrading

There is no automatic upgrade from pre-v0.1.0, and **there is no safe “git pull and re-run initial-setup.sh” on a 20.04 host with local drift**. `initial-setup.sh` still rewrites nginx/php/fail2ban from templates.

- Clean 26.04: `initial-setup.sh`.
- 20.04 production SST + local mods: `docs/upgrade-from-ubuntu-20.04.md` and `tools/audit-mail-upgrade.sh`.
- 26.04 that already has the web stack: `setup-mail.sh` only.
