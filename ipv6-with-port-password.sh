#!/bin/bash
# ============================
# 3PROXY FULL FIX FOR ALMALINUX 8 / ROCKY 8
# WITH USER/PASS
# ============================

clear
echo "==> Cài dependencies..."
yum install -y epel-release >/dev/null 2>&1
yum install -y gcc make wget tar net-tools unzip pcre-devel openssl-devel glibc-static >/dev/null 2>&1

IFACE=$(ip route get 1 | awk '{print $5; exit}')
echo "Interface: $IFACE"

IP4=$(curl -4 -s icanhazip.com)
IP6PREFIX=$(curl -6 -s icanhazip.com | cut -f1-7 -d ':')

WORKDIR="/home/duyanmmo"
mkdir -p $WORKDIR
cd $WORKDIR

FIRST_PORT=$FIRST_PORT
COUNT=$COUNT
LAST_PORT=$((FIRST_PORT + COUNT - 1))

USERPASS="duyan:123456"

hex=(0 1 2 3 4 5 6 7 8 9 a b c d e f)

gen_ipv6(){ printf "%s%s%s%s" "${hex[$RANDOM%16]}" "${hex[$RANDOM%16]}" "${hex[$RANDOM%16]}" "${hex[$RANDOM%16]}" ; }

rm -f data.txt
for ((port=$FIRST_PORT; port<=$LAST_PORT; port++)); do
    echo "$IP4:$port:$IP6PREFIX:$(gen_ipv6)" >> data.txt
done

echo "==> Build 3proxy..."
wget -q https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.zip
unzip -q 0.9.4.zip
cd 3proxy-0.9.4
make -f Makefile.Linux >/dev/null 2>&1

mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
cp src/3proxy /usr/local/etc/3proxy/bin/

echo "==> Tạo config..."
cat <<EOF >/usr/local/etc/3proxy/3proxy.cfg
daemon
auth strong
users $USERPASS
allow $USERPASS
maxconn 2000

nserver 1.1.1.1
nserver 8.8.8.8

nscache 65536
flush
EOF

while IFS=":" read -r IPV4 PORT P6PREFIX RANDSEG; do
    IPV6="$P6PREFIX:$RANDSEG"
cat <<EOF >> /usr/local/etc/3proxy/3proxy.cfg
proxy -6 -n -a -p$PORT -i$IPV4 -e$IPV6
flush
EOF
done < data.txt

echo "==> Add IPv6..."
while IFS=":" read -r IPV4 PORT P6PREFIX RANDSEG; do
    ip -6 addr add "$P6PREFIX:$RANDSEG/64" dev "$IFACE"
done < data.txt

echo "==> Firewall..."
while IFS=":" read -r IPV4 PORT P6PREFIX RANDSEG; do
    iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
done < data.txt

echo "==> Xuất danh sách..."
awk -F ":" -v u="$USERPASS" '{print $1":"$2":"u}' data.txt > proxy.txt

echo "==> START 3proxy..."
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &

echo "==============================="
echo " DONE — proxy.txt đã tạo xong!"
echo "==============================="
