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
OPENDJDIR="$MAINDIR/opendj"      # location of the open installation directory
BINDIR="$OPENDJDIR/bin"          # OpenDJ's bin directory 
INSTALLUSER="root"               # user who is performing the installation
OPENDJUSER="opendj"              # OpenDJ process owner; also file ownership
JAVAVERSION="1.6.0_45"           # java version this server has been tested with

# Directory Server Parameters
# The values for the following parameters are set to their default values
# Update these values based on your environment

ROOTDNUSER="cn=SBAC Admin"       # the OpenDJ rootDN account (default is SBAC Admin)
ROOTDNPASS="cangetin"            # the OpenDJ rootDN password (default is cangetin; THIS SHOULD BE CHANGED ASAP)
ADMINPORT="4444"                 # the OpenDJ admin port (default is 4444)
REPLPORT="4989"                  # the port to use for OpenDJ replication (default is 4989)
ADMINUID="admin"  
ADMINPASS="cangetin"             # this password SHOULD BE CHANGED ASAP
BASEDN="dc=smarterbalanced,dc=org"

clear
echo "************************************************************************"
echo
echo "SBAC Environment OpenDJ Replication Configuration Script"
echo
echo "This script will create a replication environment between OpenDJ servers."
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
    echo "CONFIRMED:  The java executable was found in the PATH variable"
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

echo "CONFIRMED:  You may continue with the configuration."
echo
echo "Hit the <ENTER> key to continue"
read CONTINUE

# Initialize variables
FQDN1=""
FQDN2=""

echo "Replication is configured between two hosts:  Host 1 <--> Host 2"
echo
# Get FQDN
while [ -z "$FQDN1" ]; do
    read -p "Enter the Fully Qualified Domain Name (FQDN) of the FIRST host (Ex. ldap1.example.com): " FQDN1
done
echo
# Get FQDN
while [ -z "$FQDN2" ]; do
    read -p "Enter the Fully Qualified Domain Name (FQDN) of the SECOND host (Ex. ldap2.example.com): " FQDN2
done

echo
echo "You are attempting to configure replication between the following two servers:"
echo
echo "HOST1:  $FQDN1"
echo "HOST2:  $FQDN2"
echo
echo "The $FQDN1 database will be used to initialize the $FQDN2 database."
echo
echo "Hit the <ENTER> key to continue"
read CONTINUE

echo
echo "Enabling replication between $FQDN1 and $FQDN2..."
echo

$BINDIR/dsreplication enable --host1 $FQDN1 --port1 $ADMINPORT --bindDN1 "$ROOTDNUSER" --bindPassword1 $ROOTDNPASS --replicationPort1 $REPLPORT --host2 $FQDN2 --port2 $ADMINPORT --bindDN2 "$ROOTDNUSER" --bindPassword2 $ROOTDNPASS --replicationPort2 $REPLPORT --adminUID $ADMINUID --adminPassword $ADMINPASS --baseDN "$BASEDN" -n -X

echo
echo "Initializing the database on $FQDN2 from $FQDN1..."
echo

$BINDIR/dsreplication initialize --baseDN $BASEDN --adminUID $ADMINUID --adminPassword $ADMINPASS --hostSource $FQDN1 --portSource $ADMINPORT --hostDestination $FQDN2 --portDestination $ADMINPORT -n -X

echo
echo "This completes replication configuration between $FQDN1 and $FQDN2."
echo
echo "Execute this script again to configure replication between additional servers."
echo
echo "Have a nice day!"
echo
