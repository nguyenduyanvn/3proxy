#!/bin/bash

############################################################
# Squid Proxy Installer
# Author: Yujin Boby
# Email: admin@serverOk.in
# Github: https://github.com/serverok/squid-proxy-installer/
# Web: https://serverok.in/squid
# If you need professional assistance, reach out to
# https://serverok.in/contact
############################################################

if [ `whoami` != root ]; then
	echo "ERROR: You need to run the script as user root or add sudo before command."
	exit 1
fi

/usr/bin/wget -q --no-check-certificate -O /usr/local/bin/sok-find-os https://raw.githubusercontent.com/serverok/squid-proxy-installer/master/sok-find-os.sh > /dev/null 2>&1
chmod 755 /usr/local/bin/sok-find-os

/usr/bin/wget -q --no-check-certificate -O /usr/local/bin/squid-uninstall https://raw.githubusercontent.com/serverok/squid-proxy-installer/master/squid-uninstall.sh > /dev/null 2>&1
chmod 755 /usr/local/bin/squid-uninstall

if [[ -d /etc/squid/ || -d /etc/squid3/ ]]; then
    echo "Squid Proxy already installed. If you want to reinstall, first uninstall squid proxy by running command: squid-uninstall"
    exit 1
fi

if [ ! -f /usr/local/bin/sok-find-os ]; then
    echo "/usr/local/bin/sok-find-os not found"
    exit 1
fi

SOK_OS=$(/usr/local/bin/sok-find-os)

if [ $SOK_OS == "ERROR" ]; then
    echo "OS NOT SUPPORTED.\n"
    echo "Contact https://serverok.in/contact to add support for your OS."
    exit 1;
fi

if [ $SOK_OS == "ubuntu2204" ] || [ $SOK_OS == "ubuntu2004" ] || [ $SOK_OS == "ubuntu1804" ] || [ $SOK_OS == "ubuntu1604" ] || [ $SOK_OS == "ubuntu1404" ]; then
    /usr/bin/apt update > /dev/null 2>&1
    /usr/bin/apt -y install squid > /dev/null 2>&1
    mv /etc/squid/squid.conf /etc/squid/squid.conf.bak
    touch /etc/squid/blacklist.acl
    systemctl enable squid
    systemctl restart squid
elif [ $SOK_OS == "debian8" ] || [ $SOK_OS == "debian9" ] || [ $SOK_OS == "debian10" ] || [ $SOK_OS == "debian11" ] || [ $SOK_OS == "debian12" ]; then
    /usr/bin/apt update > /dev/null 2>&1
    /usr/bin/apt -y install squid > /dev/null 2>&1
    mv /etc/squid/squid.conf /etc/squid/squid.conf.bak
    touch /etc/squid/blacklist.acl
    systemctl enable squid
    systemctl restart squid
elif [ $SOK_OS == "centos7" ] || [ $SOK_OS == "centos8" ] || [ $SOK_OS == "almalinux8" ] || [ $SOK_OS == "almalinux9" ] || [ $SOK_OS == "centos8s" ] || [ $SOK_OS == "centos9" ]; then
    yum install squid -y
    mv /etc/squid/squid.conf /etc/squid/squid.conf.bak
    touch /etc/squid/blacklist.acl
    systemctl enable squid
    systemctl restart squid
fi

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${NC}"
echo -e "${GREEN}Thank you for using ServerOk Squid Proxy Installer.${NC}"
echo
echo -e "${CYAN}To change squid proxy port, see ${GREEN}https://serverok.in/how-to-change-port-of-squid-proxy-server${NC}"
echo -e "${NC}"
