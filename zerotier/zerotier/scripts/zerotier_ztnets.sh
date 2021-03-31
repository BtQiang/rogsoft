#!/bin/sh

source /koolshare/scripts/base.sh

POST_DATA1=
POST_DATA2=


json_init(){
	POST_DATA2='{}'
}

json_add_string(){
	POST_DATA2=$(echo ${POST_DATA2} | jq --arg var "$2" '. + {'$1': $var}')
}

json_dump1() {
	echo ${POST_DATA1} | jq .
}

json_dump2() {
	echo ${POST_DATA2} | jq .
}

ZERO_SHELL=$(ps|grep "zerotier_config.sh"|grep -v grep)
if [ -n "${ZERO_SHELL}" ];then
	http_response empty
	exit 0
fi

POST_DATA1='{}'

#ZT_NETS=$(zerotier-cli listnetworks|grep listnetworks|grep -Eo "zt\w+")
#if [ -z "$ZT_NETS" ];then
#	ZT_NETS=$(ifconfig|grep -E "^zt"|awk '{print $1}'|sed '1!G;h;$!d')
#fi
ZT_NETS=$(ifconfig|grep -E "^zt"|awk '{print $1}'|sed '1!G;h;$!d')
for IFNET in ${ZT_NETS}
do
	P0=$(ifconfig ${IFNET})
	P1=${IFNET}
	P2=$(echo "$P0" | grep -Eo 'inet addr:([0-9]{1,3}[\.]){3}[0-9]{1,3}'|awk -F":" '{print $2}')
	P3=$(echo "$P0" | grep -Eo '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}')
	#P3=$(echo "$P0" | grep -Eo 'P-t-P:([0-9]{1,3}[\.]){3}[0-9]{1,3}'|awk -F":" '{print $2}')
	P4=$(echo "$P0" | grep -Eo 'RX bytes:[0-9]+ \(.+) '|grep -Eo '\(.+)'|sed 's/[()]//g')
	P5=$(echo "$P0" | grep -Eo 'TX bytes:[0-9]+ \(.+)'|grep -Eo '\(.+)'|sed 's/[()]//g')
	json_init
	json_add_string if "$P1"
	json_add_string ip "$P2"
	json_add_string hw "$P3"
	json_add_string rx "$P4"
	json_add_string tx "$P5"
	POST_DATA1=$(echo ${POST_DATA1} | jq --argjson args "${POST_DATA2}" '. + {'\"${IFNET}\"': $args}')
	json_dump2
done

json_dump1
if [ "${#POST_DATA1}" -le "2" ];then
	http_response empty
	exit 1
fi

POST_DATA1=$(echo ${POST_DATA1}|base64_encode)
if [ -n "${ZT_NETS}" ]; then
	http_response ${POST_DATA1}
else
	http_response empty
fi
