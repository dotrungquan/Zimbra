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

zmprov ma $username zimbraIsDelegatedAdminAccount FALSE


elif [ "$rg" == 'G' ]
then
   echo "Please enter the user name (example: user@example.com) you wish to grant delegated domain admin rights."
   read -p "username: " username@$admindomain

zmprov ma $username zimbraIsDelegatedAdminAccount TRUE
zmprov ma $username +zimbraAdminConsoleUIComponents accountListView
zmprov ma $username +zimbraAdminConsoleUIComponents DLListView
zmprov grr domain $DOMAIN usr $username +listAccount
zmprov grr domain $DOMAIN usr $username listDomain
zmprov grr domain $DOMAIN usr $username set.account.zimbraAccountStatus
zmprov grr domain $DOMAIN usr $username set.account.sn
zmprov grr domain $DOMAIN usr $username set.account.displayName
zmprov grr domain $DOMAIN usr $username +addDistributionListMember
zmprov grr domain $DOMAIN usr $username +getDistributionListMembership
zmprov grr domain $DOMAIN usr $username +getDistributionList
zmprov grr domain $DOMAIN usr $username +listDistributionList
zmprov grr domain $DOMAIN usr $username +removeDistributionListMember
zmprov grr domain $DOMAIN usr $username domainAdminRights
zmprov grr domain $DOMAIN usr $username domainAdminConsoleRights
zmprov grr domain $DOMAIN usr $username adminConsoleAliasRights
zmprov grr domain $DOMAIN usr $username modifyAccount
zmprov grr domain $DOMAIN usr $username countAlias
zmprov grr domain $DOMAIN usr $username -configureAdminUI
zmprov grr domain $DOMAIN usr $username -get.account.zimbraAdminConsoleUIComponents
zmprov grr domain $DOMAIN usr $username -get.dl.zimbraAdminConsoleUIComponents
zmprov grr domain $DOMAIN usr $username -set.account.zimbraIsDelegatedAdminAccount
zmprov grr domain $DOMAIN usr $username -set.dl.zimbraIsAdminGroup



else
   echo "Invalid option, abort"
   exit 0
fi

exit 0
