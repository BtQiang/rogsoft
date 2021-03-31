#!/bin/sh

eval $(dbus export zerotier_)
source /koolshare/scripts/base.sh
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】:'
config_path="/jffs/softcenter/etc/zerotier-one"
LOG_FILE=/tmp/upload/zerotier_log.txt
LOCK_FILE=/var/lock/zerotier-one.lock
SNAT_FLAG=1
BASH=${0##*/}
ARGS=$@

set_lock(){
	exec 233>${LOCK_FILE}
	flock -n 233 || {
		# bring back to original log
		http_response "$ACTION"
		# echo_date "$BASH $ARGS" | tee -a ${LOG_FILE}
		exit 1
	}
}

unset_lock(){
	flock -u 233
	rm -rf ${LOCK_FILE}
}

#--------------------------------------------------------------------------
del_rules() {
	iptables -t nat -D POSTROUTING -o $zt0 -j MASQUERADE 2>/dev/null
	iptables -t nat -D POSTROUTING -s $ip_segment -j MASQUERADE 2>/dev/null
}

zero_route(){
	for i in $(seq 1 $zerotier_staticnum_x)
	do
		j=`expr $i - 1`
		route_enable=`dbus get zerotier_enable_x_$j`
		zero_ip=`dbus get zerotier_ip_x_$j`
		zero_route=`dbus get zerotier_route_x_$j`
		if [ "$1" = "ADD" ]; then
			if [ $route_enable -ne 0 ]; then
				ip route ADD $zero_ip via $zero_route dev $zt0
				#echo "$zt0"
			fi
		else
			ip route del $zero_ip via $zero_route dev $zt0
		fi
	done
}
#--------------------------------------------------------------------------

close_in_five() {
	echo_date "插件将在5秒后自动关闭！！"
	local i=5
	while [ $i -ge 0 ]; do
		sleep 1
		echo_date $i
		let i--
	done
	stop_zerotier
	dbus set zerotier_enable=0
	sync
	echo_date "插件已关闭！！"
	echo_date ======================= 梅林固件 - 【科学上网】 ========================
	unset_lock
	exit
}

close_port(){
	echo_date "关闭本插件在防火墙上打开的所有端口!"
	cd /tmp
	iptables -t filter -S|grep -w "zerotier_rule"|sed 's/-A/iptables -t filter -D/g' > clean.sh && chmod 777 clean.sh && ./clean.sh > /dev/null 2>&1 && rm clean.sh
	iptables -t nat -S|grep -w "zerotier_rule"|sed 's/--mode fullcone/ --mode fullcone/g'|sed 's/-A/iptables -t nat -D/g' > clean.sh && chmod 777 clean.sh && ./clean.sh > /dev/null 2>&1 && rm clean.sh
}

stop_zerotier(){
	# stop first
	local ZERO_PID=$(pidof zerotier-one)
	if [ -n "${ZERO_PID}" ];then
		echo_date "关闭zerotier-one进程！"
		kill -9 ${ZERO_PID} >/dev/null 2>&1
	fi

	# stop other process
	killall zerotier-cli >/dev/null 2>&1
	killall zerotier_ifaces.sh >/dev/null 2>&1
	killall zerotier_peerss.sh >/dev/null 2>&1
	killall zerotier_status.sh >/dev/null 2>&1
	killall zerotier_ztnets.sh >/dev/null 2>&1

	close_port
	iptables -t nat -D POSTROUTING -o ztppitfurk -j MASQUERADE >/dev/null 2>&1
}

start_zerotier(){
	# 1. stop first
	stop_zerotier >/dev/null 2>&1

	# 2. insert module
	local TU=$(lsmod |grep -w tun)
	local CM=$(lsmod | grep xt_comment)
	local OS=$(uname -r)
	if [ -z "${TU}" ];then
		"echo_date 加载tun内核模块！"
		modprobe tun
	fi
	if [ -z "${CM}" -a -f "/lib/modules/${OS}/kernel/net/netfilter/xt_comment.ko" ];then
		"echo_date 加载xt_comment.ko内核模块！"
		insmod /lib/modules/${OS}/kernel/net/netfilter/xt_comment.ko
	fi

	# 3. start zerotier-one process
	echo_date "启动zerotier-one进程..."
	zerotier-one >/dev/null 2>&1 &
	local ZTPID
	local i=10
	until [ -n "$ZTPID" ]; do
		i=$(($i - 1))
		ZTPID=$(pidof zerotier-one)
		if [ "$i" -lt 1 ]; then
			echo_date "zerotier进程启动失败！"
			echo_date "关闭插件！"
			close_in_five
		fi
		usleep 250000
	done
	echo_date "zerotier-one进程启动成功，pid：${ZTPID}"

	# 4 open firewall, incase zerotier-one can't connect to nerwork
	local FWENABLE=$(nvram get fw_enable_x)
	if [ "${FWENABLE}" == "1" ];then
		local PORTS=$(netstat -nlp|grep zerotier-one|awk '{print $4}'|awk -F":" '{print $2}'|sort -un)
		
		echo_date "添加防火墙入站规则，打开zerotier监听端口："${PORTS}
		for PORT in $PORTS
		do
			iptables -I INPUT -p tcp --dport $PORT -j ACCEPT -m comment --comment "zerotier_rule" >/dev/null 2>&1
			iptables -I INPUT -p udp --dport $PORT -j ACCEPT -m comment --comment "zerotier_rule" >/dev/null 2>&1
		done
	fi
	
	# 5. check zerotier ONLINE status
	echo_date "等待zerotier连接到网络，此处可能会等待较长时间，请稍候..."
	local RET ADD VER STA
	local j=120
	until [ "$STA" == "ONLINE" ]; do
		usleep 250000
		j=$(($j - 1))
		# stop some process first
		killall zerotier_status.sh >/dev/null 2>&1
		killall zerotier-cli >/dev/null 2>&1
		local CAS=$(echo $j|awk '{for(i=1;i<=NF;i++)if(!($i%5))print $i}')
		local RET=$(zerotier-cli info|grep "info" 2>/dev/null)
		local ADD=$(echo "$RET"|awk '{print $3}' 2>/dev/null)
		local VER=$(echo "$RET"|awk '{print $4}' 2>/dev/null)
		local STA=$(echo "$RET"|awk '{print $5}' 2>/dev/null)
		
		[ -n "$CAS" ] && echo_date "节点ID：$ADD，版本：$VER，在线状态：$STA"
		if [ "$j" -lt 1 ]; then
			echo_date "zerotier在30s内没有连接到网络！请检查你的路由器网络是否畅通！"
			echo_date "在网络较差的情况下，可能需要等更久的时间，状态才会变成ONLINE"
			echo_date "如果一直是在OFFLINE状态下，可能无法访问其它zerotier网络下的主机！"
			echo_date "插件将继续运行，运行完毕后，请注意插件界面的zerotier network状态！"
			#echo_date "关闭插件！"
			#close_in_five
			break
		fi
	done
	echo_date "节点ID：$ADD，版本：$VER，在线状态：$STA"
	echo_date "成功连接zerotier网络！"

	# 6. check network join status
	ZTNETS=$(zerotier-cli -j listnetworks 2>/dev/null)
	local JSON_1=$(echo "$ZTNETS"|grep -Eo "\[")
	local JSON_2=$(echo "$ZTNETS"|grep -Eo "\]")
	if [ -z "$JSON_1" -o -z "$JSON_2" ];then
		echo_date "─────────────────────────────────────────────────────────────"
		echo_date "出现未知错误，无法获取zerotier网络状态！"
		echo_date "这可能是zerotier-one进程运行出现问题！"
		echo_date "关闭插件！"
		echo_date "─────────────────────────────────────────────────────────────"
		close_in_five
	fi
	
	if [ "${ZTNETS}" == "[]" ];then
		echo_date "─────────────────────────────────────────────────────────────"
		echo_date "提醒：检测到你尚未加入任何zerotier网络！"
		echo_date "请前往zerotier后台：my.zerotier.com 创建网络并获取 NETWORK ID"
		echo_date "然后将 NETWORK ID 填入本插件，点击\"+\"加入zerotier网络！"
		echo_date "─────────────────────────────────────────────────────────────"
		return 1
	fi

	# 7. 检查配置
	local ZT_NU=$(echo $ZTNETS | jq '. | length' 2>/dev/null)
	local COUNT=0
	echo_date "检测到你配置了 ${ZT_NU} 个zerotier网络！"
	until [ "$COUNT" == "$ZT_NU" ]; do
		local NETWORK=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].id')
		local NAME=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].name')
		local STATUS=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].status')
		local TYPE=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].type')
		local MAC=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].mac')
		local MTU=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].mtu')
		local BROADCAST=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].broadcastEnabled')
		local BRIDGE=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].bridge')
		local DEVICE=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].portDeviceName')
		local IPADDR=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].assignedAddresses[]'|tr "\n" " ")

		if [ "$COUNT" -ge "1" ];then
			echo_date ""
		fi

		# 虽然命令 zerotier-cli -j listnetworks 说是有网卡(DEVICE)了，还是检查下网卡是否存在
		local IS_DEVICE=$(ifconfig $DEVICE 2>/dev/null)
		if [ -z "$DEVICE" -o -z "$IS_DEVICE" ];then
			echo_date "─────────────────────────────────────────────────────────────"
			echo_date "出现未知错误，device参数为空！"
			echo_date "这可能是系统tun网卡加载错误导致的"
			echo_date "请重启路由器后重新尝试！关闭插件！"
			echo_date "─────────────────────────────────────────────────────────────"
			close_in_five
		fi
		
		# OK, NOT_FOUND, ACCESS_DENIED, or PORT_ERROR
		# ref: https://zerotier.atlassian.net/wiki/spaces/SD/pages/29065282/Command+Line+Interface+zerotier-cli
		if [ "${STATUS}" == "PORT_ERROR" ];then
			echo_date "─────────────────────────────────────────────────────────────"
			echo_date "加入zerotier network: ${NETWORK} 错误，错误代码：PORT_ERROR
			echo_date "请重启路由器后重新尝试！关闭插件！"
			echo_date "─────────────────────────────────────────────────────────────"
			close_in_five
		fi

		if [ "${STATUS}" == "NOT_FOUND" ];then
			echo_date "─────────────────────────────────────────────────────────────"
			echo_date "加入zerotier network: ${NETWORK} 错误，错误代码：NOT_FOUND
			echo_date "请确认是否输入了正确的 Network ID，关闭插件！"
			echo_date "─────────────────────────────────────────────────────────────"
			close_in_five
		fi
		 # sometime status show REQUESTING_CONFIGURATION
		if [ "${STATUS}" == "ACCESS_DENIED" -o "${STATUS}" != "OK" ];then
			echo_date "─────────────────────────────────────────────────────────────"
			echo_date "加入zerotier network: ${NETWORK} ..."
			echo_date "当前状态：${STATUS}"
			echo_date "提醒：请前往zerotier后台授权设备：${ADD} 加入：${NETWORK}！"
			echo_date "如果zerotier后台没出现该设备，请使用[MANUALLY ADD MEMBER]功能手动添加！"
			echo_date "授权设备：${ADD} 加入zerotier局域网后，虚拟网卡才能正确获得IP地址!"
			SNAT_FLAG=0
		fi

		if [ "${STATUS}" == "OK" ];then
			# 虽然命令 zerotier-cli -j listnetworks 说是有IP了，还是检查下网卡是否有IP地址
			local IS_IPADDR=$(ifconfig ${DEVICE} | grep "inet addr" | cut -d ":" -f2 | awk '{print $1}' 2>/dev/null)
			if [ -z "$IPADDR" -o -z "$IS_IPADDR" ];then
				echo_date "─────────────────────────────────────────────────────────────"
				echo_date "出现未知错误，网卡${DEVICE}没有获取到ip地址！"
				echo_date "请检查你的zerotier后台设置是否正确！"
				echo_date "关闭插件！"
				echo_date "─────────────────────────────────────────────────────────────"
				close_in_five
			fi
			# 成功，打印网络信息
			echo_date "─────────────────────────────────────────────────────────────"
			echo_date "加入zerotier network: ${NETWORK} 成功！"
			echo_date "┌ network: $NETWORK"
			echo_date "├ name: $NAME"
			echo_date "├ status: $STATUS"
			echo_date "├ type: $TYPE"
			echo_date "├ mac: $MAC"
			echo_date "├ mtu: $MTU"
			echo_date "├ brodcast: $BROADCAST"
			echo_date "├ bridge: $BRIDGE"
			echo_date "├ device: $DEVICE"
			echo_date "└ ipaddr: $IPADDR"
		fi
		
		# 1. firewall
		iptables -I INPUT -i ${DEVICE} -j ACCEPT -m comment --comment "zerotier_rule" >/dev/null 2>&1
		iptables -I FORWARD -i ${DEVICE} -o ${DEVICE} -j ACCEPT -m comment --comment "zerotier_rule" >/dev/null 2>&1
		iptables -I FORWARD -i ${DEVICE} -j ACCEPT -m comment --comment "zerotier_rule" >/dev/null 2>&1

		# 2. DNAT
		local ZTADD=$(echo ${IPADDR}|awk -F "/" '{print $1}')
		local LANIP=$(ifconfig br0|grep -Eo "inet addr.+"|awk -F ":| " '{print $3}' 2>/dev/null)
		if [ -n "${LANIP}" -a -n "${ZTADD}" ];then
			echo_date "写入DNAT规则..."
			iptables -t nat -A PREROUTING -d ${ZTADD} -j DNAT --to-destination ${LANIP} -m comment --comment "zerotier_rule"
			if [ "$?" == "0" ];then
				echo_date "DNAT规则写入成功！"
			fi
		fi

		# 3. SNAT
		local IPTABLE_FLAG=$(iptables -t nat -S|grep -w ${DEVICE}|grep -w MASQUERADE 2>/dev/null)
		if [ -z "${IPTABLE_FLAG}" -a "${zerotier_nat}" == "1" -a "${SNAT_FLAG}" == "1" ];then
			local RULE_INDEX=$(iptables -t nat -nvL POSTROUTING --line-numbers|sed '1,2d'|sed -n '/MASQUERADE/='|sort -n|head -n1 2>/dev/null)
			if [ -n "${RULE_INDEX}" ];then
				echo_date "写入SNAT规则..."
				#iptables -t nat -I POSTROUTING -s ${ZTADD}/24 -j MASQUERADE --mode fullcone -m comment --comment "zerotier_rule"
				iptables -t nat -I POSTROUTING ${RULE_INDEX} -o ${DEVICE} -j MASQUERADE --mode fullcone -m comment --comment "zerotier_rule"
				if [ "$?" == "0" ];then
					echo_date "SNAT规则写入成功！"
				fi
			fi
		fi

		# count + 1
		let COUNT+=1
		echo_date "─────────────────────────────────────────────────────────────"
	done

	# start on boot
	if [ ! -L "/koolshare/init.d/S99zerotier.sh" ];then
		ln -sf /koolshare/scripts/zerotier_config.sh /koolshare/init.d/S99zerotier.sh
	fi
	
	# finish
	echo_date "zerotier插件启动完毕！"
}

leave_network_now(){
	# 1. check network id -1
	if [ -z "$zerotier_leave_id" ];then
		echo_date "Network ID为空，请检查设置..."
		return 1
	fi

	# 2. check network id -1
	if [ "${#zerotier_leave_id}" != "16" ];then
		echo_date "Network ID格式错误，正确的应该是16位，请检查设置..."
		return 1
	fi
		
	# 3. check zerotier running status
	local ZTPID=$(pidof zerotier-one)
	if [ -n "$ZTPID" ];then
		echo_date "zerotier-one进程运行正常，pid：${ZTPID}"
	fi

	# 4. get network device name, eg: ztppitfurk, zt44xahn7g
	local L_DEVICE=$(zerotier-cli listnetworks|grep listnetworks|grep $zerotier_leave_id|grep -Eo "zt\w+")

	# 5. start to leave
	echo_date "离开 Network ID: $zerotier_leave_id ..."
	local RET=$(zerotier-cli leave $zerotier_leave_id)
	echo_date $RET

	# 6 leave status
	local L_STATUS=$(echo $RET|grep leave|grep -Eo "OK")
	if [ "$L_STATUS" == "OK" ];then
		echo_date "离开 Network ID: $zerotier_leave_id 成功！"
	else
		echo_date "删除 Network ID: $zerotier_leave_id 的配置文件！"
		rm -rf /koolshare/configs/zerotier-one/network.d/${zerotier_leave_id}*
	fi
	
	# 7 remove iptables rules related to $zerotier_leave_id
	if [ -n "$L_DEVICE" ];then
		echo_date "删除此网络的相关防火墙规则!"
		cd /tmp
		iptables -t filter -S|grep -w "zerotier_rule"|grep $L_DEVICE|sed 's/-A/iptables -t filter -D/g' > clean.sh && chmod 777 clean.sh && ./clean.sh > /dev/null 2>&1 && rm clean.sh
		iptables -t nat -S|grep -w "zerotier_rule"|grep $L_DEVICE|sed 's/--mode fullcone/ --mode fullcone/g'|sed 's/-A/iptables -t nat -D/g' > clean.sh && chmod 777 clean.sh && ./clean.sh > /dev/null 2>&1 && rm clean.sh
	fi
	
	echo_date "完成！"
}

join_moon_now(){
	if [ -n "$1" ];then
		local MOON_ID=$1
	fi
	echo_date "加入moon: $MOON_ID"

	local RET=$(zerotier-cli orbit $MOON_ID $MOON_ID)

	echo_date $RET
}

join_network_now(){
	# 1. check network id -1
	if [ -z "$zerotier_join_id" ];then
		echo_date "Network ID为空，请检查设置..."
		return 1
	fi

	# 2. check network id -1
	if [ "${#zerotier_join_id}" != "16" ];then
		echo_date "Network ID格式错误，正确的应该是16位，请检查设置..."
		return 1
	fi

	# 3. check network id -2
	local SUF=$(echo $zerotier_join_id | sed 's/^000000//g')
	if [ "${#SUF}" == "10" ];then
		echo_date "检测到moon配置id：$zerotier_join_id，即将加入moon..."
		join_moon_now $zerotier_join_id
		return 0
	fi
		
	# 4. check zerotier running status
	local ZTPID=$(pidof zerotier-one)
	if [ -n "$ZTPID" ];then
		echo_date "zerotier-one进程运行正常，pid：${ZTPID}"
	fi

	# 5. check zerotier ONLINE status
	echo_date "检查zerotier是否已经连接到网络，请稍候..."
	local RET_C ADD VER STA
	local j=120
	until [ "$STA" == "ONLINE" ]; do
		usleep 250000
		j=$(($j - 1))
		# stop some process first
		killall zerotier_status.sh >/dev/null 2>&1
		killall zerotier-cli >/dev/null 2>&1
		local CAS=$(echo $j|awk '{for(i=1;i<=NF;i++)if(!($i%5))print $i}')
		local RET_C=$(zerotier-cli info|grep "info" 2>/dev/null)
		local ADD=$(echo "$RET_C"|awk '{print $3}' 2>/dev/null)
		local VER=$(echo "$RET_C"|awk '{print $4}' 2>/dev/null)
		local STA=$(echo "$RET_C"|awk '{print $5}' 2>/dev/null)
		
		[ -n "$CAS" ] && echo_date "节点ID：$ADD，版本：$VER，在线状态：$STA"
		if [ "$j" -lt 1 ]; then
			echo_date "zerotier在30s内没有连接到网络！请检查你的路由器网络是否畅通！"
			echo_date "在网络较差的情况下，可能需要等更久的时间，状态才会变成ONLINE"
			echo_date "如果一直是在OFFLINE状态下，可能无法访问其它zerotier网络下的主机！"
			echo_date "插件将继续运行，运行完毕后，请注意插件界面的zerotier network状态！"
			#echo_date "关闭插件！"
			#close_in_five
			break
		fi
	done
	echo_date "节点ID：$ADD，版本：$VER，在线状态：$STA"
	echo_date "成功连接zerotier网络！"

	# 6. start to join
	echo_date "加入 Network ID: $zerotier_join_id ..."
	local RET_J=$(zerotier-cli join $zerotier_join_id)
	echo_date $RET_J

	# 7 join status
	local J_STATUS=$(echo $RET_J|grep join|grep -Eo "OK")
	if [ "$J_STATUS" == "OK" ];then
		echo_date "加入 Network ID: $zerotier_join_id 成功！"
	else
		rm -rf /koolshare/configs/zerotier-one/network.d/${zerotier_join_id}*
		echo_date "-------------------------------------------------------------------"
		echo_date "加入 Network ID: $zerotier_join_id 失败！错误代码：$J_STATUS"
		echo_date "请确认是否输入了正确的 Network ID！"
		echo_date "-------------------------------------------------------------------"
		return 1
	fi

	local ZTNETS=$(zerotier-cli -j listnetworks 2>/dev/null)
	local JSON_1=$(echo "$ZTNETS"|grep -Eo "\[")
	local JSON_2=$(echo "$ZTNETS"|grep -Eo "\]")
	if [ -z "$JSON_1" -o -z "$JSON_2" ];then
		echo_date "──────────────────────────────────────────────────────────────────"
		echo_date "出现未知错误，无法获取zerotier网络状态！"
		echo_date "这可能是zerotier-one进程运行出现问题！"
		echo_date "关闭插件！"
		echo_date "──────────────────────────────────────────────────────────────────"
		close_in_five
	fi
	
	if [ "${ZTNETS}" == "[]" ];then
		echo_date "──────────────────────────────────────────────────────────────────"
		echo_date "提醒：检测到你尚未加入任何zerotier网络！"
		echo_date "请前往zerotier后台：my.zerotier.com 创建网络并获取 NETWORK ID"
		echo_date "然后将 NETWORK ID 填入本插件，点击\"+\"加入zerotier网络！"
		echo_date "──────────────────────────────────────────────────────────────────"
		return 1
	fi

	# 7. get network device name, eg: ztppitfurk, zt44xahn7g
	local ZT_NU=$(echo $ZTNETS | jq '. | length' 2>/dev/null)
	local COUNT=0
	until [ "$COUNT" == "$ZT_NU" ]; do
		local NETWORK=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].id')
		local NAME=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].name')
		local STATUS=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].status')
		local TYPE=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].type')
		local MAC=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].mac')
		local MTU=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].mtu')
		local BROADCAST=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].broadcastEnabled')
		local BRIDGE=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].bridge')
		local DEVICE=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].portDeviceName')
		local IPADDR=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].assignedAddresses[]'|tr "\n" " ")

		# 虽然命令 zerotier-cli -j listnetworks 说是有网卡(DEVICE)了，还是检查下网卡是否存在
		local IS_DEVICE=$(ifconfig $DEVICE 2>/dev/null)
		if [ -z "$DEVICE" -o -z "$IS_DEVICE" ];then
			echo_date "──────────────────────────────────────────────────────────────────"
			echo_date "出现未知错误，device参数为空！"
			echo_date "这可能是系统tun网卡加载错误导致的"
			echo_date "请重启路由器后重新尝试！关闭插件！"
			echo_date "──────────────────────────────────────────────────────────────────"
			close_in_five
		fi
		
		if [ "$NETWORK" == "$zerotier_join_id" ];then
			echo_date "等待zerotier连接上 Network ID: ${NETWORK} 网络..."
		fi
		
		local j=60
		until [ "${STATUS}" == "PORT_ERROR" -o "${STATUS}" == "NOT_FOUND" -o "${STATUS}" == "ACCESS_DENIED" -o "${STATUS}" == "OK" ]; do
		#until [ -n "${STATUS}" ]; do
			j=$(($j - 1))
			local ZTNETS=$(zerotier-cli -j listnetworks 2>/dev/null)
			local NETWORK=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].id')
			local NAME=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].name')
			local STATUS=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].status')
			local TYPE=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].type')
			local MAC=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].mac')
			local MTU=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].mtu')
			local BROADCAST=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].broadcastEnabled')
			local BRIDGE=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].bridge')
			local DEVICE=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].portDeviceName')
			local IPADDR=$(echo "$ZTNETS" | jq -r --argjson count $COUNT '.[$count].assignedAddresses[]'|tr "\n" " ")
			
			local CAS=$(echo $j|awk '{for(i=1;i<=NF;i++)if(!($i%5))print $i}')
			if [ -n "${CAS}" ];then
				echo_date "等待${j}s..."
			fi
			if [ "$j" -lt 1 ]; then
				echo_date "等待超时..."
				break
			fi
			sleep 1
		done
		let COUNT+=1

		if [ "$NETWORK" != "$zerotier_join_id" ];then
			continue
		fi

		# echo_date "检测到网卡：$DEVICE 已经正确加载..."
		
		# status
		if [ "${STATUS}" == "PORT_ERROR" ];then
			echo_date "──────────────────────────────────────────────────────────────────"
			echo_date "加入zerotier network: ${NETWORK} 错误，错误代码：PORT_ERROR
			echo_date "请重启路由器后重新尝试！关闭插件！"
			echo_date "──────────────────────────────────────────────────────────────────"
			close_in_five
		fi

		if [ "${STATUS}" == "NOT_FOUND" ];then
			echo_date "──────────────────────────────────────────────────────────────────"
			echo_date "加入zerotier network: ${NETWORK} 错误，错误代码：NOT_FOUND
			echo_date "请确认是否输入了正确的 Network ID，关闭插件！"
			echo_date "──────────────────────────────────────────────────────────────────"
			close_in_five
		fi
		
		# sometime status show REQUESTING_CONFIGURATION
		if [ "${STATUS}" == "ACCESS_DENIED" -o "${STATUS}" != "OK" ];then
			echo_date "──────────────────────────────────────────────────────────────────"
			echo_date "加入zerotier network: ${NETWORK} ..."
			echo_date "当前状态：${STATUS}"
			echo_date "提醒：请前往zerotier后台授权设备：${ADD} 加入：${NETWORK}！"
			echo_date "如果zerotier后台没出现该设备，请使用[MANUALLY ADD MEMBER]功能手动添加！"
			echo_date "授权设备：${ADD} 加入zerotier局域网后，虚拟网卡才能正确获得IP地址!"
			echo_date "──────────────────────────────────────────────────────────────────"
		fi

		if [ "${STATUS}" == "OK" ];then
			# 虽然命令 zerotier-cli -j listnetworks 说是有IP了，还是检查下网卡是否有IP地址
			local IS_IPADDR=$(ifconfig ${DEVICE} | grep "inet addr" | cut -d ":" -f2 | awk '{print $1}' 2>/dev/null)
			if [ -z "$IPADDR" -o -z "$IS_IPADDR" ];then
				echo_date "──────────────────────────────────────────────────────────────────"
				echo_date "出现未知错误，网卡${DEVICE}没有获取到ip地址！"
				echo_date "请检查你的zerotier后台设置是否正确！"
				echo_date "关闭插件！"
				echo_date "──────────────────────────────────────────────────────────────────"
				#close_in_five
			fi
			# 成功，打印网络信息
			echo_date "──────────────────────────────────────────────────────────────────"
			echo_date "加入zerotier network: ${NETWORK} 成功！"
			echo_date "┌ network: $NETWORK"
			echo_date "├ name: $NAME"
			echo_date "├ status: $STATUS"
			echo_date "├ type: $TYPE"
			echo_date "├ mac: $MAC"
			echo_date "├ mtu: $MTU"
			echo_date "├ brodcast: $BROADCAST"
			echo_date "├ bridge: $BRIDGE"
			echo_date "├ device: $DEVICE"
			echo_date "└ ipaddr: $IPADDR"
			echo_date "──────────────────────────────────────────────────────────────────"
			echo_date "加入 Network ID: ${NETWORK} 完毕！"
		fi
	done
}

upload_moon_now(){
	# get moon name from skipd
	if [ -z "${zerotier_moon_name}" ];then
		echo_date "参数错误！请装插件后再试！"
		rm -rf /tmp/upload/*.moon >/dev/null 2>&1
		return 1
	fi

	# find moon files
	if [ -f "/tmp/upload/${zerotier_moon_name}" ];then
		echo_date "找到你上传的moon配置文件：${zerotier_moon_name}"
	else
		echo_date "没有找到你上传的moon配置文件！"
		rm -rf /tmp/upload/*.moon >/dev/null 2>&1
		return 1
	fi

	# file format 1: must have prefix and suffix
	local SPL=$(echo ${zerotier_moon_name}|grep -Eo "\."|wc -l)
	if [ "$SPL" != "1" ];then
		echo_date "你上传的moon配置文件：${zerotier_moon_name} 格式错误！"
		echo_date "正确的moon配置文件名例子：0000003bcf160f91.moon"
		echo_date "本次退出！"
		rm -rf /tmp/upload/*.moon >/dev/null 2>&1
		return 1
	fi

	# prefix length must be 16, and start with 000000
	local PRE=$(echo ${zerotier_moon_name}|awk -F "." '{print $1}')
	local MAH=$(echo $PRE|grep -Eo "^000000")
	if [ "${#PRE}" != "16" -o -z "${MAH}" ];then
		echo_date "你上传的moon配置文件：${zerotier_moon_name}文件名错误！"
		echo_date "正确的moon配置文件名例子：0000003bcf160f91.moon"
		echo_date "本次退出！"
		rm -rf /tmp/upload/*.moon >/dev/null 2>&1
		return 1
	fi
	
	# suffix must be "moon"
	local SUF=$(echo ${zerotier_moon_name}|awk -F "." '{print $2}')
	if [ "${SUF}" != "moon" ];then
		echo_date "你上传的moon配置文件：${zerotier_moon_name}文件后缀错误！"
		echo_date "正确的moon配置文件名例子：0000003bcf160f91.moon"
		echo_date "本次退出！"
		rm -rf /tmp/upload/*.moon >/dev/null 2>&1
		return 1
	fi

	# moon file content format must be data，for example: file 0000003bcf160f91.moon, rusult: 0000003bbff60f9e.moon: data
	if [ -n "$(which file)" ];then
		local FORMAT=$(file /tmp/upload/${zerotier_moon_name}|awk '{print $2}')
		if [ "$FORMAT" == "data" ];then
			echo_date "你上传的moon配置文件：${zerotier_moon_name} 格式正确"
		else
			echo_date "你上传的moon配置文件：${zerotier_moon_name} 格式错误！"
			echo_date "请检查你的moon配置文件！"
			echo_date "删除相关文件并退出！"
			rm -rf /tmp/upload/*.moon >/dev/null 2>&1
			return 1
		fi
	fi

	# see if this moon have been configed
	if [ -f "/koolshare/configs/zerotier-one/moons.d/${zerotier_moon_name}" ];then
		echo_date "检测到你上传的moon配置文件已经配置过了！"
		echo_date "如果你需要重新配置此moon，请先删除此moon的配置后重新加入！"
		echo_date "本次退出！"
		rm -rf /tmp/upload/*.moon >/dev/null 2>&1
		return 1
	fi

	# see if zerotier-one running
	local ZTPID=$(pidof zerotier-one)
	if [ -z "$ZTPID" ];then
		echo_date "检测到zerotier-one进程未运行！"
		echo_date "请重启插件后重试！"
		echo_date "本次退出！"
		rm -rf /tmp/upload/*.moon >/dev/null 2>&1
		return 1		
	fi
	# install xxx.moon file
	echo_date "安装moon配置文件：${zerotier_moon_name}！"
	mkdir -p /koolshare/configs/zerotier-one/moons.d
	mv /tmp/upload/${zerotier_moon_name} /koolshare/configs/zerotier-one/moons.d/

	# restart zerotier
	echo_date "安装成功，重启zerotier"
	start_zerotier

	# message
	local SHORT_MOON=$(echo $PRE|sed 's/^000000//g')
	echo_date "请在使用[zerotier peers]查看moon：${SHORT_MOON} 是否加入成功。"
}

orbit_moon_now(){
	# get moon id from skipd
	if [ -z "${zerotier_orbit_moon_id}" ];then
		echo_date "参数错误！请装插件后再试！"
		return 1
	fi

	# format
	local MAH=$(echo ${zerotier_orbit_moon_id}|grep -Eo "^000000")
	if [ "${#zerotier_orbit_moon_id}" != "16" -o -z "${MAH}" ];then
		echo_date "moon id：${zerotier_orbit_moon_id} 格式错误！"
		echo_date "正确的moon id示例：0000003bcf160f91"
		echo_date "本次退出！"
		return 1
	fi

	# if this moon exist
	if [ -f "/koolshare/configs/zerotier-one/moons.d/${zerotier_orbit_moon_id}.moon" ];then
		echo_date "检测到此moon id: ${zerotier_orbit_moon_id} 已经配置过了！"
		echo_date "如果你需要重新配置此moon，请先删除此moon的配置后重新加入！"
		echo_date "本次退出！"
		return 1
	fi

	# see if zerotier-one running
	local ZTPID=$(pidof zerotier-one)
	if [ -z "$ZTPID" ];then
		echo_date "检测到zerotier-one进程未运行！"
		echo_date "请重启插件后重试！"
		echo_date "本次退出！"
		rm -rf /tmp/upload/*.moon >/dev/null 2>&1
		return 1		
	fi

	# orbit now
	local RET=$(zerotier-cli orbit ${zerotier_orbit_moon_id} ${zerotier_orbit_moon_id})
	local OOK=$(echo $RET|grep "200 orbit OK")
	if [ -n "$OOK" ];then
		echo_date "$RET"
	else
		echo_date "zerotier 加入moon失败！"
		echo_date "请尝试重装插件后重试！"
		echo_date "本次退出！"
		return 1
	fi

	# detect moon file existence
	echo_date "检测zerotier是否连接上moon id: ${zerotier_orbit_moon_id} ..."
	local i=30
	until [ -f "/koolshare/configs/zerotier-one/moons.d/${zerotier_orbit_moon_id}.moon" ]; do
		i=$(($i - 1))
		local CAS=$(echo $i|awk '{for(i=1;i<=NF;i++)if(!($i%10))print $i}')
		[ -n "$CAS" ] && echo_date "请等待${i}s..."
		if [ "$i" -lt 1 ]; then
			echo_date "检测超时：在30s内没有检测到zerotier连接上moon id: ${zerotier_orbit_moon_id}！"
			echo_date "请在插件内使用[zerotier peers]按钮查看moon：${zerotier_orbit_moon_id} 是否加入成功。"
			break
		fi
		sleep 1
	done
	echo_date "zerotier moon id: ${zerotier_orbit_moon_id} 配置成功！"

	# status
	local SHORT_MOON=$(echo ${zerotier_orbit_moon_id}|sed 's/^000000//g')
	echo_date "请在插件内使用[zerotier peers]按钮查看moon：${zerotier_orbit_moon_id} 是否加入成功。"
}

deorbit_moon_now(){
	# get moon id from skipd
	if [ -z "${zerotier_deorbit_moon_id}" ];then
		echo_date "参数错误！请装插件后再试！"
		return 1
	fi

	# find coresponding moon in moons.d
	if [ ! -f "/koolshare/configs/zerotier-one/moons.d/${zerotier_deorbit_moon_id}.moon" ];then
		echo_date "检测到当前zerotier并未加入该moon，无需离开！"
		echo_date "本次退出！"
		return 1
	fi

	# see if zerotier-one running
	local ZTPID=$(pidof zerotier-one)
	if [ -z "$ZTPID" ];then
		echo_date "检测到zerotier-one进程未运行！"
		echo_date "尝试删除moon配置文件，以便下次zerotier启动不会加入该moon！"
		rm -rf /koolshare/configs/zerotier-one/moons.d/${zerotier_deorbit_moon_id}.moon >/dev/null 2>&1
		echo_date "删除成功！"
	fi

	# start to leave
	local RET=$(zerotier-cli deorbit ${zerotier_deorbit_moon_id})
	local DOK=$(echo $RET|grep "200 deorbit OK")
	if [ -n "$DOK" ];then
		echo_date "$RET"
	else
		echo_date "zerotier 离开moon失败！"
		echo_date "尝试删除moon配置文件并重启zerotier-one进程，以离开此moon！"
		rm -rf /koolshare/configs/zerotier-one/moons.d/${zerotier_deorbit_moon_id}.moon >/dev/null 2>&1
		echo_date "删除成功，重启zerotier！"
		start_zerotier
		echo_date "请在插件内使用[zerotier peers]按钮查看是否成功离开。"		
		return 1
	fi
	# remove moon file to ensure deorbit ok
	if [ -f "/koolshare/configs/zerotier-one/moons.d/${zerotier_deorbit_moon_id}" ];then
		echo_date "移除moon配置文件！"
		rm -rf /koolshare/configs/zerotier-one/moons.d/${zerotier_deorbit_moon_id}.moon >/dev/null 2>&1
	fi

	# finish
	echo_date "离开moon完成！"

	# status
	# zerotier-cli peers
}

case $1 in
start)
	if [ "${zerotier_enable}" == "1" ]; then
		start_zerotier | tee -a ${LOG_FILE}
	else
		logger "zerotier插件未开启，跳过！"
	fi
	;;
esac

case $2 in
web_submit)
	set_lock
	true > ${LOG_FILE}
	http_response "$1"
	# 调试
	# echo_date "$BASH $ARGS" | tee -a ${LOG_FILE}
	if [ "${zerotier_enable}" == "1" ]; then
		start_zerotier | tee -a ${LOG_FILE}
	else
		stop_zerotier | tee -a ${LOG_FILE}
		echo_date "停止zerotier！" | tee -a ${LOG_FILE}
	fi
	echo XU6J03M6 | tee -a ${LOG_FILE}
	unset_lock
	;;
join_network)
	set_lock
	true > ${LOG_FILE}
	http_response "$1"
	# 调试
	echo_date "$BASH $ARGS" | tee -a ${LOG_FILE}
	join_network_now | tee -a ${LOG_FILE}
	echo XU6J03M6 | tee -a ${LOG_FILE}
	unset_lock
	;;
leave_network)
	set_lock
	true > ${LOG_FILE}
	http_response "$1"
	# 调试
	echo_date "$BASH $ARGS" | tee -a ${LOG_FILE}
	leave_network_now | tee -a ${LOG_FILE}
	echo XU6J03M6 | tee -a ${LOG_FILE}
	unset_lock
	;;
upload_moon)
	set_lock
	true > ${LOG_FILE}
	http_response "$1"
	# 调试
	echo_date "$BASH $ARGS" | tee -a ${LOG_FILE}
	upload_moon_now | tee -a ${LOG_FILE}
	echo XU6J03M6 | tee -a ${LOG_FILE}
	unset_lock
	;;
orbit_moon)
	set_lock
	true > ${LOG_FILE}
	http_response "$1"
	# 调试
	echo_date "$BASH $ARGS" | tee -a ${LOG_FILE}
	orbit_moon_now | tee -a ${LOG_FILE}
	echo XU6J03M6 | tee -a ${LOG_FILE}
	unset_lock
	;;
deorbit_moon)
	set_lock
	true > ${LOG_FILE}
	http_response "$1"
	# 调试
	echo_date "$BASH $ARGS" | tee -a ${LOG_FILE}
	deorbit_moon_now | tee -a ${LOG_FILE}
	echo XU6J03M6 | tee -a ${LOG_FILE}
	unset_lock
	;;
esac