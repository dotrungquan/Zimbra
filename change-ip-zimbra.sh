#!/bin/bash 
#Auth: DOTRUNGQUAN.INFO
oldip=$(grep -r "address" /etc/network/interfaces |cut -c 9-)
myhostname=$(cat /etc/hostname)
read -p "Nhập vào IP moi : " newip

echo "Đang tiến hành Stop dịch vụ"

su - zimbra -c "zmcontrol stop"

echo "Đang tiến hành thay đổi file cấu hình"

echo "Đang tiến hành khỏi động lại dịch vụ"

cp /opt/zimbra/conf/nginx/includes/nginx.conf.memcache /opt/zimbra/conf/nginx/includes/nginx.conf.memcache.bak
cp /opt/zimbra/conf/nginx/includes/nginx.conf.zmlookup /opt/zimbra/conf/nginx/includes/nginx.conf.zmlookup.bak
sed -i -e 's/'$oldip'/'$newip'/g' /opt/zimbra/conf/nginx/includes/nginx.conf.memcache
sed -i -e 's/'$oldip'/'$newip'/g' /opt/zimbra/conf/nginx/includes/nginx.conf.zmlookup

su - zimbra -c "zmcontrol start"

echo "Dịch vụ khởi động thành công"
