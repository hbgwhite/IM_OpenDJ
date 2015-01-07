#!/bin/bash

################################################################################
#  Educational Online Test Delivery System
#  Copyright (c) 2013 American Institutes for Research
#
#  Distributed under the AIR Open Source License, Version 1.0
#  See accompanying file AIR-License-1_0.txt or at
#  https://bitbucket.org/sbacoss/eotds/wiki/AIR_Open_Source_License
################################################################################


MAINDIR="/opt"                   # all files will be installed in this folder
SCRIPTDIR="$MAINDIR/scripts"     # location of the script directory
LOGSDIR="$MAINDIR/scripts/logs"  # location of the script directory
OPENDJDIR="$MAINDIR/opendj"      # location of the open installation directory
INSTALLUSER="root"               # user who is performing the installation
OPENDJUSER="opendj"              # OpenDJ process owner; also file ownership
JAVAVERSION="1.6.0_45"           # java version this server has been tested with

clear
echo "************************************************************************"
echo
echo "SBAC Environment OpenDJ Installation Script"
echo
echo "Phase 1 of 4:  System Verification"
echo
echo "In this phase, the script will verify the existing Linux environment."
echo
echo "************************************************************************"
echo "Hit the <ENTER> key to continue"
read CONTINUE

echo "Step 1.  Verifying identity of current user..."
# verify that the user running this script is the opendj user
USER=`whoami`
if [[ "$USER" != "$INSTALLUSER" ]]; then
    echo "ERROR:  You are executing this script as: $USER.  You must execute this script as: $INSTALLUSER!"
    echo
    exit
else
    echo "CONFIRMED:  You are executing this script as: $USER"
    echo
fi

echo "Step 2.  Verifying the current working directory..."
# verify the current directory; this script should be run out of /opt
CWD=`pwd`
if [[ "$CWD" != "$MAINDIR" ]]; then
    echo "ERROR:  This script needs to be run out of the /opt folder!"
    echo
    exit
else
    echo "CONFIRMED:  You are executing this script from the /opt folder"
    echo
fi

echo "Step 3.  Searching for the current version of Java..."
if type -p java; then
    echo "CONFIRMED:  The java exectuable was found in the PATH variable"
    _java=java
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
    echo "CONFIRMED:  The java executable was found in the JAVA_HOME variable"
    _java="$JAVA_HOME/bin/java"
else
    echo "ERROR:  The java executable was not found on this server."
    echo "        Java is a requirement for the opendj server."
    exit
fi

if [[ "$_java" ]]; then
    VERSION=$("$_java" -version 2>&1 | awk -F '"' '/version/ {print $2}')
    if [[ "$VERSION" != "$JAVAVERSION" ]]; then
        echo "ERROR:  You must be running Java $VERSION"
        echo
        exit
    else
        echo "CONFIRMED:  You are running java version $VERSION"
        echo
    fi
fi

echo "Step 4. Checking for the existance of the dropbox user..."
DROPBOXUSER=`grep dropbox /etc/passwd`
if [[ -z "$DROPBOXUSER" ]]; then
    echo "ERROR:  The dropbox user does not exist on this server."
    echo
    exit
else
    echo "CONFIRMED:  The dropbox user exists."
    echo
fi

echo "Step 5. Checking to see if $SCRIPTDIR already exists..."
# check to see if the script directory exists, if so, exit the installation script
if [ -e $SCRIPTDIR ]; then
    echo "ERROR:  $SCRIPTDIR already exists!"
    echo
    exit
else
    echo "$SCRIPTDIR does not exist"
    echo
fi

echo "Step 6. Checking to see if $OPENDJDIR already exists..."
# check to see if the opendj directory exists, if so, exit the installation script
if [ -e $OPENDJDIR ]; then
    echo "ERROR:  $OPENDJDIR already exists!"
    echo
    exit
else
    echo "$OPENDJDIR does not exist"
    echo
fi

echo "CONFIRMED:  This is a new installation."
echo
echo "Hit the <ENTER> key to continue"
read CONTINUE

clear
echo "************************************************************************"
echo
echo "SBAC Environment OpenDJ Installation Script"
echo
echo "Phase 2 of 4: Extraction of SBAC-Specific Files"
echo
echo "In this phase, the script will extract SBAC-specific files into their destination folders"
echo
echo "************************************************************************"
echo "Hit the <ENTER> key to continue"
read CONTINUE

echo "Step 7. Extracting the OpenDJ binaries..."
unzip artifacts/OpenDJ-2.6.0.zip

if [ -d $OPENDJDIR ]; then
    echo "CONFIRMED:  The binaries have been extracted to the following folder: $OPENDJDIR."
    echo
else
    echo "ERROR:  There was an error creating the opendj folder structure!"
    echo
    exit
fi

echo "Step 8. Creating folder structure for XML processing scripts ($SCRIPTDIR)..."
cp -R artifacts/scripts .

if [ -d $LOGSDIR ]; then
    echo "CONFIRMED:  The folder structure for the XML processing scripts has been created."
    echo
else
    echo "ERROR:  There was an error creating the XML processing scripts folder structure!"
    echo
    exit
fi

echo "Step 9. Checking for the existance of the opendj user..."
USER=`grep $OPENDJUSER /etc/passwd`
if [[ -z "$USER" ]]; then
    useradd -d /opt/opendj -c "OpenDJ Service Account" -s /bin/bash $OPENDJUSER
    echo "INFO:  The $OPENDJUSER user was created."
    echo
else
    echo "INFO:  The $OPENDJUSER user already exists."
    echo
fi

echo "Step 10. Changing file ownership to the $OPENDJUSER user..."
chown -R $OPENDJUSER:$OPENDJUSER $OPENDJDIR
chown -R $OPENDJUSER:$OPENDJUSER $SCRIPTDIR
echo "INFO:  Files in the $OPENDJDIR and $SCRIPTDIR are now owned by the $OPENDJUSER user."


echo "Hit the <ENTER> key to continue"
read CONTINUE

clear
echo "************************************************************************"
echo
echo "SBAC Environment OpenDJ Installation Script"
echo
echo "Phase 3 of 4:  Installation of OpenDJ Server..."
echo
echo "In this phase, the script will perform an installation of OpenDJ"
echo
echo "************************************************************************"
echo "Hit the <ENTER> key to continue"
read CONTINUE

echo "Step 11. Checking if port 1389 is available..."
LDAPPORT=`netstat -an | grep 1389`
if [[ -z "$LDAPPORT" ]]; then
    echo "CONFIRMED:  Port 1389 is available."
    echo
else
    echo "ERROR:  Port 1389 is currently in use."
    echo
    exit
fi

echo "Step 12. Checking if port 4444 is available..."
LDAPPORT=`netstat -an | grep 4444`
if [[ -z "$LDAPPORT" ]]; then
    echo "CONFIRMED:  Port 4444 is available."
    echo
else
    echo "ERROR:  Port 4444 is currently in use."
    echo
    exit
fi

echo "Step 13. Installing OpenDJ server..."
cd $OPENDJDIR
./setup --cli --no-prompt --rootUserDN "cn=SBAC Admin" --rootUserPassword password --ldapPort 1389 --adminConnectorPort 4444 --baseDN "dc=smarterbalanced,dc=org" --addBaseEntry --acceptLicense --doNotStart
cd $MAINDIR
echo

echo "Hit the <ENTER> key to continue"
read CONTINUE

clear
echo "************************************************************************"
echo
echo "SBAC Environment OpenDJ Installation Script"
echo
echo "Phase 4 of 4:  Customizing the OpenDJ Server..."
echo
echo "In this phase, the script will add SBAC-specific customizations to the OpenDJ server"
echo
echo "************************************************************************"
echo "Hit the <ENTER> key to continue"
read CONTINUE

echo "Step 14. Copying the SBAC customizations into the OpenDJ server..."
echo
unzip -o artifacts/OpenDJ-customizations.zip
chown -R $OPENDJUSER:$OPENDJUSER $OPENDJDIR
echo

echo "Step 15. Importing SBAC directory information tree (DIT)..."
echo
/bin/su - $OPENDJUSER -c "$OPENDJDIR/bin/import-ldif -b dc=smarterbalanced,dc=org -n userRoot -l $OPENDJDIR/ldif/sbac.ldif"
echo

echo "Step 16. Updating the OpenDJ Java properties..."
echo
$OPENDJDIR/bin/dsjavaproperties
echo

echo "Step 17. Starting OpenDJ directory server..."
echo
/bin/su - $OPENDJUSER -c $OPENDJDIR/bin/start-ds
echo

echo "Note: You can log in to the OpenDJ with the following credentials:"
echo
echo "bindDN:   cn=SBAC Admin"
echo "password: cangetin"
echo
echo "You should change these credentials as soon as possible!"
echo 
echo "This completes the installation process."
echo
echo "Have a nice day!"
echo
