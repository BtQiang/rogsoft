#!/bin/sh

source /koolshare/scripts/base.sh

echo zerotier-cli peers > /tmp/upload/zerotier_peers_status.txt
echo "" >> /tmp/upload/zerotier_peers_status.txt
zerotier-cli peers >> /tmp/upload/zerotier_peers_status.txt 2>&1

http_response $1
