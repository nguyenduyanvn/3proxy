#!/bin/bash
# taoproxyipv6.sh — PRO MAX 3proxy 0.8.6
# Supported MODE:
#   nopass  → tạo proxy không pass
#   pass    → tạo proxy có user/pass
#   delete  → xóa proxy + IPv6 + iptables + config
#   stop    → dừng 3proxy
#   restart → restart 3proxy

set -e
ulimit -n 65535 || true

WORKDIR="/home/duyanmmo"
CONFIG="/usr/local/etc/3proxy/3proxy.cfg"
WORKDATA="$WORKDIR/data.txt"
IFACE=$(ip route get 1 2>/dev/null | awk '/dev/ {print $5; exit}')
[ -z "$IFACE" ] && IFACE="eth0"

log(){ echo "[*] $*"; }
ok(){ echo "[+] $*"; }
err(){ echo "[!] $*" >&2; }

# ================= STOP =================
if [ "$MODE" = "stop" ]; then
    ok "Stopping 3proxy..."
    pkill 3proxy 2>/dev/null || true
    ok "3proxy stopped."
    exit 0
fi

# ================= RESTART =================
if [ "$MODE" = "restart" ]; then
    ok "Restarting 3proxy..."
    pkill 3proxy 2>/dev/null || true
    /usr/local/etc/3proxy/bin/3proxy $CONFIG &
    sleep 1
    if pgrep 3proxy >/dev/null; then ok "3proxy restarted!"; else err "Failed."; fi
    exit 0
fi

# ================= DELETE =================
if [ "$MODE" = "delete" ]; then
    ok "XÓA TOÀN BỘ PROXY + CONFIG + IPv6 + IPTABLES..."

    # Stop proxy
    pkill 3proxy 2>/dev/null || true

    # Remove config
    rm -f $CONFIG

    # Remove IPv6
    ip -6 addr show dev $IFACE | awk '/inet6/ {print $2}' > /tmp/old_ipv6.txt
    while read ip; do
        ip -6 addr del "$ip" dev $IFACE 2>/dev/null || true
    done < /tmp/old_ipv6.txt

    # Clean iptables
    iptables -F || true

    # Clean files
    rm -rf $WORKDIR/*

    ok "VPS SẠCH — SẴN SÀNG TẠO PROXY MỚI."
    exit 0
fi

# ================= INSTALL DEPENDENCIES =================
install() {
    if command -v yum >/dev/null; then
        yum install -y gcc make wget curl net-tools >/dev/null || true
    elif command -v dnf >/dev/null; then
        dnf install -y gcc make wget curl net-tools >/dev/null || true
    else
        apt update -y
        apt install -y gcc make wget curl net-tools
    fi
}

install_3proxy() {
    if [ -x /usr/local/etc/3proxy/bin/3proxy ]; then
        ok "3proxy đã tồn tại."
        return
    fi

    ok "Tải & build 3proxy..."
    cd /root
    wget -q -O 3proxy-0.8.6.tar.gz "https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
    tar -xzf 3proxy-0.8.6.tar.gz
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux >/dev/null
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
}

hex4(){ printf "%x%x%x%x" $((RANDOM%16)) $((RANDOM%16)) $((RANDOM%16)) $((RANDOM%16)); }
gen_ipv6(){ printf "%s:%s:%s:%s:%s\n" "$IP6_PREFIX" "$(hex4)" "$(hex4)" "$(hex4)" "$(hex4)"; }

gen_data() {
    :> $WORKDATA
    p=$FIRST_PORT
    while [ $p -le $LAST_PORT ]; do
        ip6=$(gen_ipv6)
        echo "$IP4/$p/$ip6" >> $WORKDATA
        p=$((p+1))
    done
}

gen_config() {
cat > $CONFIG <<EOF
daemon
maxconn 2000
auth none
allow *
flush
EOF

if [ "$MODE" = "pass" ]; then
cat >> $CONFIG <<EOF
users $USER:CL:$PASS
auth strong
allow $USER
EOF
fi

while IFS="/" read ip4 port ip6; do
cat >> $CONFIG <<EOF
proxy -n -a -p$port -i$ip4 -e$ip6
flush
EOF
done < $WORKDATA
}

apply_ipv6() {
    while IFS="/" read ip4 port ip6; do
        ip -6 addr add "$ip6/64" dev $IFACE 2>/dev/null || true
    done < $WORKDATA
}

apply_fw() {
    for p in $(seq $FIRST_PORT $LAST_PORT); do
        iptables -I INPUT -p tcp --dport $p -j ACCEPT
    done
}

run_3proxy() {
    pkill 3proxy || true
    /usr/local/etc/3proxy/bin/3proxy $CONFIG &
}

# ================= MAIN CREATE MODE =================
install
install_3proxy

mkdir -p $WORKDIR
IP4=$(curl -s -4 icanhazip.com)
IP6F=$(curl -s -6 icanhazip.com)
IP6_PREFIX=$(echo $IP6F | cut -d: -f1-4)

FIRST_PORT=${FIRST_PORT:-20000}
COUNT=${COUNT:-100}
LAST_PORT=$((FIRST_PORT+COUNT-1))

gen_data
gen_config
apply_ipv6
apply_fw
run_3proxy

if [ "$MODE" = "pass" ]; then
    awk -F'/' -v U="$USER" -v P="$PASS" '{print $1 ":" $2 ":" U ":" P}' $WORKDATA > $WORKDIR/proxy.txt
else
    awk -F'/' '{print $1 ":" $2}' $WORKDATA > $WORKDIR/proxy.txt
fi

ok "HOÀN TẤT. File proxy: $WORKDIR/proxy.txt"
