#!/bin/bash
#Auth: DOTRUNGQUAN.INFO
read -p "Nhap vao link Logo App (Size: 283x32): " logoapp
read -p "Nhap vao link Logo Login (Size: 350x48): " logologin
read -p "Nhap vao domain: " domain

echo "Thong tin nhap hoan tat, vui long cho"

su - zimbra -c "zmprov md $domain zimbraSkinLogoURL 'http://mail.$domain'"
su - zimbra -c "zmprov md $domain zimbraSkinLogoLoginBanner $logologin"
su - zimbra -c "zmprov md $domain zimbraSkinLogoAppBanner $logoapp"
echo "Dang khoi dong lai dich vu"
su - zimbra -c "zmmailboxdctl restart"
echo "Logo da thay doi hoan tat, vui long xoa cache va kiem tra"
