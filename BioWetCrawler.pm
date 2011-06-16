#!/usr/bin/perl

################################################################################
#       BioWetCrawler.pm
#		This package crawls through webpages until maximum depth and returns
# 		an array of hashes, each contains the from-url and the to-url
#       
#       Copyright 2011 Matthias Gerstl 
#       
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#       
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#       
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#       MA 02110-1301, USA.
################################################################################

package BioWetCrawler;

# load packages
use strict;
use URI::URL;
use LWP::UserAgent;
use HTML::LinkExtor;
use WWW::RobotRules;
use LWP::Simple qw(get);


# Variables needed in subs
my @crawlerLinks;
my $rules = WWW::RobotRules->new('BioWetCrawler');

# Callback needed for LinkExtor
sub callback {
   my($tag, %attr) = @_;
   # search only for <a href...>
   return if $tag ne 'a';
   push(@crawlerLinks, values %attr);
}

# Creates correct Url
sub getCorrectUrl {
	my $url = shift;
	my $correctUrl;
	# parse url
	if ($url !~ /:\/\//){
		$url = "http://".$url;
	}
	my @urlArray = split(/\//, $url);
	# generate domain
	if ($urlArray[0] =~ /https:/){
		$correctUrl = "https://".$urlArray[2];
	} else {
		$correctUrl = "http://".$urlArray[2];
	}
	for (my $i=3; $i<=$#urlArray; ++$i){
		$correctUrl .= $urlArray[$i];
	}
	return ($correctUrl);
}

sub getDomain {
	# Variables
	my $url = shift;
	my $domain;	
	my @urlArray = split(/\//, $url);
	# generate domain
	if ($urlArray[0] =~ /https:/){
		$domain = "https://".$urlArray[2];
	} else {
		$domain = "http://".$urlArray[2];
	}
	return ($domain);
}

# Crawl through webpages
sub crawl {
	# Variables
	my $start = $_[1];
	my $maxDepth = $_[2];
	my $inDomain = $_[3];
	my $nextLink = 1;
	my $start = getCorrectUrl($start); 	# creates correct starturl if it is faulty
	my $domain = getDomain($start); # extracts domain from starturl
	my @next = ($start);			# contains start url and all found urls
	my (@allLinks, @newLinks);		# temporary arrays
	my @result;						# array of hashes, each with from-url and to-url of pages
	my ($res, $base);				# temporary variables
	my $userAgent = LWP::UserAgent->new;				# to retrieve webpages
	my $linkExtor = HTML::LinkExtor->new(\&callback);	# to extract links
		
	# Counter
	my $tempCounter;
	my $oldLinkCounter = 0;	
	my $newLinkCounter = 1;		# 1 because of start url is in @next
	my $actualDepth = 1;		# 1 because start url is depth 1
	
	# Start crawler
	while ($actualDepth <= $maxDepth){
		$tempCounter = $newLinkCounter;
		for (my $i=$oldLinkCounter; $i<$tempCounter; ++$i){
			# Check if page was crawled before
			if (!(grep /^$next[$i]$/, @allLinks)){
				# Crawler search only in domain
				if ($inDomain == 1){
					my $tempDomain = getDomain($next[$i]);
					if ($tempDomain eq $domain){
						$nextLink = 1;
					} else {
						$nextLink = 0;
					}
				}
				# Crawl next link saved in array
				if ($nextLink == 1){
					my $robots_txt = get $next[$i];
					$rules->parse($next[$i], $robots_txt) if defined $robots_txt;
					if($rules->allowed($next[$i])) {
						push (@allLinks, $next[$i]);
						# Delete existing crawler links
						@crawlerLinks = ();
						# Retrieve page and extract links
						$res = $userAgent->request(HTTP::Request->new(
							GET => $next[$i]),sub {$linkExtor->parse($_[0])});
						# Expand all link URLs to absolute ones and save it to array
						$base = $res->base;
						@newLinks = map { $_ = url($_, $base)->abs; } @crawlerLinks;
						push (@next, @newLinks);
						# Fill resultarray with links
						for (my $j=0; $j<=$#newLinks; ++$j){
							$result[$#result+1]{from} = $next[$i];
#							$result[$#result+1]{to} = $newLinks[$j];
							$result[$#result]{to} = $newLinks[$j];
							++$newLinkCounter;
						}
					}
				}
			}
		}
		++$actualDepth;
		$oldLinkCounter = $tempCounter;
	}
	return (\@result);
}

1;


#####################################################################
#	# VARIABLES
#	my $start = "www.bioinformatics.org";	# or http://www.test.org or https://www.test.org
#	my $maxDepth = 2;			
#	my $inDomain = 1	# or " "
#
#	# CRAWLING
#	my @linkHash = @{BioWetCrawler->crawl($start, $maxDepth,1)};
#
#	# OUTPUT
#	for (my $i=0; $i<=$#linkHash; ++$i){
#		print $linkHash[$i]{from}." => ".$linkHash[$i]{to}."\n";
#	}
