#!/bin/bash
# ===========================
# 3PROXY IPV6 PRO MAX (NOPASS)
# AUTO FIX ULIMIT + IPV6 + BUILD 3PROXY
# ===========================

set -e

echo "[+] PROXY PRO MAX — AUTO SETUP"

# ===========================
# 1) FIX ULIMIT VĨNH VIỄN
# ===========================
echo "[+] Fix ulimit system..."

cat <<EOF >> /etc/security/limits.conf
* soft nofile 262144
* hard nofile 262144
root soft nofile 262144
root hard nofile 262144
EOF

echo "session required pam_limits.so" >> /etc/pam.d/login || true

echo "fs.file-max = 262144" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

ulimit -n 262144

echo "[+] ulimit hiện tại: $(ulimit -n)"

# ===========================
# 2) CÀI GÓI CẦN THIẾT
# ===========================
echo "[+] Cài đặt gcc, make, wget..."
yum install -y epel-release >/dev/null 2>&1 || true
yum install -y gcc make wget tar unzip >/dev/null 2>&1

# ===========================
# 3) TẢI & BUILD 3PROXY
# ===========================

echo "[+] Tải và build 3proxy 0.8.6..."

cd /root
rm -rf 3proxy* >/dev/null 2>&1

wget -O 3proxy.tar.gz https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz
tar -xvf 3proxy.tar.gz >/dev/null
cd 3proxy-3proxy-0.8.6

make -f Makefile.Linux >/dev/null

mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
cp src/3proxy /usr/local/etc/3proxy/bin/

echo "[+] Cài 3proxy OK."

# ===========================
# 4) LẤY IP
# ===========================
iface=$(ip route get 1 | awk '{print $5; exit}')

IPV4=$(curl -4 -s icanhazip.com)
IPV6_FULL=$(curl -6 -s icanhazip.com)
IPV6_PREFIX=$(echo "$IPV6_FULL" | cut -d":" -f1-4)

echo "[+] Interface: $iface"
echo "[+] IPv4: $IPV4"
echo "[+] IPv6 prefix: $IPV6_PREFIX"

# ===========================
# 5) NHẬN BIẾN
# ===========================
MODE=${MODE:-nopass}
FIRST_PORT=${FIRST_PORT:-20000}
COUNT=${COUNT:-100}

LAST_PORT=$((FIRST_PORT + COUNT - 1))

WORKDIR="/home/duyanmmo"
mkdir -p $WORKDIR
cd $WORKDIR

echo "[+] Tạo $COUNT proxy từ port $FIRST_PORT → $LAST_PORT"
echo "[+] MODE = $MODE"

# ===========================
# 6) HÀM RANDOM IPV6
# ===========================
gen_ipv6() {
    printf "%s:%x:%x:%x:%x\n" "$IPV6_PREFIX" $RANDOM $RANDOM $RANDOM $RANDOM
}

# ===========================
# 7) TẠO DANH SÁCH PROXY
# ===========================
rm -f data.txt proxy.txt

echo "[+] Tạo danh sách IPv6..."

port=$FIRST_PORT
for i in $(seq 1 $COUNT); do
    ipv6=$(gen_ipv6)
    echo "$IPV4/$port/$ipv6" >> data.txt
    echo "$IPV4:$port" >> proxy.txt
    port=$((port + 1))
done

echo "[+] Đã tạo $COUNT proxy."

# ===========================
# 8) TẠO CONFIG 3PROXY
# ===========================
CONFIG="/usr/local/etc/3proxy/3proxy.cfg"

echo "[+] Tạo file config 3proxy..."

cat <<EOF > $CONFIG
daemon
nserver 1.1.1.1
nserver 8.8.8.8
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
maxconn 5000
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
EOF

while IFS=/ read -r ip port ipv6; do
cat <<EOF >> $CONFIG
proxy -6 -n -a -p$port -i$ip -e$ipv6
flush
EOF
done < data.txt

echo "[+] Config OK."

# ===========================
# 9) ADD IPV6 VÀ FIREWALL
# ===========================
echo "[+] Add IPv6 vào interface..."

while IFS=/ read -r ip port ipv6; do
    ip -6 addr add "$ipv6"/64 dev "$iface" || true
done < data.txt

echo "[+] Mở port firewall..."
for port in $(seq $FIRST_PORT $LAST_PORT); do
    iptables -I INPUT -p tcp --dport $port -j ACCEPT
done

# ===========================
# 10) START 3PROXY
# ===========================
echo "[+] Start 3proxy..."

pkill 3proxy || true
/usr/local/etc/3proxy/bin/3proxy $CONFIG &

echo "[+] PROXY TXT: $WORKDIR/proxy.txt"
echo "[+] HOÀN TẤT!"
