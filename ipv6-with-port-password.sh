#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# ============ HÀM HỖ TRỢ CHUNG ============

random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c12
	echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

detect_os() {
    if [ -f /etc/redhat-release ]; then
        OS_FAMILY="rhel"
    elif [ -f /etc/debian_version ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
        OS_FAMILY="debian"
    else
        OS_FAMILY="unknown"
    fi
}

install_deps() {
    detect_os
    echo "==> Cài đặt gói cần thiết..."
    if [ "$OS_FAMILY" = "rhel" ]; then
        yum -y install epel-release >/dev/null 2>&1 || true
        yum -y install wget gcc net-tools bsdtar zip iptables >/dev/null
        RC_LOCAL="/etc/rc.d/rc.local"
    elif [ "$OS_FAMILY" = "debian" ]; then
        apt-get update -y >/dev/null
        apt-get install -y wget gcc net-tools libarchive-tools zip iptables >/dev/null
        RC_LOCAL="/etc/rc.local"
    else
        echo "Không nhận diện được OS, dùng mặc định kiểu RHEL..."
        RC_LOCAL="/etc/rc.d/rc.local"
    fi
}

detect_iface() {
    IFACE=$(ip -o -4 route show to default 2>/dev/null | awk '{print $5}' | head -n1)
    [ -z "$IFACE" ] && IFACE=$(ip -o link show | awk -F': ' '$2!="lo"{print $2; exit}')
    [ -z "$IFACE" ] && IFACE="eth0"
    echo "$IFACE"
}

install_3proxy() {
    echo "==> Cài 3proxy..."
    URL="https://github.com/nguyenduyanvn/3proxy/raw/refs/heads/main/3proxy-0.9.4.tar.gz"
    wget -qO- $URL | bsdtar -xvf- >/dev/null
    cd 3proxy-0.9.4
    make -f Makefile.Linux >/dev/null
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd "$WORKDIR"
}

gen_3proxy() {
cat <<EOF
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
auth strong

users $(awk -F "/" '{printf "%s:CL:%s ", $1, $2}' ${WORKDATA})

$(awk -F "/" '{print "allow " $1 "\nproxy -6 -n -a -p" $4 " -i" $3 " -e" $5 "\nflush"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    # ip:port:user:pass
    awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' "${WORKDATA}" > "${WORKDIR}/proxy.txt"
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "user$port/$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -j ACCEPT"}' "${WORKDATA}"
}

gen_ifconfig() {
    awk -F "/" -v IFACE="$IFACE" '{print "ifconfig " IFACE " inet6 add " $5 "/64"}' "${WORKDATA}"
}

# ============ BẮT ĐẦU CHẠY ============

install_deps

WORKDIR="/home/duyanmmo"
WORKDATA="${WORKDIR}/data.txt"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR" || exit 1

IFACE=${IFACE:-$(detect_iface)}
echo "==> Dùng interface: $IFACE"

install_3proxy

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "IPv4 = $IP4"
echo "IPv6 prefix = $IP6"

# ---- LẤY FIRST_PORT & COUNT ----
if [ -z "$FIRST_PORT" ]; then
  read -p "Enter FIRST_PORT (21000-61000): " FIRST_PORT
fi

if [ -z "$COUNT" ]; then
  COUNT=2000
fi

LAST_PORT=$(($FIRST_PORT + $COUNT - 1))

echo "==> Sẽ tạo $COUNT proxy từ port $FIRST_PORT → $LAST_PORT"

# ---- GEN FILE CẤU HÌNH ----
gen_data > "$WORKDATA"
gen_iptables > "${WORKDIR}/boot_iptables.sh"
gen_ifconfig > "${WORKDIR}/boot_ifconfig.sh"
chmod +x "${WORKDIR}/boot_iptables.sh" "${WORKDIR}/boot_ifconfig.sh"

gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg

# ---- TẠO RC.LOCAL AUTO START ----
cat > "$RC_LOCAL" <<EOF
#!/bin/bash
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 100000
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

chmod +x "$RC_LOCAL"
bash "$RC_LOCAL"

gen_proxy_file_for_user

echo "====================================="
echo " DONE! Proxy list: ${WORKDIR}/proxy.txt"
echo " Mẫu: ip:port:user:pass"
echo "====================================="
