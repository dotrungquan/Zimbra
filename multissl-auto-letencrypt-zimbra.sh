#!/bin/bash
#Auth: DOTRUNGQUAN.INFO
#pathnetw="/etc/network/interfaces"
#ip=$(grep -r "address" $pathnetw |cut -c 9-)
read -p "Nhập vào Tên Miền (Ví dụ: dotrungquan.info ): " domain
read -p "Nhập vào HostName (Ví dụ: mail.$domain): " hostname
read -p "Nhập vào IP Server (Yêu cầu nhập chính xác): " ipserver
#ipserver=$(grep -r "address" /etc/network/interfaces |cut -c 9-)
su - zimbra -c 'zmcontrol stop'
## Tao zimbraVirtualHostName
su - zimbra -c "zmprov md $domain zimbraVirtualHostName $hostname zimbraVirtualIPAddress $ipserver"
certbot certonly --standalone -d $hostname
mkdir -p /tmp/$domain/

cp /etc/letsencrypt/live/$hostname/* /tmp/$domain/


wget --no-check-certificate -O /tmp/$domain/ISRG-X1.pem https://letsencrypt.org/certs/isrgrootx1.pem
wget --no-check-certificate -O /tmp/$domain/R3.pem https://letsencrypt.org/certs/lets-encrypt-r3.pem

cat /tmp/$domain/R3.pem > /tmp/$domain/chain.pem
cat /tmp/$domain/ISRG-X1.pem >> /tmp/$domain/chain.pem

wget -P /tmp/$domain/ https://tool.dotrungquan.info/share/ssl/CA.pem

chown -R zimbra:zimbra /tmp/$domain/
su - zimbra -c "/opt/zimbra/bin/zmcontrol restart"
su - zimbra -c "/opt/zimbra/bin/zmcertmgr verifycrt comm /tmp/$domain/privkey.pem /tmp/$domain/cert.pem /tmp/$domain/CA.pem"
#su - zimbra -c "/opt/zimbra/bin/zmcertmgr deploycrt comm /tmp/$domain/cert.pem /tmp/$domain/CA.pem"
su - zimbra -c "/opt/zimbra/libexec/zmdomaincertmgr savecrt '$domain' /tmp/$domain/cert.pem /tmp/$domain/privkey.pem"

mkdir -p /opt/zimbra/conf/domaincerts/

cp /tmp/$domain/cert.pem /opt/zimbra/conf/domaincerts/$domain.crt
cp /tmp/$domain/chain.pem /opt/zimbra/conf/domaincerts/$domain.ca.crt
cp /tmp/$domain/privkey.pem /opt/zimbra/conf/domaincerts/$domain.key


su - zimbra -c "zmprov mcf zimbraReverseProxySNIEnabled TRUE"
su - zimbra -c "/opt/zimbra/bin/zmproxyctl restart"
