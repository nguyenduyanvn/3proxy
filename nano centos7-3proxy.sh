#!/bin/bash
# 3proxy IPv6 - CentOS 7 optimized
# Yêu cầu: VPS CentOS 7, có IPv6 /64

set -euo pipefail

###================= CONFIG =================###

WORKDIR="/home/duyanmmo"
WORKDATA="${WORKDIR}/data.txt"
LOGDIR="/usr/local/etc/3proxy/logs"
PROXY_TXT="${WORKDIR}/proxy.txt"
PROXY_CSV="${WORKDIR}/proxy.csv"
SERVICE_NAME="3proxy-ipv6"

C_RESET="\e[0m"
C_RED="\e[31m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"

log()   { echo -e "${C_GREEN}[INFO]${C_RESET} $*"; }
warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
error() { echo -e "${C_RED}[ERROR]${C_RESET} $*"; }

###================= UTILS =================###

random_str() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c5
  echo
}

array=(0 1 2 3 4 5 6 7 8 9 a b c d e f)
gen64() {
  ip64() {
    echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
  }
  echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "Vui lòng chạy script bằng ROOT!"
    exit 1
  fi
}

detect_iface() {
  IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5;exit}')
  IFACE=${IFACE:-eth0}
  log "Interface phát hiện: $IFACE"
}

check_ipv6() {
  log "Kiểm tra IPv6 (ping6 ipv6.google.com)..."
  if ping6 -c1 -W2 ipv6.google.com >/dev/null 2>&1; then
    log "IPv6 hoạt động OK."
  else
    warn "IPv6 KHÔNG ping được ra ngoài!"
    read -rp "Tiếp tục dù IPv6 lỗi? (y/N): " ans
    [[ $ans =~ ^[Yy]$ ]] || { error "Dừng script vì IPv6 không ổn."; exit 1; }
  fi
}

install_deps() {
  log "Cài các gói cần thiết..."
  yum -y install epel-release >/dev/null 2>&1 || true
  yum -y install gcc make wget curl net-tools bsdtar zip iproute iptables-services >/dev/null
}

build_3proxy() {
  if [[ -x /usr/local/etc/3proxy/bin/3proxy ]]; then
    log "3proxy đã cài, bỏ qua bước build."
    return
  fi

  log "Tải & build 3proxy..."
  mkdir -p /opt/3proxy-build
  cd /opt/3proxy-build
  wget -qO- https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz | tar xz
  cd 3proxy-3proxy-0.8.6
  make -f Makefile.Linux
  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp src/3proxy /usr/local/etc/3proxy/bin/
  log "Build 3proxy xong."
}

detect_ips() {
  IP4=$(curl -4 -s icanhazip.com)
  # Lấy IPv6 trên interface, ưu tiên cái trên card mạng (chuẩn nhất)
  IP6_FULL=$(ip -6 addr show dev "$IFACE" scope global | awk '/inet6/ {print $2;exit}')
  if [[ -z "$IP6_FULL" ]]; then
    warn "Không thấy IPv6 trên interface, fallback sang icanhazip..."
    IP6_FULL="$(curl -6 -s icanhazip.com)/128"
  fi

  IPV6_PREFIX=$(echo "$IP6_FULL" | cut -d'/' -f1 | cut -d':' -f1-4)

  echo
  log "IP phát hiện được:"
  echo "  IPv4       : $IP4"
  echo "  IPv6 full  : $IP6_FULL"
  echo "  Prefix /64 : $IPV6_PREFIX"
  echo

  if ! [[ "$IPV6_PREFIX" =~ ^[0-9a-fA-F:]+$ ]]; then
    error "Prefix IPv6 không hợp lệ, dừng lại."
    exit 1
  fi
}

prompt_ports() {
  while :; do
    read -rp "Nhập FIRST_PORT (10000-60000): " FIRST_PORT
    [[ "$FIRST_PORT" =~ ^[0-9]+$ ]] || { echo "Nhập số đi bạn."; continue; }
    (( FIRST_PORT >= 1000 && FIRST_PORT <= 60000 )) && break
    echo "Port ngoài khoảng 1000-60000."
  done

  while :; do
    read -rp "Nhập SỐ LƯỢNG proxy muốn tạo (vd 100, 500, 2000): " COUNT
    [[ "$COUNT" =~ ^[0-9]+$ ]] || { echo "Nhập số đi bạn."; continue; }
    (( COUNT > 0 )) && break
    echo "Số lượng phải > 0."
  done

  LAST_PORT=$(( FIRST_PORT + COUNT - 1 ))
  log "Sẽ tạo $COUNT proxy, port từ $FIRST_PORT → $LAST_PORT"
}

generate_data() {
  log "Sinh data proxy..."
  mkdir -p "$WORKDIR"
  > "$WORKDATA"
  for ((p = FIRST_PORT; p <= LAST_PORT; p++)); do
    user=$(random_str)
    pass=$(random_str)
    ipv6=$(gen64 "$IPV6_PREFIX")
    echo "$user/$pass/$IP4/$p/$ipv6" >> "$WORKDATA"
  done
}

gen_scripts() {
  log "Tạo script gán IPv6..."
  cat <<EOF > "${WORKDIR}/boot_ifconfig.sh"
#!/bin/bash
$(awk -F "/" -v iface="$IFACE" '{print "ip -6 addr add "$5"/64 dev "iface" 2>/dev/null"}' "$WORKDATA")
EOF
  chmod +x "${WORKDIR}/boot_ifconfig.sh"

  log "Tạo script mở iptables..."
  cat <<EOF > "${WORKDIR}/boot_iptables.sh"
#!/bin/bash
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport "$4" -j ACCEPT"}' "$WORKDATA")
EOF
  chmod +x "${WORKDIR}/boot_iptables.sh"

  # Bật iptables và lưu
  systemctl enable iptables.service >/dev/null 2>&1 || true
}

gen_3proxy_cfg() {
  log "Tạo 3proxy.cfg..."
  mkdir -p "$LOGDIR"

  cat <<EOF > /usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 4000
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

users $(awk -F "/" 'BEGIN{ORS="";} {printf $1 ":CL:" $2 " "}' "$WORKDATA")

$(awk -F "/" '{
  print "auth strong"
  print "allow "$1
  print "proxy -6 -n -a -p"$4" -i"$3" -e"$5
  print "flush"
}' "$WORKDATA")
EOF
}

create_service() {
  log "Tạo systemd service ${SERVICE_NAME}.service..."

  cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
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
  systemctl enable --now "${SERVICE_NAME}.service"
}

export_files() {
  log "Xuất proxy.txt & proxy.csv..."

  awk -F "/" '{print $3":"$4":"$1":"$2}' "$WORKDATA" > "$PROXY_TXT"

  {
    echo "ip,port,user,pass,ipv6"
    awk -F "/" '{print $3","$4","$1","$2","$5}' "$WORKDATA"
  } > "$PROXY_CSV"
}

summary() {
  echo
  echo -e "${C_GREEN}HOÀN TẤT CÀI ĐẶT 3PROXY + IPv6 TRÊN CENTOS 7!${C_RESET}"
  echo "File proxy.txt : $PROXY_TXT"
  echo "File proxy.csv : $PROXY_CSV"
  echo "Service        : ${SERVICE_NAME}.service (systemctl status ${SERVICE_NAME})"
  echo
}

###================= MAIN =================###

main() {
  require_root
  detect_iface
  check_ipv6
  install_deps
  build_3proxy
  detect_ips
  prompt_ports
  generate_data
  gen_scripts
  gen_3proxy_cfg
  create_service
  export_files
  summary
}

main
