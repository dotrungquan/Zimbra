#!/bin/bash
read -p "Nhap Vao Doamin: " admindomain
# Domain of concern to be changed
DOMAIN='$admindomain'

WHO=`whoami`
if [ $WHO != "zimbra" ]
then
  echo
  echo "Execute this scipt as user zimbra (\"su - zimbra\")"
  echo
  exit 1
fi

echo
echo
echo "Zimbra Delegate Admin control"
echo "*************************************************"
echo "Utility to grant/revoke delegated administrators"
echo
echo "Please choose R for revoke or G for grant (RG) or any other key to abort."
read -p "RG: " rg

if [ "$rg" == 'R' ]
then
   echo "Please enter the user name (example: user@example.com) you wish to revoke delegated domain admin rights from."
   read -p "username: " username

su - zimbra -c"zmprov ma $username zimbraIsDelegatedAdminAccount FALSE"


elif [ "$rg" == 'G' ]
then
   echo "Please enter the user name (example: user@example.com) you wish to grant delegated domain admin rights."
   read -p "username: " username

su - zimbra -c "zmprov ma $username zimbraIsDelegatedAdminAccount TRUE"
su - zimbra -c "zmprov ma $username +zimbraAdminConsoleUIComponents accountListView"
su - zimbra -c "zmprov ma $username +zimbraAdminConsoleUIComponents DLListView"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username +listAccount"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username listDomain"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username set.account.zimbraAccountStatus"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username set.account.sn"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username set.account.displayName"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username +addDistributionListMember"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username +getDistributionListMembership"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username +getDistributionList"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username +listDistributionList"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username +removeDistributionListMember"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username domainAdminRights"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username domainAdminConsoleRights"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username adminConsoleAliasRights"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username modifyAccount"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username countAlias"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username -configureAdminUI"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username -get.account.zimbraAdminConsoleUIComponents"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username -get.dl.zimbraAdminConsoleUIComponents"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username -set.account.zimbraIsDelegatedAdminAccount"
su - zimbra -c "zmprov grr domain $DOMAIN usr $username -set.dl.zimbraIsAdminGroup"



else
   echo "Invalid option, abort"
   exit 0
fi

exit 0
