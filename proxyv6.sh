#!/bin/bash
# 3proxy IPv6 – AlmaLinux 8/9 (stable, full features, AUTO IPv6 prefix)

set -euo pipefail

###================== CONFIG ==================###

WORKDIR="/home/duyanmmo"
WORKDATA="${WORKDIR}/data.txt"
BACKUPDIR="${WORKDIR}/backup"
LOGDIR="/usr/local/etc/3proxy/logs"
PROXY_TXT="${WORKDIR}/proxy.txt"
PROXY_CSV="${WORKDIR}/proxy.csv"

# Color
C_RESET="\e[0m"
C_RED="\e[31m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"

log()   { echo -e "${C_GREEN}[INFO]${C_RESET} $*"; }
warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
error() { echo -e "${C_RED}[ERROR]${C_RESET} $*"; }

###================== BASIC CHECKS ==================###

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "Vui lòng chạy bằng quyền root!"
    exit 1
  fi
}

detect_iface() {
  IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5;exit}')
  IFACE=${IFACE:-eth0}
  log "Interface đang dùng: ${IFACE}"
}

check_ipv6() {
  log "Kiểm tra IPv6 routing (ping6 ipv6.google.com)..."
  if ping6 -c1 -W2 ipv6.google.com >/dev/null 2>&1; then
    log "IPv6 hoạt động OK."
  else
    warn "IPv6 không ping được ra ngoài!"
    read -rp "Bạn vẫn muốn tiếp tục? (y/N): " a
    [[ $a =~ ^[Yy]$ ]] || { error "Dừng script vì IPv6 không ổn."; exit 1; }
  fi
}

install_deps() {
  log "Cài đặt package cần thiết..."
  yum -y install epel-release >/dev/null 2>&1 || true
  yum -y install wget gcc make curl net-tools bsdtar zip iproute iptables tar >/dev/null
}

###================== IPv6 GENERATOR ==================###

random_str() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c5
  echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
  ip64() {
    echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
  }
  echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

###================== BACKUP ==================###

backup_old() {
  if [[ -f "${WORKDATA}" || -f "${PROXY_TXT}" || -f "${PROXY_CSV}" ]]; then
    TS=$(date +%Y%m%d-%H%M%S)
    mkdir -p "${BACKUPDIR}/${TS}"
    cp -a "${WORKDIR}"/. "${BACKUPDIR}/${TS}/" 2>/dev/null || true
    log "Backup cấu hình cũ -> ${BACKUPDIR}/${TS}"
  fi
}

###================== INSTALL 3PROXY ==================###

install_3proxy() {
  log "Cài đặt 3proxy..."
  mkdir -p /opt/3proxy-build
  cd /opt/3proxy-build
  wget -qO- https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz | tar xz
  cd 3proxy-3proxy-0.8.6
  make -f Makefile.Linux
  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp src/3proxy /usr/local/etc/3proxy/bin/
  log "Build 3proxy hoàn tất."
}

###================== GEN DATA ==================###

generate_data() {
  log "Sinh ${PROXY_COUNT} proxy..."
  > "${WORKDATA}"
  for ((i=0;i<PROXY_COUNT;i++)); do
    port=$((FIRST_PORT + i))
    user="u$(random_str)"
    pass="$(random_str)"
    ipv6=$(gen64 "${IPV6_PREFIX}")
    echo "${user}/${pass}/${IP4}/${port}/${ipv6}" >> "${WORKDATA}"
  done
}

gen_scripts() {
  log "Tạo script mở iptables..."
  cat <<EOF > "${WORKDIR}/boot_iptables.sh"
#!/bin/bash
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -j ACCEPT"}' "${WORKDATA}")
EOF
  chmod +x "${WORKDIR}/boot_iptables.sh"

  log "Tạo script gán IPv6..."
  cat <<EOF > "${WORKDIR}/boot_ifconfig.sh"
#!/bin/bash
$(awk -F "/" -v iface="${IFACE}" '
{
  printf "if ! ip -6 addr show dev %s | grep -q %s; then ip -6 addr add %s/64 dev %s; fi\n", iface, $5, $5, iface;
}' "${WORKDATA}")
EOF
  chmod +x "${WORKDIR}/boot_ifconfig.sh"
}

###================== 3PROXY CONFIG ==================###

gen_3proxy_cfg() {
  log "Tạo cấu hình 3proxy..."
  cat <<EOF > /usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 2000
nserver 1.1.1.1
nserver 8.8.8.8
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536

log ${LOGDIR}/3proxy-%y%m%d.log D
rotate 30

auth strong
users $(awk -F "/" 'BEGIN{ORS="";}{printf $1":CL:"$2" "}' "${WORKDATA}")

$(awk -F "/" '{
print  "auth strong\nallow "$1"\nproxy -6 -n -a -p"$4" -i"$3" -e"$5"\nflush\n"
}' "${WORKDATA}")
EOF
}

create_service() {
  log "Tạo systemd service proxyipv6.service..."
  cat <<EOF > /etc/systemd/system/proxyipv6.service
[Unit]
Description=3proxy IPv6 Proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=${WORKDIR}/boot_ifconfig.sh
ExecStartPre=${WORKDIR}/boot_iptables.sh
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always
RestartSec=2
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now proxyipv6.service
}

export_files() {
  log "Xuất proxy.txt..."
  awk -F "/" '{print $3":"$4":"$1":"$2}' "${WORKDATA}" > "${PROXY_TXT}"

  log "Xuất proxy.csv..."
  {
    echo "ip,port,user,pass,ipv6"
    awk -F "/" '{print $3","$4","$1","$2","$5}' "${WORKDATA}"
  } > "${PROXY_CSV}"
}

test_random() {
  read -rp "Test ngẫu nhiên 5 proxy? (y/N): " t
  [[ $t =~ ^[Yy]$ ]] || return

  shuf -n 5 "${PROXY_TXT}" | while read -r line; do
    ip=$(echo "$line" | cut -d: -f1)
    port=$(echo "$line" | cut -d: -f2)
    user=$(echo "$line" | cut -d: -f3)
    pass=$(echo "$line" | cut -d: -f4)
    echo -e "${C_YELLOW}Testing: $line${C_RESET}"
    curl -sx "http://${user}:${pass}@${ip}:${port}" https://api64.ipify.org --max-time 10 || echo "Fail"
    echo
  done
}

###================== MAIN ==================###

main() {
  require_root
  detect_iface
  check_ipv6
  install_deps

  mkdir -p "${WORKDIR}"
  backup_old

  # Detect IP
  IP4=$(curl -4 -s icanhazip.com)
  IP6_RAW=$(curl -6 -s icanhazip.com || true)
  IP6_SUG=$(echo "${IP6_RAW}" | cut -f1-4 -d":")

  echo
  log "IP detect được:"
  echo "IPv4: ${IP4}"
  echo "IPv6 đầy đủ: ${IP6_RAW}"
  echo "Prefix /64 tự động dùng: ${IP6_SUG}"
  echo

  # *** AUTO PREFIX: không hỏi nữa ***
  IPV6_PREFIX="${IP6_SUG}"

  if ! [[ "${IPV6_PREFIX}" =~ ^[0-9a-fA-F:]+$ ]]; then
    error "Prefix IPv6 không hợp lệ (AUTO detect lỗi)!"
    exit 1
  fi

  read -rp "Nhập FIRST_PORT (từ 10000 đến 60000): " FIRST_PORT
  read -rp "Nhập số lượng proxy muốn tạo (vd 100, 500, 2000): " PROXY_COUNT

  install_3proxy
  generate_data
  gen_scripts
  gen_3proxy_cfg
  create_service
  export_files

  echo
  echo -e "${C_GREEN}Hoàn tất cài đặt 3proxy + IPv6!${C_RESET}"
  echo "Proxy list: ${PROXY_TXT}"
  echo "CSV list  : ${PROXY_CSV}"
  echo "Service   : proxyipv6 (systemctl status proxyipv6)"
  echo

  test_random
}

main
