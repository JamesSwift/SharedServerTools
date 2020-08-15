# SharedServerTools
Interactive scripts to turn a fresh ubuntu 20.04 install into a manageable, secured, multi-domain web server.

These scripts perform the most common setup steps, including:
- setting up hostname and ip addresses
- running fail2ban to monitor and block ssh attacks
- hardening SSL parameters
- aquiring and installing SSL certificates for each domain
- creating dkim key pairs to authenticate emails sent from the server
- running each domain as a seperate system user

Don't worry, the scripts walk you through each change before it is made, nothing should break. After the inital setup, you should be able to install other software and modify configuration files without causing issues.

The scripts assume a basic knowledge of server configurations, and they assume you won't intentionally be trying to break anything. They are not meant to be exposed to end-users, and are not hardened for input sanitization.


# Installation
    sudo apt install -y git
    git clone https://github.com/JamesSwift/SharedServerTools.git
    sudo ./SharedServerTools/initial-setup.sh
