# SharedServerTools v0.3.0
Interactive scripts to turn a fresh ubuntu 22.04 install into a manageable, secured, multi-domain web server.

These scripts perform common setup steps, including:
- setting up hostname and ip addresses
- installing fail2ban to monitor and block attacks
- running each website as a specified system user
- acquiring and installing SSL certificates for each domain
- hardening SSL parameters

Don't worry, the scripts walk you through each change before it is made, nothing should break. After the initial setup, 
you should be able to install other software and modify configuration files without causing issues.

The scripts assume a basic knowledge of server configurations, and they assume you won't intentionally be trying to break 
anything. They are not meant to be exposed to end-users, and are not hardened for input sanitization.


# Installation
    sudo apt install -y git
    git clone https://github.com/JamesSwift/SharedServerTools.git
    sudo ./SharedServerTools/initial-setup.sh


# Upgrading
Sadly there is no safe upgrade path from pre v0.1.0 versions to this one. I wrote this project 
for myself, and as my needs 
have changed I have changed the scripts without regard for other setups. If you pull 
the latest git master it will likely result in problems when you try to modify existing 
setups. Sorry.

