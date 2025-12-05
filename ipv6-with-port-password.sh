#!/bin/bash
# ==========================================
# 3PROXY IPV6 PRO MAX - WITH USER/PASS
# Dùng 3proxy-0.9.4.tar.gz từ GitHub DUYAN
# ==========================================

set -e

echo "==> Cài đặt dependencies..."
yum install -y epel-release >/dev/null 2>&1 || true
yum install -y gcc make wget tar net-tools pcre-devel openssl-devel >/dev/null 2>&1 || true

apt update >/dev/null 2>&1 || true
apt install -y gcc make wget tar net-tools >/dev/null 2>&1 || true

WORKDIR="/home/duyanmmo"
WORKDATA="$WORKDIR/data.txt"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "==> Lấy IPv4 & IPv6..."
IP4=$(curl -4 -s icanhazip.com)
IP6_FULL=$(curl -6 -s icanhazip.com)

# Lấy prefix /64 bằng cách giữ 4 block đầu
IP6_PREFIX=$(echo "$IP6_FULL" | cut -d':' -f1-4)

echo "IPv4 = $IP4"
echo "IPv6 full = $IP6_FULL"
echo "IPv6 prefix dùng để random = $IP6_PREFIX"

FIRST_PORT=${FIRST_PORT}
COUNT=${COUNT}
USER=${USER}
PASS=${PASS}

LAST_PORT=$((FIRST_PORT + COUNT - 1))

echo "==> Tạo $COUNT proxy từ port $FIRST_PORT đến $LAST_PORT"

echo "==> Sinh file data.txt..."
rm -f "$WORKDATA"

hex=(0 1 2 3 4 5 6 7 8 9 a b c d e f)

gen_block() {
    echo "${hex[$RANDOM % 16]}${hex[$RANDOM % 16]}${hex[$RANDOM % 16]}${hex[$RANDOM % 16]}"
}

gen_ipv6() {
    echo "$IP6_PREFIX:$(gen_block):$(gen_block):$(gen_block):$(gen_block)"
}

for ((port=$FIRST_PORT; port<=$LAST_PORT; port++)); do
    IPV6=$(gen_ipv6)
    # format: ipv4/port/ipv6
    echo "$IP4/$port/$IPV6" >> "$WORKDATA"
done

echo "==> Tải 3proxy từ link DUYAN..."
cd "$WORKDIR"
rm -rf 3proxy-0.9.4 3proxy-0.9.4.tar.gz

wget -q -O 3proxy-0.9.4.tar.gz "https://github.com/nguyenduyanvn/3proxy/raw/refs/heads/main/3proxy-0.9.4.tar.gz"
tar -xzf 3proxy-0.9.4.tar.gz

cd 3proxy-0.9.4
echo "==> Build 3proxy..."
make -f Makefile.Linux >/dev/null 2>&1

mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
cp src/3proxy /usr/local/etc/3proxy/bin/
chmod +x /usr/local/etc/3proxy/bin/3proxy

echo "==> Tạo config 3proxy..."
cat <<EOF >/usr/local/etc/3proxy/3proxy.cfg
daemon
auth strong
users $USER:CL:$PASS
allow $USER
maxconn 2000

nserver 1.1.1.1
nserver 8.8.8.8
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844

nscache 65536
setgid 65535
setuid 65535

flush
EOF

# Append proxy rules
while IFS="/" read -r IP PORT IPV6; do
cat <<EOF >> /usr/local/etc/3proxy/3proxy.cfg
proxy -6 -n -a -p$PORT -i$IP -e$IPV6
flush
EOF
done < "$WORKDATA"

echo "==> Add IPv6 vào interface..."
IFACE=$(ip route get 1 | awk '{print $5; exit}')

while IFS="/" read -r IP PORT IPV6; do
    ip -6 addr add "$IPV6/64" dev "$IFACE" || true
done < "$WORKDATA"

echo "==> Mở port firewall..."
while IFS="/" read -r IP PORT IPV6; do
    iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT || true
done < "$WORKDATA"

echo "==> Xuất proxy.txt..."
awk -F "/" -v u="$USER" -v p="$PASS" '{print $1":"$2":"u":"p}' "$WORKDATA" > "$WORKDIR/proxy.txt"

echo "==> Khởi chạy 3proxy..."
pkill 3proxy || true
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &

echo "========================================"
echo " DONE! Proxy list: $WORKDIR/proxy.txt"
echo " Format: ip:port:user:pass"
echo "========================================"
