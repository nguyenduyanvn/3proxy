#!/bin/bash
set -e

echo "==> Cài dependencies..."
yum install -y epel-release >/dev/null 2>&1
yum install -y gcc make wget tar unzip net-tools pcre-devel openssl-devel glibc-static >/dev/null 2>&1

IFACE=$(ip route get 1 | awk '{print $5; exit}')
IP4=$(curl -4 -s icanhazip.com)
PREFIX=$(curl -6 -s icanhazip.com | cut -f1-4 -d ':')

echo "Interface: $IFACE"
echo "IPv4: $IP4"
echo "IPv6 Prefix: $PREFIX"

WORKDIR="/home/duyanmmo"
mkdir -p $WORKDIR
cd $WORKDIR

FIRST=$FIRST_PORT
COUNT=$COUNT
LAST=$((FIRST + COUNT - 1))

echo "==> Sinh data.txt..."
rm -f data.txt

hex=(0 1 2 3 4 5 6 7 8 9 a b c d e f)

gen6(){ printf "%s%s%s%s" "${hex[$RANDOM%16]}" "${hex[$RANDOM%16]}" "${hex[$RANDOM%16]}" "${hex[$RANDOM%16]}"; }

for ((p=$FIRST; p<=$LAST; p++)); do
    IPV6="$PREFIX:$(gen6):$(gen6):$(gen6):$(gen6)"
    echo "$IP4:$p:$IPV6" >> data.txt
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
maxconn 2000
nserver 1.1.1.1
nserver 8.8.8.8
flush
EOF

while IFS=":" read -r IP PORT V6; do
cat <<EOF >>/usr/local/etc/3proxy/3proxy.cfg
proxy -6 -n -a -p$PORT -i$IP -e$V6
flush
EOF
done < data.txt

echo "==> Add IPv6..."
while IFS=":" read -r IP PORT V6; do
    ip -6 addr add "$V6/64" dev "$IFACE" || true
done < data.txt

echo "==> Firewall..."
while IFS=":" read -r IP PORT V6; do
    iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
done < data.txt

echo "==> Xuất proxy.txt..."
awk -F ":" '{print $1":"$2}' data.txt > proxy.txt

echo "==> Start 3proxy..."
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &

echo "DONE — proxy.txt đã tạo xong!"
