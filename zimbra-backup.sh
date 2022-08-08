#!/bin/bash
 
 # Zimbra Backup Script
 # Requires ncftp to run
 # This script is intended to run from the crontab as root
 # Date outputs and su vs sudo corrections by other contributors, thanks, sorry I don't have names to attribute!
 # Free to use and free of any warranty!  Daniel W. Martin, 5 Dec 2008

 
 # Outputs the time the backup started, for log/tracking purposes
 echo Time backup started = $(date +%T)
 before="$(date +%s)"

 # Live sync before stopping Zimbra to minimize sync time with the services down
 # Comment out the following line if you want to try single cold-sync only
 rsync -avHK --delete --exclude '*data/ldap*' /opt/zimbra/ /backup/zimbra

 # which is the same as: /opt/zimbra /backup 
 # Including --delete option gets rid of files in the dest folder that don't exist at the src 
 # this prevents logfile/extraneous bloat from building up overtime.

 # Now we need to shut down Zimbra to rsync any files that were/are locked
 # whilst backing up when the server was up and running.
 before2="$(date +%s)"

 # 
 echo Service down at  $(date +%T)
 # Stop Zimbra Services
 su - zimbra -c "/opt/zimbra/bin/zmcontrol stop"
 sleep 15

 # Kill any orphaned Zimbra processes
 kill -9 `ps -u zimbra -o "pid="`

 # Only enable the following command if you need all Zimbra user owned
 # processes to be killed before syncing
 # ps auxww | awk '{print $1" "$2}' | grep zimbra | kill -9 `awk '{print $2}'`
 
 
 
 # Sync to backup directory
 rsync -avHK --delete --exclude '*data/ldap*' /opt/zimbra/ /backup/zimbra
 rm -rf /backup/zimbra-ldap/*
 
 #su - zimbra -c '/opt/zimbra/libexec/zmslapcat -c /backup/zimbra-ldap'
 # Backup ldap directory
 su - zimbra -c "/opt/zimbra/libexec/zmslapcat -c /backup/zimbra-ldap"
 su - zimbra -c "/opt/zimbra/libexec/zmslapcat /backup/zimbra-ldap"

 # Restart Zimbra Services
 su - zimbra -c "/opt/zimbra/bin/zmcontrol start"

 # 
 echo Service started at : $(date +%T)
 
 # Calculates and outputs amount of time the server was down for
 after="$(date +%s)"
 elapsed="$(expr $after - $before2)"
 hours=$(($elapsed / 3600))
 elapsed=$(($elapsed - $hours * 3600))
 minutes=$(($elapsed / 60))
 seconds=$(($elapsed - $minutes * 60))
 echo Server was down for: "$hours hours $minutes minutes $seconds seconds"

 # Create a txt file in the backup directory that'll contains the current Zimbra
 # server version. Handy for knowing what version of Zimbra a backup can be restored to.
 su - zimbra -c "zmcontrol -v > /backup/zimbra/conf/zimbra_version.txt"
 # or examine your /opt/zimbra/.install_history

 # Display Zimbra services status
 echo Displaying Zimbra services status...
 su - zimbra -c "/opt/zimbra/bin/zmcontrol status"
 
 # Create archive of backed-up directory for offsite transfer
 # cd /backup/zimbra
#"$(date +%F --date='-2 day')"
# tar -zcvf /backup/tar/mail-bak-"$(date +%a)""_""$(date +%F)".tgz -C /backup/zimbra .
###########delete file dump truoc khi nen file vao /backup/tar/#########
echo "REMOVE OLD TAR"

#rm -f /backup/tar/mail-bak-"$(date +%F --date='-2 day')".tgz
#remove folder ngay
rm -rf /backup/tar/"$(date +%F --date='-2 day')"

echo "TAR /opt/zimbra AND /backup/zimbra-ldap"
###########tao folder ngay
mkdir -p /backup/tar/"$(date +%F)"

###########nen thu muc backup cua zimbra vao /backup/tar/
tar -zcvf /backup/tar/"$(date +%F)"/mail-bak-"$(date +%F)".tgz -C /backup/zimbra .

###########nen thu muc backup ldap cua zimbra vao /backup/tar/
tar -zcvf /backup/tar/"$(date +%F)"/mail-ldap-bak-"$(date +%F)".tgz -C /backup/zimbra-ldap .

 # Transfer file to backup server
# ncftpput -u <username> -p <password> <ftpserver> /<desired dest. directory> /tmp/mail.backup.tgz

 # Outputs the time the backup finished
 echo Time backup finished = $(date +%T)

 # Calculates and outputs total time taken
 after="$(date +%s)"
 elapsed="$(expr $after - $before)"
 hours=$(($elapsed / 3600))
 elapsed=$(($elapsed - $hours * 3600))
 minutes=$(($elapsed / 60))
 seconds=$(($elapsed - $minutes * 60))
 echo Time taken: "$hours hours $minutes minutes $seconds seconds"
#
########chmod /opt/zimbra o+r phuc vu cho nrpe check tinh toan ven file cau hinh##
#chmod -R o+r /opt/zimbra/
#
#empty dumpfile backup server IPB
echo "REMOVE OLD TAR FILE REMOTE HOST"
ssh IPB rm -rf /opt/backup/tar/"$(date +%F --date='-1 day')"

echo "COPY NEW TAR FILE TO REMOTE HOST"
ssh IPB "mkdir -p /opt/backup/tar/'$(date +%F)'"
scp /backup/tar/"$(date +%F)"/mail-bak-"$(date +%F)".tgz root@IPB:/opt/backup/tar/"$(date +%F)"/
scp /backup/tar/"$(date +%F)"/mail-ldap-bak-"$(date +%F)".tgz root@IPB:/opt/backup/tar/"$(date +%F)"/

#
#rsync to backup server IPB
#echo Time rsync started = $(date +%T)
#

echo "RSYNC /opt/zimbra AND /backup/zimbra-ldap"
rsync -avHK --delete --exclude '*data/ldap*' /backup/zimbra/ root@IPB:/opt/zimbra
#rsync ldap bak file
rsync -avHK --delete /backup/zimbra-ldap/ root@IPB:/opt/backup/zimbra-ldap


echo Time rsync finished = $(date +%T)
#

##Delete old ldap
echo "DELETE OLD LDAP"
ssh root@IPB "su - zimbra -c 'zmcontrol stop'"
sleep 20
ssh root@IPB "rm -rf /opt/zimbra/data/ldap/*"

## Make folder for new ldap
echo "MAKE FOLDER FOR NEW LDAP"
ssh root@IPB "su - zimbra -c 'mkdir -p /opt/zimbra/data/ldap/config'"
ssh root@IPB "su - zimbra -c 'mkdir -p /opt/zimbra/data/ldap/mdb/db'"

## Import Ldap Config
echo "IMPORT LDAP CONFIG"
ssh root@IPB "su - zimbra -c '/opt/zimbra/libexec/zmslapadd -c /opt/backup/zimbra-ldap/ldap-config.bak'"

## Import Ldap Database
echo "IMPORT LDAP DATABASE"
ssh root@IPB "su - zimbra -c '/opt/zimbra/libexec/zmslapadd /opt/backup/zimbra-ldap/ldap.bak'"

## Reboot Remote Host
echo "REBOOT REMOTE HOST"
ssh root@IPB "reboot"
sleep 600
ssh root@IPB "su - zimbra -c 'zmcontrol stop'"

#
##comment 31/03/2014: thuong xuyen nhan canh bao warning dung luong /backup/ mountpoint####
#delete backupfile after 3 day
#rm -f /backup/tar/mail-bak-"$(date +%F --date='-2 day')".tgz

