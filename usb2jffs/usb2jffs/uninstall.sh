#!/bin/sh

sh /koolshare/scripts/usb2jffs_configs.sh stop 3

rm -rf /koolshare/res/icon-usb2jffs.png >/dev/null 2>&1
rm -rf /koolshare/scripts/usb2jffs* >/dev/null 2>&1
rm -rf /koolshare/webs/Module_usb2jffs.asp >/dev/null 2>&1
rm -rf /koolshare/init.d/*usb2jffs >/dev/null 2>&1
rm -rf /koolshare/scripts/uninstall_usb2jffs.sh >/dev/null 2>&1

