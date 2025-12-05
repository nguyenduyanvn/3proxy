#!/bin/bash
# taoproxyipv6.sh — PRO MAX — SUPPORT NOPASS & PASS (3proxy 0.8.6)

set -e
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

WORKDIR="/home/duyanmmo"
mkdir -p $WORKDIR
WORKDATA="$WORKDIR/data.txt"

log() { echo "[*] $*"; }
ok()  { echo "[+] $*"; }
err() { echo "[!] $*" >&2; }

# ==========================
#  RANDOM IPv6 GENERATOR
# ==========================
hex4() {
    printf "%x%x%x%x" $((RANDOM%16)) $((RANDOM%16)) $((RANDOM%16)) $((RANDOM%16))
}

gen_ipv6() {
    printf "%s:%s:%s:%s:%s\n" "$IP6_PREFIX" "$(hex4)" "$(hex4)" "$(hex4)" "$(hex4)"
}

# ==========================
#  INSTALL DEPENDENCIES
# ==========================
install_deps() {
    ok "Cài đặt gcc, make, wget..."
    yum install -y gcc make wget curl net-tools >/dev/null 2>&1 || true
}

# ==========================
#  INSTALL 3PROXY 0.8.6
# ==========================
install_3proxy() {
    if [ -x /usr/local/etc/3proxy/bin/3proxy ]; then
        ok "3proxy đã tồn tại — bỏ qua bước build."
        return
    fi

    ok "Tải và build 3proxy 0.8.6..."
    cd /root
    rm -rf 3proxy-* || true

    wget -q https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz
    tar -xzf 3proxy-0.8.6.tar.gz
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux >/dev/null

    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    chmod +x /usr/local/etc/3proxy/bin/3proxy

    ok "Cài 3proxy OK."
}

# ==========================
#  GENERATE PROXY DATA
# ==========================
gen_data() {
    ok "Tạo danh sách IPv6..."
    : > $WORKDATA

    p=$FIRST_PORT
    while [ $p -le $LAST_PORT ]; do
        ipv6=$(gen_ipv6)
        echo "//$IP4/$p/$ipv6" >> $WORKDATA
        p=$((p+1))
    done

    ok "Đã tạo $(wc -l < $WORKDATA) proxy."
}

# ==========================
#  GENERATE 3PROXY CONFIG
# ==========================
gen_config() {
    ok "Tạo file config 3proxy..."

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

# ----- MODE = nopass ------
if [ "$MODE" = "nopass" ]; then
    awk -F "/" '
    {
        ip4=$3; port=$4; ip6=$5;
        print "proxy -6 -n -a -p" port " -i" ip4 " -e" ip6;
        print "flush";
    }' $WORKDATA >> /usr/local/etc/3proxy/3proxy.cfg
fi

# ----- MODE = pass ------
if [ "$MODE" = "pass" ]; then
cat >>/usr/local/etc/3proxy/3proxy.cfg <<EOF
users $USER:CL:$PASS
auth strong
EOF

    awk -F "/" -v USER="$USER" '
    {
        ip4=$3; port=$4; ip6=$5;
        print "proxy -6 -n -a -p" port " -i" ip4 " -e" ip6 " -u" USER;
        print "flush";
    }' $WORKDATA >> /usr/local/etc/3proxy/3proxy.cfg
fi

ok "Config OK."
}

# ==========================
#  FIREWALL + IPv6
# ==========================
gen_fw() {
cat > $WORKDIR/iptables.sh <<EOF
#!/bin/bash
for p in \$(seq $FIRST_PORT $LAST_PORT); do
    iptables -I INPUT -p tcp --dport \$p -j ACCEPT
done
EOF
chmod +x $WORKDIR/iptables.sh

cat > $WORKDIR/ifconfig.sh <<EOF
#!/bin/bash
while read l; do
    ip6=\$(echo \$l | awk -F "/" '{print \$5}')
    ip -6 addr add \$ip6/64 dev $IFACE 2>/dev/null
done < $WORKDATA
EOF
chmod +x $WORKDIR/ifconfig.sh
}

# ==========================
#  RUN 3PROXY
# ==========================
start_3proxy() {
    pkill 3proxy 2>/dev/null || true
    bash $WORKDIR/iptables.sh
    bash $WORKDIR/ifconfig.sh
    /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &
}

# ==========================
#  OUTPUT proxy.txt
# ==========================
save_proxy_txt() {
    if [ "$MODE" = "nopass" ]; then
        awk -F "/" '{print $3 ":" $4}' $WORKDATA > $WORKDIR/proxy.txt
    else
        awk -F "/" -v U="$USER" -v P="$PASS" '{print $3 ":" $4 ":" U ":" P}' $WORKDATA > $WORKDIR/proxy.txt
    fi
    ok "PROXY TXT: $WORKDIR/proxy.txt"
}

# ==========================
#  MAIN
# ==========================
install_deps
install_3proxy

IFACE=$(ip route get 1 | awk '/dev/ {print $5}')
IP4=$(curl -4 -s icanhazip.com)
RAW6=$(curl -6 -s icanhazip.com)
IP6_PREFIX=$(echo "$RAW6" | cut -d':' -f1-4)

ok "Interface: $IFACE"
ok "IPv4: $IP4"
ok "IPv6 prefix: $IP6_PREFIX"

FIRST_PORT=${FIRST_PORT:-20000}
COUNT=${COUNT:-100}
LAST_PORT=$((FIRST_PORT + COUNT - 1))

ok "Tạo $COUNT proxy từ port $FIRST_PORT → $LAST_PORT"
ok "MODE = $MODE"

gen_data
gen_fw
gen_config
start_3proxy
save_proxy_txt

ok "HOÀN TẤT!"
