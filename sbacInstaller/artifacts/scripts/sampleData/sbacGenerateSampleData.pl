#!/usr/bin/perl

use strict;

###################################################################################################
# Educational Online Test Delivery System                                                         #
# Copyright (c) 2013 American Institutes for Research                                             #
#                                                                                                 #
# Distributed under the AIR Open Source License, Version 1.0                                      #
# See https://bitbucket.org/sbacoss/eotds/wiki/AIR_Open_Source_License                            #
#                                                                                                 #
# This script generates an XML file that can be used for testing the data load process.  It reads #
# values from the following sample data files to create the XML file:                             #
#                                                                                                 #
#     districts   - sample district names and district IDs                                        #
#     schools     - sample school names and school IDs                                            #
#     states      - sample state names and state IDs                                              #
#     first.names - sample first names                                                            #
#     last.names  - sample last names                                                             #
#                                                                                                 #
# Author: Bill Nelson (Identity Fusion, Inc.) - bill.nelson@identityfusion.com                    #
#                                                                                                 #
# Change Log:                                                                                     #   
#                                                                                                 #
#  12/19/2013 - Initial script creation.                                                          #
#                                                                                                 #
###################################################################################################

my $emailDomain   = "example.com";   # domain name to use for email addresses
my $districtsFile = "districts";     # file containing sample districts and district IDs
my $schoolsFile   = "schools";       # file containing sample schools and school IDs
my $statesFile    = "states";        # file containing sample states and state IDs
my $fnamesFile    = "first.names";   # file containing sample first names
my $lnamesFile    = "last.names";    # file containing sample last names
my $rolesFile     = "roles";         # file containing sample role names

# read districts file into an array
open(DATAFILE, $districtsFile) or die "Error!  Could not open: $districtsFile) - $!";
my @districts  = <DATAFILE>;
close (DATAFILE);

# read schools file into an array
open(DATAFILE, $schoolsFile) or die "Error!  Could not open: $schoolsFile) - $!";
my @schools  = <DATAFILE>;
close (DATAFILE);

# read schools file into an array
open(DATAFILE, $statesFile) or die "Error!  Could not open: $statesFile) - $!";
my @states  = <DATAFILE>;
close (DATAFILE);

# read first names file into an array
open(DATAFILE, $fnamesFile) or die "Error!  Could not open: $fnamesFile) - $!";
my @firstnames  = <DATAFILE>;
close (DATAFILE);

# read last names file into an array
open(DATAFILE, $lnamesFile) or die "Error!  Could not open: $lnamesFile) - $!";
my @lastnames  = <DATAFILE>;
close (DATAFILE);

# read roles file into an array
open(DATAFILE, $rolesFile) or die "Error!  Could not open: $rolesFile) - $!";
my @roles  = <DATAFILE>;
close (DATAFILE);

##########################################################################################################
#                                           Main Program                                                 #
##########################################################################################################

my $startTime = time;  # capture the start time of this script

# verify number of input parameters equals 1 (the number of sample data records to create)
my $numArgs = $#ARGV + 1;
if ($numArgs == 0) {
    die "\nMissing input file parameter.\nUsage $0 {# entries to generate}\n\n";
}

# we have at least one input parameter; construct the name of data file based on this
my $addFileName  = "add$ARGV[0]entries.testfile";   # construct name of file for additions
my $delFileName  = "del$ARGV[0]entries.testfile";   # build a corresponding file for deletions
my $ldifDelName  = "del$ARGV[0]entries.ldif";       # build a corresponding LDIF file for using the ldapdelete command

# determine if data file already exists
if (-e $addFileName) {
    # Send message to log file indicating start of file processing
    die "\nProcessing terminated!  File already exists:  $addFileName\n\n";
}

# Print messages indicating processing has completed
print "\nGenerating sample data ($ARGV[0] entries).\n\n";

# open the XML file for appending
open(my $addfile, '>>',  $addFileName) or die "Error!  Could not open XML file ($addFileName) - $!";
open(my $delfile, '>>',  $delFileName) or die "Error!  Could not open XML file ($delFileName) - $!";
open(my $ldifdel, '>>',  $ldifDelName) or die "Error!  Could not open XML file ($ldifDelName) - $!";

# add content to the file used to add new users
say $addfile "<?xml version=\"1.0\" encoding=\"ISO-8859-2\"?>";
say $addfile "<Users>";

# add content to the file used to add new users
say $delfile "<?xml version=\"1.0\" encoding=\"ISO-8859-2\"?>";
say $delfile "<Users>";


my $count = 0;
print "Processing: ";

for (my $i=0; $i <$ARGV[0]; $i++) {

   my $fname        = $firstnames[rand @firstnames];
   my $lname        = $lastnames[rand @lastnames];
   my $fullState    = $states[rand @states];
   my $fullSchool   = $schools[rand @schools];
   my $fullDistrict = $districts[rand @districts];
   my $role         = $roles[rand @roles];

   my ($state,$stateID)       = split(/-/,$fullState);
   my ($districtID,$district) = split(/-/,$fullDistrict);
   my ($schoolID,$school)     = split(/-/,$fullSchool);

   chomp($fname);
   chomp($lname);
   chomp($state);
   chomp($stateID);
   chomp($district);
   chomp($districtID);
   chomp($school);
   chomp($schoolID);
   chomp($role);

   my $email                 = "$fname\.$lname\@$emailDomain";
   my $uuid                  = "$email-".randomString();
   my $phone                 = randomPhone();
   my $level                 = randomString();      # in lieu of valid data, use random data
   my $roleID                = randomString();      # in lieu of valid data, use random data
   my $client                = randomString();      # in lieu of valid data, use random data
   my $clientID              = randomString();      # in lieu of valid data, use random data
   my $groupOfStates         = randomString();      # in lieu of valid data, use random data
   my $groupOfStatesID       = randomString();      # in lieu of valid data, use random data
   my $groupOfDistricts      = randomString();      # in lieu of valid data, use random data
   my $groupOfDistrictsID    = randomString();      # in lieu of valid data, use random data
   my $groupOfInstitutions   = randomString();      # in lieu of valid data, use random data
   my $groupOfInstitutionsID = randomString();      # in lieu of valid data, use random data

   # all user actions will be an ADD
   say $addfile "  <User Action=\"ADD\">";
   say $delfile "  <User Action=\"DEL\">";                              # content for SBAC deletion file
   say $addfile "     <UUID>$uuid</UUID>";
   say $delfile "     <UUID>$uuid</UUID>";                              # content for SBAC deletion file
   say $ldifdel "sbacuuid=$uuid,ou=people,dc=smarterbalanced,dc=org";   # content for LDIF file
   say $addfile "     <FirstName>$fname</FirstName>";
   say $addfile "     <LastName>$lname</LastName>";
   say $addfile "     <Email>$email</Email>";
   say $addfile "     <Phone>$phone</Phone>";
   say $addfile "     <Role>";
   say $addfile "       <RoleID>$roleID</RoleID>";
   say $addfile "       <Name>$role</Name>";
   say $addfile "       <Level>$level</Level>";
   say $addfile "       <ClientID>$clientID</Client>";
   say $addfile "       <Client>$client</Client>";
   say $addfile "       <GroupOfStatesID>$groupOfStatesID</GroupOfStatesID>";
   say $addfile "       <GroupOfStates>$groupOfStates</GroupOfStates>";
   say $addfile "       <StateID>$stateID</StateID>";
   say $addfile "       <State>$state</State>";
   say $addfile "       <GroupOfDistrictsID>$groupOfDistrictsID</GroupOfDistrictsID>";
   say $addfile "       <GroupOfDistricts>$groupOfDistricts</GroupOfDistricts>";
   say $addfile "       <DistrictID>$districtID<DistrictID/>";
   say $addfile "       <District>$district<District/>";
   say $addfile "       <GroupOfInstitutionsID>$groupOfInstitutionsID</GroupOfInstitutions>";
   say $addfile "       <GroupOfInstitutions>$groupOfInstitutions</GroupOfInstitutions>";
   say $addfile "       <InstitutionID>$schoolID</InstitutionID>";
   say $addfile "       <Institution>$school</Institution>";
   say $addfile "     </Role>";
   say $addfile "  </User>";
   say $delfile "  </User>";                              # content for deletion file

   # increment count; just for grins
   $count++;

   print ".";

}

say $addfile "</Users>";
say $delfile "</Users>";                                  # content for deletion file
close $addfile;
close $delfile;
close $ldifdel;

my $endTime = time;                            # capture the end time of this script
my $processingTime = $endTime - $startTime;    # compute processing time

# Print messages indicating processing has completed
print "\n\nProcessing completed. $count entries created.  Elapsed Time: $processingTime Seconds\n\n";





sub randomPhone {

  my @chars = ("0".."9");
  my $areaCode;
  my $prefix;
  my $number;

  $areaCode .= $chars[rand @chars] for 1..3;
  $prefix   .= $chars[rand @chars] for 1..3;
  $number   .= $chars[rand @chars] for 1..4;

  my $phoneNumber = "($areaCode)$prefix-$number";

  return $phoneNumber;

}    # end of randomPhone



sub randomString {

  my @chars = ("A".."Z", "a".."z", "0".."9");
  my $string;

  $string .= $chars[rand @chars] for 1..10;

  return $string;

}    # end of randomString
