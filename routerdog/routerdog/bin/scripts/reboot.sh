#!/bin/sh

# sync before reboot
sync

# reboot now
local usb2jffs=$(mount|grep -E "/jffs"|grep -Eo "mtdblock" 2>/dev/null)
if [ -n "${usb2jffs}" ];then
	reboot
else
	echo b > /proc/sysrq-trigger
fi