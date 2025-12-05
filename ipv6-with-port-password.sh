#!/bin/bash
set -e

echo "==> Cài đặt dependencies..."
yum install -y wget curl unzip iproute iptables-services >/dev/null 2>&1 || true
apt install -y wget curl unzip iproute2 iptables >/dev/null 2>&1 || true

WORKDIR="/home/duyanmmo"
mkdir -p $WORKDIR
cd $WORKDIR

echo "==> Lấy IPv4 & IPv6 prefix..."
IP4=$(curl -4 -s icanhazip.com)
IP6_PREFIX=$(curl -6 -s icanhazip.com | sed 's/:[0-9a-fA-F]\{1,4\}$//')

echo "IPv4 = $IP4"
echo "IPv6 prefix = $IP6_PREFIX"

echo "==> Tải 3proxy binary..."
wget -q -O 3proxy_bin.zip "https://raw.githubusercontent.com/duyanmmo/3proxy_binary/main/3proxy_bin.zip"
unzip -o 3proxy_bin.zip -d 3proxy_bin >/dev/null

mkdir -p /usr/local/etc/3proxy/bin
cp 3proxy_bin/3proxy /usr/local/etc/3proxy/bin/
chmod +x /usr/local/etc/3proxy/bin/3proxy

echo "==> Tạo danh sách proxy..."
rm -f data.txt proxy.txt

START_PORT=${FIRST_PORT}
COUNT=${COUNT}
USER=${USER}
PASS=${PASS}

gen_ipv6(){
    HEX=$(printf "%04x" $(( RANDOM % 65535 )))
    echo "${IP6_PREFIX}:${HEX}"
}

for ((i=0; i<$COUNT; i++)); do
    PORT=$(( START_PORT + i ))
    IPV6=$(gen_ipv6)
    echo "$IP4:$PORT/$IPV6" >> data.txt
    echo "$IP4:$PORT:$USER:$PASS" >> proxy.txt
done

echo "==> Add IPv6 vào interface..."
IFACE=$(ip route get 1 | awk '{print $5; exit}')
while read line; do
    IPV6=$(echo $line | cut -d'/' -f2)
    ip -6 addr add $IPV6/64 dev $IFACE || true
done < data.txt

echo "==> Mở port firewall..."
while read line; do
    PORT=$(echo $line | cut -d'/' -f1 | cut -d':' -f2)
    iptables -I INPUT -p tcp --dport $PORT -j ACCEPT || true
done < data.txt

echo "==> Tạo config 3proxy..."
cat <<EOF >/usr/local/etc/3proxy/3proxy.cfg
daemon
nserver 1.1.1.1
nserver 8.8.8.8
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535

users $USER:CL:$PASS
auth strong

flush

$(while read line; do
    IP4=$(echo $line | cut -d'/' -f1 | cut -d':' -f1)
    PORT=$(echo $line | cut -d'/' -f1 | cut -d':' -f2)
    IPV6=$(echo $line | cut -d'/' -f2)
    echo "proxy -6 -n -a -p$PORT -i$IP4 -e$IPV6"
done < data.txt)
EOF

echo "==> Khởi chạy 3proxy..."
pkill 3proxy || true
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &

echo "========================================"
echo " DONE! Proxy list: $WORKDIR/proxy.txt"
echo " Format: ip:port:user:pass"
echo "========================================"
