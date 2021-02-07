#! /bin/sh

source $KSROOT/scripts/base.sh
routerdog_pid=$(pidof router_dog)
LOGTIME=$(TZ=UTC-8 date -R "+%Y-%m-%d %H:%M:%S")
if [ -n "${routerdog_pid}" ];then
	http_response "【$LOGTIME】路由狗进程运行正常！（PID：${routerdog_pid}）"
else
	http_response "【$LOGTIME】路由狗进程未运行！"
fi
