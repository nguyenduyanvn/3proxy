#!/bin/bash
# ===================================================
# 3PROXY IPV6 PRO MAX - NO PASSWORD
# Bản FIX FULL tối ưu cho Almalinux / Rocky / CentOS 8
# ===================================================

clear
echo "==> Cài đặt các gói cần thiết..."
yum install -y epel-release >/dev/null 2>&1
yum install -y gcc make wget tar net-tools zip >/dev/null 2>&1

# Lấy tên interface tự động
IFACE=$(ip -o -4 route show to default | awk '{print $5}')
echo "==> Interface: $IFACE"

# Lấy IPv4 & IPv6 prefix
IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-7 -d':')

echo "IPv4 = $IP4"
echo "IPv6 prefix = $IP6"

WORKDIR="/home/duyanmmo"
mkdir -p $WORKDIR
cd $WORKDIR

FIRST_PORT=$FIRST_PORT
COUNT=$COUNT
LAST_PORT=$((FIRST_PORT + COUNT - 1))

echo "==> Sẽ tạo $COUNT proxy từ port $FIRST_PORT đến $LAST_PORT"

# Generate random IPv6
hex=(0 1 2 3 4 5 6 7 8 9 a b c d e f)
gen_ipv6() {
    echo "${hex[$RANDOM % 16]}${hex[$RANDOM % 16]}${hex[$RANDOM % 16]}${hex[$RANDOM % 16]}"
}

gen_data() {
    for ((port=$FIRST_PORT; port<=$LAST_PORT; port++)); do
        echo "//$IP4/$port/$IP6:$(gen_ipv6)"
    done
}

gen_data > data.txt

echo "==> Tải & build 3proxy..."
cd $WORKDIR
wget -q https://github.com/nguyenduyanvn/3proxy/raw/refs/heads/main/3proxy-0.9.4.tar.gz
tar -xzf 3proxy-0.9.4.tar.gz
cd 3proxy-0.9.4
make -f Makefile.Linux >/dev/null 2>&1

mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
cp src/3proxy /usr/local/etc/3proxy/bin/

echo "==> Tạo config 3proxy..."
cat <<EOF >/usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 2000

nserver 1.1.1.1
nserver 8.8.8.8
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844

nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush

$(awk -F "/" '{print "proxy -6 -n -a -p"$4" -i"$1" -e"$3"\nflush\n"}' OFS="/" data.txt)
EOF

echo "==> Add IPv6 vào interface..."
awk -F "/" '{print "ip -6 addr add "$3"/64 dev '"$IFACE"'" }' data.txt > boot_ipv6.sh
bash boot_ipv6.sh

echo "==> Mở port firewall..."
awk -F "/" '{print "iptables -I INPUT -p tcp --dport "$2" -j ACCEPT"}' data.txt > boot_fw.sh
bash boot_fw.sh

echo "==> Xuất proxy.txt..."
awk -F "/" '{print $1":"$2}' data.txt > proxy.txt

echo "==> Khởi chạy 3proxy..."
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &

echo "======================================="
echo " DONE! Proxy list: $WORKDIR/proxy.txt"
echo " Format: ip:port"
echo "======================================="
