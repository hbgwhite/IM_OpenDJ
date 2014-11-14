# Welcome to the OpenDJ Project #

## About
This repository contains ForgeRock OpenDJ source code and any scripts necessary to create an OpenDJ identity repository for the Smarter Balanced Assessment Consortium (SBAC) / [SmarterApp](http://smarterapp.org) system..

## License
The code is released under the [CDDL1.0 license](http://opensource.org/licenses/CDDL-1.0).

## Support
Community support for the ForgeRock OpenDJ server may be found here:  [ForgeRock - OpenDJ](http://opendj.forgerock.org).
Please direct all questions and/or comments to Bill Nelson at [bill.nelson@identityfusion.com](mailto:bill.nelson@identityfusion.com)

## Content Overview
Files in the repository include the following:

* SBAC_SSO_Design-v1.10-03282014.pdf    - SBAC SSO Design Document
* sbacInstaller 		              - SBAC OpenDJ Installation Files
*  sbacOpenDJ-Installation-12312013.pdf - Installation instructions
*  installOpenDJ.sh                     - Bash script used to perform installation of OpenDJ server
*  artifacts  			      - Artifacts used during the installation process
*    OpenDJ-2.6.0.zip                   - Pre-built version of OpenDJ 2.6.0
*    OpenDJ-customizations.zip          - OpenDJ SBAC customizations (schema, configuration, etc.)
*    scripts                            - XML Processing Scripts Folder (used during active data processing)
*      sampleData                       - Folder containing scripts/files for generating sample data
*       sbacBulkDeleteUsers.sh          - Bash script to perform mass deletion of users from the OpenDJ server
*       sbacGenerateSampleData.pl       - Perl script used to generate sample data for testing purposes 
*       districts                       - Sample districts (used by sbacGenerateSampleData.pl) 
*       first.names                     - Sample first names (used by sbacGenerateSampleData.pl) 
*       last.names                      - Sample last names (used by sbacGenerateSampleData.pl) 
*       roles                           - Sample roles (used by sbacGenerateSampleData.pl) 
*       schools                         - Sample schools (used by sbacGenerateSampleData.pl) 
*       state                           - Sample states (used by sbacGenerateSampleData.pl)s
*      sbacProcessXML.pl                - Perl script used to process XML data and load it into the OpenDJ server
*      sbacWatchXMLFolder.pl            - Perl script used to monitor the upload folder for new files.  
*      logs                             - log file(s) location; one log is generated per day
*      sbacXMLFiles                     - location of XML files once they have been processed
*  configureReplicaton.sh  	      - Bash script to configure replication between two OpenDJ servers
* source 			              - source code folder
*  2.6.0				      - OpenDJ 2.6.0 source code