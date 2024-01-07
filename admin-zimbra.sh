#!/bin/bash
# Auth: DOTRUNGQUAN.INFO

function change_logo() {
    read -p "Nhập vào link Logo Login (Size: 440x60): " logologin
    read -p "Nhập vào link Logo App (Size: 200x35): " logoapp
    read -p "Nhập vào domain: " domain

    echo "Thông tin nhập hoàn tất, vui lòng chờ"

    su - zimbra -c "zmprov md $domain zimbraSkinLogoURL 'http://mail.$domain'"
    su - zimbra -c "zmprov md $domain zimbraSkinLogoLoginBanner $logologin"
    su - zimbra -c "zmprov md $domain zimbraSkinLogoAppBanner $logoapp"
    echo "Đang khởi động lại dịch vụ"
    su - zimbra -c "zmmailboxdctl restart"
    echo "Logo đã thay đổi hoàn tất, vui lòng xóa cache và kiểm tra"
}

function create_mail_account() {
    read -p "Nhập tên tài khoản mới: " account
    read -p "Nhập mật khẩu mới: " passwd
    read -p "Nhập tên hiển thị: " name

    # Sử dụng câu lệnh zmprov để tạo tài khoản email
    su - zimbra -c "zmprov ca $account $passwd displayName '$name'"

    # Kiểm tra xem tài khoản đã được tạo thành công hay không
    if [ $? -eq 0 ]; then
        echo "Tài khoản email đã được tạo thành công."
    else
        echo "Có lỗi xảy ra trong quá trình tạo tài khoản email."
    fi
}

function create_dkim_key() {
    local domain=$1
    su - zimbra -c "/opt/zimbra/libexec/zmdkimkeyutil -a -d $domain"
}

function view_dkim_key() {
    local domain=$1
    su - zimbra -c "/opt/zimbra/libexec/zmdkimkeyutil -q -d $domain"
}

function dkim_menu() {
    while true; do
        echo "---- MENU ----"
        echo "1. Tạo DKIM key"
        echo "2. Xem DKIM key"
        echo "0. Thoát"
        read -p "Nhập lựa chọn của bạn: " choice

        if [ "$choice" -eq 1 ]; then
            read -p "Nhập domain: " domain
            create_dkim_key "$domain"
        elif [ "$choice" -eq 2 ]; then
            read -p "Nhập domain: " domain
            view_dkim_key "$domain"
        elif [ "$choice" -eq 0 ]; then
            break
        else
            echo "Lựa chọn không hợp lệ!"
        fi
    done

    echo "Nếu bạn chưa biết cách cấu hình DKIM, xem bài viết này:"
    echo "Link bài viết: https://dotrungquan.info/huong-dan-cau-hinh-dkim-spf-dmarc-zimbra-mail/"
}

function delegate_admin() {
    echo > /usr/local/sbin/delegate-admin.sh
    wget -O /usr/local/sbin/delegate-admin.sh https://raw.githubusercontent.com/dotrungquan/Zimbra/main/delegate-admin.sh
    chmod +x /usr/local/sbin/delegate-admin
    su - zimbra
    bash /usr/local/sbin/delegate-admin.sh
}

while true; do
    echo "---- MENU CHÍNH ----"
    echo "1. Đổi Logo"
    echo "2. Tạo tài khoản mail"
    echo "3. Tạo hoặc xem DKIM"
    echo "4. Phân quyền admin"
    echo "0. Thoát"
    read -p "Nhập lựa chọn của bạn: " main_choice

    case $main_choice in
    1)
        change_logo
        ;;
    2)
        create_mail_account
        ;;
    3)
        dkim_menu
        ;;
    4)
        delegate_admin
        ;;
    0)
        echo "Chương trình kết thúc."
        exit 0
        ;;
    *)
        echo "Lựa chọn không hợp lệ!"
        ;;
    esac
done
