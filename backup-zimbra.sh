#!/bin/bash
# Author: Vu Van Than - Linux System Admin
# Reviwer: Nguyen Trung Thang
# Version v1 June 11 2018
ZHOME=/opt/backup
ZBACKUP=$ZHOME/Data/mailbox
ZCONFD=/opt/zimbra/conf/
DATE=`date +"%a"`
DATE_REPORT=`date`
ZDUMPDIR=$ZBACKUP/$DATE
ZMBOX=/opt/zimbra/bin/zmmailbox
if [ ! -d $ZDUMPDIR ]; then
mkdir -p $ZDUMPDIR
fi
echo " Running zmprov ... "
 for mbox in `/opt/zimbra/bin/zmprov -l gaa`
 do
echo " Generating files from backup $mbox ..."
       $ZMBOX -z -m $mbox getRestURL "//?fmt=zip" > $ZDUMPDIR/$mbox.zip
echo " Generating files from backup $mbox ..." >> report.txt    
echo " Backup account is done ..."
 done
echo " Report $DATE_REPORT ..." >> report.txt
echo " Uploading backup to Google Drive ..."
 cd $ZBACKUP
 /usr/bin/rclone copy $DATE remote:
echo " Upload done ..."
 find $ZBACKUP -mtime +0 -print0 | xargs -0 rm -rf 
#find files modified greater than 24 hours ago
