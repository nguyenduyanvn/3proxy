#!/bin/sh
echo "Vui lòng nhập IPV6ADDR:"
read IPV6ADDR
echo "Vui lòng nhập IPV6_DEFAULTGW:"
read IPV6_DEFAULTGW

echo "Thực hiện cấu hình IPv6..."
echo "IPV6_FAILURE_FATAL=no
IPV6_ADDR_GEN_MODE=stable-privacy
IPV6ADDR=$IPV6ADDR/64
IPV6_DEFAULTGW=$IPV6_DEFAULTGW" >> /etc/sysconfig/network-scripts/ifcfg-eth0
service network restart

# Phần còn lại của script
... (thay thế bằng đoạn mã thứ hai của bạn)
