#!/bin/sh

source /koolshare/scripts/base.sh

OBJECT_1=
OBJECT_2=

json_init(){
	OBJECT_2='{}'
}

json_add_string(){
	OBJECT_2=$(echo ${OBJECT_2} | jq --arg var "$2" '. + {'$1': $var}')
}

json_dump1() {
	echo ${OBJECT_1} | jq '.'
}

json_dump2() {
	echo ${OBJECT_2} | jq '.'
}

exit_status(){
	http_response empty
	exit
}

RECOU=1
set_route_table(){
	eval $(dbus export zerotier_route_)
	local DEV="$1"
	local ROT="$2"
	local LEN=$(echo "$ROT" | jq '. | length' 2>/dev/null)
	local COU=0
	until [ "$COU" == "$LEN" ]; do
		local VIA=$(echo "$ROT" | jq -r --argjson count $COU '.[$count].via')
		if [ "$VIA" != "null" ];then
			local TGT=$(echo "$ROT" | jq -r --argjson count $COU '.[$count].target')
			#echo ip route add $TGT via $VIA dev $DEV
			local T1=$(eval echo \$zerotier_route_enable_${RECOU})
			local T2=$(eval echo \$zerotier_route_gateway_${RECOU})
			local T3=$(eval echo \$zerotier_route_ipaddr_${RECOU})
			[ "$T1" != "1" ] && dbus set zerotier_route_enable_${RECOU}=1 && echo "111"
			[ "$T2" != "$VIA" ] && dbus set zerotier_route_gateway_${RECOU}=$VIA && echo "222"
			[ "$T3" != "$TGT" ] && dbus set zerotier_route_ipaddr_${RECOU}=$TGT && echo "333"
		fi
		let COU+=1
		let RECOU+=1
	done

	# zerotier_route_enable_1=1
	# zerotier_route_gateway_1=192.168.2.1
	# zerotier_route_ipaddr_1=192.168.2.22

	# ip route add 192.168.2.0/24 via 192.168.192.166 dev ztppitfurk proto static 
	# ip route add 192.168.56.0/24 via 192.168.192.234 dev ztppitfurk proto static 
	
	#echo "$DEV"
	#echo "$ROT" | jq .
	#echo "$LEN"
}

listnetworks(){
	OBJECT_1='{}'

	# not json
	ZTNETS=$(zerotier-cli -j listnetworks 2>/dev/null)
	local JSON_1=$(echo "$ZTNETS"|grep -Eo "\{")
	local JSON_2=$(echo "$ZTNETS"|grep -Eo "\}")
	if [ -z "$JSON_1" -o -z "$JSON_2" ];then
		#echo "not json"
		exit_status
	fi

	# get object number
	local ZT_NU=$(echo $ZTNETS | jq '. | length' 2>/dev/null)
	local COUNT=0
	until [ "$COUNT" == "$ZT_NU" ]; do
		#local ZTNET=$(echo "$ZTNETS" | jq --argjson count $COUNT '.[$count]')
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
		local ROUTES=$(echo "$ZTNETS" | jq -r -c --argjson count $COUNT '.[$count].routes')

		#echo "ZTNET: $ZTNET"
		#echo "NETWORK: $NETWORK"
		#echo "NAME: $NAME"
		#echo "STATUS: $STATUS"
		#echo "TYPE: $TYPE"
		#echo "MAC: $MAC"
		#echo "MTU: $MTU"
		#echo "BROADCAST: $BROADCAST"
		#echo "BRIDGE: $BRIDGE"
		#echo "DEVICE: $DEVICE"
		#echo "IPADDR: $IPADDR"
		#echo "ROUTES: $ROUTES"

		json_init
		json_add_string NETWORK "$NETWORK"
		json_add_string NAME "$NAME"
		json_add_string STATUS "$STATUS"
		json_add_string TYPE "$TYPE"
		json_add_string MAC "$MAC"
		json_add_string MTU "$MTU"
		json_add_string BROADCAST "$BROADCAST"
		json_add_string BRIDGE "$BRIDGE"
		json_add_string DEVICE "$DEVICE"
		json_add_string IPADDR "$IPADDR"
		json_add_string ROUTES "$ROUTES"
		#json_dump2
		OBJECT_1=$(echo ${OBJECT_1} | jq --argjson args "${OBJECT_2}" '. + {'\"${COUNT}\"': $args}')

		# write DNAT
		local LANIP=$(ifconfig br0|grep -Eo "inet addr.+"|awk -F ":| " '{print $3}' 2>/dev/null)
		local ZTADD=$(echo ${IPADDR}|awk -F "/" '{print $1}')
		local MATCH=$(iptables -t nat -S PREROUTING|grep zerotier_rule|grep $ZTADD)
		if [ -n "${LANIP}" -a -n "${ZTADD}" -a -z "${MATCH}" ];then
			iptables -t nat -A PREROUTING -d ${ZTADD} -j DNAT --to-destination ${LANIP} -m comment --comment "zerotier_rule"
		fi

		# write SNAT
		local IPTABLE_FLAG_1=$(iptables -t nat -S|grep -w ${DEVICE}|grep -w MASQUERADE|grep -w zerotier_rule 2>/dev/null)
		if [ -z "${IPTABLE_FLAG_1}" -a "$(dbus get zerotier_nat)" == "1" -a -n "${ZTADD}" -a -n "${DEVICE}" ];then
			local RULE_INDEX=$(iptables -t nat -nvL POSTROUTING --line-numbers|sed '1,2d'|sed -n '/MASQUERADE/='|sort -n|head -n1 2>/dev/null)
			if [ -n "${RULE_INDEX}" ];then
				iptables -t nat -I POSTROUTING ${RULE_INDEX} -o ${DEVICE} -j MASQUERADE --mode fullcone -m comment --comment "zerotier_rule"
			fi
		fi

		# write forward
		local IPTABLE_FLAG_2=$(iptables -t filter -S|grep -w ${DEVICE}|grep -w zerotier_rule 2>/dev/null)
		if [ -z "${IPTABLE_FLAG_2}" -a -n "${ZTADD}" -a -n "${DEVICE}" ];then
			iptables -I INPUT -i ${DEVICE} -j ACCEPT -m comment --comment "zerotier_rule" >/dev/null 2>&1
			iptables -I FORWARD -i ${DEVICE} -o ${DEVICE} -j ACCEPT -m comment --comment "zerotier_rule" >/dev/null 2>&1
			iptables -I FORWARD -i ${DEVICE} -j ACCEPT -m comment --comment "zerotier_rule" >/dev/null 2>&1
		fi
		
		# set_route_table "$DEVICE" "$ROUTES"
		# show_route_table "$DEVICE" "$ROUTES"
		
		let COUNT+=1
	done
}

ZERO_SHELL=$(ps|grep "zerotier_config.sh"|grep -v grep)
if [ -n "${ZERO_SHELL}" ];then
	http_response empty
	exit 0
fi

listnetworks
#json_dump1

if [ "${#OBJECT_1}" -le "2" ];then
	exit_status
fi

OBJECT_1=$(echo ${OBJECT_1}|base64_encode)
if [ -n "${OBJECT_1}" ]; then
	http_response ${OBJECT_1}
else
	exit_status
fi
