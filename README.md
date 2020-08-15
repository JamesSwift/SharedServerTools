# SharedServerTools
Interactive scripts to turn a fresh ubuntu 20.04 install into a manageable, secured, multi-domain web and email server.

These scripts perform common setup steps, including:
- setting up hostname and ip addresses
- installing fail2ban to monitor and block attacks
- running each website as a specified system user
- acquiring and installing SSL certificates for each domain
- hardening SSL parameters
- creating dkim key pairs to authenticate emails sent from the server
- setting up spamassassin
- defining exactly which email addresses a user can send mail "From: "

Don't worry, the scripts walk you through each change before it is made, nothing should break. After the initial setup, 
you should be able to install other software and modify configuration files without causing issues.

The scripts assume a basic knowledge of server configurations, and they assume you won't intentionally be trying to break 
anything. They are not meant to be exposed to end-users, and are not hardened for input sanitization.


# Installation
    sudo apt install -y git
    git clone https://github.com/JamesSwift/SharedServerTools.git
    sudo ./SharedServerTools/initial-setup.sh


# Upgrading
Sadly there is no safe upgrade path. I wrote this project for myself, and as my needs 
have changed I have changed the scripts without regard for other setups. If you pull 
the latest git master it will likely result in problems when you try to modify existing 
setups. Sorry.


# Email Addresses
This tool configures exim to deliver email to local user accounts in the usual unix way. 
For example james@server.mydomain.com will be delivered to local user james. However, you 
will likely wish a user to receive email for additional domains as well, for example 
`info@mysite.com` and `me@myothersite.com` should also be delivered to user james. 
This tool has made this possible by editing the files found in `/etc/exim4/virtual/`.

For example, for the above to work, you would edit the following files:

`/etc/exim4/virtual/myothersite.com`

    me : james@localhost

`/etc/exim4/virtual/mysite.com`

    info : james@localhost

If the file doesn't exist already, run `add-email-domain.sh` which will create it and 
also create the dkim files to sign outgoing messages.


# Spam Filtering
This tool sets up spamassassin for you, so that each message gets a spam score. If you 
wish to have spam put into a user's Spam folder automatically, add the following file 
as `~/.forward`:

    #   Exim filter   <<== do not edit or remove this line!
    if $h_X-SA-Status: matches "^Yes" then
        save $home/mail/Spam
        finish
    endif


# DKIM/DMARC
When you create a new website or add an email domain, a pair of DKIM keys are 
automatically created and all messages sent from that domain will be signed with them. 
At the time of creation some sample DNS entries are provided. If you wish to see them 
at a later point, simply run `add-email-domain.sh` again and it will output the existing 
DNS entries again for you.


# Default "From: " Header
If you send email via the server, you may wish the messages to come from an email address 
other than `user@server.mydomain.com`. You can of course set this manually each time, but to 
change the default address for a user, edit the `/etc/email-addresses` file. For example:

    user: me@myothersite.com
