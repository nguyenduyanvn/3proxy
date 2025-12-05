#!/bin/bash
# taoproxyipv6.sh — PRO MAX 3proxy 0.8.6
# Hỗ trợ:
#   MODE=nopass  → proxy ip:port
#   MODE=pass    → proxy ip:port:user:pass
#   FIRST_PORT, COUNT, USER, PASS

set -e
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Tăng ulimit riêng cho process này & 3proxy
ulimit -n 65535 2>/dev/null || true

WORKDIR="/home/duyanmmo"
mkdir -p "$WORKDIR"
WORKDATA="$WORKDIR/data.txt"

log() { echo "[*] $*"; }
ok()  { echo "[+] $*"; }
err() { echo "[!] $*" >&2; }

# ================= CÀI GÓI CẦN THIẾT =================
install_deps() {
    ok "Cài gcc, make, wget, curl, net-tools..."
    if command -v yum >/dev/null 2>&1; then
        yum install -y gcc make wget curl net-tools >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y gcc make wget curl net-tools >/dev/null 2>&1 || true
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1 || true
        apt-get install -y gcc make wget curl net-tools >/dev/null 2>&1 || true
    fi
}

# ================= CÀI 3PROXY 0.8.6 =================
install_3proxy() {
    if [ -x /usr/local/etc/3proxy/bin/3proxy ]; then
        ok "3proxy đã tồn tại, bỏ qua bước build."
        return
    fi

    ok "Tải & build 3proxy 0.8.6..."
    cd /root
    rm -rf 3proxy-* 3proxy-0.8.6.tar.gz >/dev/null 2>&1 || true

    wget -q -O 3proxy-0.8.6.tar.gz "https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
    tar -xzf 3proxy-0.8.6.tar.gz
    cd 3proxy-3proxy-0.8.6

    make -f Makefile.Linux >/dev/null

    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    chmod +x /usr/local/etc/3proxy/bin/3proxy

    ok "Cài 3proxy OK."
}

# ================= RANDOM IPv6 =================
hex4() {
    printf "%x%x%x%x" $((RANDOM%16)) $((RANDOM%16)) $((RANDOM%16)) $((RANDOM%16))
}

gen_ipv6() {
    printf "%s:%s:%s:%s:%s\n" "$IP6_PREFIX" "$(hex4)" "$(hex4)" "$(hex4)" "$(hex4)"
}

# ================= SINH DATA =================
gen_data() {
    ok "Sinh danh sách proxy..."
    : > "$WORKDATA"
    port="$FIRST_PORT"
    while [ "$port" -le "$LAST_PORT" ]; do
        ip6=$(gen_ipv6)
        # Lưu dạng: IPv4/port/IPv6
        echo "$IP4/$port/$ip6" >> "$WORKDATA"
        port=$((port+1))
    done
    ok "Đã sinh $(wc -l < "$WORKDATA") proxy."
}

# ================= TẠO CONFIG 3PROXY =================
gen_config() {
    ok "Tạo /usr/local/etc/3proxy/3proxy.cfg ..."

    CONFIG="/usr/local/etc/3proxy/3proxy.cfg"
    cat >"$CONFIG" <<EOF
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
EOF

    if [ "$MODE" = "pass" ]; then
        # Cấu hình auth
        cat >>"$CONFIG" <<EOF
users $USER:CL:$PASS
auth strong
allow $USER
EOF
    else
        # Không pass
        echo "auth none" >>"$CONFIG"
        echo "allow *" >>"$CONFIG"
    fi

    # 0.8.6 không hỗ trợ -6, chỉ dùng -n -a -p -i -e
    while IFS=/ read -r ip4 port ip6; do
        echo "proxy -n -a -p$port -i$ip4 -e$ip6" >>"$CONFIG"
        echo "flush" >>"$CONFIG"
    done < "$WORKDATA"

    ok "Config OK."
}

# ================= FIREWALL & IPv6 =================
apply_fw_and_ipv6() {
    ok "Thêm IPv6 vào interface $IFACE..."
    while IFS=/ read -r ip4 port ip6; do
        ip -6 addr add "$ip6/64" dev "$IFACE" 2>/dev/null || true
    done < "$WORKDATA"

    ok "Mở port firewall..."
    for p in $(seq "$FIRST_PORT" "$LAST_PORT"); do
        iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || true
    done
}

# ================= START 3PROXY =================
start_3proxy() {
    ok "Restart 3proxy..."
    pkill 3proxy 2>/dev/null || true
    /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg &
    sleep 1
    if pgrep 3proxy >/dev/null 2>&1; then
        ok "3proxy đang chạy."
    else
        err "3proxy KHÔNG chạy, kiểm tra lại config."
    fi
}

# ================= LƯU proxy.txt =================
save_proxy_list() {
    PROXYTXT="$WORKDIR/proxy.txt"
    if [ "$MODE" = "pass" ]; then
        awk -F'/' -v U="$USER" -v P="$PASS" '{print $1 ":" $2 ":" U ":" P}' "$WORKDATA" > "$PROXYTXT"
    else
        awk -F'/' '{print $1 ":" $2}' "$WORKDATA" > "$PROXYTXT"
    fi
    ok "Đã tạo $PROXYTXT"
}

# ================= MAIN =================
echo "==== TẠO PROXY IPV6 – 3PROXY 0.8.6 – MODE=$MODE ===="

MODE=${MODE:-nopass}
FIRST_PORT=${FIRST_PORT:-20000}
COUNT=${COUNT:-100}
LAST_PORT=$((FIRST_PORT + COUNT - 1))

install_deps
install_3proxy

IFACE=$(ip route get 1 2>/dev/null | awk '/dev/ {print $5; exit}')
[ -z "$IFACE" ] && IFACE="eth0"

IP4=$(curl -4 -s icanhazip.com || echo "")
IP6_FULL=$(curl -6 -s icanhazip.com || echo "")

if [ -z "$IP4" ] || [ -z "$IP6_FULL" ]; then
    err "Không lấy được IPv4 hoặc IPv6 (curl icanhazip.com)."
    exit 1
fi

IP6_PREFIX=$(echo "$IP6_FULL" | cut -d':' -f1-4)

ok "Interface: $IFACE"
ok "IPv4: $IP4"
ok "IPv6 full: $IP6_FULL"
ok "IPv6 prefix: $IP6_PREFIX"
ok "Sẽ tạo $COUNT proxy từ port $FIRST_PORT → $LAST_PORT"

rm -f "$WORKDATA" "$WORKDIR/proxy.txt" 2>/dev/null || true

gen_data
gen_config
apply_fw_and_ipv6
start_3proxy
save_proxy_list

echo "===== HOÀN TẤT ====="
