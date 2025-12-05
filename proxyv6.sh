#!/bin/bash
# 3proxy IPv6 – AlmaLinux 8/9 (FINAL FIXED VERSION)
# Auto detect IPv6 prefix from network interface (NOT from icanhazip)
# Guaranteed correct prefix such as 2001:df5:e6c0:1

set -euo pipefail

###================== CONFIG ==================###

WORKDIR="/home/duyanmmo"
WORKDATA="${WORKDIR}/data.txt"
BACKUPDIR="${WORKDIR}/backup"
LOGDIR="/usr/local/etc/3proxy/logs"
PROXY_TXT="${WORKDIR}/proxy.txt"
PROXY_CSV="${WORKDIR}/proxy.csv"

C_RESET="\e[0m"
C_GREEN="\e[32m"
C_RED="\e[31m"
C_YELLOW="\e[33m"

log()   { echo -e "${C_GREEN}[INFO]${C_RESET} $*"; }
warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
error() { echo -e "${C_RED}[ERROR]${C_RESET} $*"; }

###================== BASIC CHECK ==================###

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "Vui lòng chạy script bằng root!"
    exit 1
  fi
}

detect_iface() {
  IFACE=$(ip route get 1.1.1.1 | awk '{print $5;exit}')
  IFACE=${IFACE:-eth0}
  log "Interface: ${IFACE}"
}

check_ipv6() {
  log "Kiểm tra IPv6..."
  if ping6 -c1 -W2 ipv6.google.com >/dev/null 2>&1; then
    log "IPv6 hoạt động OK."
  else
    warn "IPv6 không ping ra được!"
    read -rp "Tiếp tục? (y/N): " x
    [[ $x =~ ^[Yy]$ ]] || exit 1
  fi
}

install_deps() {
  log "Cài đặt package cần thiết..."
  yum -y install epel-release >/dev/null 2>&1 || true
  yum -y install wget gcc make curl net-tools bsdtar zip iproute iptables tar >/dev/null
}

###================== IPv6 GENERATOR ==================###

rnd() { tr </dev/urandom -dc A-Za-z0-9 | head -c5; echo; }

hex() {
  printf "%04x" $(( RANDOM % 65535 ))
}

gen_ipv6() {
  echo "${PREFIX}:${1}:${2}:${3}:${4}"
}

###================== BACKUP ==================###

backup_old() {
  [[ -d "$WORKDIR" ]] || mkdir -p "$WORKDIR"
  TS=$(date +%Y%m%d-%H%M%S)
  mkdir -p "${BACKUPDIR}/${TS}"
  cp -a "${WORKDIR}"/* "${BACKUPDIR}/${TS}/" 2>/dev/null || true
  log "Đã backup vào ${BACKUPDIR}/${TS}"
}

###================== INSTALL 3PROXY ==================###

install_3proxy() {
  log "Cài 3proxy..."
  mkdir -p /opt/3proxy-build
  cd /opt/3proxy-build
  wget -qO- https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz | tar xz
  cd 3proxy-3proxy-0.8.6
  make -f Makefile.Linux
  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp src/3proxy /usr/local/etc/3proxy/bin/
  log "Build 3proxy xong."
}

###================== AUTO DETECT IPV6 PREFIX ==================###

detect_ipv6_prefix() {
  log "Lấy IPv6 từ interface (CHUẨN NHẤT)..."

  IP6_FULL=$(ip -6 addr show dev "${IFACE}" scope global | awk '/inet6/ {print $2;exit}')
  [[ -z "$IP6_FULL" ]] && { error "Không tìm thấy IPv6 trên interface!"; exit 1; }

  PREFIX=$(echo "$IP6_FULL" | cut -d'/' -f1 | cut -d':' -f1-4)

  log "IPv6 full: ${IP6_FULL}"
  log "PREFIX /64 detected: ${PREFIX}"
}

###================== GENERATE PROXY DATA ==================###

generate_data() {
  IP4=$(curl -4 -s icanhazip.com)
  log "Sinh ${COUNT} proxy..."

  > "$WORKDATA"

  for ((i=0;i<COUNT;i++)); do
    p=$((PORT+i))
    u=$(rnd)
    pw=$(rnd)
    ipv6=$(gen_ipv6 "$(hex)" "$(hex)" "$(hex)" "$(hex)")

    echo "${u}/${pw}/${IP4}/${p}/${ipv6}" >> "$WORKDATA"
  done
}

###================== SCRIPT BOOT ==================###

make_scripts() {
cat <<EOF > "${WORKDIR}/boot_ifconfig.sh"
#!/bin/bash
$(awk -v iface="$IFACE" -F "/" '{print "ip -6 addr add "$5"/64 dev "iface" 2>/dev/null"}' "$WORKDATA")
EOF
chmod +x "${WORKDIR}/boot_ifconfig.sh"

cat <<EOF > "${WORKDIR}/boot_iptables.sh"
#!/bin/bash
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport "$4" -j ACCEPT"}' "$WORKDATA")
EOF
chmod +x "${WORKDIR}/boot_iptables.sh"

log "Đã tạo boot_ifconfig + boot_iptables."
}

###================== 3PROXY CONFIG ==================###

make_3proxy_cfg() {
  log "Tạo config 3proxy..."

cat <<EOF > /usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 5000
nscache 65536
nserver 1.1.1.1
nserver 8.8.8.8
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844

log ${LOGDIR}/3proxy-%y%m%d.log D
rotate 30
auth strong

users $(awk -F "/" '{printf $1":CL:"$2" "}' "$WORKDATA")

$(awk -F "/" '{
print "auth strong";
print "allow "$1;
print "proxy -6 -n -a -p"$4" -i"$3" -e"$5"";
print "flush";
}' "$WORKDATA")
EOF
}

###================== SYSTEMD SERVICE ==================###

make_service() {
cat <<EOF > /etc/systemd/system/proxyipv6.service
[Unit]
Description=3proxy IPv6 Proxy
After=network.target

[Service]
Type=simple
ExecStartPre=${WORKDIR}/boot_ifconfig.sh
ExecStartPre=${WORKDIR}/boot_iptables.sh
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now proxyipv6
log "Service proxyipv6 đã khởi động."
}

###================== EXPORT FILES ==================###

export_files() {
  awk -F "/" '{print $3":"$4":"$1":"$2}' "$WORKDATA" > "$PROXY_TXT"
  awk -F "/" '{print $3","$4","$1","$2","$5}' "$WORKDATA" > "$PROXY_CSV"
  log "Xuất proxy.txt & proxy.csv xong."
}

###================== MAIN ==================###

main() {
  require_root
  detect_iface
  check_ipv6
  install_deps
  backup_old
  install_3proxy
  detect_ipv6_prefix

  read -rp "FIRST_PORT (10000–60000): " PORT
  read -rp "Số lượng proxy cần tạo: " COUNT

  generate_data
  make_scripts
  make_3proxy_cfg
  make_service
  export_files

  log "=== HOÀN TẤT – PROXY SẴN SÀNG ==="
  echo "Proxy list: $PROXY_TXT"
}

main
