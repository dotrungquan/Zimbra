#!/bin/bash 
oldip=$(grep -r "address" /etc/network/interfaces |cut -c 9-)
myhostname=$(/etc/hostname)
read -p "Nhập vào IP moi : " newip

su - zimbra -c "zmcontrol stop"
su - zimbra -c "zmcontrol start"

sed -i -e 's/'$oldip'/'$newip'/g' /opt/zimbra/conf/nginx/includes/nginx.conf.memcache
sed -i -e 's/'$oldip'/'$newip'/g' /opt/zimbra/conf/nginx/includes/nginx.conf.zmlookup
