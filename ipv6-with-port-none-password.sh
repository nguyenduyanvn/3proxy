#!/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c5
	echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	echo "$1:$(ip64)"
}

install_3proxy() {
    URL="https://github.com/nguyenduyanvn/3proxy/raw/refs/heads/main/3proxy-0.9.4.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR
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

$(awk -F "/" '{print "proxy -6 -n -a -p" $4 " -i" $3 " -e" $5 "\nflush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    awk -F "/" '{print $3 ":" $4}' ${WORKDATA} > proxy.txt
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "//NONE//$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -j ACCEPT"}' ${WORKDATA}
}

gen_ifconfig() {
    awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA}
}

# --------------------------
# BẮT ĐẦU CHẠY CHÍNH
# --------------------------

echo "installing apps"
yum -y install wget gcc net-tools bsdtar zip >/dev/null

WORKDIR="/home/duyanmmo"
WORKDATA="${WORKDIR}/data.txt"
rm -rf $WORKDIR
mkdir $WORKDIR && cd $WORKDIR

install_3proxy

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-7 -d':')

echo "IPv4 = $IP4"
echo "IPv6 Prefix = $IP6"

# =============================
# XỬ LÝ FIRST_PORT & COUNT
# =============================
if [ -z "$FIRST_PORT" ]; then
    read -p "Enter FIRST_PORT: " FIRST_PORT
fi

if [ -z "$COUNT" ]; then
    COUNT=2000
fi

LAST_PORT=$(($FIRST_PORT + $COUNT - 1))

echo "Tạo $COUNT proxy từ port $FIRST_PORT → $LAST_PORT"

# =============================
# GEN FILES
# =============================

gen_data > $WORKDIR/data.txt
gen_iptables > $WORKDIR/boot_iptables.sh
gen_ifconfig > $WORKDIR/boot_ifconfig.sh
chmod +x boot_*.sh

gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg

cat <<EOF > /etc/rc.local
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 10048
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
EOF

chmod +x /etc/rc.local
bash /etc/rc.local

gen_proxy_file_for_user

echo "DONE! Proxy list nằm trong: ${WORKDIR}/proxy.txt"
