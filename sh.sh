#!/bin/bash
# Set the PATH to include common command directories
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
apt update -y
sudo apt install build-essential -y
wget https://raw.githubusercontent.com/khacnam/dev/main/squid-4.10.tar.gz
tar xzf squid-4.10.tar.gz
cd squid-4.10
./configure 'CXXFLAGS=-DMAXTCPLISTENPORTS=65000' --enable-ltdl-convenience
make && make install
chmod 777 /usr/local/squid/var/logs/
mkdir /var/spool/squid3
mkdir /etc/squid
echo "* - nofile 500000" >> /etc/security/limits.conf
rm -rf /etc/squid/squid.conf
cat <<EOF > /etc/squid/squid.conf
forwarded_for delete
via off
dns_v4_first off
acl to_ipv6 dst ipv6
access_log none
cache deny all
dns_nameservers 1.1.1.1
max_filedesc 65535
coredump_dir /var/spool/squid
acl QUERY urlpath_regex cgi-bin \?
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320
auth_param basic program /usr/local/squid/libexec/basic_ncsa_auth /etc/squid/squid.passwords
auth_param basic children 1024
auth_param basic realm Proxy
auth_param basic credentialsttl 2 hours
auth_param basic casesensitive off
acl password proxy_auth REQUIRED
include /etc/squid/ports.conf
http_access deny !to_ipv6
http_access allow password
http_access allow to_ipv6
http_access allow all
cache deny all
request_header_access follow_x_forwarded_for deny all
request_header_access X-Forwarded-For deny all
request_header_access Allow allow all
request_header_access Authorization allow all
request_header_access WWW-Authenticate allow all
request_header_access Proxy-Authorization allow all
request_header_access Proxy-Authenticate allow all
request_header_access Cache-Control allow all
request_header_access Transfer-Encoding allow all
request_header_access Content-Encoding allow all
request_header_access Content-Length allow all
request_header_access Content-Type allow all
request_header_access Date allow all
request_header_access Expires allow all
request_header_access Host allow all
request_header_access If-Modified-Since allow all
request_header_access Last-Modified allow all
request_header_access Location allow all
request_header_access Pragma allow all
request_header_access Accept allow all
request_header_access Accept-Charset allow all
request_header_access Accept-Encoding allow all
request_header_access Accept-Language allow all
request_header_access Content-Language allow all
request_header_access Mime-Version allow all
request_header_access Retry-After allow all
request_header_access Title allow all
request_header_access Content-Encoding allow all
request_header_access Content-Length allow all
request_header_access Content-Type allow all
request_header_access Date allow all
request_header_access Expires allow all
request_header_access Host allow all
request_header_access If-Modified-Since allow all
request_header_access Last-Modified allow all
request_header_access Location allow all
request_header_access Pragma allow all
request_header_access Accept allow all
request_header_access Accept-Charset allow all
request_header_access Accept-Encoding allow all
request_header_access Accept-Language allow all
request_header_access Content-Language allow all
request_header_access Mime-Version allow all
request_header_access Retry-After allow all
request_header_access Title allow all
request_header_access Connection allow all
request_header_access Proxy-Connection allow all
request_header_access User-Agent allow all
request_header_access Referer allow all
request_header_access Cookie allow all
request_header_access Set-Cookie allow all
request_header_access Content-Disposition allow all
request_header_access Range allow all
request_header_access Accept-Ranges allow all
request_header_access Vary allow all
request_header_access Etag allow all
request_header_access If-None-Match allow all
request_header_replace Referer example.com
request_header_access All deny all
request_header_access From deny all
request_header_access Referer deny all
request_header_access User-Agent deny all
reply_header_access Via deny all
reply_header_access Server deny all
reply_header_access WWW-Authenticate deny all
reply_header_access Link deny all
reply_header_access Allow allow all
reply_header_access Proxy-Authenticate allow all
reply_header_access Cache-Control allow all
reply_header_access Content-Encoding allow all
reply_header_access Content-Length allow all
reply_header_access Content-Type allow all
reply_header_access Date allow all
reply_header_access Expires allow all
reply_header_access Last-Modified allow all
reply_header_access Location allow all
reply_header_access Pragma allow all
reply_header_access Content-Language allow all
reply_header_access Retry-After allow all
reply_header_access Title allow all
reply_header_access Content-Disposition allow all
reply_header_access Connection allow all
reply_header_access All deny all
shutdown_lifetime 3 seconds
include /etc/squid/outgoing.conf
EOF
cd 
wget https://raw.githubusercontent.com/khacnam/dev/main/setup.sh
chmod 0755 /root/setup.sh
./setup.sh
