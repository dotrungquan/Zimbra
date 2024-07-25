#!/bin/bash
#Auth: DOTRUNGQUAN.INFO
read -p "Nhập vào Tên Miền (Ví dụ: dotrungquan.info): " domain
read -p "Nhập vào HostName (Ví dụ: mail.$domain): " hostname
read -p "Nhập vào IP Server (Yêu cầu nhập chính xác): " ipserver
certbot certonly --standalone -d $hostname
mkdir -p /tmp/$domain/
cp /etc/letsencrypt/live/$hostname/* /tmp/$domain/
wget -P /tmp/$domain/ https://tool.dotrungquan.info/share/ssl/CA.pem
touch /tmp/$domain/full.pem
cat /tmp/$domain/fullchain.pem /tmp/$domain/CA.pem > /tmp/$domain/full.pem
cat /tmp/$domain/cert.pem /tmp/$domain/CA.pem > /tmp/$domain/ca.bundle
chown -R zimbra:zimbra /tmp/$domain/

su - zimbra -c "zmprov md $domain zimbraVirtualHostName $hostname zimbraVirtualIPAddress $ipserver"
su - zimbra -c "/opt/zimbra/bin/zmcertmgr verifycrt comm /tmp/$domain/privkey.pem /tmp/$domain/cert.pem /tmp/$domain/full.pem"
su - zimbra -c "/opt/zimbra/libexec/zmdomaincertmgr savecrt '$domain' /tmp/$domain/ca.bundle /tmp/$domain/privkey.pem"
cp /tmp/$domain/cert.pem /opt/zimbra/conf/domaincerts/$domain.crt
cp /tmp/$domain/chain.pem /opt/zimbra/conf/domaincerts/$domain.ca.crt
cp /tmp/$domain/privkey.pem /opt/zimbra/conf/domaincerts/$domain.key
chown -R zimbra:zimbra /opt/zimbra/conf/domaincerts/
su - zimbra -c "zmprov mcf zimbraReverseProxySNIEnabled TRUE"
su - zimbra -c "/opt/zimbra/bin/zmproxyctl restart"
