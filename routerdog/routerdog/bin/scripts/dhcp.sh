#!/bin/sh

killall -SIGUSR2 dnsmasq

dhcpFile=$(cat /var/lib/misc/dnsmasq.leases)

echo "${dhcpFile}"


