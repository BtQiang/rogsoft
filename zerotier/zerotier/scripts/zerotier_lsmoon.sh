#!/bin/sh

source /koolshare/scripts/base.sh
eval $(dbus export usb2jffs_)

if [ ! -d "/koolshare/configs/zerotier-one/moons.d" ];then
	http_response ""
	exit 0
fi

cd /koolshare/configs/zerotier-one/moons.d
FILES=$(ls -alrh 000000*.moon|sed 's/.moon//g'|awk '{print $NF}'|sed "s/$/>/g"|tr -d '\n'|sed 's/>$/\n/g')
if [ -z "${FILES}" ];then
	http_response ""
else
	http_response ${FILES}
fi