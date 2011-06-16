# Implements the DB class for Bio-Wet

# BIO-WET is a Bioinformatics Web Service Evaluation Toolkit
# DB access for Bio-WET

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


package bioWetDB;
use Exporter;
use POSIX;
use Data::Dumper;
use strict;

# @ISA=('Exporter');
# @EXPORT=('hmmerparser');


#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^^^^ Variables ^^^^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#

my %urlData;

# control table for DB entry
# key of hash is string with object name
# val of hash is position (index+1) in argument array
my %position = (
	"UID"			=>  1,
	"PID"			=>  2,
	"eff_uri"		=>  3,
	"domain"		=>  4,
	"PageRank"		=>  5,
	"HTMLerrors"	=>  6,
	"CSSerrors"		=>  7,
	"meta.title.data"	=>  8,
	"meta.description.data"	=> 9,
	"doctype.data"	=> 10,
	"markup_content_ratio" => 11,
	"Date" 			=> 12
);

# Inversion of hash table above
my %positionInvert;

my $maxPosition = 12;			# max. number of values in table

my %timelineQuery;				# hash for values in timeline query


#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^^^^Class Methods ^^^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#

# new method
# arg1:		class
# arg2:		data base name
# arg3:		time stamp (unix format)
# return:	handle for object
sub new
{
    my $class = shift;
    my $this =
    {
        _dbName => shift,
		_date => shift,
    };
    
	my $dn = $this->{_dbName};
    my $dbh = DBI->connect("dbi:SQLite:dbname=$dn","","");
    $this->{ _dbHandle} = $dbh;
    
    ## print "dbName is $this->{_dbName}\n";
 
 	# Invert position hash. Don't know of a better place to do it
 
 	%positionInvert = reverse %position;
    
    bless $this, $class;
    return $this;
}


#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#
#^^^^^^^^^^^^^ Methods ^^^^^^^^^^^^#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^#

# Puts an entry in DB
# arg1:		class
# arg2:		entry for DB
sub enter
{
	my $this = $_[0];
	my $ssRef = $_[1];
	my $father = $_[2];

	%urlData = ();
			
	analyseHash ($ssRef, "");
	
	insertDB ($this, $father);
}


# Sets up a DB query. Returns handle for query
# arg1:		class
# arg2:		URL to be queried
# arg3:		start timestamp
# arg4:		end timestamp
# return:	Query handle
sub queryTimelineSetup
{
	my $this = $_[0];
	my $domain = $_[1];
	my $start = $_[2];
	my $end = $_[3];

	my %vars;
	my @varsRef;
	my $dbh = $this->{ _dbHandle};
	
	my $query = "SELECT * FROM bioWetDB WHERE Domain=? AND Date BETWEEN ? AND ?";
	my $sth = $dbh->prepare($query);
	$sth->execute($domain, $start, $end);
	
	# set up references for column binding
	for (my $i = 0; $i < $maxPosition; $i++)
	{
		$varsRef[$i] = \$vars{$positionInvert{$i + 1}};
	}
	
	$sth->bind_columns(undef, @varsRef);
	
	# sets up global hash to be able to get results later
	$timelineQuery{$sth} = \%vars;
	
	return $sth;
}


# fetches next DB entry. Returns hash with values
# arg1:		class
# arg2:		Query handle
# return:	Query handle
sub queryTimeline
{
	my $this = $_[0];
	my $sth = $_[1];


	if (!exists $timelineQuery{$sth})			# is Query handle still valid?
	{ return undef; }							# no, report that
	
	if ($sth->fetch())							# get DB entry
	{											# DB entry exists
		my $vars = $timelineQuery{$sth};
		my $kwd = getKeywords($this, $vars->{"UID"});
		$vars->{"Keywords"} = $kwd;
		return ($vars);
	}
	else										# no more elements
	{
		delete $timelineQuery{$sth};			# delete hash entry
		return undef;
	}
}


# analyses complex hash type, flatten hirarchy to a single string
# arg1:		pointer to hash
# arg2:		prefix for print
sub analyseHash
{
	my $hashRef = $_[0];
	my $prefix = $_[1];
		
	foreach my $key (keys(%$hashRef))
	{
		my $val = $$hashRef{$key};
		if (ref($val) eq "HASH")
		{
			## print "$prefix.$key\t=>\n";
			analyseHash ($val, $prefix . ".$key");
		}
		else
		{
			## print "$prefix.$key\t=>\t$val\n";
			my $keyCut = substr($prefix.".".$key, 1);
			$urlData{$keyCut} = $val;		
		}
	}		
}


# subroutine which inserts the variables in the DB
# arg1:		this
# arg2:		name of parent entry
sub insertDB
{
	my $this = $_[0];
	my $father = $_[1];
	
	my $dbh = $this->{ _dbHandle};
	my @tableDB;
	my $uid = undef;
	my $PID = undef;
	
	
	# initialize array with undef values
	for (my $i = 0; $i < $maxPosition; $i++)
	{ $tableDB[$i] = undef; }

	# get PID, if a parent exists
	if (defined $father)
	{
		$PID = getUID($this, $father);
		$urlData{PID} = $PID;
	}

	# scan all entries in the flattened data
	foreach my $keySS (keys(%urlData))
	{
		# look if the key exists in the control table
		if (exists $position{$keySS})
		{	# enter data into array on position defined by the position hash
			$tableDB[$position{$keySS} - 1] = $urlData{$keySS};
		} 
	}

	$tableDB[$position{Date} - 1] = $this->{ _date};			# time stamp is from an object member var

	my $sth = $dbh->prepare("INSERT INTO bioWetDB VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
	my $rv = $sth->execute(@tableDB)                or die $sth->errstr;
	
	if ($rv <= 0)
	{
		die "Insert >".$tableDB[$position{eff_uri} - 1]."< was not successful!\n";
	}
	
	# get UID of inserted entry, we need it later
	my $query = "SELECT UID FROM bioWetDB WHERE URL=? AND Date=?";
	$sth = $dbh->prepare($query);
	$sth->execute($tableDB[$position{eff_uri} - 1], $this->{ _date});
	$sth->bind_columns(undef, \$uid);

	$sth->fetch();							# should deliver only one entry, test it
	if (! defined $uid)
	{
		die "Internal error, inserted entry not found in DB!\n";
	}
	elsif (defined $PID)
	{
		enterRel($this, $PID, $uid);
	}
	
	# Now process the Keywords
	if (exists $urlData{'meta.keywords.data'})
	{
		my @kwd = split(/,/, $urlData{'meta.keywords.data'});

		$sth = $dbh->prepare("INSERT INTO bioWetKWD VALUES (?, ?, ?)");
		foreach my $kwdEntry (@kwd)
		{
			insertKeyword($this, $uid, $kwdEntry);
		}		
	}
}


# tests if son URI is already in DB. If yes, it checks if father->son
# relationship is already in the DB and enters it if not.
# arg1:		this
# arg2:		father
# arg3:		son
# return:	false '', if entry doesn't exit, 1 otherwise
sub testURIs
{
	my $this = $_[0];
	my $fatherURI = $_[1];
	my $sonURI = $_[2];
	
	my $sonUID = getUID($this, $sonURI);
	if (! defined $sonUID) { return ''; }
	
	# if both father and son UID exist, enter them in relation table
	my $fatherUID = getUID($this, $fatherURI);
	if (defined $fatherUID) { enterRel($this, $fatherUID, $sonUID); }
		
	return 1;
}


# gets UID of a specific URI
# arg1:		this
# arg2:		URI
# return:	UID of entry
sub getUID
{
	my $this = $_[0];
	my $URI = $_[1];

	my $dbh = $this->{ _dbHandle};
	my $uid;

	my $query = "SELECT UID FROM bioWetDB WHERE URL=? AND Date=?";
	my $sth = $dbh->prepare($query);
	$sth->execute($URI, $this->{ _date});
	$sth->bind_columns(undef, \$uid);

	$sth->fetch();							# should deliver only one entry, return it

	return $uid;
}


# checks if father->son relationship is already in the DB and enters it if not.
# arg1:		this
# arg2:		father UID
# arg3:		son UID
sub enterRel
{
	my $this = $_[0];
	my $fatherUID = $_[1];
	my $sonUID = $_[2];

	my $cnt;
	my $dbh = $this->{ _dbHandle};

	my $query = "SELECT COUNT(*) FROM bioWetRel WHERE Father=? AND Son=? AND Date=?";
	my $sth = $dbh->prepare($query);
	$sth->execute($fatherUID, $sonUID, $this->{ _date});
	$sth->bind_columns(undef, \$cnt);

	$sth->fetch();							# should deliver only one entry, return it

	if ($cnt < 1)							# test if entry already exists
	{
		$sth = $dbh->prepare("INSERT INTO bioWetRel VALUES (?, ?, ?)");
		my $rv = $sth->execute($fatherUID, $sonUID, $this->{ _date})                or die $sth->errstr;
	}
}


# subroutine which entres one keyword entry in DB
# arg1:		this
# arg2:		PID to which keyword belongs
# arg3:		keyword (phrase)
sub insertKeyword
{
	my $this = $_[0];
	my $PID = $_[1];
	my $kwd = $_[2];
	
	my $cnt = undef;
	my $Keyword = $kwd;

	if ($kwd =~ /^\s*(.*)/) { $Keyword = $1;	}		# remove leading whitespace in keywords
	$Keyword =~ s/\s*$//;								# remove trailing whitespace

	my $dbh = $this->{ _dbHandle};
	my $query = "SELECT COUNT(*) FROM bioWetKWD WHERE PID=? AND Keyword=?";
	my $sth = $dbh->prepare($query);
	$sth->execute($PID, $Keyword);
	$sth->bind_columns(undef, \$cnt);

	$sth->fetch();							# should deliver only one entry, return it

	if ($cnt < 1)							# test if entry already exists
	{	
		$sth = $dbh->prepare("INSERT INTO bioWetKWD VALUES (?, ?, ?)");
		$sth->execute(undef, $PID, $Keyword)                or die $sth->errstr;
	}
}


# subroutine which return keywords belonging to a PID
# arg1:		this
# arg2:		PID for keywords
# return:	reference to keyword array
sub getKeywords
{
	my $this = $_[0];
	my $PID = $_[1];

	my @kwdArray;
	my $kwd;
	
	my $dbh = $this->{ _dbHandle};
	my $query = "SELECT Keyword FROM bioWetKWD WHERE PID=?";
	my $sth = $dbh->prepare($query);
	$sth->execute($PID);
	$sth->bind_columns(undef, \$kwd);

	while($sth->fetch())							# fetch entries
	{
		push(@kwdArray, $kwd);
	}
	
	return \@kwdArray;
}


1;
