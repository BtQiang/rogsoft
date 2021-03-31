#!/bin/sh

source /koolshare/scripts/base.sh

ZERO_SHELL=$(ps|grep "zerotier_config.sh"|grep -v grep)
if [ -n "${ZERO_SHELL}" ];then
	http_response "插件增在启动中...@@waitting"
	exit 0
fi

zerotier_pid=$(pidof zerotier-one)
LOGTIME=$(TZ=UTC-8 date -R "+%Y-%m-%d %H:%M:%S")

#killall zerotier-cli >/dev/null 2>&1
INFO=$(zerotier-cli info|sed 's/ /@@/g')

if [ -n "${zerotier_pid}" ];then
	http_response "zerotier-one 进程运行正常！（PID：${zerotier_pid}）@@${INFO}"
else
	http_response "zerotier-one 进程未运行！@@${INFO}"
fi
