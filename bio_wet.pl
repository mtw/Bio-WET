#!/usr/bin/perl
# -*-CPerl-*-
# Last changed Time-stamp: <2011-05-30 18:28:130 hk>

# BIO-WET is a Bioinformatics Web Service Evaluation Toolkit
# Control routine for the various modules

# ***********************************************************************
# *  Copyright notice
# *
# *  Copyright 2010-2011 Michael T. Wolfinger <m.wolfinger@incore.at>,
# *  Hans Kraus <hans@hanswkraus.com>
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

my @allowedURI = (										# allowed URIs, all others are excluded
	"http://",
	"https://"
	);

my ( $URI, $content, $pr, $Yinboundlinks);
my $domain = "www.bioinformatics.org";
my $depth = 2;											# default value of crawler depth
my $indomain = '';										# switch for staying in domain
my $keywords = '';										# switch for keyword options
my %data = ();
my $dbFile = "/mnt/e/DataBase/bioWetDB.sqlite";			# dir where DB files should be created


#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^^^^^^^^ Main ^^^^^^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
sub main
{
	Getopt::Long::config('no_ignore_case');
	&usage() unless GetOptions(
		"site=s" => \$domain,
		"depth=i" => \$depth,
		"indomain" => \$indomain,
		"keywords" => \$keywords,
		"-help"  => \&usage,
		"v"
	);

# print "Domain: $domain\tDepth: $depth\tID: $indomain\tKW: $keywords\t\n";
# print join(' ', @ARGV), "\n";
	my $kwd = join(' ', @ARGV);
	
	# get timestamp and create new DB object
	my $sysTime = time();
	my $dbObject = bioWetDB->new($dbFile, $sysTime);
	
	# create new pageInfo object
	my $pgInfo = pageInfo->new();

#	$domain = 'http://www.bioinformatics.org/account/login.php?return=/news%2Fsubscribe.php%3Fgroup_id%3D10%26change%3D1';

	my $to = $domain;
	removeSlash(\$to);
	replacePercent(\$to);

	print "Start:\t\t$to\t";

	my $ss = $pgInfo->getInfo($to);

	# output($ss);
	# print Dumper($ss);
	
	$dbObject->enter($ss, undef);
	print "\n";
#	exit;

#####################################################################
#~ #VARIABLES
#~ my $start = "http://www.bioinformatics.org/";
#~ my $start = "http://www.bioinformatics.ca/links_directory";	# or http://www.test.org or https://www.test.org
#~ my $start = "http://localhost/~matthias/BioWetPages/subpage/subpageVier.html";
#~ my $maxDepth = 3;
#~ my $inDomain = 1;	# or " "
#~ # CRAWLING
#~ my @linkHash = @{BioWetCrawler->crawl($start, $maxDepth,$inDomain)};
#~ # OUTPUT
#~ for (my $i=0; $i<=$#linkHash; ++$i){
	#~ print $linkHash[$i]{from}." => ".$linkHash[$i]{to}."\n";
#~ }
#~ 
#~ #GET ACTUAL INFORMATION IN COMMAND LINE
#~ #kill -usr1 pid
#~ #CANCEL CRAWLING AND GET ALL CRAWLED LINKS
#~ #kill -usr2 pid

	my	@linkHash = @{BioWetCrawler->crawl($domain, $depth, $indomain)};
#	print "Domain: $domain\tLength: $#linkHash\n";
	for (my $i=0; $i<=$#linkHash; ++$i)
	{
		my $from = $linkHash[$i]{from};
		my $to = $linkHash[$i]{to};

		if (! defined $to || $to eq "")
		{ next; }

		$from = substr($from, 0);
		$to = substr($to, 0);

#		print "From:\n", Dumper($from), "\n";
#		print "To:\n", Dumper($to), "\n";

		if (! testURI($to))
		{ next; }

		removeSlash(\$from);
		removeSlash(\$to);

		replacePercent(\$from);
		replacePercent(\$to);

		print "Entry: $i\t$to\t";

		if (! $dbObject->testURIs($from, $to))
		{	
			$ss = $pgInfo->getInfo($to);
			
			# output($ss);
			# print Dumper($ss);
			
			$dbObject->enter($ss, $from);
		}
		else
		{
			print "Entry already in DB\t";
		}
		
		print "\n";
	}		
}


#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^^^^^ Subroutines ^^^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#


# removes last slash of a string, if there is any
# could lead to erros if slash is part of a parameter instead of the path
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
	
	$$sRef =~ s/%20/ /g;
	$$sRef =~ s/%2C/,/g;		
	$$sRef =~ s/%2F/\//g;
	$$sRef =~ s/%3F/?/g;
	$$sRef =~ s/%3D/=/g;
	$$sRef =~ s/%26/&/g;	
}

# test URI if it is a allowd one (to exlude mailto:, ...)
# arg1:		URI
#return:	1 for allowed URI, '' otherwise
sub testURI
{
	my $URI = shift;
	
	foreach my $u (@allowedURI)
	{
		if (index($URI, $u) == 0)
		{
			return 1;
		}
	}
	
	return '';
} 


# ***** output site summary *****
sub output {
	my $ss = shift;
	my %ss = %$ss;    					# site summary
	print "\n\n";
	print "*********************************************************\n";
	print "** WET Results for domain  " . ${ss}{domain} . "\n";
	print "*********************************************************\n";
	print "** \n";
	print "** Effective URI fetched: " . ${$ss}{eff_uri} . "\n";
	print "** \n";
	print "** ONPAGE check\n";
	print "** \n";
	print "** HTML validity errors: " . ${ss}{HTMLerrors} . "\n";
	print "** Google PageRank: " . ${ss}{PageRank} . "\n";
	print "** Delicious bookmark count: " . ${ss}{DeliciousCount} . "\n";
	print "** \n";

	if ( ${$ss}{doctype}{found} ) {
		print "** DOCTYPE: " . ${$ss}{doctype}{data} . "\n";
	}
	else { print "** DOCTYPE: n/a\n"; }
	if ( ${$ss}{meta}{title}{found} ) {
		print "** TITLE tag: " . ${$ss}{meta}{title}{data} . "\n";
	}
	if ( ${$ss}{meta}{keywords}{found} ) {
		print "** META keywords: " . ${$ss}{meta}{keywords}{data} . "\n";
	}
	else {
		print "** META keywords: n/a\n";
	}
	if ( ${$ss}{meta}{description}{found} ) {
		print "** META description: " . ${$ss}{meta}{description}{data} . "\n";
	}
	else {
		print "** META description: n/a\n";
	}
	if ( ${$ss}{meta}{gwt}{found} ) {
		print "** META Google-Site-Verification : found\n";
	}
	else {
		print "** META Google-Site-Verification : n/a\n";
	}
	if ( ${$ss}{meta}{ext_css}{found} ) {
		print "** external CSS files: " . ${$ss}{meta}{ext_css}{data} . "\n";
	}
	print "** \n";
	print "** HTML markup / content ratio: ".${$ss}{markup_content_ratio}." \% \n";
	print "*********************************************************\n";
	print "\n\n";
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
 -site         <string> specify domain                ($domain)
 -depth        <int> specify depth of crawler         ($depth)
 -indomain     switch, crawler stays in domain
 -keywords     switch, do Google keyword search
 -             delimits options, keywords start
 -help                  print this information

EOF
	exit;
}


main();			# call main subroutine
