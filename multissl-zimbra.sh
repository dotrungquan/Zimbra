#!/bin/bash
# Auth: DOTRUNGQUAN.INFO

# Nhập các thông tin từ người dùng
read -p "Nhập vào Tên Miền (Ví dụ: dotrungquan.info): " domain
read -p "Nhập vào HostName (Ví dụ: mail.$domain): " hostname
read -p "Nhập vào IP Server (Yêu cầu nhập chính xác): " ipserver

# Xoá thư mục SSL cũ
rm -rf /etc/letsencrypt/live/$hostname/
# Chạy certbot để yêu cầu chứng chỉ SSL
certbot certonly --standalone -d "$hostname"

# Kiểm tra sự tồn tại của thư mục chứa `-*`
if ls /etc/letsencrypt/live/"$hostname"-* 1> /dev/null 2>&1; then
    # Đổi tên thư mục chứng chỉ SSL
    mv /etc/letsencrypt/live/"$hostname"-* /etc/letsencrypt/live/"$hostname"
else
    echo "Không tìm thấy thư mục với định dạng $hostname-*"
fi
# Tạo thư mục và các file chứng chỉ
rm -rf /tmp/$domain/
mkdir -p /tmp/$domain/
cp /etc/letsencrypt/live/$hostname/* /tmp/$domain/
wget -P /tmp/$domain/ https://letsencrypt.org/certs/isrgrootx1.pem.txt
touch /tmp/$domain/zimbra_chain.pem
cat /tmp/$domain/isrgrootx1.pem.txt >> /tmp/$domain/zimbra_chain.pem
cat /tmp/$domain/chain.pem >> /tmp/$domain/zimbra_chain.pem
touch /tmp/$domain/$domain.crt
cat /tmp/$domain/cert.pem >> /tmp/$domain/$domain.crt
cat /tmp/$domain/zimbra_chain.pem >> /tmp/$domain/$domain.crt
chown -R zimbra:zimbra /tmp/$domain/
# Tạo vhost
su - zimbra -c "zmprov md $domain zimbraVirtualHostName $hostname zimbraVirtualIPAddress $ipserver"
su - zimbra -c "/opt/zimbra/bin/zmcertmgr verifycrt comm /tmp/$domain/privkey.pem /tmp/$domain/cert.pem /tmp/$domain/zimbra_chain.pem"
# Lưu vhost
su - zimbra -c "/opt/zimbra/libexec/zmdomaincertmgr savecrt '$domain' /tmp/$domain/$domain.crt /tmp/$domain/privkey.pem"
# Copy chứng chỉ
echo > /opt/zimbra/conf/domaincerts/$domain.crt
echo > /opt/zimbra/conf/domaincerts/$domain.key
cat /tmp/$domain/$domain.crt > /opt/zimbra/conf/domaincerts/$domain.crt
cat /tmp/$domain/privkey.pem > /opt/zimbra/conf/domaincerts/$domain.key
chown -R zimbra:zimbra /opt/zimbra/conf/domaincerts/
# Khởi động
su - zimbra -c "zmprov mcf zimbraReverseProxySNIEnabled TRUE"
su - zimbra -c "/opt/zimbra/bin/zmproxyctl restart"
