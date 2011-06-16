# Implements the pageInfo class for Bio-Wet
# Reads out the various page info items (PageRank, html Errors, ...)

package pageInfo;
use Exporter;
use POSIX;
use Data::Dumper;
use strict;
# Last changed Time-stamp: <2011-05-30 12:28 hk>

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

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^Global Variables ^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#

# prefixes which occur in a href constructs
my @prefixList = (
	"http://",
	"https://",
	"mailto:"
	);

# Postfixes, namely extensions, which shouldn't be analysed
my @postfixList = (
	".gz",
	".txt",
	".pdf",
	".xls",
	".doc",
	".tar",
	".jpg",
	".png"
	);

my $maxRecursion = 10;				# macimum recursion depth for Curl recursion

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^^^^Class Methods ^^^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#

# new method
# arg1:		class
# return:	handle for object
sub new
{
    my $class = shift;
    my $this =
    {
    };
    
    bless $this, $class;
    return $this;
}


#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^^^^^^^ Methods ^^^^^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#

# get info from URI
# arg1:		class
# arg2:		domain/URI
# return:	handle for object
sub getInfo
{
	my $class = shift;
	my $domain = shift;

	my ( $URI, $content, $pr, $Yinboundlinks);
	my %data = ();
	my %site = ();
	my $ss   = \%site;    									# site reference (site summary)


	$URI = testPrefix(\$domain);							# return URI and adapt domain

	$site{domain} = $domain;
	$site{eff_uri} = $URI;
	
#	print "Domain: $domain\tURI: $URI\n";
	
	if (! testDocument($URI))
	{
#		print "Curl\t";
		$content = get_content_Curl($ss, $URI, 0);
		if (defined $content) {	parse_HTML( $ss, $content ); }
		else { $site{eff_uri} = $URI; }						# could be munched up by a trial to resolve redirection 	
#		print "Validator\t";
		check_HTML_validity( $ss, $URI );
#		print "PageRank\t";
		get_Google_PageRank( $ss, $URI );
#		print "JSON\n";
		get_bookmark_count_delicious( $ss, $domain );
	}
	return ($ss);
}


#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^^^^^ Subroutines ^^^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#

# build URI and domain
# arg1:		domain info reference, http ... is removed on exit
# return:	complete URI (http:// added if necessary)
sub testPrefix
{
	my $dmRef = $_[0];
	my $val = $$dmRef;
	
	for (my $i = 0; $i < @prefixList; $i++)					# loop through all the prefixes
	{														# and look if domain starts with one of them
		my $l = length($prefixList[$i]);
		my $s = substr($val, 0, $l);
		if ($s ne $prefixList[$i]) { next; }				# no, iterate on
		$$dmRef = substr($val, $l);							# yes, remove prefix from domain
		my @a = split(/\//, $$dmRef);						# domain is only part up to first slash
		$$dmRef = $a[0];									# that is the first element of the array
		return ($val);
	}
	return($prefixList[0].$val);
}


# Tests if postfix (extension) denotes a common document format
# arg1:		URI
# return:	'' if a document, 1 otherwise
sub testDocument
{
	my $URI = $_[0]; 
	
	foreach my $pf (@postfixList)							# loop through all the postfixes
	{														# and look if URI ends with one of them
		my $l = length($pf);
		my $s = substr($URI, -$l);
		if ($pf eq $s) { return(1); }						# document found
	}
	
	return ('');
}


# ***** get Google PageRank *****
sub get_Google_PageRank {
	my ( $ss, $d, $rank_agent, $pr );
	$ss         = shift;                            # site summary reference
	$d          = shift;                            # URI
	$rank_agent = WWW::Google::PageRank->new;
	$pr         = scalar( $rank_agent->get($d) );
	$pr         = 'n/a' unless ( defined $pr );
	${$ss}{PageRank} = $pr;
	return;
}

# ***** get bookmark count from delicious *****
sub get_bookmark_count_delicious {
	my ( $ss, $d, $count, $request_uri, $ua, $body, $json );
	$ss = shift;    # site summary reference
	$d  = shift;    # URI
	$request_uri = "http://feeds.delicious.com/v2/json/urlinfo/data?url=" . $d;
	$ua          = LWP::UserAgent->new();
	$ua->default_header( "HTTP_REFERER" => "www.bioinformatics.org" );
	$body = $ua->get($request_uri);
	if (index(lc($body->decoded_content), lc("Server Hangup")) < 0)	# prevent "malformed JSON string, neither array, object, number, string or atom, at character offset 0"
	{
		$json = from_json( $body->decoded_content );
	
		#print Dumper (  @$json[0] );
		unless ( defined @$json[0] ) {
			$count = 'n/a';
		}
		else {
			$count = @$json[0]->{'total_posts'};
		}
	}
	else
	{
		print "Server Hangup\n";
		$count = 'n/a';
	}
	${$ss}{DeliciousCount} = $count;
	return;
}

# ***** get diggs from digg.com *****
sub get_diggs {
	my ( $d, $count, $request_uri, $ua, $body, $json, $diggs );
	$d = shift;
	if ( $d =~ /^www./ ) {
		$d =~ s/^www.//g;
	}

	# print Dumper ($d);
	$request_uri =
"http://services.digg.com/1.0/endpoint?method=story.getAll&type=json&domain="
	  . $d;
	$ua = LWP::UserAgent->new();
	$ua->default_header( "HTTP_REFERER" => "www.kmu-booster.at" );
	$body = $ua->get($request_uri);
	$json = from_json( $body->decoded_content );
	print Dumper ($json);
	unless ( defined $json ) {
		$diggs = 'n/a';
	}
	else {
		$diggs = $json->{'count'};
	}
	return $diggs;
}

# ***** check for HTML validation errors *****
sub check_HTML_validity {
	my ( $ss, $d, $v, $errors );
	$ss = shift;    # site summary reference
	$d  = shift;    # URI
	
#	print "URI: $d\t";
	$v = WebService::Validator::HTML::W3C->new( detailed => 1 );
	eval
	{
		if ( $v->validate($d) ) {
			if ( $v->is_valid ) {
				$errors = 0;
			}
			else {
	
				#printf ("%s is not valid\n", $v->uri);
				#foreach my $error ( @{$v->errors} ) {
				#printf("%s at line %d\n", $error->msg,
				#     $error->line);
				#}
				# length of array -> number of errors
				$errors = scalar @{ $v->errors };
			}
		}
		else {
			printf( "Failed to validate the website: %s\n", $v->validator_error );
			$errors = "n/a";
		}
	};
	
	if($@)
	{
		print "Failed to validate the website: $d, undefined error in validator\n";
		$errors = "n/a";
	}
	
	${$ss}{HTMLerrors} = $errors;
	return;
}

# ***** evaluate HTML  *****
sub parse_HTML {
	my ( $ss, $uri, $content, $tree, $item, $decl, $hs, $cc, $ratio);
	my ( @head, $body, %meta );
	$ss      = shift;       # site summary reference
	$content = shift;		# content
	$tree    = HTML::TreeBuilder->new();
	$tree->parse($content);
	$tree->eof();

	@head = $tree->look_down( '_tag' => 'head' );
	$body = $tree->look_down( '_tag' => 'body' );

	# TODO: store @head in a DB for later reference

	# get content/markup ratio

	#$cc = $body->as_text();
	my $plain_text = HTML::FormatText->new->format(parse_html($content));
	#print "len(content): ".length($content)."\n";
	#print "len(cc): ".length($cc)."\n";
	#print "len(plain_text): ". length($plain_text)."\n";
	$ratio = (100*length ($plain_text)/length($content));
	#print "*****************ALL\n";
	#print Dumper ($content);
	#print "*****************CLEAN\n";
	#print Dumper ($plain_text);
	#print "*****************DONE\n";

	#print "RATIO: $ratio \%\n";
	${$ss}{markup_content_ratio} = $ratio;

	# parse DOCTYPE
	$decl = $$tree{_decl}{text};
	#print "DOCTYPE DECLARATION: $decl\n";
	if ($decl) {
		if ( $decl =~ m&doctype(.*?)//dtd\s+([^/]*)&i ) {
			${$ss}{doctype}{found} = 1;
			${$ss}{doctype}{data}  = $2;
		}
		else {
			${$ss}{doctype}{found} = 0;
		}
	}

	#foreach $item (@head) {
	my ( $title, $keywords, $descr, $gsv, $y_key, $alexa, @ext_css );

	#  $tree = HTML::TreeBuilder->new_from_content($item->as_HTML);
	$title = $tree->look_down( '_tag' => 'title' );
	$keywords = $tree->look_down(
		'_tag' => 'meta',
		'name' => qr//,     #only those meta tags that have a 'name' attribute
		sub { $_[0]->attr('name') =~ m/keywords/i }
	);
	$descr = $tree->look_down(
		'_tag' => 'meta',
		'name' => qr//,     #only those meta tags that have a 'name' attribute
		sub { $_[0]->attr('name') =~ m/description/i }
	);
	$gsv = $tree->look_down(
		'_tag' => 'meta',
		'name' => qr//,     #only those meta tags that have a 'name' attribute
		sub { $_[0]->attr('name') =~ m/google-site-verification/i }
	);
	$y_key = $tree->look_down(
		'_tag' => 'meta',
		'name' => qr//,     #only those meta tags that have a 'name' attribute
		sub { $_[0]->attr('name') =~ m/y_key/i }
	);
	@ext_css = $tree->look_down(
		'_tag' => 'link',
		'rel' => qr//,
		sub { $_[0]->attr('rel') =~ m/stylesheet/i }
	);

	#TODO: hier mit foreach durchgehen ...
	if ($title) {
		$meta{title}{found} = 1;
		$meta{title}{data}  = $title->as_text;
	}
	if ($keywords) {
		$meta{keywords}{found} = 1;
		$meta{keywords}{data} =
		  get_attribute_value( $keywords->as_HTML, "meta", "content" );
	}
	if ($descr) {
		$meta{description}{found} = 1;
		$meta{description}{data} =
		  get_attribute_value( $descr->as_HTML, "meta", "content" );
	}
	if ($gsv)   { $meta{gwt}{found}   = 1; }
	if ($y_key) { $meta{y_key}{found} = 1; }
	if (@ext_css) {
		$meta{ext_css}{found} = 1;
		$meta{ext_css}{data}  = scalar(@ext_css);
	}

	#}
	$tree->delete;
	${$ss}{meta} = {%meta};
}

# ***** get attribute values from tag *****
sub get_attribute_value {
	my ($html, $tag, $attr, $value, $h, $elem );
	$html  = shift;
	$tag   = shift;
	$attr  = shift;
	$h     = HTML::TagParser->new($html);
	$elem  = $h->getElementsByTagName($tag);
	if (defined $elem)
	{
		if (defined $attr) { $value = $elem->getAttribute($attr); }		
	}
	$value = 'n/a' unless ( defined $value );
	return $value;
}

# ***** fetch an arbitrary URI using Curl *****
sub get_content_Curl {
	my ($ss, $req_url,$curl,$response_body,$response_code,$retcode,$tree,$refresh, $refresh_val);
	$ss      = shift;
	$req_url = shift;
	my $rec = shift;					# recursion count
	$curl = new WWW::Curl::Easy;

	# $curl->setopt(CURLOPT_HEADER,1);
	$curl->setopt(CURLOPT_FOLLOWLOCATION,1);
	$curl->setopt(CURLOPT_URL, $req_url );

	# NOTE - do not use a typeglob here. A reference to a typeglob is okay though.
	# prohibit curl to print everything to stdout
	open (my $fileb, ">", \$response_body);
	$curl->setopt(CURLOPT_WRITEDATA,$fileb);

	$retcode = $curl->perform;

	if ( $retcode == 0 ) {
		#$response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
		#print("$response_body\n");
		#return $response_body;
	}
	else {print(  "An error happened: ". $curl->strerror($retcode). " ($retcode)\n" ); return undef; }

	# check if there is a META refesh statement
	$tree    = HTML::TreeBuilder->new();
	$tree->parse($response_body);
	$tree->eof();
	#print Dumper($tree);
	$refresh = $tree->look_down(
		'_tag' => 'meta',
		'http-equiv' => qr//,     #only those META tags that have a 'http-equiv' attribute
		sub { $_[0]->attr('http-equiv') =~ m/refresh/i }
		);
	if ($refresh) {
			$refresh_val = get_attribute_value( $refresh->as_HTML, "meta", "content" );	
#			print "Found a meta refresh tag at $req_url \n";
			# get the value of attribute 'content'
			if ($refresh_val =~ m/\s*(\d+)?\s*;?\s*[URL=]*([^"+]*)/i ){ 
				#$print " ---> $1 <----\n";
				unless ($2){
#					print "Ahh, it seems they're just reloading via META refresh, not redirecting ... using $req_url\n";
					return $response_body;
				}
				unless ($2 =~ m/^http/i ) {	$req_url = $req_url . $2; }
				else {$req_url = $2;}
#				print " ===> $req_url <===\n";
				${$ss}{eff_uri} = $req_url;
				if ($rec >= $maxRecursion)
				{ return get_content_Curl($ss, $req_url, $rec + 1); }
				else {print(  "An error happened, Curl recursion deeper than $maxRecursion\n" ); return undef; }
			}
			else {
				die ("Could not get the new request URL from meta refresh tag, exiting ...\n");
			}
	}
	else{ # no META refresh tag found
#		print "NO meta refresh tag found, continuing ...\n";
		return $response_body;
	}
}

1;
