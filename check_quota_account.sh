#!/bin/bash

# Đường dẫn tới file kết quả
output_file="/root/mail_usage.txt"

# Xóa nội dung cũ của file kết quả nếu có
> $output_file

# Liệt kê tất cả các tài khoản
su - zimbra -c "zmprov -l gaa" > /root/all_accounts.txt

# Đọc từng tài khoản và lấy thông tin dung lượng
while read account; do
    usage=$(su - zimbra -c "zmmailbox -z -m $account gms")
    echo "$account: $usage" >> $output_file
done < /root/all_accounts.txt
