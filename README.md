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

## Version assumptions (September 2026)

| Component | Target |
| --- | --- |
| OS | Ubuntu 26.04 LTS (Resolute Raccoon) |
| Exim | 4.99, Ubuntu split config (`/etc/exim4/conf.d` + `update-exim4.conf`) |
| Dovecot | 2.4 (config syntax is not compatible with 2.3) |
| PHP | distro default via `php-fpm` (8.5 on 26.04) |
| SpamAssassin | 4.x `spamd` systemd unit |

Ubuntu 24.04 LTS can run the **Exim** half (taint-safe split config, Exim 4.97). Dovecot 2.4 drop-in settings will not load on 24.04's Dovecot 2.3; use 26.04 if you want IMAP/POP3 from these scripts.

# Installation

    sudo apt install -y git
    git clone https://github.com/JamesSwift/SharedServerTools.git
    sudo ./SharedServerTools/initial-setup.sh

`initial-setup.sh` asks whether to enable mail after the hostname TLS certificate exists. To add mail later on a web-only server:

    sudo ./SharedServerTools/setup-mail.sh

# Enabling mail on a server that was stuck off 22.04+

Mail was removed on 2022-05-02 (`3a5a388`) because Ubuntu 22.04 shipped Exim 4.95, which **rejects tainted data in file names**. The old virtual-domain and DKIM snippets used `$domain` / `$local_part` (and From: headers) directly in paths. Same-day attempts (`eaa8e9d`, `d0a1555`, `1bb9f1c`) mixed `_data` variables incorrectly and then the stack was stripped.

This restore keeps Ubuntu's split Exim layout and de-taints with `dsearch` (the approach documented in Exim 4.99 spec chapter 51):

1. Upgrade the host to Ubuntu 26.04 LTS (or install 26.04 fresh).
2. Clone this repo and run `sudo ./initial-setup.sh` (say yes to mail) **or** `sudo ./setup-mail.sh` if the web stack is already in place.
3. Existing `/etc/exim4/virtual/` alias files and `/etc/exim4/dkim/*/dkim.private` keys are reused if you copy them over; the paths did not change.
4. Publish the DKIM/SPF/DMARC records printed by `add-email-domain.sh` (re-run it for a domain to reprint DNS).
5. Point MX at this host. Submission is 587 (STARTTLS) and 465 (implicit TLS). IMAP/POP3 are 993/995 with TLS required.

What we did **not** bring back:

- Replacing Dovecot's entire `10-*.conf` files (those were Ubuntu 22.04 / Dovecot 2.3 copies and will not parse on 2.4). Overrides live in `conf.d/99-sharedservertools.conf`.
- Replacing Debian's `remote_smtp_smarthost` transport. `dc_eximconfig_configtype='internet'` uses stock `remote_smtp`, which already honours `DKIM_*` macros.
- `sa-exim` (not in Ubuntu 26.04). Spam is handled by Exim's `spam =` ACL against `spamd`.
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

There is no safe upgrade path from pre v0.1.0 versions. Pulling git master onto an old customized host may still surprise you. For mail: if you still have `/etc/exim4/virtual` and `/etc/exim4/dkim` from before May 2022, copy them aside, upgrade Ubuntu, run `setup-mail.sh`, then copy those directories back and `update-exim4.conf && systemctl restart exim4`.
