#!/usr/bin/perl
# -*-CPerl-*-
# Last changed Time-stamp: <2011-05-30 18:28:130 hk>

# BIO-WET is a Bioinformatics Web Service Evaluation Toolkit
# Test and example code for DB readout

# ***********************************************************************
# *  Copyright notice
# *
# *  Copyright 2010-2011 Hans Kraus <hans@hanswkraus.com>
# *  All rights reserved
# *
# *  This program is free software: you can redistribute it and/or modify
# *  it under the terms of the GNU General Public License as published by
# *  the Free Software Foundation, either version 3 of the License, or
# *  (at your option) any later version.
# *
# *  This program is distributed in the hope that it will be useful,
# *  but WITHOUT ANY WARRANTY; without even the implied warranty of
# *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# *  GNU General Public License for more details.
# *
# *  You should have received a copy of the GNU General Public License
# *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
# *
# *  This copyright notice MUST APPEAR in all copies of the script!
# ***********************************************************************
#
# TODOs:
# - fix bug in get_content_Curl with looping redirects, eg. cnn.com
# - check content/markup calculation routine
# - W3C validation service (HTML + CSS)
# - various Google parameters (visibility,pagespeed)
# - DMOZ
# - Wikipedia, see http://en.wikipedia.org/w/api.php
# - social bookmarking services ( Mister Wong, technorati etc)
# - Wayback engine
# - Web thumnails via Net::Amazon::Thumbnail, see also http://www.perlmonks.org/?node_id=593234
#
# - store collected information in a data structure (see below)
# - later: use Storabele and Tie::RDBM to store DS in a DB (for later reference)

use strict;

use warnings;
#use Dumpvalue;
use JSON;
use LWP::UserAgent;
use WWW::Google::PageRank;
use WWW::Curl::Easy;
use WebService::Validator::HTML::W3C;
use Data::Dumper;
use Getopt::Long;
use HTML::TreeBuilder;
use HTML::TagParser;
use HTML::Strip;
use HTML::Parse;
use HTML::FormatText;

use DBI;
use bioWetDB;
use pageInfo;
use BioWetCrawler;

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^^^^ Variables ^^^^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#

my $domain = "www.bioinformatics.org";
my $dbFile = "/mnt/e/DataBase/bioWetDB.sqlite";			#  DB file; this contains DB


#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^^^^^^^^ Main ^^^^^^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
sub main
{
	Getopt::Long::config('no_ignore_case');
	&usage() unless GetOptions(
		"v"
	);

	# get timestamp and create new DB object
	my $sysTime = time();
	my $dbObject = bioWetDB->new($dbFile, $sysTime);

	my $start = 0;								# minimum time stamp in Unix
	my $end = 2**32 - 1;						# maximum time stamp in Unix
	
	print "Domain: $domain\tStart: $start\tEnd: $end\n";
	my $sth = $dbObject->queryTimelineSetup($domain, $start, $end);

	my $vars = $dbObject->queryTimeline($sth);
	while (defined $vars)
	{
		print Dumper($vars), "\n";
		
		$vars = $dbObject->queryTimeline($sth);
	}
}


#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^^^^^ Subroutines ^^^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#


# removes last slash of a string, if there is any
# arg1:		reference to string
sub removeSlash
{
	my $sRef = shift;

	$$sRef =~ s%/$%%;
}


# replaces %.. constructs with the appropriate chars
# arg1:		reference to string
sub replacePercent
{
	my $sRef = shift;
	
	$$sRef =~ s/%2C/,/;		
	$$sRef =~ s/%2F/\//;
}


sub usage {
	print <<EOF;
*********************************************************************
**                      BIO - WET                                  **
**    Bioinformatics Web Services Evaluation Toolkit               **
**    (c) 2010-2011 Michael T. Wolfinger <m.wolfinger\@incore.at>  **
**                  Hans Kraus           <hans\@fotokraus.at>      **
*********************************************************************

Usage: $0 [options]

program specific options:                             default:
 -help                  print this information

EOF
	exit;
}


main();			# call main subroutine
