#!/bin/bash 
oldip=$(grep -r "address" /etc/network/interfaces |cut -c 9-)
myhostname=$(cat /etc/hostname)
read -p "Nhập vào IP moi : " newip

su - zimbra -c "zmcontrol stop"

cp /opt/zimbra/conf/nginx/includes/nginx.conf.memcache /opt/zimbra/conf/nginx/includes/nginx.conf.memcache.bak
cp /opt/zimbra/conf/nginx/includes/nginx.conf.zmlookup /opt/zimbra/conf/nginx/includes/nginx.conf.zmlookup.bak
sed -i -e 's/'$oldip'/'$newip'/g' /opt/zimbra/conf/nginx/includes/nginx.conf.memcache
sed -i -e 's/'$oldip'/'$newip'/g' /opt/zimbra/conf/nginx/includes/nginx.conf.zmlookup

su - zimbra -c "zmcontrol start"
