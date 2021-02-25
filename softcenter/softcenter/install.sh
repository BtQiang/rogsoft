#!/bin/sh

alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y年%m月%d日\ %X)】'
MODEL=
FW_TYPE_CODE=
FW_TYPE_NAME=

get_model(){
	local ODMPID=$(nvram get odmpid)
	local PRODUCTID=$(nvram get productid)
	if [ -n "${ODMPID}" ];then
		MODEL="${ODMPID}"
	else
		MODEL="${PRODUCTID}"
	fi
}

get_fw_type() {
	local KS_TAG=$(nvram get extendno|grep koolshare)
	if [ -d "/koolshare" ];then
		if [ -n "${KS_TAG}" ];then
			FW_TYPE_CODE="2"
			FW_TYPE_NAME="koolshare官改固件"
		else
			FW_TYPE_CODE="4"
			FW_TYPE_NAME="koolshare梅林改版固件"
		fi
	else
		if [ "$(uname -o|grep Merlin)" ];then
			FW_TYPE_CODE="3"
			FW_TYPE_NAME="梅林原版固件"
		else
			FW_TYPE_CODE="1"
			FW_TYPE_NAME="华硕官方固件"
		fi
	fi
}	

get_ui_type(){
	# # 获取机型
	# get_model

	# # 获取固件类型
	# get_fw_type

	# 参数获取
	[ "${MODEL}" == "RT-AC86U" ] && local ROG_RTAC86U=0
	[ "${MODEL}" == "GT-AC2900" ] && local ROG_GTAC2900=1
	[ "${MODEL}" == "GT-AX11000" ] && local ROG_GTAX11000=1
	local KS_TAG=$(nvram get extendno|grep koolshare)
	local EXT_NU=$(nvram get extendno)
	local EXT_NU=$(echo ${EXT_NU%_*} | grep -Eo "^[0-9]{1,10}$")
	local BUILDNO=$(nvram get buildno)
	[ -z "${EXT_NU}" ] && EXT_NU="0" 

	# UI类型判断
	# -------------------------------
	# RT-AC86U
	if [ -n "${KS_TAG}" -a "${MODEL}" == "RT-AC86U" -a "${EXT_NU}" -lt "81918" -a "${BUILDNO}" != "386" ];then
		# RT-AC86U的官改固件，在384_81918之前的固件都是ROG皮肤，384_81918及其以后的固件（包括386）为ASUSWRT皮肤
		ROG_RTAC86U=1
	fi

	# GT-AC2900
	if [ "${MODEL}" == "GT-AC2900" ] && [ "{FW_TYPE_CODE}" == "3" -o "{FW_TYPE_CODE}" == "4" ];then
		# GT-AC2900从386.1开始已经支持梅林固件，其UI是ASUSWRT
		ROG_GTAC2900=0
	fi

	# GT-AX11000
	if [ "${MODEL}" == "GT-AX11000" -o "${MODEL}" == "GT-AX11000_BO4" ] && [ "{FW_TYPE_CODE}" == "3" -o "{FW_TYPE_CODE}" == "4" ];then
		# GT-AX11000从386.2开始已经支持梅林固件，其UI是ASUSWRT
		ROG_GTAX11000=0
	fi
	
	if [ "${MODEL}" == "GT-AC5300" -o "${ROG_RTAC86U}" == "1" -o "${ROG_GTAC2900}" == "1" -o "${ROG_GTAX11000}" == "1" -o "${MODEL}" == "GT-AXE11000" ];then
		# GT-AC5300、RT-AC86U部分版本、GT-AC2900部分版本、GT-AX11000部分版本、GT-AXE11000全部版本，骚红皮肤
		ROG=1
		UI_TYPE="ROG"
	fi
	
	if [ "${MODEL}" == "TUF-AX3000" ];then
		# 官改固件，橙色皮肤
		TUF=1
		UI_TYPE="TUF"C
	fi

	if [ -z "${ROG}" -a -z "${TUF}" ];then
		# 普通皮肤
		ASUSWRT=1
		UI_TYPE="ASUSWRT"
	fi
}

get_current_jffs_device(){
	# 查看当前/jffs的挂载点是什么设备，如/dev/mtdblock9, /dev/sda1；有usb2jffs的时候，/dev/sda1，无usb2jffs的时候，/dev/mtdblock9，出问题未正确挂载的时候，为空
	local cur_patition=$(df -h | /bin/grep /jffs | awk '{print $1}')
	if [ -n "${cur_patition}" ];then
		jffs_device=${cur_patition}
		return 0
	else
		jffs_device=""
		return 1
	fi
}

get_usb2jffs_status(){
	# 如果正在使用usb2jffs，使用USB磁盘挂载了/jffs分区，那么软件中心需要同时更新到/jffs和cifs2
	get_current_jffs_device
	if [ "$?" != "0" ]; then
		return 1
	fi
	
	local mounted_nu=$(mount | /bin/grep "${jffs_device}" | grep -E "/tmp/mnt/|/jffs"|/bin/grep -c "/dev/s")
	if [ "${mounted_nu}" != "2" ]; then
		return 1
	fi

	local CIFS_STATUS=$(df -h|grep "/cifs2"|awk '{print $1}'|grep "/dev/mtdblock")
	if [ -z "${CIFS_STATUS}" ];then
		return 1
	fi
		
	if [ ! -d "/cifs2/.koolshare" ];then
		return 1

	fi

	# user has mount USB disk to /jffs, and orgin jffs mount device: /dev/mtdblock? mounted on /cifs2
	return 0
}

softcenter_install() {
	local KSPATH=$1

	if [ ! -d "/tmp/softcenter" ]; then
		echo_date "没有找到 /tmp/softcenter 文件夹，退出！"
		return 1
	fi
	
	# make some folders
	echo_date "创建软件中心相关的文件夹..."
	mkdir -p /${KSPATH}/configs/dnsmasq.d
	mkdir -p /${KSPATH}/scripts
	mkdir -p /${KSPATH}/etc
	mkdir -p /${KSPATH}/.koolshare/bin/
	mkdir -p /${KSPATH}/.koolshare/init.d/
	mkdir -p /${KSPATH}/.koolshare/scripts/
	mkdir -p /${KSPATH}/.koolshare/configs/
	mkdir -p /${KSPATH}/.koolshare/webs/
	mkdir -p /${KSPATH}/.koolshare/res/
	mkdir -p /tmp/upload
	
	# remove useless files
	echo_date "尝试清除一些不需要的文件..."
	[ -L "/${KSPATH}/configs/profile" ] && rm -rf /${KSPATH}/configs/profile
	[ -L "/${KSPATH}/.koolshare/webs/files" ] && rm -rf /${KSPATH}/.koolshare/webs/files
	[ -d "/tmp/files" ] && rm -rf /tmp/files

	# do not install some file for some model
	JFFS_TOTAL=$(df|grep -Ew "/${KSPATH}" | awk '{print $2}')
	if [ -n "${JFFS_TOTAL}" -a "${JFFS_TOTAL}" -le "20000" ];then
		echo_date "JFFS空间已经不足2MB！进行精简安装！"
		rm -rf /tmp/softcenter/bin/htop
	else
		echo_date "JFFS空间足够，开始安装！"
	fi
	
	# coping files
	echo_date "开始复制软件中心相关文件..."
	cp -rf /tmp/softcenter/webs/* /${KSPATH}/.koolshare/webs/
	cp -rf /tmp/softcenter/res/* /${KSPATH}/.koolshare/res/
	# ----ui------
	get_ui_type
	echo_date "获取当前固件UI类型，UI_TYPE: ${UI_TYPE}"
	if [ "${UI_TYPE}" == "ROG" ]; then
		echo_date "为软件中心安装ROG风格的皮肤..."
		cp -rf /tmp/softcenter/ROG/res/* /${KSPATH}/.koolshare/res/
	elif [ "${UI_TYPE}" == "TUF" ]; then
		echo_date "为软件中心安装TUF风格的皮肤..."
		sed -i 's/3e030d/3e2902/g;s/91071f/92650F/g;s/680516/D0982C/g;s/cf0a2c/c58813/g;s/700618/74500b/g;s/530412/92650F/g' /tmp/softcenter/ROG/res/*.css >/dev/null 2>&1
		sed -i 's/3e030d/3e2902/g;s/91071f/92650F/g;s/680516/D0982C/g;s/cf0a2c/c58813/g;s/700618/74500b/g;s/530412/92650F/g' /tmp/softcenter/webs/*.asp >/dev/null 2>&1
		cp -rf /tmp/softcenter/ROG/res/* /${KSPATH}/.koolshare/res/
	elif [ "${UI_TYPE}" == "ASUSWRT" ]; then
		echo_date "为软件中心安装ASUSWRT风格的皮肤..."
		sed -i '/rogcss/d' /${KSPATH}/.koolshare/webs/Module_Softsetting.asp >/dev/null 2>&1
	fi
	# -------------
	cp -rf /tmp/softcenter/init.d/* /${KSPATH}/.koolshare/init.d/
	cp -rf /tmp/softcenter/bin/* /${KSPATH}/.koolshare/bin/
	#for axhnd
	if [ "${MODEL}" == "RT-AX88U" ] || [ "${MODEL}" == "GT-AX11000" ];then
		cp -rf /tmp/softcenter/axbin/* /${KSPATH}/.koolshare/bin/
	fi
	cp -rf /tmp/softcenter/perp /${KSPATH}/.koolshare/
	cp -rf /tmp/softcenter/scripts /${KSPATH}/.koolshare/
	cp -rf /tmp/softcenter/.soft_ver /${KSPATH}/.koolshare/
	echo_date "文件复制结束，开始创建相关的软连接..."
	# make some link
	[ ! -L "/${KSPATH}/.koolshare/bin/base64_decode" ] && ln -sf /${KSPATH}/.koolshare/bin/base64_encode /${KSPATH}/.koolshare/bin/base64_decode
	[ ! -L "/${KSPATH}/.koolshare/scripts/ks_app_remove.sh" ] && ln -sf /${KSPATH}/.koolshare/scripts/ks_app_install.sh /${KSPATH}/.koolshare/scripts/ks_app_remove.sh
	[ ! -L "/${KSPATH}/.asusrouter" ] && ln -sf /${KSPATH}/.koolshare/bin/kscore.sh /${KSPATH}/.asusrouter
	[ -L "/${KSPATH}/.koolshare/bin/base64" ] && rm -rf /${KSPATH}/.koolshare/bin/base64
	if [ -n "$(nvram get extendno | grep koolshare)" ];then
		# for offcial mod, RT-AC86U, GT-AC5300, TUF-AX3000, RT-AX86U, etc
		[ ! -L "/${KSPATH}/etc/profile" ] && ln -sf /${KSPATH}/.koolshare/scripts/base.sh /${KSPATH}/etc/profile
	else
		# for Merlin mod, RT-AX88U, RT-AC86U, etc
		[ ! -L "/${KSPATH}/configs/profile.add" ] && ln -sf /${KSPATH}/.koolshare/scripts/base.sh /${KSPATH}/configs/profile.add
	fi
	echo_date "软连接创建完成！"

	#============================================
	# check start up scripts 
	echo_date "开始检查软件中心开机启动项！"
	if [ ! -f "/${KSPATH}/scripts/wan-start" ];then
		cat > /${KSPATH}/scripts/wan-start <<-EOF
		#!/bin/sh
		/koolshare/bin/ks-wan-start.sh start
		EOF
	else
		STARTCOMAND1=$(cat /${KSPATH}/scripts/wan-start | grep -c "/koolshare/bin/ks-wan-start.sh start")
		[ "$STARTCOMAND1" -gt "1" ] && sed -i '/ks-wan-start.sh/d' /${KSPATH}/scripts/wan-start && sed -i '1a /koolshare/bin/ks-wan-start.sh start' /${KSPATH}/scripts/wan-start
		[ "$STARTCOMAND1" == "0" ] && sed -i '1a /koolshare/bin/ks-wan-start.sh start' /${KSPATH}/scripts/wan-start
	fi
	
	if [ ! -f "/${KSPATH}/scripts/nat-start" ];then
		cat > /${KSPATH}/scripts/nat-start <<-EOF
		#!/bin/sh
		/koolshare/bin/ks-nat-start.sh start_nat
		EOF
	else
		STARTCOMAND2=$(cat /${KSPATH}/scripts/nat-start | grep -c "/koolshare/bin/ks-nat-start.sh start_nat")
		[ "$STARTCOMAND2" -gt "1" ] && sed -i '/ks-nat-start.sh/d' /${KSPATH}/scripts/nat-start && sed -i '1a /koolshare/bin/ks-nat-start.sh start_nat' /${KSPATH}/scripts/nat-start
		[ "$STARTCOMAND2" == "0" ] && sed -i '1a /koolshare/bin/ks-nat-start.sh start_nat' /${KSPATH}/scripts/nat-start
	fi
	
	if [ ! -f "/${KSPATH}/scripts/post-mount" ];then
		cat > /${KSPATH}/scripts/post-mount <<-EOF
		#!/bin/sh
		/koolshare/bin/ks-mount-start.sh start \$1
		EOF
	else
		STARTCOMAND3=$(cat /${KSPATH}/scripts/post-mount | grep -c "/koolshare/bin/ks-mount-start.sh start \$1")
		[ "$STARTCOMAND3" -gt "1" ] && sed -i '/ks-mount-start.sh/d' /${KSPATH}/scripts/post-mount && sed -i '1a /koolshare/bin/ks-mount-start.sh start $1' /${KSPATH}/scripts/post-mount
		[ "$STARTCOMAND3" == "0" ] && sed -i '/ks-mount-start.sh/d' /${KSPATH}/scripts/post-mount && sed -i '1a /koolshare/bin/ks-mount-start.sh start $1' /${KSPATH}/scripts/post-mount
	fi
	
	if [ ! -f "/${KSPATH}/scripts/services-start" ];then
		cat > /${KSPATH}/scripts/services-start <<-EOF
		#!/bin/sh
		/koolshare/bin/ks-services-start.sh
		EOF
	else
		STARTCOMAND4=$(cat /${KSPATH}/scripts/services-start | grep -c "/koolshare/bin/ks-services-start.sh")
		[ "$STARTCOMAND4" -gt "1" ] && sed -i '/ks-services-start.sh/d' /${KSPATH}/scripts/services-start && sed -i '1a /koolshare/bin/ks-services-start.sh' /${KSPATH}/scripts/services-start
		[ "$STARTCOMAND4" == "0" ] && sed -i '1a /koolshare/bin/ks-services-start.sh' /${KSPATH}/scripts/services-start
	fi
	
	if [ ! -f "/${KSPATH}/scripts/services-stop" ];then
		cat > /${KSPATH}/scripts/services-stop <<-EOF
		#!/bin/sh
		/koolshare/bin/ks-services-stop.sh
		EOF
	else
		STARTCOMAND5=$(cat /${KSPATH}/scripts/services-stop | grep -c "/koolshare/bin/ks-services-stop.sh")
		[ "$STARTCOMAND5" -gt "1" ] && sed -i '/ks-services-stop.sh/d' /${KSPATH}/scripts/services-stop && sed -i '1a /koolshare/bin/ks-services-stop.sh' /${KSPATH}/scripts/services-stop
		[ "$STARTCOMAND5" == "0" ] && sed -i '1a /koolshare/bin/ks-services-stop.sh' /${KSPATH}/scripts/services-stop
	fi
	
	if [ ! -f "/${KSPATH}/scripts/unmount" ];then
		cat > /${KSPATH}/scripts/unmount <<-EOF
		#!/bin/sh
		/koolshare/bin/ks-unmount.sh \$1
		EOF
	else
		STARTCOMAND6=$(cat /${KSPATH}/scripts/unmount | grep -c "/koolshare/bin/ks-unmount.sh \$1")
		[ "$STARTCOMAND6" -gt "1" ] && sed -i '/ks-unmount.sh/d' /${KSPATH}/scripts/unmount && sed -i '1a /koolshare/bin/ks-unmount.sh $1' /${KSPATH}/scripts/unmount
		[ "$STARTCOMAND6" == "0" ] && sed -i '1a /koolshare/bin/ks-unmount.sh $1' /${KSPATH}/scripts/unmount
	fi
	echo_date "开机启动项检查完毕！"

	chmod 755 /${KSPATH}/scripts/*
	chmod 755 /${KSPATH}/.koolshare/bin/*
	chmod 755 /${KSPATH}/.koolshare/init.d/*
	chmod 755 /${KSPATH}/.koolshare/perp/*
	chmod 755 /${KSPATH}/.koolshare/perp/.boot/*
	chmod 755 /${KSPATH}/.koolshare/perp/.control/*
	chmod 755 /${KSPATH}/.koolshare/perp/httpdb/*
	chmod 755 /${KSPATH}/.koolshare/scripts/*

	# reset some default value
	echo_date "设定一些默认值..."
	if [ -n "$(pidof skipd)" -a -f "/usr/bin/dbus" ];then
		/usr/bin/dbus set softcenter_installing_todo=""
		/usr/bin/dbus set softcenter_installing_title=""
		/usr/bin/dbus set softcenter_installing_name=""
		/usr/bin/dbus set softcenter_installing_tar_url=""
		/usr/bin/dbus set softcenter_installing_version=""
		/usr/bin/dbus set softcenter_installing_md5=""
	fi
	#============================================
	# now try to reboot httpdb if httpdb not started
	# /koolshare/bin/start-stop-daemon -S -q -x /koolshare/perp/perp.sh
}

exit_install(){
	local state=$1
	local module=softcenter
	case $state in
		1)
			echo_date "本软件中心适用于【koolshare 梅林改/官改 hnd/axhnd/axhnd.675x】固件平台！"
			echo_date "你的固件平台不能安装！！!"
			echo_date "本软件中心支持机型/平台：https://github.com/koolshare/rogsoft#rogsoft"
			echo_date "退出安装！"
			rm -rf /tmp/${module}* >/dev/null 2>&1
			echo_date "-----------------------------------------------------------------------------"
			exit 1
			;;
		0|*)
			rm -rf /tmp/${module}* >/dev/null 2>&1
			echo_date "-----------------------------------------------------------------------------"
			exit 0
			;;
	esac
}

install_now(){
	get_usb2jffs_status
	if [ "$?" == "0" ];then
		echo_date "检测到你使用USB磁盘挂载了/jffs！"
		echo_date "软件中心此次将同时安装到系统jffs和usb jffs！"
		echo_date "----------------------- 更新软件中心到USB JFFS（/jffs）-----------------------"
		softcenter_install jffs
		echo_date "-----------------------------------------------------------------------------"
		echo_date "----------------------- 更新软件中心到系统 JFFS（/cifs2）----------------------"
		softcenter_install cifs2
		echo_date "-----------------------------------------------------------------------------"
	else
		echo_date "----------------------- 更新软件中心到系统 JFFS（/jffs）-----------------------"
		softcenter_install jffs
		echo_date "-----------------------------------------------------------------------------"
	fi
	rm -rf /tmp/softcenter*
}

install(){
	get_model
	get_fw_type
	local LINUX_VER=$(uname -r|awk -F"." '{print $1$2}')
	if [ -d "/koolshare" -a -f "/usr/bin/skipd" -a "${LINUX_VER}" -ge "41" ];then
		echo_date 机型：${MODEL} ${FW_TYPE_NAME} 符合安装要求，开始安装软件中心！
		install_now
	else
		exit_install 1
	fi
}

install
