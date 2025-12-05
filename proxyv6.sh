#!/bin/bash
# 3proxy IPv6 – AlmaLinux 8/9 (full features, VN)
# by Duy An (nâng cấp từ script cũ)

set -euo pipefail

#########################
# CẤU HÌNH CƠ BẢN
#########################

WORKDIR="/home/duyanmmo"
WORKDATA="${WORKDIR}/data.txt"
BACKUPDIR="${WORKDIR}/backup"
LOGDIR="/usr/local/etc/3proxy/logs"
PROXY_TXT="${WORKDIR}/proxy.txt"
PROXY_CSV="${WORKDIR}/proxy.csv"

# Màu cho output
C_RESET="\e[0m"
C_RED="\e[31m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_CYAN="\e[36m"

log_info()  { echo -e "${C_GREEN}[INFO]${C_RESET} $*"; }
log_warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*"; }
log_error() { echo -e "${C_RED}[ERROR]${C_RESET} $*"; }

#########################
# HÀM HỖ TRỢ
#########################

require_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "Vui lòng chạy script với quyền root (sudo)."
    exit 1
  fi
}

detect_iface() {
  local iface
  iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')
  if [[ -z "${iface}" ]]; then
    log_warn "Không auto detect được interface, mặc định dùng eth0."
    IFACE="eth0"
  else
    IFACE="${iface}"
  fi
  log_info "Sử dụng network interface: ${IFACE}"
}

check_ipv6_routing() {
  log_info "Kiểm tra IPv6 routing (ping6 ipv6.google.com)..."
  if ping6 -c1 -W2 ipv6.google.com >/dev/null 2>&1; then
    log_info "IPv6 hoạt động OK."
  else
    log_warn "IPv6 không ping được ra ngoài (ipv6.google.com)."
    log_warn "Nếu bạn chắc chắn IPv6 vẫn hoạt động, có thể tiếp tục."
    read -rp "Tiếp tục cài đặt dù IPv6 ping lỗi? (y/N): " ans
    ans=${ans:-n}
    if [[ "${ans}" != "y" && "${ans}" != "Y" ]]; then
      log_error "Dừng script vì IPv6 không hoạt động ổn định."
      exit 1
    fi
  fi
}

random_str() {
  tr </dev/urandom -dc A-Za-z0-9 | head -c5
  echo
}

# Preload bảng hex random để sinh IPv6 nhanh hơn (tăng hiệu năng)
preload_hex_table() {
  HEX_TABLE=()
  while IFS= read -r line; do
    HEX_TABLE+=("$line")
  done < <(tr </dev/urandom -dc 'a-f0-9' | fold -w4 | head -n 10000)
}

rand_hex4() {
  # lấy random từ bảng có sẵn
  local idx=$((RANDOM % ${#HEX_TABLE[@]}))
  echo "${HEX_TABLE[$idx]}"
}

# gen64: sinh IPv6 đầy đủ từ prefix /64 dạng 4 block (vd 2001:db8:1234:abcd)
gen64() {
  local prefix="$1"
  echo "${prefix}:$(rand_hex4):$(rand_hex4):$(rand_hex4):$(rand_hex4)"
}

install_deps() {
  log_info "Cài đặt package cần thiết..."
  yum -y install epel-release >/dev/null 2>&1 || true
  yum -y install wget gcc make curl net-tools bsdtar zip iproute iptables >/dev/null
}

install_3proxy() {
  log_info "Cài đặt 3proxy..."
  local URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"

  mkdir -p /opt/3proxy-build
  cd /opt/3proxy-build

  wget -qO- "${URL}" | tar xz
  cd 3proxy-3proxy-0.8.6

  make -f Makefile.Linux

  mkdir -p /usr/local/etc/3proxy/bin /usr/local/etc/3proxy/stat "${LOGDIR}"
  cp src/3proxy /usr/local/etc/3proxy/bin/

  log_info "Đã build xong 3proxy."
}

backup_old_config() {
  if [[ -f /usr/local/etc/3proxy/3proxy.cfg || -f "${WORKDATA}" || -f "${PROXY_TXT}" ]]; then
    mkdir -p "${BACKUPDIR}"
    local ts
    ts=$(date +%Y%m%d-%H%M%S)
    local dest="${BACKUPDIR}/backup-${ts}"
    mkdir -p "${dest}"

    log_info "Backup config cũ vào: ${dest}"

    [[ -f /usr/local/etc/3proxy/3proxy.cfg ]] && cp /usr/local/etc/3proxy/3proxy.cfg "${dest}/"
    [[ -f "${WORKDATA}" ]] && cp "${WORKDATA}" "${dest}/"
    [[ -f "${PROXY_TXT}" ]] && cp "${PROXY_TXT}" "${dest}/"
    [[ -f "${PROXY_CSV}" ]] && cp "${PROXY_CSV}" "${dest}/"
    [[ -f "${WORKDIR}/boot_iptables.sh" ]] && cp "${WORKDIR}/boot_iptables.sh" "${dest}/"
    [[ -f "${WORKDIR}/boot_ifconfig.sh" ]] && cp "${WORKDIR}/boot_ifconfig.sh" "${dest}/"
  fi
}

gen_3proxy_cfg() {
  log_info "Tạo cấu hình 3proxy..."

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
stacksize 6291456

# Logging theo ngày, rotate 30 file
log ${LOGDIR}/3proxy-%y%m%d.log D
rotate 30

flush
auth strong

# users: user:CL:pass
users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' "${WORKDATA}")

# tạo proxy cho từng dòng trong data.txt
$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e" $5 "\n" \
"flush\n"}' "${WORKDATA}")
EOF
}

gen_proxy_txt() {
  log_info "Tạo file proxy.txt (IP4:PORT:USER:PASS)..."
  awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' "${WORKDATA}" > "${PROXY_TXT}"
}

gen_proxy_csv() {
  log_info "Tạo file proxy.csv (ip,port,user,pass,ipv6)..."
  {
    echo "ip,port,user,pass,ipv6"
    awk -F "/" '{print $3","$4","$1","$2","$5}' "${WORKDATA}"
  } > "${PROXY_CSV}"
}

gen_data() {
  log_info "Sinh dữ liệu proxy (user/pass/ip4/port/ipv6)..."
  : > "${WORKDATA}"

  for ((i=0; i<PROXY_COUNT; i++)); do
    port=$((FIRST_PORT + i))
    user="user$(random_str)"
    pass="$(random_str)"
    ipv6=$(gen64 "${IP6_PREFIX}")
    echo "${user}/${pass}/${IP4}/${port}/${ipv6}" >> "${WORKDATA}"
  done

  log_info "Đã sinh ${PROXY_COUNT} proxy."
}

gen_iptables_script() {
  log_info "Tạo script mở iptables..."
  cat <<EOF > "${WORKDIR}/boot_iptables.sh"
#!/bin/bash
# mở port cho proxy IPv4
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' "${WORKDATA}")
EOF
  chmod +x "${WORKDIR}/boot_iptables.sh"
}

gen_ifconfig_script() {
  log_info "Tạo script gán IPv6 cho interface ${IFACE}..."
  cat <<EOF > "${WORKDIR}/boot_ifconfig.sh"
#!/bin/bash
# Gán IPv6, tránh add trùng
$(awk -F "/" -v iface="${IFACE}" '
{
  printf "if ! ip -6 addr show dev %s | grep -q \"%s\"; then ip -6 addr add %s/64 dev %s; fi\n", iface, $5, $5, iface
}' "${WORKDATA}")
EOF
  chmod +x "${WORKDIR}/boot_ifconfig.sh"
}

create_systemd_service() {
  log_info "Tạo systemd service: proxyipv6.service (auto restart)..."
  cat <<EOF >/etc/systemd/system/proxyipv6.service
[Unit]
Description=3proxy IPv6 Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/bash ${WORKDIR}/boot_ifconfig.sh
ExecStartPre=/bin/bash ${WORKDIR}/boot_iptables.sh
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always
RestartSec=3
LimitNOFILE=1000048

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now proxyipv6.service
  log_info "Đã enable & start proxyipv6.service"
}

upload_proxy_list() {
  if [[ ! -f "${PROXY_TXT}" ]]; then
    log_error "Không tìm thấy ${PROXY_TXT} để upload."
    return
  fi
  log_info "Upload proxy.txt lên transfer.sh..."
  local url
  url=$(curl --silent --upload-file "${PROXY_TXT}" https://transfer.sh/proxy.txt || true)
  if [[ -n "${url}" ]]; then
    echo -e "${C_CYAN}Link download proxy: ${url}${C_RESET}"
  else
    log_warn "Upload thất bại."
  fi
}

test_random_proxies() {
  if [[ ! -f "${PROXY_TXT}" ]]; then
    log_error "Không tìm thấy ${PROXY_TXT} để test."
    return
  fi

  read -rp "Test ngẫu nhiên bao nhiêu proxy? (mặc định 5): " N
  N=${N:-5}

  log_info "Test ${N} proxy ngẫu nhiên (cần curl)..."
  shuf -n "${N}" "${PROXY_TXT}" | while IFS=: read -r ip port user pass; do
    echo -e "${C_YELLOW}Test proxy: ${user}:${pass}@${ip}:${port}${C_RESET}"
    curl -sS --max-time 10 -x "http://${user}:${pass}@${ip}:${port}" https://api64.ipify.org || echo "Lỗi hoặc timeout"
    echo
  done
}

#########################
# MAIN INSTALL
#########################

main_install() {
  require_root
  detect_iface
  check_ipv6_routing
  install_deps
  preload_hex_table

  mkdir -p "${WORKDIR}"
  cd "${WORKDIR}"

  # Lấy IPv4
  IP4=$(curl -4 -s icanhazip.com || true)
  if [[ -z "${IP4}" ]]; then
    log_warn "Không lấy được IPv4 tự động."
    read -rp "Nhập IPv4 public của server: " IP4
  fi

  # Lấy IPv6 đầy đủ, cắt 4 block đầu làm prefix /64
  IP6_RAW=$(curl -6 -s icanhazip.com || true)
  IP6_AUTO_PREFIX=$(echo "${IP6_RAW}" | cut -f1-4 -d':' || true)

  echo
  log_info "IP detect được:"
  echo "  IPv4: ${IP4}"
  echo "  IPv6 đầy đủ: ${IP6_RAW}"
  echo "  Gợi ý prefix /64: ${IP6_AUTO_PREFIX}"
  echo

  read -rp "Nhập prefix IPv6 /64 (ví dụ ${IP6_AUTO_PREFIX} hoặc prefix khác bạn muốn): " IP6_PREFIX
  IP6_PREFIX=${IP6_PREFIX:-$IP6_AUTO_PREFIX}

  if [[ -z "${IP6_PREFIX}" ]]; then
    log_error "Prefix IPv6 rỗng, dừng script."
    exit 1
  fi

  log_info "Dùng IPv6 prefix: ${IP6_PREFIX}::/64"

  # Hỏi số lượng proxy & FIRST_PORT
  while :; do
    read -rp "Nhập FIRST_PORT (từ 10000 đến 60000): " FIRST_PORT
    [[ "${FIRST_PORT}" =~ ^[0-9]+$ ]] || { log_warn "Vui lòng nhập số hợp lệ!"; continue; }
    if (( FIRST_PORT >= 10000 && FIRST_PORT <= 60000 )); then
      break
    else
      log_warn "Nằm ngoài khoảng 10000–60000, nhập lại."
    fi
  done

  read -rp "Nhập số lượng proxy muốn tạo (vd 200, 500, 2000): " PROXY_COUNT
  PROXY_COUNT=${PROXY_COUNT:-2000}
  if (( PROXY_COUNT <= 0 )); then
    log_error "Số lượng proxy phải > 0."
    exit 1
  fi

  LAST_PORT=$((FIRST_PORT + PROXY_COUNT - 1))
  log_info "Sẽ tạo ${PROXY_COUNT} proxy, port từ ${FIRST_PORT} đến ${LAST_PORT}"

  backup_old_config
  install_3proxy
  gen_data
  gen_iptables_script
  gen_ifconfig_script
  gen_3proxy_cfg
  gen_proxy_txt
  gen_proxy_csv
  create_systemd_service

  echo
  echo -e "${C_GREEN}=======================================${C_RESET}"
  echo -e "${C_GREEN} ĐÃ HOÀN TẤT CÀI ĐẶT 3PROXY + IPv6     ${C_RESET}"
  echo -e "${C_GREEN} File proxy: ${PROXY_TXT}              ${C_RESET}"
  echo -e "${C_GREEN} File CSV  : ${PROXY_CSV}              ${C_RESET}"
  echo -e "${C_GREEN} Service   : proxyipv6.service         ${C_RESET}"
  echo -e "${C_GREEN}=======================================${C_RESET}"
  echo

  read -rp "Bạn có muốn test thử vài proxy ngay bây giờ? (y/N): " ans
  ans=${ans:-n}
  if [[ "${ans}" == "y" || "${ans}" == "Y" ]]; then
    test_random_proxies
  fi

  read -rp "Bạn có muốn upload proxy.txt lên transfer.sh để tải nhanh? (y/N): " ans2
  ans2=${ans2:-n}
  if [[ "${ans2}" == "y" || "${ans2}" == "Y" ]]; then
    upload_proxy_list
  fi

  echo
  log_info "Hoàn thành. Sau này nếu muốn restart:  systemctl restart proxyipv6"
  log_info "Kiểm tra log 3proxy:  ls ${LOGDIR}"
}

#########################
# ENTRYPOINT
#########################

main_install
