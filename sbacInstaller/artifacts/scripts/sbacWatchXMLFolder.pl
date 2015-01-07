#!/usr/bin/perl

use strict;
use warnings;
use Linux::Inotify2;

###################################################################################################
# Educational Online Test Delivery System                                                         #
# Copyright (c) 2013 American Institutes for Research                                             #
#                                                                                                 #
# Distributed under the AIR Open Source License, Version 1.0                                      #
# See https://bitbucket.org/sbacoss/eotds/wiki/AIR_Open_Source_License                            #
#                                                                                                 #
# This script monitors the specified data directory for newly uploaded XML files.  It then calls  #
# the sbacProcessXML.pl script to process newly uploaded files.                                   #
#                                                                                                 #
# Author: Bill Nelson (Identity Fusion, Inc.) - bill.nelson@identityfusion.com                    #
#                                                                                                 #
# Change Log:                                                                                     #   
#                                                                                                 #
#  05/03/2014 - Created XML-specific version of this script.                                      #
#  12/19/2013 - Initial script creation.                                                          #
#                                                                                                 #
###################################################################################################

my $inputXMLFileDir    = "/opt/dropboxes/amplify";           # folder where the XML files are uploaded

$|++;

my $inotify = new Linux::Inotify2 or die "Unable to create new inotify object: $!";


$inotify->watch("$inputXMLFileDir", IN_CLOSE_WRITE, sub {

 my $event = shift;

 # Note:  $event->fullname returns the FQFN of the file
 #        $event->name only returns the name of the file
 my $name = $event->name;

 # call the SBAC script to process user objects contained in the new file
 `/opt/scripts/sbacProcessXML.pl $name`;
 
}) or die "watch creation failed: $!";

1 while $inotify->poll;
