#!/bin/bash

###################################################################################################
# Educational Online Test Delivery System                                                         #
# Copyright (c) 2013 American Institutes for Research                                             #
#                                                                                                 #
# Distributed under the AIR Open Source License, Version 1.0                                      #
# See https://bitbucket.org/sbacoss/eotds/wiki/AIR_Open_Source_License                            #
#                                                                                                 #
# this script performs a bulk deletion of directory server objects.                               #
#                                                                                                 #
# The file passed in on the command line ($1) should contain a list of all DNs that you wish to   #
#     delete from the directory server                                                            #
#                                                                                                 #
# NOTE:  use of this script bypasses standard SBAC user processing and is therefore not audited   #
#        by the SBAC user management servers.  you should only use this script during testing     #
#                                                                                                 #
# Author: Bill Nelson (Identity Fusion, Inc.) - bill.nelson@identityfusion.com                    #
#                                                                                                 #
###################################################################################################

bindDN="XXXXXXXXXX"    # replace with the bindDN of a service account or rootDN with permissions 
bindPass="XXXXXXXX"    # replace with password of the OpenDJ service account

/opt/opendj/bin/ldapdelete -h localhost -p 1389 -D "$bindDN" -w $bindPass -f $1
