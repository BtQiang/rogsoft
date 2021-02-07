#!/bin/sh

source /koolshare/scripts/base.sh
eval $(dbus export routerdog_)
LOG_FILE=/tmp/upload/routerdog_log.txt
LOCK_FILE=/var/lock/routerdog.lock
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'

set_lock() {
	exec 1000>"$LOCK_FILE"
	flock -x 1000
}
unset_lock() {
	flock -u 1000
	rm -rf "$LOCK_FILE"
}
sync_ntp(){
	# START_TIME=$(date +%Y/%m/%d-%X)
	echo_date "尝试从ntp服务器：ntp1.aliyun.com 同步时间..."
	ntpclient -h ntp1.aliyun.com -i3 -l -s >/tmp/ali_ntp.txt 2>&1
	SYNC_TIME=$(cat /tmp/ali_ntp.txt|grep -E "\[ntpclient\]"|grep -Eo "[0-9]+"|head -n1)
	if [ -n "${SYNC_TIME}" ];then
		SYNC_TIME=$(date +%Y/%m/%d-%X @${SYNC_TIME})
		echo_date "完成！时间同步为：${SYNC_TIME}"
	else
		echo_date "时间同步失败，跳过！"
	fi
}
fun_wan_start(){
	if [ "${routerdog_enable}" == "1" ];then
		if [ ! -L "/koolshare/init.d/S95routerdog.sh" ];then
			echo_date "添加开机启动..."
			ln -sf /koolshare/scripts/routerdog_config.sh /koolshare/init.d/S95routerdog.sh
		fi
	else
		if [ -L "/koolshare/init.d/S95routerdog.sh" ];then
			echo_date "删除开机启动..."
			rm -rf /koolshare/init.d/S95routerdog.sh >/dev/null 2>&1
		fi
	fi
}
start_routerdog() {
	# 插件开启的时候同步一次时间
	if [ "${routerdog_enable}" == "1" -a -n "$(which ntpclient)" ];then
		sync_ntp
	fi

	# 关闭router_dog进程
	if [ -n "$(pidof router_dog)" ];then
		echo_date "关闭当前路由狗进程..."
		killall router_dog >/dev/null 2>&1
	fi

	# 开启router_dog
	if [ "$routerdog_enable" == "1" ]; then
		echo_date "启动路由狗主程序..."
		export GOGC=40
		cd /koolshare/bin
		./router_dog >/dev/null 2>&1 &
		#start-stop-daemon -S -q -b -m -p /tmp/var/sign.pid -x router_dog
		sleep 1
		local SDPID
		local i=10
		until [ -n "$SDPID" ]; do
			i=$(($i - 1))
			SDPID=$(pidof router_dog)
			if [ "$i" -lt 1 ]; then
				echo_date "路由狗进程启动失败！"
				echo_date "可能是内存不足造成的，建议使用虚拟内存后重试！"
				close_in_five
			else
				echo_date "正在等待路由狗主程序启动 ..."
			fi
			usleep 500000
		done
		echo_date "路由狗启动成功，pid：${SDPID}"
		fun_wan_start
	else
		stop
	fi
	echo_date "路由狗插件启动完毕，本窗口将在5s内自动关闭！"
}
close_in_five() {
	echo_date "插件将在5秒后自动关闭！！"
	local i=5
	while [ $i -ge 0 ]; do
		sleep 1
		echo_date $i
		let i--
	done
	stop
	echo_date "插件已关闭！！"
	unset_lock
	exit
}
stop() {
	# 关闭router_dog进程
	if [ -n "$(pidof router_dog)" ];then
		echo_date "停止路由狗主进程，pid：$(pidof router_dog)"
		killall router_dog >/dev/null 2>&1
	fi

	if [ -L "/koolshare/init.d/S95routerdog.sh" ];then
		echo_date "删除开机启动..."
   		rm -rf /koolshare/init.d/S95routerdog.sh >/dev/null 2>&1
   	fi
}

case $1 in
start)
	set_lock
	if [ "${routerdog_enable}" == "1" ]; then
		logger "[软件中心]: 启动路由狗！"
		start_routerdog
	fi
	unset_lock
	;;
restart)
	set_lock
	if [ "${routerdog_enable}" == "1" ]; then
		stop
		start_routerdog
	fi
	unset_lock
	;;
stop)
	set_lock
	stop
	unset_lock
	;;
esac

case $2 in
web_submit)
	set_lock
	true > $LOG_FILE
	http_response "$1"
	if [ "${routerdog_enable}" == "1" ]; then
		stop | tee -a $LOG_FILE
		start_routerdog | tee -a $LOG_FILE
	else
		stop | tee -a $LOG_FILE
		echo_date "路由狗已经停止运行，本窗口将再5s后关闭！" | tee -a $LOG_FILE
	fi
	echo XU6J03M6 | tee -a $LOG_FILE
	unset_lock
	;;
esac
