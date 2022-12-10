#!/bin/bash
pathnetw="/etc/network/interfaces"
ip=$(grep -r "address" $pathnetw |cut -c 9-)
read -p "Enter Your Domain (example.com):" domain
read -p "Enter Your HostName (mail.example.com):" hostname
dir="/temp/$domain"

su - zimbra -c "zmprov md '$domain' zimbraVirtualHostName '$hostname' zimbraVirtualIPAddress '$ip'"

# mkdir -p /tmp/$domain/

chown -R zimbra:zimbra '$dir'

wget -P /tmp/'$domain'/ https://tool.dotrungquan.info/share/ssl/CA.pem

su - zimbra -c "/opt/zimbra/bin/zmcertmgr verifycrt comm /tmp/$domain/ssl.key /tmp/$domain/ssl.crt /tmp/$domain/CA.pem"
cat /tmp/$domain/ssl.crt /tmp/$domain/ssl.ca.crt >> /tmp/$domain/ssl.bundle
su - zimbra -c "/opt/zimbra/libexec/zmdomaincertmgr savecrt '$domain' /tmp/$domain/ssl.bundle /tmp/$domain/ssl.key"
mkdir -p /opt/zimbra/conf/domaincerts/

ln -s /tmp/$domain/ssl.crt /opt/zimbra/conf/domaincerts/$domain.crt
ln -s /tmp/$domain/ssl.ca.crt /opt/zimbra/conf/domaincerts/$domain.ca.crt
ln -s /tmp/$domain/ssl.key /opt/zimbra/conf/domaincerts/$domain.key

su - zimbra -c "/opt/zimbra/bin/zmproxyctl restart"
