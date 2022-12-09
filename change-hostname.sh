#!/bin/bash
#Author: DOTRUNGQUAN.INFO
read -p "Nhap Vao HostName Cu: " oldhostname
read -p "Nhap Vao HostName Moiw: " newhostname
#read -p "Nhap vao Domain Moi: " domainnew

su - zimbra -c 'zmcontrol stop'
su - zimbra -c "/opt/zimbra/libexec/zmsetservername -n $newhostname"

su - zimbra -c "/opt/zimbra/bin/zmcertmgr createca -new"
su - zimbra -c "/opt/zimbra/bin/zmcertmgr createcrt -new -subjectAltNames $newhostname -days 365"
su - zimbra -c "/opt/zimbra/bin/zmcertmgr deploycrt self"
su - zimbra -c "/opt/zimbra/bin/zmcertmgr deployca"
su - zimbra -c "/opt/zimbra/bin/zmcertmgr viewdeployedcrt"

cp /opt/zimbra/conf/nginx/includes/nginx.conf.web /opt/zimbra/conf/nginx/includes/nginx.conf.web.bak
cp /opt/zimbra/conf/nginx/includes/nginx.conf.lets.conf /opt/zimbra/conf/nginx/includes/nginx.conf.lets.conf.bak
cp /opt/zimbra/conf/nginx/includes/nginx.conf.web.https.default /opt/zimbra/conf/nginx/includes/nginx.conf.web.https.default.bak
cp /opt/zimbra/conf/nginx/includes/nginx.conf.web.http.default /opt/zimbra/conf/nginx/includes/nginx.conf.web.http.default.bak
sed -i -e 's/'$oldhostname'/'$newhostname'/g' /opt/zimbra/conf/nginx/includes/nginx.conf.web
sed -i -e 's/'$oldhostname'/'$newhostname'/g' /opt/zimbra/conf/nginx/includes/nginx.conf.lets.conf
sed -i -e 's/'$oldhostname'/'$newhostname'/g' /opt/zimbra/conf/nginx/includes/nginx.conf.web.https.default
sed -i -e 's/'$oldhostname'/'$newhostname'/g' /opt/zimbra/conf/nginx/includes/nginx.conf.web.http.default

su - zimbra -c  "zmloggerhostmap -d $oldhostname $oldhostname"
su - zimbra -c  "zmloggerhostmap -d mail $oldhostname"

sed -i -e 's/'$oldhostname'/'$newhostname'/g' /etc/hostname
sed -i -e 's/'$oldhostname'/'$newhostname'/g' /etc/hosts
sed -i -e 's/'$oldhostname'/'$newhostname'/g' /etc/dnsmasq.conf

#su - zimbra -c "zmprov ca admin@'$domainnew' 321j1o0WCkyAR2PP zimbraIsAdminAccount TRUE"


reboot
