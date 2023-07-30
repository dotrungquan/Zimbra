#!/bin/bash
read -p "Enter Your Domain: " domain
# install certbot snapd
#apt-get install snapd -y
#snap install --classic certbot
#ln -s /snap/bin/certbot /usr/bin/certbot
# install certbot apt
apt-get install certbot -y
# install certificate
su - zimbra -c 'zmcontrol stop'
certbot certonly --standalone -d $domain
mkdir -p  /opt/zimbra/ssl/zimbra/commercial/
cp /etc/letsencrypt/live/$domain/privkey.pem /opt/zimbra/ssl/zimbra/commercial/commercial.key
chown zimbra:zimbra /opt/zimbra/ssl/zimbra/commercial/commercial.key
wget --no-check-certificate -O /tmp/ISRG-X1.pem https://raw.githubusercontent.com/dotrungquan/SSL/main/CA.pem
echo > /etc/letsencrypt/live/$domain/chain.pem
cat /tmp/ISRG-X1.pem >> /etc/letsencrypt/live/$domain/chain.pem
chow
su - zimbra -c "/opt/zimbra/bin/zmcertmgr verifycrt comm /opt/zimbra/ssl/zimbra/commercial/commercial.key /etc/letsencrypt/live/$domain/cert.pem /etc/letsencrypt/live/$domain/chain.pem"
# install certbot-zimbra
folder=/root/certbot-zimbra-0.7.11
if [ ! -d  $folder ]
then
        wget --content-disposition https://github.com/YetOpen/certbot-zimbra/archive/0.7.11.tar.gz
        tar xzf certbot-zimbra-0.7.11.tar.gz
        cd certbot-zimbra-0.7.11 && cp certbot_zimbra.sh /usr/local/bin/
        /usr/local/bin/certbot_zimbra.sh -d
        su - zimbra -c 'zmcontrol restart'
else
        cd certbot-zimbra-0.7.11 && cp certbot_zimbra.sh /usr/local/bin/
        /usr/local/bin/certbot_zimbra.sh -d
        su - zimbra -c 'zmcontrol restart'
fi
# cron install certification
a=`grep "/usr/bin/certbot" /var/spool/cron/root`
if [[ -z "$a" ]]
then
        echo "0 0 * * * root /usr/bin/certbot renew --pre-hook \"/usr/local/bin/certbot_zimbra.sh -p\" --deploy-hook \"/usr/local/bin/certbot_zimbra.sh -d\"" >> /var/spool/cron/root
fi
