#!/bin/bash
# ============================
# 3PROXY FULL FIX FOR ALMALINUX 8 / ROCKY 8
# NO PASSWORD VERSION
# ============================

clear
echo "==> Cài đặt dependencies..."
yum install -y epel-release >/dev/null 2>&1
yum install -y gcc make wget tar net-tools unzip pcre-devel openssl-devel glibc-static >/dev/null 2>&1

# Detect interface
IFACE=$(ip route get 1 | awk '{print $5; exit}')
echo "Interface: $IFACE"

IP4=$(curl -4 -s icanhazip.com)
IP6PREFIX=$(curl -6 -s icanhazip.com | cut -f1-7 -d ':')

WORKDIR="/home/duyanmmo"
mkdir -p $WORKDIR
cd $WORKDIR

echo "IPv4 = $IP4"
echo "IPv6 prefix = $IP6PREFIX"

FIRST_PORT=$FIRST_PORT
COUNT=$COUNT
LAST_PORT=$((FIRST_PORT + COUNT - 1))

# Generate IPv6
hex=(0 1 2 3 4 5 6 7 8 9 a b c d e f)
gen_ipv6() {
    printf "%s%s%s%s" "${hex[$RANDOM%16]}" "${hex[$RANDOM%16]}" "${hex[$RANDOM%16]}" "${hex[$RANDOM%16]}"
}

echo "==> Sinh danh sách proxy..."
rm -f data.txt
for ((port=$FIRST_PORT; port<=$LAST_PORT; port++)); do
    FULL6="$IP6PREFIX:$(gen_ipv6)"
    echo "$IP4:$port:$FULL6" >> data.txt
done

echo "==> Cài 3proxy..."
cd $WORKDIR
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
nserver 2001:4860:4860::8888

nscache 65536
setgid 65535
setuid 65535
flush
EOF

while IFS=":" read -r IPV4 PORT IPV6; do
cat <<EOF >> /usr/local/etc/3proxy/3proxy.cfg
proxy -6 -n -a -p$PORT -i$IPV4 -e$IPV6
flush
EOF
done < data.txt

echo "==> Add IPv6..."
while IFS=":" read -r IPV4 PORT IPV6; do
    ip -6 addr add "$IPV6/64" dev "$IFACE"
done < data.txt

echo "==> Mở port firewall..."
while IFS=":" read -r IPV4 PORT IPV6; do
    iptables -I INPUT -p tcp --dport "$PORT" -j ACCEPT
done < data.txt

echo "==> Xuất proxy list..."
awk -F ":" '{print $1":"$2}' data.txt > proxy.txt

echo "==> Start 3proxy..."
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &

echo "==============================="
echo " DONE — proxy.txt đã tạo xong!"
echo "==============================="
