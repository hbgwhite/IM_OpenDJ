#!/usr/bin/perl

use strict;
use warnings;
use Net::LDAP;
use Net::LDAP::Util qw(ldap_error_text);
use Net::SMTP;
use File::Copy qw(move);
use LWP::UserAgent;
use HTTP::Request;
use Email::Sender::Simple qw(sendmail);
use Email::Stuffer;
use Email::Sender::Transport::SMTPS ();

###################################################################################################
# Educational Online Test Delivery System                                                         #
# Copyright (c) 2013 American Institutes for Research                                             #
#                                                                                                 #
# Distributed under the AIR Open Source License, Version 1.0                                      #
# See https://bitbucket.org/sbacoss/eotds/wiki/AIR_Open_Source_License                            #
#                                                                                                 #
# This script takes an XML file as input and updates the OpenDJ server with the actions           #
# contained in the XML file.  The format of each action is defined as follows:                    #
#                                                                                                 #
# <User Action="action">                                                                          #
#                                                                                                 #
# Where "action" can be defined as follows:                                                       #
#                                                                                                 #
#     ADD    - add a new Smarter Balanced user to the directory server                            #
#     MOD    - modify an existing user in the directory server                                    #
#     RESET  - reset the password of an existing user in the directory server                     #
#     SETPWD - set a user's password to a known value                                             #
#     LOCK   - lock an existing user's account in the directory server                            #
#     UNLOCK - unlock an existing user's account in the directory server                          #
#     DEL    - delete a user from the directory server                                            #
#     SYNC   - MOD an existing record or ADD a new record to the directory; based on XML data     #
#     NOTIFY - (Operational) include this email address on any script notifications               #
#                                                                                                 #
# Author: Bill Nelson (Identity Fusion, Inc.) - bill.nelson@identityfusion.com                    #
#                                                                                                 #
# Change Log:                                                                                     #   
#                                                                                                 #
#  09/09/2016 - Updated email subroutine to use new libraries that allow email authentication     #
#				w/server                                                                          #
#  11/27/2015 - Modified processPasswordReset() to allow optional app defined message to be       #
#               included in password reset message.                                               #
#  02/27/2015 - Added translation of encoded CERs to Tenancy Chain received through XML           #
#  02/25/2015 - Added translation of encoded apostrophe, quotes, ampersand, lesser than and       #
#               greater than to email (and, consequently, uid which is a duplicate of email),     #
#               first name, and last name values received through XML                             #
#  02/25/2015 - Added translation of encoded apostrophe to standard apostrophe                    #
#  02/20/2015 - Update $adminEmail from lschneider@amplify.com to sbacssoerrors@listserv.air.org  #
#  02/02/2015 - Update $adminEmail from '<jkimelman@amplify.com>' to 'lschneider@amplify.com'     #
#  02/02/2015 - Update $adminEmail from 'schung@amplify.com' to '<jkimelman@amplify.com>'         #
#  01/29/2015 - Change $emailBody in processAddAction() from "fall of 2014" to "spring of 2015"   #
#  10/29/2014 - Updated email server to mail.opentestsystem.org:10025 per Rami Levi request #959  #
#  05/28/2014 - Added code to escape the following characters in the DN: " # + , ; < = > \        #
#  05/12/2014 - Updated email server to mail-dev.opentestsystem.org:10025 as per Scott Huitt.     #
#  05/03/2014 - Add NOTIFY action to allow data file to include list of additional email          #
#               addresses that will receive an email notification when this script completes.     #
#               Allow <Password> element to be passed in during ADD and MOD actions. This is only #
#               being used for Smarter Balanced in their CSV file processing, but it is anticipate#
#               that this will be used for others as well.  Removed DEBUG statements in LOCK and  #
#               UNLOCK subroutines.  Removed hardcoded telephone number in MOD subroutine.        #
#               Renamed script from sbacProcessDataFile.pl to sbacProcessXML.pl.                  #
#  04/07/2014 - In the ADD and MOD actions, look for an empty @roleArray before populating the    #
#               sbacTenancyChain.  If the @roleArray is empty, omit the attribute from the data.  #
#  04/03/2014 - Updated regular expression to allow zero or more spaces in a Phone element that   #
#               does not contain a phone number.                                                  #
#  03/05/2014 - Corrected regular expression that detects empty role elements.  Added extended    #
#               logging for tenancy chain processing while console logging is enabled. Updated    #
#               the generateRandomPassword() subroutine to generate a password of 6 alphabetic    #
#               characters followed by 1 numeric character and 1 special character.               #
#  02/11/2014 - Added SETPASSWORD action processing to allow Help Desk to reset passwords to a    #
#               known value.                                                                      #
#  01/03/2014 - Changes based on UAT testing.  Updated $fromAddress and new account email.        #
#               Send error to HTTP server when invalid element observed on ADD or MOD operation.  #
#  01/01/2014 - Updated the script to perform a single LDAP connect at the beginning and a        #
#               single disconnect at the end - rather than multiple open/close to LDAP server.    #
#  12/31/2013 - Updated New User email body.                                                      #
#  12/27/2013 - Added processEarlyExit() subroutine to standardize processing of early script     #
#               exit procesing.                                                                   #
#  12/18/2013 - Added $testXMLFile control flag to indicate whether the XML file is used for test #
#               purposes or if it is real.  User email is suppressed when processing a test file  #
#               and passwords are hard coded to "password". Added new subroutine to move the      #
#               input XML file to a different folder once is has been processed. Added variable   #
#               to configure the user's email server. Tested the processing of this file from the #
#               sbacDirectoryWatch.pl script.                                                     #
#  12/16/2013 - Corrected bug in tenancy chain processing where the chain did not include empty   #
#               elements properly.                                                                #
#  12/15/2013 - Add processing of SYNC operation. Added sendHTTPResponse() to send HTTP Response. #
#               reformatted file and added additional comments.  Added $sendHTTPResponse and      #
#               $sendEmailResponse control flags.                                                 #
#  11/24/2013 - Added password RESET processing.                                                  #
#  11/15/2013 - Send email to admin user with file processing results.                            #
#  11/02/2013 - Added log file processing.  Send new user email with temp password.               #
#  10/27/2013 - Initial script creation.                                                          #
#                                                                                                 #
###################################################################################################


# Control Variables - these variables controle the flow and/or output in the script (defaults shown in parentheses)

my $consoleOutput      = 0;                                # (0) - 0 = disable console messages;   1 = enable console messages
my $sendHTTPResponse   = 1;                                # (1) - 0 = do not send HTTP response;  1 = send HTTP response
my $sendEmailResponse  = 1;                                # (1) - 0 = do not send email response; 1 = send email response
my $useSmtpAuth        = 1;                                # (1) - 0 = do not include auth credentials when emailing; 1 = include auth credentials when emailing
my $extendedLogging    = 1;                                # (1) - 0 = disable extended logging;   1 = enable extended logging
my $emailOverride      = 0;                                # (0) - 0 = use email addr from file;   1 = explicitly specify email addr
my $testXMLFile        = 0;                                # (0) - 0 = processing real XML file;   1 = processing test XML file

# Environmental Variables - these variables may be customized to reflect your environment

my $inputXMLFileDir    = "[XML-UPLOAD]";                   # folder where the XML files are uploaded
my $processedFileDir   = "[PROCESSED-FILES]";              # folder where the XML files are stored after processing
my $httpResponseServer = "[CALLBACK-URL]";                 # HTTP server for callback response
my $ldapHost           = "[LDAP-HOST]";                    # host name of the OpenDJ server
my $ldapPort           = "[LDAP-PORT]";                    # port number of the OpenDJ server
my $ldapBindDN         = "[BIND-DN]";                      # replace with the bindDN of a service account or rootDN with permissions
my $ldapBindPass       = "[BIND-PASSWORD]";                # replace with password of the OpenDJ service account
my $ldapBaseDN         = "[BASEDN]";                       # location where the users may be found
my $ldapTimeout        = "10";                             # how long to wait for a connection to the LDAP server before timing out

# Email Variables - these variables are specific to subroutines which generate emails

my $fromAddress       = '[EMAIL-SENDER]';                  # all email will come from this email address
my $fromPerson        = '[EMAIL-NAME';                     # the name of the person sending the email
my $emailAddrOverride = '[OVERRIDE-EMAIL]';                # when $emailOverride flag is set, send recipient's email to this addr
my $adminEmail        = '[ADMIN-EMAIL]';                   # email address of user who is monitoring script results
my $defaultPassword   = "[DEFAULT-PASSWORD]";              # default password for test users
my $smtpServer        = '[SMTP-SERVER]';                   # replace with your email server 
my $smtpPort          = 25;                                # port to connect to on smtp server 
my $smtpUser          = '[EMAIL-AUTHENTICATION-USER]';     # replace with your email server username
my $smtpPassword      = '[EMAIL-AUTHENTICATION-PASSWORD]'; # replace with your email server password


# Script Specific Variables - these are used within the processing of the script

my $xmlUserParseFlag = 0;  # global flag; indicates whether we are processing an action or not
                           # 0 = not currently processing a user; 1 = currently processing user

my $xmlAction = "";        # the action being performed on the user; valid actions include those 
                           # defined in this files' header

# initialize counters; these will be used in a summary report
my $userCount   = 0;       # number of users processed
my $errCount    = 0;       # number of errors found during processing
my $addCount    = 0;       # number of users added to the directory server
my $modCount    = 0;       # number of users modified in the directory server
my $resetCount  = 0;       # number of passwords reset for users in the directory server
my $pwdChgCount = 0;       # number of passwords changed (to a known value) for users in the directory server
my $lockCount   = 0;       # number of users whose accounts have been locked
my $unlockCount = 0;       # number of users whose accounts have been unlocked
my $delCount    = 0;       # number of users whose accounts have been deleted
my $syncCount   = 0;       # number of synchronization events processed (look to the $addCount and $modCount for details)
my $notifyCount = 0;       # number of users that will receive a email once this script has completed.
my $roleCount   = 0;       # number of total roles processed for all users found in the data file
my $lineCount   = 0;       # number of lines processed (used for extended logging)

# initialize other varilables for this script
my @userData;              # array containing user data
my @errorData;             # array containing error data
my @emailList;             # list of additional email addresses for notifications
my $errorEntry     = "";   # string containing specific error data
my $dataFileExists = 1;    # used during early exit from this script; 1 = move data file; 0 = don't attempt to move the data file


##########################################################################################################
#                                           Main Program                                                 #
##########################################################################################################

my $startTime = time;  # capture the start time of this script

# Send message to log file indicating start of file processing
updateLog("INFO", "\"Smarter Balanced user processing initiated.\"");

# verify number of input parameters equals 1 (the filename to process)
my $numArgs = $#ARGV + 1;
if ($numArgs ==0) {

    # Process an early exit from the script
    my $errorMessage = "Missing input file parameter.<br><br>Usage is:  $0 {XML filename}.<br><br>";
    # update the flag to indicate that the specified data file does not exist
    $dataFileExists = 0;

    processEarlyExit($errorMessage,$dataFileExists);
}

# we have at least one input parameter; construct the name of data file based on this
my $xmlFileName = "$inputXMLFileDir/$ARGV[0]";

# Send message to log file indicating start of file processing
updateLog("INFO", "\"Input file = $xmlFileName\"");

# determine if data file exists
if (!(-e $xmlFileName)) {

    # Process an early exit from the script
    my $errorMessage = "Invalid Filename ($xmlFileName).  File Does Not Exist!<br><br>";

    # update the flag to indicate that the specified data file does not exist
    $dataFileExists = 0;

    processEarlyExit($errorMessage,$dataFileExists);

}

# print message to console (if flag enabled)
if ($consoleOutput == 1) { print "\nProcessing Input File: $xmlFileName\n"; }

# if the filename contains the string "testfile" anywhere in it, then this is a file
# to be used for testing purposes only; i.e. email should not be sent to the end user
if ($xmlFileName =~ /testfile/) { 
    if ($consoleOutput == 1) { 
        print "\nProcessing Input File: This file is used for testing purposes ONLY!"; 
        print "\nProcessing Input File: End-user email has been disabled.  End-user password is set to \"password\" for ADD operations.\n\n"; 
    }
    updateLog("INFO", "\"This file is used for testing only; no email will be sent to users\"");
    $testXMLFile = 1;
}

# open the XML file for reading
open(XMLFILE, $xmlFileName) or die "Error!  Could not open XML file ($xmlFileName) - $!";

# Open a TCP connection with the OpenDJ Server, timeout if no response in 10s
my $ldapHandle = Net::LDAP->new("$ldapHost", port=>$ldapPort, timeout=>$ldapTimeout) or die "$@";

# Bind to the directory server with the credentials provided
my $mesg = $ldapHandle->bind("$ldapBindDN", password=>"$ldapBindPass");

# check for valid bind operation or print error if unable to bind
if ($mesg->code) {

    # Process an early exit from the script
    my $errorMessage = "Cannot bind to the directory server: $ldapHost:$ldapPort".ldap_error_text($mesg->code)."<br><br>";
    processEarlyExit($errorMessage,$dataFileExists);

}

my $line = "";
foreach $line (<XMLFILE>)  {   

    # the loop detects the action being performed and then proceeds to capture all user data
    # associated with that action.  once the end of data has been detected (as seen with the </User>
    # tag), then the appropriate subroutine is called to process the action.

    # remove Carriage Return (\r) and Line Feed (\n) character(s)
    $line =~ s/\r|\n//g;

    # print message to console (if flag enabled)
    if ($consoleOutput == 1) { print "Processing Line ($xmlUserParseFlag): [$line]\n"; }

    $lineCount++;

    if ($line =~ /<User Action="(.*)">/) {       # beginning of action

        # terminate processing if we detect another action before processing
        # of the current action is completed
        if ($xmlUserParseFlag == 1) {

           # Process an early exit from the script
           my $errorMessage = "New action detected before current action completed.  Corrupt XML file.<br><br>";
           processEarlyExit($errorMessage,$dataFileExists);

        } else {

            $xmlAction = $1;
            $xmlUserParseFlag = 1;

            # print message to console (if flag enabled)
            if ($consoleOutput == 1) { print "Processing Action: $xmlAction\n"; }

        }

    } elsif ($line =~ /<\/User>/) {              # end of action

        $userCount++;
        $xmlUserParseFlag = 0;

        # call the appropriate subroutine to process the action 
        # NOTE: a reference to the array is passed to the subroutine, not the array, itself

        # print message to console (if flag enabled)
        if ($consoleOutput == 1) { print "Processing Action: [$xmlAction]\n"; }

        if    ($xmlAction eq "ADD")    { processAddAction(\@userData);  } 
        elsif ($xmlAction eq "MOD")    { processModAction(\@userData);  } 
        elsif ($xmlAction eq "DEL")    { processDelAction(\@userData);  }
        elsif ($xmlAction eq "LOCK")   { processLockAction(\@userData); }
        elsif ($xmlAction eq "UNLOCK") { processUnlockAction(\@userData); }
        elsif ($xmlAction eq "RESET")  { processResetAction(\@userData); }
        elsif ($xmlAction eq "SETPWD") { processPwdChangeAction(\@userData); }
        elsif ($xmlAction eq "SYNC")   { processSyncAction(\@userData); }
        elsif ($xmlAction eq "NOTIFY") { processNotifyAction(\@userData); }
        else  { 

                 # Process an early exit from the script
                 my $errorMessage = "Invalid User Action ($xmlAction) Detected!<br><br>";
                 processEarlyExit($errorMessage,$dataFileExists);

        }

        # initialize the current array after processing; use the undef() to free up memory
        undef(@userData);
        $xmlAction = ""; 

    } elsif (($line =~ /<\?xml version/) || ($line =~ /<Users\>/) || ($line =~ /<\/Users\>/) || ($line =~ /^$/)) {    # ignore these lines

        # print message to console (if flag enabled)
        if ($consoleOutput == 1) { print "Line Ignored:  $line\n"; }

        ;

    } else {

        # add the current line to the array if it is not a blank line
        push(@userData, $line);

    }
}

# Send message to log file indicating that all users have been processed
if ($userCount == 1) {
    updateLog("INFO", "\"$userCount user object has been processed in the XML file.\"");
} else {
    updateLog("INFO", "\"$userCount user objects have been processed in the XML file.\"");
}

########## Close Connections ##########

# unbind and disconnect from the OpenDJ server
$ldapHandle->unbind;
$ldapHandle->disconnect;

# close the XML file
close(XMLFILE);

########## Move the Input File ##########

moveXMLFile();

########## Message Console ##########

# print message to console (if flag enabled)
if ($consoleOutput == 1) { 
    print "\nSummary Results:  Processed $lineCount lines and found $userCount users and $roleCount roles\n\n";
    print "Details:\n";
    print "-------------------------\n";
    print "Users Added:         $addCount\n";
    print "Users Modified:      $modCount\n";
    print "Users Deleted:       $delCount\n";
    print "Passwords Reset:     $resetCount\n";
    print "Passwords Changed:   $pwdChgCount\n";
    print "Users Locked:        $lockCount\n";
    print "Users Unlocked:      $unlockCount\n";
    print "Users Synchronized:  $syncCount\n";
    print "Users Notified:      $notifyCount\n";
    print "\n";
}

########## HTTP Response ##########

if ($sendHTTPResponse == 1) { 

    # Send notification to the HTTP Server
    # NOTE: a reference to the error array is passed, not the array, itself
    sendHTTPResponse(\@errorData);
}

########## Email Response ##########

my $endTime = time;                            # capture the end time of this script
my $processingTime = $endTime - $startTime;    # compute processing time

if ($sendEmailResponse == 1) { 

    # notify the administrator of the process run results
    my $emailSubject = "Smarter Balanced Data File Processed";
    my $emailBody = "File name: $xmlFileName.<br><br>Total Procesing Time: $processingTime Seconds<br><br>Results: Total($userCount); Added($addCount); Modified($modCount); Deleted($delCount); Pass Reset($resetCount); Pass Change($pwdChgCount); Locked($lockCount); Unlocked($unlockCount); Synchronized($syncCount); Notify($notifyCount); Errors($errCount).<br><br>";

    if ($errCount > 0) {
        $emailBody .= "Error Results:<br><br>";

        # Extract the error messages from the array
        foreach (@errorData) {
            $errorEntry = $_."<br><br>";
            $emailBody .= $errorEntry;
        }
    }

    if ($emailOverride == 1) {
        $adminEmail = $emailAddrOverride;
    }
    sendEmail($emailSubject,$emailBody,$adminEmail,$fromAddress,"Admin");

    # if extended logging is enabled, add additional details to log file
    if ( $extendedLogging == 1 ) { updateLog("INFO", "\"Administrator notified of run results ($adminEmail)\""); }

}

########## Update Log File ##########

# Send a message to log file indicating results of file processing
updateLog("INFO", "\"Results: Total($userCount); Add($addCount); Mod($modCount); Del($delCount); Pass Reset($resetCount); Pass Change($pwdChgCount); Lock($lockCount); Unlock($unlockCount); Synch($syncCount); Notify($notifyCount); Errors($errCount).\"");

# Send messages to log file indicating processing has completed
updateLog("INFO", "\"Smarter Balanced user processing COMPLETED. Elapsed Time: $processingTime Seconds\"");
updateLog("INFO", "\"*******************************\"");



##########################################################################################################
#                                           Subroutines                                                  #
##########################################################################################################


##########################################################################################################
# Subroutine:  translateCER()                                                                            #
#                                                                                                        #
# This subroutine translates Character Entity Records required within XML into single characters         #
# accepted by OpenDJ.                                                                                    #
##########################################################################################################

sub translateCER {

  my $input = $_[0];

  # If Character Entity Records are in the data received by translateCER, translate them into single characters
  if ( $input =~ m/&[^;]*;/ ) {

    # Translate apostrophes
    $input =~ s/&apos;/'/g;

    # Escape translated double quotes with a backslash during the translation since this data is being 
    # handled within double quotes in this script
    $input =~ s/&quot;/\"/g;

    # Translate less than
    $input =~ s/&lt;/</g;

    # Translate greater than
    $input =~ s/&gt;/>/g;

    # Translate ampersands
    $input =~ s/&amp;/&/g;
  }

  return $input;

} # end of translateCER()

##########################################################################################################
# Subroutine:  processAddAction()                                                                        #
#                                                                                                        #
# This subroutine adds a new record to the directory server.  The XML data for an ADD operation contains #
# all of the attributes necessary to create the user's object.  This operation creates a new user based  #
# on this data.                                                                                          #
##########################################################################################################

sub processAddAction {

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "In Subroutine, processing ADD Action\n"; }

  # define a local array that contains the values of the data passed in
  my @addUserArray = @{$_[0]};
  my @uniqueRoleArray = ();
  my $uniqueRoleArray = "";

  if ($consoleOutput == 1) { print "\nAdd User Array:   [@addUserArray]\n"; }

  # LDIF Variables
  my $sbacuuid        = "";     # Smarter Balanced UUID
  my $uid             = "";     # User's uid 
  my $DN              = "";     # User's Distinguished Name (constructed from $sbacuuid and constants)
  my $sn              = "";     # User's last name
  my $givenName       = "";     # User's first name
  my $cn              = "";     # User's full name (constructed from $sn and $givenName)
  my $mail            = "";     # User's email address
  my $userPassword    = "";     # User's initial password
  my $telephoneNumber = "";     # User's telephone number

  my $processingRoleFlag = 0;   # Flag to indicate if we are currently processing data associated with a user's role (tenancy chain)
  my $sbacTenancyChain = "";    # The actual tenancy chain
  my $numRoleElements  = 0;     # The number of elements in the @roleArray
  my @roleArray;                # Array for storing role components (tenancy chain)

  # extract the attributes from the data
  # WARNING: no checking is performed for the redefining of attribute values.  When the code 
  # exits this loop, the attributes will be set to the LAST VALUE found in the @addUserArray
  foreach (@addUserArray) {

      if ($_ =~ /<UUID>(.*)<\/UUID>$/) {                     # UUID (sbacUUID)

          $sbacuuid = $1;
          my $oldSBACuuid = $1;

          # escape any special characters in the DN that may cause the server problems
          # when creating the distinguished name
          $sbacuuid =~ s/(["+,;<>\\])/\\\1/g;

          $DN  = "sbacUUID=$sbacuuid,$ldapBaseDN";

          # return the sbacuuid attribute to its original value
          $sbacuuid = $oldSBACuuid;

          if ($consoleOutput == 1) { print "\nDN:  $DN\n"; }

      } elsif ($_ =~ /<FirstName>(.*)<\/FirstName>$/) {      # first name (givenName)

          $givenName = translateCER($1);

      } elsif ($_ =~ /<LastName>(.*)<\/LastName>$/) {        # last name (sn)

          $sn = translateCER($1);

      } elsif ($_ =~ /<Email>(.*)<\/Email>$/) {              # email address (mail, uid)

          $mail = translateCER($1);
          $uid  = $mail;

      } elsif ($_ =~ /<Phone>(.*)<\/Phone>$/) {              # telephone number (telephoneNumber)

          $telephoneNumber = $1;

      } elsif ($_ =~ /<Phone(.*)$/) {                        # EMPTY telephone number (telephoneNumber)

          $telephoneNumber = "undef";

      } elsif ($_ =~ /<Password>(.*)<\/Password>$/) {         # password (userPassword)

          $userPassword = $1;

      } elsif ($_ =~ /<Password(.*)$/) {                     # EMPTY password (userPassword)

          # this is really a 'do nothing' case
          # this is here just to recognize the field
          $userPassword = "";

      } elsif ($_ =~ /<Role>$/) {                            # first role tag (start processing)

          $processingRoleFlag = 1;
          $sbacTenancyChain = "|";
          $roleCount++;

          if ($consoleOutput == 1) { print "Starting Tenancy Chain: [$sbacTenancyChain]\n"; }

      } elsif ($_ =~ /<\/Role>$/) {                          # last role tag (end processing)

          $processingRoleFlag = 0;
#         $sbacTenancyChain .= "|";
          push(@roleArray,$sbacTenancyChain);

          if ($consoleOutput == 1) { print "Ending Tenancy Chain:   [$sbacTenancyChain]\n"; }

      } elsif ($processingRoleFlag == 1) {                   # grab value; order is guaranteed by XML file creator program

          if ($_ =~ /<RoleId>(.*)\<\/RoleId>$/) {

             # determine if this role identifier has already been used in this entry

             # print message to console (if flag enabled)
             if ($consoleOutput == 1) { 
                 print "Role Array Size: $uniqueRoleArray\n";
                 print "Role Array: [";
                 print @uniqueRoleArray;
                 print "]\n";
             }

             my @matches = grep { /$1/ } @uniqueRoleArray;  # determine if there are already occurrances
             my $numMatches = @matches;                     # determine number of occurrances

             if ($numMatches > 1) {

                 # Process an early exit from the script
                 my $errorMessage = "Invalid Role Identifier ($1) Detected!<br><br>Role already defined in chain.<br><br>";
                 processEarlyExit($errorMessage,$dataFileExists);

             } else {
                 # save this role identifier
                 push (@uniqueRoleArray,$1);
             }
          }

          # build/continue building the tenancy chain
          if ($_ =~ /\<.*\>(.*)\</.*\>$/) {   # this element has a value (i.e. <Name>Test Author</Name>)

              $sbacTenancyChain .= translateCER($1)."|";

              if ($consoleOutput == 1) { print "Building Tenancy Chain: [$sbacTenancyChain]\n"; }

          } elsif ($_ =~ /<(.*)\/>$/) {       # this is an empty element (i.e. <ClientID/>)

              $sbacTenancyChain .= "|";

              if ($consoleOutput == 1) { print "Building Tenancy Chain: [$sbacTenancyChain]\n"; }

          }
      } else {

         $errCount++;    # Keep track of how many errors we have incurred

         # Save the error and include it in a final report
         $errorEntry = "ADD:$DN:Invalid Element Found While Processing ADD in Smarter Balanced User XML File: \"$_\"";
         push(@errorData, $errorEntry);

         # Process an early exit from the script
         my $errorMessage = "Invalid Element Found While Processing ADD in Smarter Balanced User XML File:  $_<br><br>";
         processEarlyExit($errorMessage,$dataFileExists);

      }

  }
  $cn = $givenName." ".$sn;

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "\nDN:  $DN\n"; }

  ##############################################
  # Update the OpenDJ Server with the new user #
  ##############################################

  # if a password was not passed in via the data file, we will generate one
  if ($userPassword eq "") {

      if ($testXMLFile == 0) {

          updateLog("INFO", "\"Generating random password for user.\"");

          # generate a random password for new users
          $userPassword = generateRandomPassword();

      } else {

          updateLog("INFO", "\"Setting password to default value.\"");

          # test file users (that don't already have a password set will
          # receive a default password
          $userPassword = $defaultPassword;

      }
  } else {

    updateLog("INFO", "\"Using password included in XML file.\"");
      
  }

  # determine the number of elements included in the role array (how many tenancy chains)
  $numRoleElements = @roleArray;

  # Add the new user to the OpenDJ server
  if ($telephoneNumber eq "undef") {

      if ($numRoleElements == 0) {

          $mesg = $ldapHandle->add($DN, attr => [
                  'sn'               => "$sn",
                  'givenName'        => "$givenName",
                  'cn'               => "$cn",
                  'sbacUUID'         => "$sbacuuid",
                  'uid'              => "$uid",
                  'mail'             => "$mail",
                  'userPassword'     => "$userPassword",
                  'inetUserStatus'   => "Active",
                  'objectClass'      => ['top', 'person', 'organizationalPerson', 'inetOrgPerson', 'sbacPerson', 'inetuser', 'iplanet-am-user-service'] ] );

      } else {

          $mesg = $ldapHandle->add($DN, attr => [
                  'sn'               => "$sn",
                  'givenName'        => "$givenName",
                  'cn'               => "$cn",
                  'sbacUUID'         => "$sbacuuid",
                  'uid'              => "$uid",
                  'mail'             => "$mail",
                  'userPassword'     => "$userPassword",
                  'inetUserStatus'   => "Active",
                  'sbacTenancyChain' => [ @roleArray ],
                  'objectClass'      => ['top', 'person', 'organizationalPerson', 'inetOrgPerson', 'sbacPerson', 'inetuser', 'iplanet-am-user-service'] ] );

      }

  } else {

      if ($numRoleElements == 0) {

          $mesg = $ldapHandle->add($DN, attr => [
                  'sn'               => "$sn",
                  'givenName'        => "$givenName",
                  'cn'               => "$cn",
                  'sbacUUID'         => "$sbacuuid",
                  'uid'              => "$uid",
                  'mail'             => "$mail",
                  'userPassword'     => "$userPassword",
                  'telephoneNumber'  => "$telephoneNumber",
                  'inetUserStatus'   => "Active",
                  'objectClass'      => ['top', 'person', 'organizationalPerson', 'inetOrgPerson', 'sbacPerson', 'inetuser', 'iplanet-am-user-service'] ] );

      } else {

          $mesg = $ldapHandle->add($DN, attr => [
                  'sn'               => "$sn",
                  'givenName'        => "$givenName",
                  'cn'               => "$cn",
                  'sbacUUID'         => "$sbacuuid",
                  'uid'              => "$uid",
                  'mail'             => "$mail",
                  'userPassword'     => "$userPassword",
                  'telephoneNumber'  => "$telephoneNumber",
                  'inetUserStatus'   => "Active",
                  'sbacTenancyChain' => [ @roleArray ],
                  'objectClass'      => ['top', 'person', 'organizationalPerson', 'inetOrgPerson', 'sbacPerson', 'inetuser', 'iplanet-am-user-service'] ] );

      }
  }

  if ($mesg->code) {

      $errCount++;    # Keep track of how many errors we have incurred

      # Send message to log file indicating error
      updateLog("WARN", "\"An error occurred while processing ADD on $DN. ".ldap_error_text($mesg->code)."\"");
      warn "\nAn error occurred while adding entry: $DN.  See logfile for details\n";

      # Save the error and include it in a final report
      $errorEntry = "ADD:".$DN.":".ldap_error_text($mesg->code);
      push(@errorData, $errorEntry);

  } else {

      # Don't send emails to users if we are processing a XML file used for testing
      if ($testXMLFile == 0) {

          # notify the user that their account has been created
          my $emailSubject = "Welcome to the Smarter Balanced development environment";
          my $emailBody = "Welcome, $cn, to Smarter Balanced!  Your account, $uid, has been created and your temporary password is: $userPassword<br><br>";
             $emailBody .= "This account will let you immediately access the Smarter Balanced development environment.<br><br>";
             $emailBody .= "You are required to change your temporary password.<br><br>";
             $emailBody .= "Click the following link to access your account and update your password: <a href=\"https://oam-secure.ci.opentestsystem.org/auth/UI/Login\">https://oam-secure.ci.opentestsystem.org/auth/UI/Login</a>.<br><br>";
             $emailBody .= "You will not be able to log into any Smarter Balanced systems until you have updated your temporary password and provided an answer to a security question.<br><br>";
             $emailBody .= "You can find out more information about Smarter Balanced systems on the <a href=\"http://portal-dev.opentestsystem.org/\">Smarter Balanced web site</a> at http://portal-dev.opentestsystem.org/.<br><br>";

          if ($emailOverride == 1) { 
              $mail = $emailAddrOverride;
          } 
          sendEmail($emailSubject,$emailBody,$mail,$fromAddress,"User");

          # if extended logging is enabled, add additional details to log file
          if ( $extendedLogging == 1 ) { updateLog("INFO", "\"User notified of new account ($mail)\""); }
      }

      $addCount++;        # Keep track of how many additions were made to the OpenDJ server
  }

  # initialize the role array after processing; use the undef() to free up memory
  undef(@roleArray);

return 1;

}    # end of processAddAction()


##########################################################################################################
# Subroutine:  processDelAction()                                                                        #
#                                                                                                        #
# This subroutine deletes an existing user from the directory server.  No notification is sent to the    #
# user for this operation.  This should be reconsidered in the future.                                   #
##########################################################################################################

sub processDelAction {

  my $DN = "";     # User's Distinguished Name (constructed from $sbacuuid and constants)

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "In Subroutine, processing DELETE Action\n"; }

  # define a local array that contains the values of the data passed in
  my @delUserArray = @{$_[0]};

  if ($consoleOutput == 1) { print "\nDel User Array:   [@delUserArray]\n"; }

  foreach (@delUserArray) {


      if ($_ =~ /<UUID>(.*)<\/UUID>$/) {                     # UUID (sbacUUID)
          $DN  = "sbacUUID=$1,$ldapBaseDN";
      } else {

          # Process an early exit from the script
          my $errorMessage = "Invalid value found ($_) for DELETE action!<br><br>";
          processEarlyExit($errorMessage,$dataFileExists);

      }

  }

  ##########################################
  # Delete the user from the OpenDJ Server #
  ##########################################

  # Delete the user from the OpenDJ server
  $mesg = $ldapHandle->delete($DN);

  # check for valid bind operation or print error if unable to update the hos
  if ($mesg->code) {

      $errCount++;    # Keep track of how many errors we have incurred

      # Send message to log file indicating error
      updateLog("WARN", "\"An error occurred while processing DEL on $DN. ".ldap_error_text($mesg->code)."\"");
      warn "\nAn error occurred while deleting entry: $DN.  See logfile for details\n";

      # Save the error and include it in a final report
      $errorEntry = "DEL:".$DN.":".ldap_error_text($mesg->code);
      push(@errorData, $errorEntry);

  } else {

      $delCount++;        # Keep track of how many user deletions were made on the OpenDJ server

  }

return 1;

}    # end of processDelAction()



##########################################################################################################
# Subroutine:  processModAction()                                                                        #
#                                                                                                        #
# This subroutine modifies an existing directory server user's attributes.  The XML data for a MOD       #
# operation is expected to consist of all attributes associated with a user so it simply updates the     #
# user's record with all of this data.                                                                   #
##########################################################################################################

sub processModAction {

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "In Subroutine, processing MOD Action\n"; }

  # define a local array that contains the values of the data passed in
  my @modUserArray = @{$_[0]};
  my @uniqueRoleArray = ();
  my $uniqueRoleArray = "";

  if ($consoleOutput == 1) { print "\nMod User Array:   [@modUserArray]\n"; }

  # LDIF Variables
  my $sbacuuid        = "";     # Smarter Balanced UUID
  my $uid             = "";     # User's uid 
  my $DN              = "";     # User's Distinguished Name (constructed from $sbacuuid and constants)
  my $sn              = "";     # User's last name
  my $givenName       = "";     # User's first name
  my $cn              = "";     # User's full name (constructed from $sn and $givenName)
  my $mail            = "";     # User's email address
  my $userPassword    = "";     # User's initial password
  my $telephoneNumber = "";     # User's telephone number

  my $processingRoleFlag = 0;     # Flag to indicate if we are currently processing data associated with a user's role (tenancy chain)
  my $sbacTenancyChain = "";    # The actual tenancy chain
  my $numRoleElements  = 0;     # The number of elements in the @roleArray
  my @roleArray;                # Array for storing role components (tenancy chain)

  # extract the attributes from the data
  # WARNING: no checking is performed for the redefining of attribute values.  When the code 
  # exits this loop, the attributes will be set to the LAST VALUE found in the @modUserArray
  foreach (@modUserArray) {

      if ($_ =~ /<UUID>(.*)<\/UUID>$/) {                     # UUID (sbacUUID)

          $sbacuuid = $1;
          $DN  = "sbacUUID=$sbacuuid,$ldapBaseDN";

          if ($consoleOutput == 1) { print "\nDN:  $DN\n"; }

      } elsif ($_ =~ /<FirstName>(.*)<\/FirstName>$/) {      # first name (givenName)

          $givenName = translateCER($1);

      } elsif ($_ =~ /<LastName>(.*)<\/LastName>$/) {        # last name (sn)

          $sn = translateCER($1);

      } elsif ($_ =~ /<Email>(.*)<\/Email>$/) {              # email address (mail, uid)

          $mail = translateCER($1);
          $uid  = $mail;

      } elsif ($_ =~ /<Phone>(.*)<\/Phone>$/) {              # telephone number (telephoneNumber)

          $telephoneNumber = $1;

      } elsif ($_ =~ /<Phone(.*)\/>$/) {                     # EMPTY telephone number (telephoneNumber)

          $telephoneNumber = "undef";

      } elsif ($_ =~ /<Password>(.*)<\/Password>$/) {         # password (userPassword)

          $userPassword = $1;

      } elsif ($_ =~ /<Password(.*)$/) {                     # EMPTY password (userPassword)

          # this is really a 'do nothing' case
          # this is here just to recognize the field
          $userPassword = "";

      } elsif ($_ =~ /<Role>$/) {                            # first role tag (start processing)

          $processingRoleFlag = 1;
          $sbacTenancyChain = "|";
          $roleCount++;

          if ($consoleOutput == 1) { print "Starting Tenancy Chain: [$sbacTenancyChain]\n"; }

      } elsif ($_ =~ /<\/Role>$/) {                          # last role tag (end processing)

          $processingRoleFlag = 0;
#         $sbacTenancyChain .= "|";
          push(@roleArray,$sbacTenancyChain);

          if ($consoleOutput == 1) { print "Ending Tenancy Chain:   [$sbacTenancyChain]\n"; }

      } elsif ($processingRoleFlag == 1) {                   # grab value; order is guaranteed by supplier of XML file

          if ($_ =~ /<RoleId>(.*)\<\/RoleId>$/) {

             # determine if this role identifier has already been used in this entry

             # print message to console (if flag enabled)
             if ($consoleOutput == 1) { 
                 print "Role Array Size: $uniqueRoleArray\n";
                 print "Role Array: [";
                 print @uniqueRoleArray;
                 print "]\n";
             }

             my @matches = grep { /$1/ } @uniqueRoleArray;  # determine if there are already occurrances
             my $numMatches = @matches;                     # determine number of occurrances

             if ($numMatches > 1) {

                 # Process an early exit from the script
                 my $errorMessage = "Invalid Role Identifier ($1) Detected ($1)<br><br>";
                 processEarlyExit($errorMessage,$dataFileExists);

             } else {
                 # save this role identifier
                 push (@uniqueRoleArray,$1);
             }
          }
          # build/continue building the tenancy chain
          if ($_ =~ /\<.*\>(.*)\</.*\>$/) {

              $sbacTenancyChain .= translateCER($1)."|";

              if ($consoleOutput == 1) { print "Building Tenancy Chain: [$sbacTenancyChain]\n"; }

          } elsif ($_ =~ /<(.*)\/>$/) {       # this is an empty element (i.e. <ClientID/>)

              $sbacTenancyChain .= "|";

              if ($consoleOutput == 1) { print "Building Tenancy Chain: [$sbacTenancyChain]\n"; }

          }
      } else {

         $errCount++;    # Keep track of how many errors we have incurred

         # Save the error and include it in a final report
         $errorEntry = "MOD:$DN:Invalid Element Found While Processing MOD in Smarter Balanced Data File: \"$_\"";
         push(@errorData, $errorEntry);

         # Process an early exit from the script
         my $errorMessage = "Invalid Element Found While Processing MOD in Smarter Balanced Data File:  $_<br><br>";
         processEarlyExit($errorMessage,$dataFileExists);

      }

  }
  $cn = $givenName." ".$sn;

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "\nDN:  $DN\n"; }

  ##############################################
  # Update the OpenDJ Server with the new user #
  ##############################################

  # Update the user in the OpenDJ server
  
  # Note:  A modify operation DOES NOT change the following attributes:  sbacUUID, inetUserStatus, userPassword, or objectClass
  #        A change to sbacUUID causes a change in the DN; therefore a moddn() operation is required
  #        A change to objectClass is uncessary as all objectclasses are already populated
  #        A change to the inetUserStatus is facililitated with the LOCK or UNLOCK operations
  #        The userPassword is set on entry creation or on password reset facilitated in the XML dump.
  #        The email/uid and sbacUUID attributes are currently the same, but this may not always be the case.  Allow the sbacUUID to be decoupled from the email/uid values if necessary (hence they are updateable).

  # determine the number of elements included in the role array (how many tenancy chains)
  $numRoleElements = @roleArray;

  if ($telephoneNumber eq "undef") {

      if ($numRoleElements == 0) {

          $mesg = $ldapHandle->modify($DN, changes => [
                  replace => [ 'sn'               => "$sn" ],
                  replace => [ 'givenName'        => "$givenName" ] ,
                  replace => [ 'cn'               => "$cn" ],
                  replace => [ 'uid'              => "$uid" ],                   
                  replace => [ 'mail'             => "$mail" ] ] );                   

      } else { 

          $mesg = $ldapHandle->modify($DN, changes => [
                  replace => [ 'sn'               => "$sn" ],
                  replace => [ 'givenName'        => "$givenName" ] ,
                  replace => [ 'cn'               => "$cn" ],
                  replace => [ 'uid'              => "$uid" ],                   
                  replace => [ 'mail'             => "$mail" ],                   
                  replace => [ 'sbacTenancyChain' => [ @roleArray ] ] ] );
      }

  } else {

      if ($numRoleElements == 0) {

          $mesg = $ldapHandle->modify($DN, changes => [
                  replace => [ 'sn'               => "$sn" ],
                  replace => [ 'givenName'        => "$givenName" ] ,
                  replace => [ 'cn'               => "$cn" ],
                  replace => [ 'uid'              => "$uid" ],                   
                  replace => [ 'mail'             => "$mail" ],                   
                  replace => [ 'telephoneNumber'  => "$telephoneNumber" ] ] );
      } else {

          $mesg = $ldapHandle->modify($DN, changes => [
                  replace => [ 'sn'               => "$sn" ],
                  replace => [ 'givenName'        => "$givenName" ] ,
                  replace => [ 'cn'               => "$cn" ],
                  replace => [ 'uid'              => "$uid" ],                   
                  replace => [ 'mail'             => "$mail" ],                   
                  replace => [ 'telephoneNumber'  => "$telephoneNumber" ],
                  replace => [ 'sbacTenancyChain' => [ @roleArray ] ] ] );
      }

  }
  
  if ($mesg->code) {

      $errCount++;    # Keep track of how many errors we have incurred

      # Send message to log file indicating error
      updateLog("WARN", "\"An error occurred while processing MOD on $DN. ".ldap_error_text($mesg->code)."\"");
      warn "\nAn error occurred while modifying entry: $DN.  See logfile for details\n";

      # Save the error and include it in a final report
      $errorEntry = "MOD:".$DN.":".ldap_error_text($mesg->code);
      push(@errorData, $errorEntry);

  } else {

      $modCount++;        # Keep track of how many modifications were made to the OpenDJ server
  }

  # initialize the role array after processing; use the undef() to free up memory
  undef(@roleArray);

return 1;

}    # end of processModAction()


##########################################################################################################
# Subroutine:  processSyncAction()                                                                       #
#                                                                                                        #
# A SYNC operation is used when the generator of the XML data file questions the integrity of the data   #
# found on the directory server.  This should only occur if the generator of the XML data believes it is #
# out of synch with the Directory Server and wants to place the directory server in a known state.       #
#                                                                                                        #
# For this to occur, the processSyncAction() subroutine will update existing users' account with the     #
# data found in the XML data file.  If the user's account does not exist, then the subroutine will       #
# create a new account consisting of the data found in the XML data file.                                #
#                                                                                                        #
# No attempt is made to detect users in the directory server that do not exist in the XML data file so   #
# this is not actually a 'true' synchronization event.                                                   #
#                                                                                                        #
# WARNING:  The SYNC operation should be used sparingly.  Processing of extremely large files is akin to #
# new data load and may take time to process.  This should not impact users with existing OpenAM sessions#
# but use of the SYNC operation will most likely be masking problems with the program responsible for    #
# generating the XML file.  This option should really be used as a last resort.                          #
##########################################################################################################

sub processSyncAction {

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "In Subroutine, processing SYNC Action\n"; }

  # define a local array that contains the values of the data passed in
  my @syncArray = @{$_[0]};

  if ($consoleOutput == 1) { print "\nSync Array:   [@syncArray]\n"; }

  # LDIF Variables
  my $sbacuuid        = "";     # Smarter Balanced UUID

  foreach (@syncArray) {

      # determine the sbacuuid attribute from the data
      if ($_ =~ /<UUID>(.*)<\/UUID>$/) {    $sbacuuid = $1;    } 

  }

  if ($consoleOutput == 1) { print "\nAttempting to Search on sbacuuid=$sbacuuid\n"; }

  # define ldap search parameters
  my $base  = $ldapBaseDN;                  # starting point of search
  my $scope = "sub";                        # how far down in the tree to search (options, "sub", "base", and "one")
  my $searchString = "sbacuuid=$sbacuuid";  # the filter to use to locate the user
  my $attrs = [ 'dn' ];                     # a comma-delimited array of attributes to return in the search

  # Search for the account in the OpenDJ server
  my $mesg = $ldapHandle->search( base => "$base", scope => "$scope", filter => "$searchString", attrs => $attrs);

  if ($mesg->code) {

      $errCount++;    # Keep track of how many errors we have incurred

      # Send message to log file indicating error
      updateLog("WARN", "\"An error occurred while processing SYNC on $sbacuuid. ".ldap_error_text($mesg->code)."\"");
      warn "\nAn error occurred while processing SYNC on $sbacuuid.  See logfile for details\n";

      # Save the error and include it in a final report
      $errorEntry = "SYNC:".$sbacuuid.":".ldap_error_text($mesg->code);
      push(@errorData, $errorEntry);

  } else {

      $syncCount++;       # Keep track of how many synchroniation operations were made to the OpenDJ server

      if ($consoleOutput == 1) { printf "\n# Entries found: %s\n", $mesg->count; }

      if ($mesg->count == 0) { 

          # Process this as an ADD Action
          processAddAction(\@syncArray);

      } elsif ($mesg->count == 1) { 

          # Process this as a MOD Action  
          processModAction(\@syncArray);

      } else {

          # There were too many entries found.  There should have been only one or no entries

          $errCount++;    # Keep track of how many errors we have incurred

          # Send message to log file indicating error
          updateLog("WARN", "\"An error occurred while processing SYNC on $sbacuuid. More than one entry found in search operation\"");
          warn "\nAn error occurred while processing SYNC on $sbacuuid.  See logfile for details\n";

          # Save the error and include it in a final report
          $errorEntry = "SYNC:$sbacuuid:More than one entry found in search operation";
          push(@errorData, $errorEntry);

      }

  }

  # initialize the array after processing; use the undef() to free up memory
  undef(@syncArray);

return 1;

}    # end of processSyncAction()


##########################################################################################################
# Subroutine:  processResetAction()                                                                      #
#                                                                                                        #
# This subroutine performs a reset of a user's password.  A password reset will generate a new random    #
# password for the user.  This generates an email for the user consisting of a link for them to connect  #
# to the OpenAM server and reset their password.                                                         #
##########################################################################################################

sub processResetAction {

  my $DN = "";     # User's Distinguished Name (constructed from $sbacuuid and constants)

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "In Subroutine, processing RESET Action\n"; }

  # define a local array that contains the values of the data passed in
  my @resetUserArray = @{$_[0]};

  if ($consoleOutput == 1) { print "\nReset User Array:   [@resetUserArray]\n"; }

 # LDIF Variables
  my $sbacuuid        = "";     # Smarter Balanced UUID
  my $DN              = "";     # User's Distinguished Name (constructed from $sbacuuid and constants)
  my $mail            = "";     # User's email address
  my $message         = "";     # Optional message to include in the password reset notification.
  my $userPassword    = "";     # User's initial password

  foreach (@resetUserArray) {

      if ($_ =~ /<UUID>(.*)<\/UUID>$/) {                     # UUID (sbacUUID)

          $DN  = "sbacUUID=$1,$ldapBaseDN";

      } elsif ($_ =~ /<Email>(.*)<\/Email>$/) {              # email address (mail)

          $mail = translateCER($1);

      } elsif ($_ =~ /<Message>(.*)<\/Message>$/) {          # optional message (message)

          $message = translateCER($1);

      } else {

          # Process an early exit from the script
          my $errorMessage = "Invalid Value ($) Found for RESET action<br><br>";
          processEarlyExit($errorMessage,$dataFileExists);

      }

  }

  #########################################
  # Reset the user from the OpenDJ Server #
  #########################################

  # generate a random password when reseting passwords for users
  $userPassword = generateRandomPassword();

  # Reset the user's password in the OpenDJ server
  $mesg = $ldapHandle->modify($DN, changes => [
          replace => [ 'userPassword'     => "$userPassword" ]] );


  if ($mesg->code) {

      $errCount++;    # Keep track of how many errors we have incurred

      # Send message to log file indicating error
      updateLog("WARN", "\"An error occurred while processing RESET on $DN. ".ldap_error_text($mesg->code)."\"");
      warn "\nAn error occurred while resetting passsword for entry: $DN.  See logfile for details\n";

      # Save the error and include it in a final report
      $errorEntry = "RESET:".$DN.":".ldap_error_text($mesg->code);
      push(@errorData, $errorEntry);

  } else {

      # notify the user that their password has been reset
      my $emailSubject = "Smarter Balanced Digital Library Account Password Reset";

      my $emailBody  = "Your Smarter Balanced password has been reset.  Your temporary password is: $userPassword<br><br>";

         # if defined, include optional message
         if ($message ne "") {

            $emailBody .= "$message<br><br>";

            if ( $extendedLogging == 1 ) { updateLog("INFO", "\"Included Message: $message)\""); }

         } 

         $emailBody .= "You are required to change your password the next time you log in.<br><br>";
         $emailBody .= "Click <a href=\"https://oam-secure.ci.opentestsystem.org/auth/UI/Login\">here</a> to access your Smarter Balanced account now.";

#     my $emailBody = "Your Smarter Balanced password has been reset.  Your temporary password is: $userPassword<br><br>You are required to change your password the next time you log in.<br><br>Click <a href=\"https://sbac.openam.airast.org/auth/UI/Login\">here</a> to access your Smarter Balanced account now.";

      if ($emailOverride == 1) {
          $mail = $emailAddrOverride;
      }
      sendEmail($emailSubject,$emailBody,$mail,$fromAddress,"User");

      # if extended logging is enabled, add additional details to log file
      if ( $extendedLogging == 1 ) { updateLog("INFO", "\"User notified of password reset ($mail)\""); }

      $resetCount++;      # Keep track of how many password resets were made to the OpenDJ server
  }

return 1;

}    # end of processResetAction()


##########################################################################################################
# Subroutine:  processPwdChangeAction()                                                                  #
#                                                                                                        #
# This subroutine modifies a user's password to a known value specified in the XML data dump.  This      #
# subroutine will NOT generate an email to the user.  It is assumed that the Help Desk Administrator has #
# already shared the password with the user while they were on the phone.                                #
##########################################################################################################

sub processPwdChangeAction {

  my $DN = "";     # User's Distinguished Name (constructed from $sbacuuid and constants)

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "In Subroutine, processing SETPWD Action\n"; }

  # define a local array that contains the values of the data passed in
  my @pwdChangeArray = @{$_[0]};

  if ($consoleOutput == 1) { print "\nPwd Change Array:   [@pwdChangeArray]\n"; }

 # LDIF Variables
  my $sbacuuid        = "";     # Smarter Balanced UUID
  my $DN              = "";     # User's Distinguished Name (constructed from $sbacuuid and constants)
  my $mail            = "";     # User's email address
  my $userPassword    = "";     # User's password

  foreach (@pwdChangeArray) {

      if ($_ =~ /<UUID>(.*)<\/UUID>$/) {                     # UUID (sbacUUID)

          $DN  = "sbacUUID=$1,$ldapBaseDN";

      } elsif ($_ =~ /<Email>(.*)<\/Email>$/) {              # email address (mail)

          $mail = translateCER($1);

      } elsif ($_ =~ /<Password>(.*)<\/Password>$/) {        # new password (userPassword)

          $userPassword = $1;

      } else {

          # Process an early exit from the script
          my $errorMessage = "Invalid Value ($) Found for SETPWD action<br><br>";
          processEarlyExit($errorMessage,$dataFileExists);

      }

  }

  ##################################################
  # Change the user's Password in th OpenDJ Server #
  ##################################################

  # Change the user's password in the OpenDJ server
  $mesg = $ldapHandle->modify($DN, changes => [
          replace => [ 'userPassword'     => "$userPassword" ]] );


  if ($mesg->code) {

      $errCount++;    # Keep track of how many errors we have incurred

      # Send message to log file indicating error
      updateLog("WARN", "\"An error occurred while processing SETPWD on $DN. ".ldap_error_text($mesg->code)."\"");
      warn "\nAn error occurred while changing the passsword for entry: $DN.  See logfile for details\n";

      # Save the error and include it in a final report
      $errorEntry = "SETPWD:".$DN.":".ldap_error_text($mesg->code);
      push(@errorData, $errorEntry);

  } else {

      # COMMENTING OUT THE SENDING OF EMAIL FOR NOW (AS PER REQTS).  LEAVING IT IN PLACE SHOULD REQTS CHANGE

      # notify the user that their password has been reset 
#     my $emailSubject = "Smarter Balanced Password Change";
#     my $emailBody = "Your Smarter Balanced password has been changed.  Your temporary password is: $userPassword<br><br>You are required to change your password the next time you log in.<br><br>Click <a href=\"https://sbac.openam.airast.org/auth/UI/Login\">here</a> to access your Smarter Balanced account now.";

#     if ($emailOverride == 1) {
#         $mail = $emailAddrOverride;
#     }
#     sendEmail($emailSubject,$emailBody,$mail,$fromAddress,"User");

#     # if extended logging is enabled, add additional details to log file
#     if ( $extendedLogging == 1 ) { updateLog("INFO", "\"User notified of password reset ($mail)\""); }

      $pwdChgCount++;      # Keep track of how many password change operations were made to the OpenDJ server
  }

return 1;

}    # end of processPwdChangeAction()

##########################################################################################################
# Subroutine:  processLockAction()                                                                       #
#                                                                                                        #
# This subroutine locks a user's account.  A lock operation essentially sets the value of the user's     #
# inetUserStatus to 'Inactive'.                                                                          #
##########################################################################################################

sub processLockAction {

  my $DN = "";     # User's Distinguished Name (constructed from $sbacuuid and constants)

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "In Subroutine, processing LOCK Action\n"; }

  # define a local array that contains the values of the data passed in
  my @lockUserArray = @{$_[0]};

  if ($consoleOutput == 1) { print "\nLock User Array:   [@lockUserArray]\n"; }

  foreach (@lockUserArray) {

      if ($_ =~ /<UUID>(.*)<\/UUID>$/) {                     # UUID (sbacUUID)
          $DN  = "sbacUUID=$1,$ldapBaseDN";
      } else {

          # Process an early exit from the script
          my $errorMessage = "Invalid Value ($) Found for LOCK action<br><br>";
          processEarlyExit($errorMessage,$dataFileExists);

      }

  }

  ######################################
  # Lock the user in the OpenDJ Server #
  ######################################

  # Lock the user's account in the OpenDJ server
  $mesg = $ldapHandle->modify($DN, replace => { "inetUserStatus" => "Inactive" } );

  # check for valid bind operation or print error if unable to update the hos
  if ($mesg->code) {

      $errCount++;    # Keep track of how many errors we have incurred

      # Send message to log file indicating error
      updateLog("WARN", "\"An error occurred while processing LOCK on $DN. ".ldap_error_text($mesg->code)."\"");
      warn "\nAn error occurred while locking entry: $DN.  See logfile for details\n";

      # Save the error and include it in a final report
      $errorEntry = "LOCK:".$DN.":".ldap_error_text($mesg->code);
      push(@errorData, $errorEntry);

  } else {

      $lockCount++;       # Keep track of how many users were locked in the OpenDJ server

  }

return 1;

}    # end of processLockAction()



##########################################################################################################
# Subroutine:  processUnlockAction()                                                                     #
#                                                                                                        #
# This subroutine unlocks a user's account.  An unlock operation essentially sets the value of the user's#
# inetUserStatus to 'Active'.                                                                            #
##########################################################################################################

sub processUnlockAction {

  my $DN = "";     # User's Distinguished Name (constructed from $sbacuuid and constants)

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "In Subroutine, processing UNLOCK Action\n"; }

  # define a local array that contains the values of the data passed in
  my @unlockUserArray = @{$_[0]};

  if ($consoleOutput == 1) { print "\nUnlock User Array:   [@unlockUserArray]\n"; }

  foreach (@unlockUserArray) {

      if ($_ =~ /<UUID>(.*)<\/UUID>$/) {                     # UUID (sbacUUID)

          $DN  = "sbacUUID=$1,$ldapBaseDN";

      } else {

          # Process an early exit from the script
          my $errorMessage = "Invalid Value ($) Found for UNLOCK action<br><br>";
          processEarlyExit($errorMessage,$dataFileExists);

      }

  }

  ########################################
  # Unlock the user in the OpenDJ Server #
  ########################################

  # Unlock the user's account in the OpenDJ server
  $mesg = $ldapHandle->modify($DN, replace => { "inetUserStatus" => "Active" } );

  # check for valid bind operation or print error if unable to update the hos
  if ($mesg->code) {

      $errCount++;    # Keep track of how many errors we have incurred

      # Send message to log file indicating error
      updateLog("WARN", "\"An error occurred while processing UNLOCK on $DN. ".ldap_error_text($mesg->code)."\"");
      warn "\nAn error occurred while unlocking entry: $DN.  See logfile for details\n";

      # Save the error and include it in a final report
      $errorEntry = "UNLOCK:".$DN.":".ldap_error_text($mesg->code);
      push(@errorData, $errorEntry);

  } else {

     $unlockCount++;     # Keep track of how many users were unlocked in the OpenDJ server

  }

return 1;

}    # end of processUnlockAction()


##########################################################################################################
# Subroutine:  processNotifyAction()                                                                     #
#                                                                                                        #
# This subroutine saves users found in the NOTIFY action onto the @emailList array.  This array will be  #
# processed in the sendEmail() subroutined and any users found will be included in the distribution.     #
##########################################################################################################

sub processNotifyAction {

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "In Subroutine, processing NOTIFY Action\n"; }

  # define a local array that contains the values of the data passed in
  my @notifyArray = @{$_[0]};

  if ($consoleOutput == 1) { print "\nNotify User Array:   [@notifyArray]\n"; }

  foreach (@notifyArray) {

      if ($_ =~ /<Email>(.*)<\/Email>$/) {                     

          my $recipient = translateCER($1);

          # add recipient to the array
          push(@emailList, $recipient);

      } else {

          # Process an early exit from the script
          my $errorMessage = "Invalid Value ($_) Found for NOTIFY action<br><br>";
          processEarlyExit($errorMessage,$dataFileExists);

      }
  }

  $notifyCount++;       # Keep track of how many notification actions were included

}


##########################################################################################################
# Subroutine:  sendEmail()                                                                               #
#                                                                                                        #
# This subroutine connects to the email server defined in the variables section of this script and sends #
# an email to a particular user based on the information passed as parameters.                           #
##########################################################################################################

sub sendEmail {

  # get parameters
  my ($emailSubject,$emailBody,$toAddress,$fromAddress,$emailType, $smtpServer, $smtpPort, $smtpUser, $smtpPassword, $useSmtpAuth) = @_;
  updateLog("DEBUG", "\nsubject=$_[0], body=$_[1], toAddress=$_[2], fromAddress=$_[3], emailType=$_[4], smtpServer=_[5], smtpPort=_[6], smtpUser=_[7], smtpPassword=_[8], useSmtpAuth=_[9]\n");

  my $email = Email::Stuffer->from($fromAddress)->to($toAddress)->subject($emailSubject)->html_body($emailBody)->email;

  my $transport = (useSmtpAuth == 1) ?
        Email::Sender::Transport::SMTPS->new({
            host => $smtpServer,
            port => $smtpPort,
            ssl => "starttls",
            sasl_username => $smtpUser,
            sasl_password => $smtpPassword
      }) :   
        Email::Sender::Transport::SMTPS->new({
            host => $smtpServer,
            port => $smtpPort
      });
    

  # Don't include additional recipients on non-admin email (the emailType will be either Admin or User)
  if ($emailType eq "Admin") {

      # add additional recipients that may have been added from the NOTIFY action
      my $emailListSize = @emailList;
      if ( $emailListSize > 0 ) {

          my $emailListRecipient;

          foreach $emailListRecipient (@emailList) { 
             $email->to( $emailListRecipient );
  
             # Send message to log file indicating that the file has been moved
             updateLog("INFO", "\"Including $emailListRecipient on the email distribution list.\"");
          }    
       }    

    }    

  sendmail($email, { transport => $transport });

  return 1;

}    # end of sendEmail()


##########################################################################################################
# Subroutine:  updateLog()                                                                               #
#                                                                                                        #
# This subroutine updates a log file with information passed in as a parameter.  Any two strings can be  #
# passed to this subroutine, but to be consistent with downstream resources, we are really only          #
# expecting the following:                                                                               #
#                                                                                                        #
# Message Type ($msgType):  INFO, WARN, ERROR                                                            #
# Message Text (#msgText):  The message being printed                                                    #
##########################################################################################################

sub updateLog {

  # get parameters
  my ($msgType, $msgText) = @_;

  # remove any carriage returns from the message text parameter
  $msgText =~ s/\n/ /g;

  # get current day/time
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  my $yyyymmdd = sprintf "%.4d%.2d%.2d", $year+1900, $mon+1, $mday;

  my $logFile  = "/opt/scripts/drc/logs/sbaclogfile-$yyyymmdd";      # log File Name

  # open log file (make sure script user has permissions to write to directory)
  open (LOGFILE, ">>$logFile") || die "\nUnable to open log file ($logFile).  $!\n\n";

  my $logMessage = sprintf "[%.2d/%.2d/%.2d:%.2d:%.2d:%.2d] %s %s",$mon+1, $mday, $year+1900, $hour, $min, $sec, $msgType, $msgText;

  print LOGFILE "$logMessage\n";

  close (LOGFILE);

return 1;

}    # end of updateLog()


##########################################################################################################
# Subroutine:  sendHTTPResponse()                                                                        #
#                                                                                                        #
# This subroutine sends an XML formatted response to the HTTP server defined in the variables section of #
# this script.  This is a response to the file processing performed by this script.                      #
##########################################################################################################

sub sendHTTPResponse {

  # define a local array that contains the values of the data passed in
  my @notificationErrorArray = @{$_[0]};

  # This subroutine places the results of the file processing on an HTTP server.
  # The response is in an XML format.

  # get the current timestamp
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  my $currentTimeStamp = sprintf "%.04d-%.02d-%.02dT%.02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec;

  # format a timestamp for when we first started the script
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($startTime);
  my $startTimeStamp = sprintf "%.04d-%.02d-%.02dT%.02d:%02d:%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec;


  # Build response message.  Place elements in individual lines for readability
  my $xmlResponse  = "<OpenamACKStatus>";
     $xmlResponse .= "<DateProcessed>$currentTimeStamp</DateProcessed>";
     $xmlResponse .= "<FileName>$ARGV[0]</FileName>";
     $xmlResponse .= "<DateStarted>$startTimeStamp</DateStarted>";

  if ( $errCount == 0 ) {
       $xmlResponse .= "<ErrorsWithUID/>";
  } else {
       $xmlResponse .= "<ErrorsWithUID>";

       # Extract the error messages from the array
       foreach (@notificationErrorArray) {
           my ($operation,$userDN,$error) = split(/:/);
           my ($userRDN,$userContainer) = split(/,/,$userDN);
           my ($rdnAttribute,$userUUID) = split(/=/,$userRDN);
           $xmlResponse .= "<UUIDError>";
           $xmlResponse .= "<UUID>$userUUID</UUID>";
           $xmlResponse .= "<Error>$error</Error>";
           $xmlResponse .= "</UUIDError>";
       }
       $xmlResponse .= "</ErrorsWithUID>";
  }

  $xmlResponse .= "<TotalRecordsProcessed>$userCount</TotalRecordsProcessed>";
  $xmlResponse .= "</OpenamACKStatus>";

  # remove any carriage returns from the message; some may have been included in the error message
  $xmlResponse =~ s/\n/ /g;

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "\nxmlResponse:  $xmlResponse\n"; }

  # Send message to log file indicating that the file has been moved
  updateLog("INFO", "\"Sending XML Response to HTTP Server.\"");

  # if extended logging is enabled, add additional details to log file
  if ( $extendedLogging == 1 ) { updateLog("INFO", "\"xmlResponse:  $xmlResponse\""); }

  # Generate the HTTP request
  my $httpRequest = HTTP::Request->new("POST", $httpResponseServer); 
  $httpRequest->header( 'Content-Type' => 'application/xml' );
  $httpRequest->content( $xmlResponse );

  # Create a new user agent and send the request
  my $userAgent = LWP::UserAgent->new;

  # Ignore certificate errors - ONLY 
  # NOTE:  It is recommended that you ONLY uncomment the next line during testing purposes
  $userAgent->ssl_opts( verify_hostname => 0 );

  # Perform the PUT request
  my $httpResponse = $userAgent->request($httpRequest);

  # the $userAgent->request() returns a hashed value that contains multiple items (header, message, return status, etc.)
  # use the code() method to get the server response code (200, 404, etc.)
  my $httpResponseCode   = $httpResponse->code();
  my $httpResponseText   = $httpResponse->status_line;

  # Send message to log file indicating that the file has been moved
  updateLog("INFO", "\"HTTP Server Answered with: $httpResponseText.\"");

  if ($httpResponseCode == "405") {
      my $httpResponseHeader = $httpResponse->header("Allow");
      updateLog("INFO", "\"Valid Methods Are: $httpResponseHeader.\"");
  }

  # initialize the error array after processing; use the undef() to free up memory
  undef(@notificationErrorArray);


return 1;

}    # end of sendHTTPResponse()


##########################################################################################################
# Subroutine:  generateRandomPassword()                                                                  #
#                                                                                                        #
# This subroutine generates a 7 character password that adheres to the following complexity rules:       #
#    *  Number of Alphabetic Characters:  5                                                              #
#    *  Number of Numeric Characters:     1                                                              #
#    *  Number of Special Characters:     1                                                              #
#                                                                                                        #
##########################################################################################################

sub generateRandomPassword {

  # define arrays of characters to choose from
  my @chars   = ("A".."Z", "a".."z");
  my @nums    = ("0".."9");
  my @special = ("%", "#", "!");

  my $string;
  $string .= $chars[rand @chars]     for 1..5;    # select 6 random alphabetic character
  $string .= $nums[rand @nums]       for 1..1;    # select 1 random numeric character
  $string .= $special[rand @special] for 1..1;    # select 1 random special character

  return $string;

}    # end of generateRandomPassword


##########################################################################################################
# Subroutine:  moveXMLFile()                                                                             #
#                                                                                                        #
# This subroutine moves the XML file from the dropbox folder and places it in the sbacXMLFiles folder.   #
##########################################################################################################

sub moveXMLFile {

  # create a timestamp specific file name
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($startTime);
  my $newFileName = sprintf "$processedFileDir/$ARGV[0]-%.04d%.02d%.02dT%.02d_%02d_%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec;

  # move the file
  move $xmlFileName, $newFileName;

  # Send message to log file indicating that the file has been moved
  updateLog("INFO", "\"$xmlFileName has been moved to $newFileName.\"");

  # print message to console (if flag enabled)
  if ($consoleOutput == 1) { print "\n$xmlFileName has been moved to $newFileName\n"; }

}    # end of moveXMLFile


##########################################################################################################
# Subroutine:  processEarlyExit()                                                                        #
#                                                                                                        #
# This subroutine processes an early termination of this script. Before it exits, however, the log file  #
# is updated and an email is sent to the administrator that is monitoring data file processing.          #
##########################################################################################################

sub processEarlyExit {

  # the errror message passed in contains HTML format; get parameter
  my ($htmlFormattedErrorMessage,$moveFile) = @_;

  # create a plain text version of the error message for the log file and console
  my $textFormattedErrorMessage = $htmlFormattedErrorMessage;
  $textFormattedErrorMessage =~ s/\<br\>/ /g;

  ########## Close Connections ##########

  # unbind and disconnect from the OpenDJ server
  $ldapHandle->unbind;
  $ldapHandle->disconnect;

  # close the XML file
  close(XMLFILE);


  ########## Move the Input File ##########

  # move the data file to the archive folder
  if ($moveFile) {
      moveXMLFile();
  }

  ########## HTTP Response ##########

  if ($sendHTTPResponse == 1) { 

      # Send notification to the HTTP Server
      # NOTE: a reference to the error array is passed, not the array, itself
      sendHTTPResponse(\@errorData);

  }

  ########## Email Response ##########

  if ($sendEmailResponse == 1) { 

      # notify the administrator of the error
      my $emailSubject = "Error Detected During Smarter Balanced Data File Processing";
      my $toAddress = $adminEmail;

      if ($emailOverride == 1) { my $toAddress = $emailAddrOverride; }

      sendEmail($emailSubject,$htmlFormattedErrorMessage,$toAddress,$fromAddress,"Admin");
  }

  ########## Update Log File ##########

  my $endTime = time;                            # capture the end time of this script
  my $processingTime = $endTime - $startTime;    # compute processing time

  # Send message to log file indicating error; all early terminations are of type ERROR
  updateLog("ERROR", "\"$textFormattedErrorMessage\"");

  # Send messages to log file indicating processing has completed
  updateLog("ERROR", "\"Smarter Balanced user processing TERMINATED.\"");
  updateLog("INFO", "\"*******************************\"");


  ########## Exit the Script ##########

  # add a newline char to the end of the die() function to suppress the line number and script name
  die ("$textFormattedErrorMessage\n");

}    # end of processEarlyExit



