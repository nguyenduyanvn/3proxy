#!/bin/bash
# taoproxyipv6.sh – PRO MAX – IPv6 NOPASS (3proxy 0.8.6 stable)

set -e
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

WORKDIR="/home/duyanmmo"
mkdir -p $WORKDIR
WORKDATA="$WORKDIR/data.txt"

log() { echo "[*] $*"; }
ok() { echo "[+] $*"; }
err() { echo "[!] $*" >&2; }

# ========== RANDOM IPv6 ==========
random_hex4() {
    printf "%x%x%x%x" $((RANDOM%16)) $((RANDOM%16)) $((RANDOM%16)) $((RANDOM%16))
}

gen_ipv6() {
    printf "%s:%s:%s:%s:%s\n" "$IP6_PREFIX" "$(random_hex4)" "$(random_hex4)" "$(random_hex4)" "$(random_hex4)"
}

# ========== CÀI ĐẶT GÓI ==========
install_deps() {
    ok "Cài đặt gcc, make, wget, curl..."
    yum install -y gcc make wget curl net-tools >/dev/null 2>&1 || true
}

# ========== CÀI 3PROXY ==========
install_3proxy() {
    if [ -x /usr/local/etc/3proxy/bin/3proxy ]; then
        ok "3proxy đã tồn tại — bỏ qua bước cài."
        return
    fi

    ok "Tải & build 3proxy 0.8.6..."
    cd /root
    rm -rf 3proxy-* 2>/dev/null || true

    wget -q https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz
    tar -xzf 3proxy-0.8.6.tar.gz
    cd 3proxy-3proxy-0.8.6

    make -f Makefile.Linux >/dev/null

    mkdir -p /usr/local/etc/3proxy/bin /usr/local/etc/3proxy/logs /usr/local/etc/3proxy/stat
    cp src/3proxy /usr/local/etc/3proxy/bin/
    chmod +x /usr/local/etc/3proxy/bin/3proxy

    ok "Cài đặt 3proxy thành công."
}

# ========== TẠO FILE DATA ==========
gen_data() {
    ok "Sinh danh sách proxy..."
    : > $WORKDATA

    p=$FIRST_PORT
    while [ $p -le $LAST_PORT ]; do
        ipv6=$(gen_ipv6)
        echo "//$IP4/$p/$ipv6" >> $WORKDATA
        p=$((p+1))
    done

    ok "Đã sinh $(wc -l < $WORKDATA) proxy."
}

# ========== CONFIG 3PROXY ==========
gen_config() {
    ok "Tạo config 3proxy..."
cat >/usr/local/etc/3proxy/3proxy.cfg <<EOF
daemon
maxconn 2000
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456
flush
EOF

    awk -F "/" -v IFACE="$IFACE" '
    {
        ip4 = $3;
        port = $4;
        ip6 = $5;
        print "proxy -6 -n -a -p" port " -i" ip4 " -e" ip6;
        print "flush";
    }' $WORKDATA >> /usr/local/etc/3proxy/3proxy.cfg

    ok "Hoàn tất file config."
}

# ========== FIREWALL ==========
gen_iptables() {
    ok "Mở port firewall..."
cat >$WORKDIR/iptables.sh <<EOF
#!/bin/bash
for p in \$(seq $FIRST_PORT $LAST_PORT); do
    iptables -I INPUT -p tcp --dport \$p -j ACCEPT
done
EOF
    chmod +x $WORKDIR/iptables.sh
}

# ========== ADD IPv6 ==========
gen_ifconfig() {
    ok "Tạo script add IPv6..."
cat >$WORKDIR/ifconfig.sh <<EOF
#!/bin/bash
while read l; do
    ip6=\$(echo \$l | awk -F "/" '{print \$5}')
    ip -6 addr add \$ip6/64 dev $IFACE 2>/dev/null
done < $WORKDATA
EOF
    chmod +x $WORKDIR/ifconfig.sh
}

# ========== START 3PROXY ==========
start_3proxy() {
    ok "Chạy lại 3proxy..."
    pkill 3proxy 2>/dev/null || true

    bash $WORKDIR/iptables.sh
    bash $WORKDIR/ifconfig.sh

    /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &

    sleep 1
    ok "3proxy started!"
}

# ========== MAIN ==========
echo "====== TẠO PROXY IPV6 – PRO MAX – 3PROXY 0.8.6 ======"

install_deps
install_3proxy

# Detect interface
IFACE=$(ip route get 1 | awk '/dev/ {print $5}')
ok "Interface: $IFACE"

# IPv4
IP4=$(curl -4 -s icanhazip.com)
ok "IPv4 = $IP4"

# IPv6 prefix
RAW6=$(curl -6 -s icanhazip.com)
IP6_PREFIX=$(echo "$RAW6" | cut -d':' -f1-4)
ok "IPv6 prefix = $IP6_PREFIX"

# Ports
FIRST_PORT=${FIRST_PORT:-20000}
COUNT=${COUNT:-100}
LAST_PORT=$((FIRST_PORT + COUNT - 1))

ok "Tạo $COUNT proxy từ $FIRST_PORT → $LAST_PORT"

gen_data
gen_iptables
gen_ifconfig
gen_config
start_3proxy

ok "PROXY LIST: $WORKDIR/proxy.txt"
awk -F "/" '{print $3 ":" $4}' $WORKDATA > $WORKDIR/proxy.txt

echo "==== DONE ===="
