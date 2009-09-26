#!/usr/bin/perl -w

# identation looks best with tw=4

# Several subroutines for yfklog, a amateur radio logbook software 
# 
# Copyright (C) 2005-2009  Fabian Kurz, DJ1YFK
#
# This program is free software; you can redistribute it and/or modify 
# it under the terms of the GNU General Public License as published by 
# the Free Software Foundation; either version 2 of the License, or 
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, 
# but WITHOUT ANY WARRANTY; without even the implied warranty of 
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the 
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License 
# along with this program; if not, write to the 
# Free Software Foundation, Inc., 59 Temple Place - Suite 330, 
# Boston, MA 02111-1307, USA. 

package yfksubs;

require Exporter;
@ISA = qw(Exporter);

@EXPORT = qw( wpx dxcc makewindow clearinputfields qsotofields saveqso readw
lastqsos callinfo getdate gettime splashscreen choseqso getqso chosepqso
entrymask fkeyline winfomask selectlist askbox toggleqsl onlinelog
preparelabels labeltex emptyqslqueue adifexport ftpupload adifimport getlogs
changemycall newlogtable oldlogtable choseeditqso geteditqso editw updateqso checkdate
awards statistics qslstatistics editdb editdbw savedbedit lotwimport
databaseupgrade xplanet queryrig tableexists changeconfig readsubconfig
connectdb connectrig jumpfield receive_qso);

use strict;
use POSIX;				# needed for acos in distance/direction calculation
use Curses;
use Net::FTP;
use IO::Socket;
use DBI;
use IPC::SysV qw(IPC_PRIVATE IPC_RMID IPC_NOWAIT IPC_CREAT);

my $havehamdb = eval "require Ham::Callsign::DB;";
my $hamdb;
if ($havehamdb) {
	require Ham::Callsign::DB;
	$hamdb = new Ham::Callsign::DB();
	$hamdb->initialize_dbs();
}

# We load the default values for some variables that can be changed in .yfklog

my $lidadditions="^QRP\$|^LGT\$";
my $csadditions="(^P\$)|(^M{1,2}\$)|(^AM\$)";
our $dbserver = '';								# Standard MySQL server
our $dbport = 3306;								# standard MySQL port	
our $dbuser = "";								# DB username
our $dbpass = "";								# DB password
our $dbname = "";								# DB name
my $dbh;
our $onlinedata = "`CALL`, `DATE`, round(`BAND`,2), `MODE`";
												# Fields for online search log
our $ftpserver = "127.0.0.1";					# ftp for online log / backup
my $ftpport   = "21";							# ftp server port
my $ftpuser   = "";								# ftp user
my $ftppass   = "";								# ftp passwd
my $ftpdir    = "log/";							# ftp directory
our $mycall    = "L1D";							# too stupid to set it? :-))
our $dpwr      = "100";							# default PWR
our $dqslsi    = "N";							# def. QSL-s for import
our $dqsls    = "N";							# def. QSL-s 
our $operator  = "";								# default OP.
our $lat1      = "52";							# Latitude of own station
our $lon1      = "-8";							# Longitude of own station
our $bands = '160 80 40 30 20 17 15 12 10 2';	# bands for award purposes
our $modes = 'CW SSB';							# modes for award purposes
our $screenlayout=0;								# screen layout, 0 or 1
our $rigmodel = 0;								# for hamlib
our $rigpath = '/dev/ttyS0';						# for hamlib
my $rig=0;
my $dband = '80';
my $dmode = 'CW';
our $checklogs = '';							# add. logs to chk fr prev QSOs
our $lotwdetails='0';							# LOTW import details?
our $autoqueryrig='0';							# Query rig at new QSO?
our $directory='/tmp/';							# where to look for stuff
our $prefix="/usr/local";								# may be changed by 'make'
my $db='';										# sqlite or mysql?
our $fieldorder=									# TAB/Field order.
'CALL DATE TON TOFF BAND MODE QTH NAME QSLS QSLR RSTS RSTR REM PWR';
my @fieldorder = split(/\s+/, $fieldorder);
our $usehamdb = 0;
our $askme=0;						# ask before clearing QSOs etc
our $logsort="N";								# Order of log display
our $prevsort="A";								# Order of prev. QSOs
our $browser='dillo';
our $hamlibtcpport = 4532;

# We read the configuration file .yfklog.

sub readsubconfig {

unless (-e "$ENV{HOME}/.yfklog/config") { return 0 };

open CONFIG, "$ENV{HOME}/.yfklog/config" or die "Cannot open configuration file. Error: $!";

while (defined (my $line = <CONFIG>))   {			# Read line into $line
	if ($line =~ /^lidadditions=(.+)/) {			# We read the $lidadditions
		$lidadditions = $1;
	}
	elsif ($line =~ /^csadditions=(.+)/) {			# We read the $csadditions
		$csadditions = $1;
	}
	elsif ($line =~ /^dbserver=(.+)/) {				# We read the MySQL Server
			$dbserver= $1;
	}
	elsif ($line =~ /^dbport=(.+)/) {				# We read the Server's port
			$dbport = $1;
	}
	elsif ($line =~ /^mycall=(.+)/) {				# We read the own call
			$mycall = "\L$1";
	}
	elsif ($line =~ /^dbuser=(.+)/) {				# We read the db Username
			$dbuser = $1;
	}
	elsif ($line =~ /^dbpass=(.+)/) {				# We read the db passwd
			$dbpass = $1;
	}
	elsif ($line =~ /^dbname=(.+)/) {				# We read the db name
			$dbname= $1;
	}
	elsif ($line =~ /^onlinedata=(.+)/) {			# We read the columns for
			$onlinedata= $1;						# the online logbook
	}
	elsif ($line =~ /^ftpserver=(.+)/) {			# We read the ftp server
			$ftpserver= $1;
	}
	elsif ($line =~ /^ftpport=(.+)/) {				# We read the ftp port
			$ftpport= $1;
	}
	elsif ($line =~ /^ftpuser=(.+)/) {				# We read the ftp username
			$ftpuser= $1;
	}
	elsif ($line =~ /^ftppass=(.+)/) {				# We read the ftp password
			$ftppass= $1;
	}
	elsif ($line =~ /^ftpdir=(.+)/) {				# We read the ftp directory 
			$ftpdir= $1;
	}
	elsif ($line =~ /^dpwr=(.+)/) {					# We read the default PWR
			$dpwr = $1;
	}
	elsif ($line =~ /^dqslsi=(.+)/) {				# def. QSL-sent fr QSO imp.
			$dqslsi= $1;
	}
	elsif ($line =~ /^dqsls=(.+)/) {				# def. QSL-sent
			$dqsls= $1;
	}
	elsif ($line =~ /^lat=(.+)/) {					# Own latitude
			$lat1= $1;
	}
	elsif ($line =~ /^lon=(.+)/) {					# Own longitude
			$lon1= $1;
	}
	elsif ($line =~ /^awardbands=(.+)/) {			# bands for award purposes
			$bands= $1;
	}
	elsif ($line =~ /^awardmodes=(.+)/) {			# modes for award purposes
			$modes= $1;
	}
	elsif ($line =~ /^screenlayout=(.+)/) {			# screen layout, see doc.
			$screenlayout= $1;
	}
	elsif ($line =~ /^rigmodel=(.+)/) {
			$rigmodel= $1;
	}
	elsif ($line =~ /^rigpath=(.+)/) {
			$rigpath = $1;
	}
	elsif ($line =~ /^checklogs=(.+)/) {
			$checklogs = $1;
	}
	elsif ($line =~ /^lotwdetails=(.+)/) {
			$lotwdetails = $1;
	}
	elsif ($line =~ /^operator=(.+)/) {
			$operator = $1;
	}
	elsif ($line =~ /^autoqueryrig=(.+)/) {
			$autoqueryrig= $1;
	}
	elsif ($line =~ /^directory=(.+)/) {
			$directory = $1;
	}
	elsif ($line =~ /^fieldorder=(.+)/) {
			$fieldorder= $1;
			@fieldorder = split(/\s+/, $fieldorder);
	}
	elsif ($line =~ /^askme=(.+)/) {
			$askme = $1;
	}
	elsif ($line =~ /^logsort=(.+)/) {
			$logsort= $1;
	}
	elsif ($line =~ /^prevsort=(.+)/) {
			$prevsort = $1;
	}
	elsif ($line =~ /^browser=(.+)/) {
			$browser= $1;
	}
	elsif ($line =~ /^usehamdb=(.+)/) {
			$usehamdb= $1;
	}
}
close CONFIG;	# Configuration read.

return 1;

} #readsubconfig

# Only open Database when config file was read.
if (&readsubconfig()) {
	&connectdb;
	&connectrig;
}

## We connect to the Database now...

sub connectdb {

if ($dbserver eq 'sqlite') {
	$db = 'sqlite';
	$dbh = DBI->connect("DBI:SQLite:dbname=$ENV{HOME}/.yfklog/$dbname", 
			$dbuser, $dbpass)
		or die "Could not connect to SQLite database: " . DBI->errstr;
}
else {	# MYSQL, only if defined.
	$db = 'mysql';
	$dbh = DBI->connect("DBI:mysql:$dbname;host=$dbserver",$dbuser,$dbpass)
		or die "Could not connect to MySQL database: " . DBI->errstr;
}
}


# Open Rig for Hamlib

sub connectrig {


}


# Now we read cty.dat from K1EA, or exit when it's not found.
my $ctydat = "$prefix/share/yfklog/cty.dat";
if (-R "./cty.dat") {
	$ctydat = "./cty.dat";
}

open CTY, "$ctydat" or die "$ctydat not found.".
			"Please download it from http://country-files.com/\n";

my %prefixes;			# hash of arrays  main prefix -> (all, prefixes,..)
my %dxcc;				# hash of arrays  main prefix -> (CQZ, ITUZ, ...)
my $mainprefix;

while (my $line = <CTY>) {
	if (substr($line, 0, 1) ne ' ') {			# New DXCC
		$line =~ /\s+([*A-Za-z0-9\/]+):\s+$/;
		$mainprefix = $1;
		$line =~ s/\s{2,}//g;
		@{$dxcc{$mainprefix}} = split(/:/, $line);
	}
	else {										# prefix-line
		$line =~ s/\s+//g;
		unless (defined($prefixes{$mainprefix}[0])) {
			@{$prefixes{$mainprefix}} = split(/,|;/, $line);
		}
		else {
			push(@{$prefixes{$mainprefix}}, split(/,|;/, $line));
		}
	}
}

close CTY;


###############################################################################
#
# &wpx derives the Prefix following WPX rules from a call. These can be found
# at: http://www.cq-amateur-radio.com/wpxrules.html
#  e.g. DJ1YFK/TF3  can be counted as both DJ1 or TF3, but this sub does 
# not ask for that, always TF3 (= the attached prefix) is returned. If that is 
# not want the OP wanted, it can still be modified manually.
#
###############################################################################
 
sub wpx {
  my ($call, $prefix,$a,$b,$c);
  $call = uc(shift);
  
  # First check if the call is in the proper format, A/B/C where A and C
  # are optional (prefix of guest country and P, MM, AM etc) and B is the
  # callsign. Only letters, figures and "/" is accepted, no further check if the
  # callsign "makes sense".
  # 23.Apr.06: Added another "/X" to the regex, for calls like RV0AL/0/P
  # as used by RDA-DXpeditions....
    
if ($call =~ 
	/^((\d|[A-Z])+\/)?((\d|[A-Z]){3,})(\/(\d|[A-Z])+)?(\/(\d|[A-Z])+)?$/) {
   
    # Now $1 holds A (incl /), $3 holds the callsign B and $5 has C
    # We save them to $a, $b and $c respectively to ensure they won't get 
    # lost in further Regex evaluations.
   
    ($a, $b, $c) = ($1, $3, $5);
    if ($a) { chop $a };            # Remove the / at the end 
    if ($c) { $c = substr($c,1,)};  # Remove the / at the beginning
    
    # In some cases when there is no part A but B and C, and C is longer than 2
    # letters, it happens that $a and $b get the values that $b and $c should
    # have. This often happens with liddish callsign-additions like /QRP and
    # /LGT, but also with calls like DJ1YFK/KP5. ~/.yfklog has a line called    
    # "lidadditions", which has QRP and LGT as defaults. This sorts out half of
    # the problem, but not calls like DJ1YFK/KH5. This is tested in a second
    # try: $a looks like a call (.\d[A-Z]) and $b doesn't (.\d), they are
    # swapped. This still does not properly handle calls like DJ1YFK/KH7K where
    # only the OP's experience says that it's DJ1YFK on KH7K.

if (!$c && $a && $b) {                  # $a and $b exist, no $c
        if ($b =~ /$lidadditions/) {    # check if $b is a lid-addition
            $b = $a; $a = undef;        # $a goes to $b, delete lid-add
        }
        elsif (($a =~ /\d[A-Z]+$/) && ($b =~ /\d$/)) {   # check for call in $a
        }
}    

	# *** Added later ***  The check didn't make sure that the callsign
	# contains a letter. there are letter-only callsigns like RAEM, but not
	# figure-only calls. 

	if ($b =~ /^[0-9]+$/) {			# Callsign only consists of numbers. Bad!
			return undef;			# exit, undef
	}

    # Depending on these values we have to determine the prefix.
    # Following cases are possible:
    #
    # 1.    $a and $c undef --> only callsign, subcases
    # 1.1   $b contains a number -> everything from start to number
    # 1.2   $b contains no number -> first two letters plus 0 
    # 2.    $a undef, subcases:
    # 2.1   $c is only a number -> $a with changed number
    # 2.2   $c is /P,/M,/MM,/AM -> 1. 
    # 2.3   $c is something else and will be interpreted as a Prefix
    # 3.    $a is defined, will be taken as PFX, regardless of $c 

    if ((not defined $a) && (not defined $c)) {  # Case 1
            if ($b =~ /\d/) {                    # Case 1.1, contains number
                $b =~ /(.+\d)[A-Z]*/;            # Prefix is all but the last
                $prefix = $1;                    # Letters
            }
            else {                               # Case 1.2, no number 
                $prefix = substr($b,0,2) . "0";  # first two + 0
            }
    }        
    elsif ((not defined $a) && (defined $c)) {   # Case 2, CALL/X
           if ($c =~ /^(\d)$/) {              # Case 2.1, number
                $b =~ /(.+\d)[A-Z]*/;            # regular Prefix in $1
                # Here we need to find out how many digits there are in the
                # prefix, because for example A45XR/0 is A40. If there are 2
                # numbers, the first is not deleted. If course in exotic cases
                # like N66A/7 -> N7 this brings the wrong result of N67, but I
                # think that's rather irrelevant cos such calls rarely appear
                # and if they do, it's very unlikely for them to have a number
                # attached.   You can still edit it by hand anyway..  
                if ($1 =~ /^([A-Z]\d)\d$/) {        # e.g. A45   $c = 0
                                $prefix = $1 . $c;  # ->   A40
                }
                else {                         # Otherwise cut all numbers
                $1 =~ /(.*[A-Z])\d+/;          # Prefix w/o number in $1
                $prefix = $1 . $c;}            # Add attached number    
            } 
            elsif ($c =~ /$csadditions/) {
                $b =~ /(.+\d)[A-Z]*/;       # Known attachment -> like Case 1.1
                $prefix = $1;
            }
            elsif ($c =~ /^\d\d+$/) {		# more than 2 numbers -> ignore
                $b =~ /(.+\d)[A-Z]*/;       # see above
                $prefix = $1;
			}
			else {                          # Must be a Prefix!
                    if ($c =~ /\d$/) {      # ends in number -> good prefix
                            $prefix = $c;
                    }
                    else {                  # Add Zero at the end
                            $prefix = $c . "0";
                    }
            }
    }
    elsif (defined $a) {                    # $a contains the prefix we want
            if ($a =~ /\d$/) {              # ends in number -> good prefix
                    $prefix = $a
            }
            else {                          # add zero if no number
                    $prefix = $a . "0";
            }
    }

# In very rare cases (right now I can only think of KH5K and KH7K and FRxG/T
# etc), the prefix is wrong, for example KH5K/DJ1YFK would be KH5K0. In this
# case, the superfluous part will be cropped. Since this, however, changes the
# DXCC of the prefix, this will NOT happen when invoked from with an
# extra parameter $_[1]; this will happen when invoking it from &dxcc.
    
if (($prefix =~ /(\w+\d)[A-Z]+\d/) && (not defined $_[1])) {
        $prefix = $1;                
}
    
return $prefix;
}
else { return undef; }    # no proper callsign received.
} # wpx ends here


##############################################################################
#
# &dxcc determines the DXCC country of a given callsign using the cty.dat file
# provided by K1EA at http://www.k1ea.com/cty/cty.dat .
# An example entry of the file looks like this:
#
# Portugal:                 14:  37:  EU:   38.70:     9.20:     0.0:  CT:
#     CQ,CR,CR5A,CR5EBD,CR6EDX,CR7A,CR8A,CR8BWW,CS,CS98,CT,CT98;
#
# The first line contains the name of the country, WAZ, ITU zones, continent, 
# latitude, longitude, UTC difference and main Prefix, the second line contains 
# possible Prefixes and/or whole callsigns that fit for the country, sometimes 
# followed by zones in brackets (WAZ in (), ITU in []).
#
# This sub checks the callsign against this list and the DXCC in which 
# the best match (most matching characters) appear. This is needed because for 
# example the CTY file specifies only "D" for Germany, "D4" for Cape Verde.
# Also some "unusual" callsigns which appear to be in wrong DXCCs will be 
# assigned properly this way, for example Antarctic-Callsigns.
# 
# Then the callsign (or what appears to be the part determining the DXCC if
# there is a "/" in the callsign) will be checked against the list of prefixes
# and the best matching one will be taken as DXCC.
#
# The return-value will be an array ("Country Name", "WAZ", "ITU", "Continent",
# "latitude", "longitude", "UTC difference", "DXCC").   
#
###############################################################################

sub dxcc {
	my $testcall = shift;
	my $matchchars=0;
	my $matchprefix='';
	my $test;
	my $zones = '';                 # annoying zone exceptions
	my $goodzone;
	my $letter='';


if ($testcall =~ /(^OH\/)|(\/OH[1-9]?$)/) {    # non-Aland prefix!
    $testcall = "OH";                      # make callsign OH = finland
}
elsif ($testcall =~ /(^3D2R)|(^3D2.+\/R)/) { # seems to be from Rotuma
    $testcall = "3D2RR";                 # will match with Rotuma
}
elsif ($testcall =~ /^3D2C/) {               # seems to be from Conway Reef
    $testcall = "3D2CR";                 # will match with Conway
}
elsif ($testcall =~ /\//) {                  # check if the callsign has a "/"
	my $prfx = &wpx($testcall,1);
	unless (defined($prfx)) {
		$prfx = "QQ";						# invalid
	}
    $testcall = $prfx."AA";				# use the wpx prefix instead, which may
                                         # intentionally be wrong, see &wpx!
}

$letter = substr($testcall, 0,1);

foreach $mainprefix (keys %prefixes) {

	foreach $test (@{$prefixes{$mainprefix}}) {
		my $len = length($test);

		if ($letter ne substr($test,0,1)) {			# gains 20% speed
			next;
		}

		$zones = '';

		if (($len > 5) && ((index($test, '(') > -1)			# extra zones
						|| (index($test, '[') > -1))) {
				$test =~ /^([A-Z0-9\/]+)([\[\(].+)/;
				$zones .= $2 if defined $2;
				$len = length($1);
		}

		if ((substr($testcall, 0, $len) eq substr($test,0,$len)) &&
								($matchchars <= $len))	{
			$matchchars = $len;
			$matchprefix = $mainprefix;
			$goodzone = $zones;
		}
	}
}

my @mydxcc;										# save typing work

if (defined($dxcc{$matchprefix})) {
	@mydxcc = @{$dxcc{$matchprefix}};
}
else {
	@mydxcc = qw/Unknown 0 0 0 0 0 0 ?/;
}

# Different zones?

if ($goodzone) {
	if ($goodzone =~ /\((\d+)\)/) {				# CQ-Zone in ()
		$mydxcc[1] = $1;
	}
	if ($goodzone =~ /\[(\d+)\]/) {				# ITU-Zone in []
		$mydxcc[2] = $1;
	}
}

# cty.dat has special entries for WAE countries which are not separate DXCC
# countries. Those start with a "*", for example *TA1. Those have to be changed
# to the proper DXCC. Since there are opnly a few of them, it is hardcoded in
# here.

if ($mydxcc[7] =~ /^\*/) {							# WAE country!
	if ($mydxcc[7] eq '*TA1') { $mydxcc[7] = "TA" }		# Turkey
	if ($mydxcc[7] eq '*4U1V') { $mydxcc[7] = "OE" }	# 4U1VIC is in OE..
	if ($mydxcc[7] eq '*GM/s') { $mydxcc[7] = "GM" }	# Shetlands
	if ($mydxcc[7] eq '*IG9') { $mydxcc[7] = "I" }		# African Italy
	if ($mydxcc[7] eq '*IT9') { $mydxcc[7] = "I" }		# Sicily
	if ($mydxcc[7] eq '*JW/b') { $mydxcc[7] = "JW" }	# Bear Island

}

# CTY.dat uses "/" in some DXCC names, but I prefer to remove them, for example
# VP8/s ==> VP8s etc.

$mydxcc[7] =~ s/\///g;

return @mydxcc; 

} # dxcc ends here 

###############################################################################
# &makewindow  Creates and refreshes a window with given name and color
# parameters.
# Since a newly initialized window's background color is at the
# default, not at the color specified with attron($win, COLOR_PAIR()) (or I am
# just too stupid to find out how to do it properly), this sub fills the window
# with whitespaces, so it will have the color which was specified with attron.
#
# usage: &makewindow($height, $width, $ypos, $xpos, $color pair);
###############################################################################

sub makewindow {
    my $wind = newwin($_[0], $_[1], $_[2], $_[3]);		# create window
	attron($wind, COLOR_PAIR($_[4]));					# set colors
	addstr($wind, 0,0, " " x ($_[0]*$_[1]));			# print x*y whitespaces
	move($wind, 0,0);									# cursor back to start
	return $wind;										# return window
}

###########################################################################
# clearinputfields  fills inputfields with spaces.
# $_[0] -> window array
# $_[1] -> when 1, clear windows 0..13, when 2 clear windows 0..25
# This is needed because in LOGGING mode only the first 14 windows are used
##########################################################################

sub clearinputfields {
	my @wi = @{$_[0]};  				# Input windows
	my $num;							# number of QSOs to delete..
	
	if ($_[1] == 1) { $num = 14 }
	else { $num = 26 }

	for (my $a=0;$a < $num;$a++) {		# go through all fields
		attron($wi[$a], COLOR_PAIR(5));	# input fields fg white, bg black
		addstr($wi[$a], 0,0, " " x 80);	# lots of spaces to fill the window
		move($wi[$a], 0,0);				# move cursor home
		refresh($wi[$a]);				# refresh
	}
}


###########################################################################
# qsotofields puts the content of the qso array (referenced by $qso, $_[0])
# into the input windows $wi, referenced by $_[1]
# When $_[2] is 1, it will update windows 0..13 for Logging mode
# When $_[2] is 2, it will update windows 0..17 for Edit mode
##########################################################################

sub qsotofields {
    my @qso= @{$_[0]};          # reference to QSO
    my @wi = @{$_[1]};          # reference to input-windows
	my $num;					# number of windows to paint

	if ($_[2] == 1) { $num = 14 }
	else { $num = 26 }

	for (my $a=0;$a < $num;$a++) {		# go through all fields in range
		attron($wi[$a], COLOR_PAIR(5));	# input fields fg white, bg black
		addstr($wi[$a], 0,0, $qso[$a]. " " x 80);	# put QSO value + spaces	
		move($wi[$a], 0,0);				# move cursor home
		refresh($wi[$a]);					# refresh
	}
}

##############################################################################
# &saveqso  Saves the passed array into the table log_$mycall, also adds
# DXCC, Prefix, Continent and QSL-Info fields. 
# The QSL-Info is taken from the REMarks field, if it contains "via:<sth>".
# the same applies for ITU, CQZ and IOTA, OPERATOR. Those can be entered in
# the REMarks
# field like OPERATOR:DL1LID ITU:34 CQZ:33 IOTA:EU-038  (with hyphen!).
# These parts will be cut
# out of the field if they represent a valid ITUZ, CQZ or IOTA nr. 
# The database is specified in the configfile and so are the server and the
# port of the server.
# If there is another parameter after the QSO-array, it is the number of the
# QSO which is edited. This QSO has to be changed in the database then
##############################################################################

sub saveqso {
	my $qslinfo = "";		# QSLinfo, IOTA and STATE will be read from the
	my $iota= "";			# remarks field, if available.
	my $state = "";
	my $grid= "";
	my @qso = (shift,shift,shift,shift,shift,shift,shift,shift,shift,shift,
			shift,shift,shift,shift);   # get the @qso array 
	my $editnr = shift;					# QSO we edit

	if ($editnr) {				# if existing QSO try get qslinfo
		my $n = $dbh->prepare("SELECT `QSLINFO` FROM log_$mycall
						WHERE `NR`='$editnr';");
		$n->execute();
		my @qslinfo = $n->fetchrow_array(); # local variable for info array
		$qslinfo = $qslinfo[0];
	}

	# Cute date/times, just in case.
	$qso[1] = substr($qso[1],0,8);
	$qso[2] = substr($qso[2],0,4);
	$qso[3] = substr($qso[3],0,4);

	# Now we have to check if it is a valid entry
	if ((my $pfx = &wpx($qso[0]) ) &&		# check for a callsign, return PFX
		(length($qso[1]) == 8) &&		# check if date has proper length
		(substr($qso[1],0,2) < 32) &&	# sane day (of course not in all months)
		(substr($qso[1],2,2) < 13) &&	# valid month
		(substr($qso[1],4,) > 1900) &&	# :-)
		(length($qso[2]) == 4) &&		# check length of time on
		(substr($qso[2],0,2) < 24) &&	# valid hour in Time on
		(substr($qso[2],3,2) < 60) &&	# valid minute Time on
		($qso[4] ne "") &&				# band has some info
		($qso[5] ne "") &&				# mode has some info
		($qso[8] ne "") &&				# QSL sent
		($qso[9] ne "") 				# QSL rxed
		# RST, PWR not checked, will be 599 / 0 by default in the database,
		# Time-OFF can be "", if so, it will be replaced with current time
		) {								# VALID ENTRY!  put into database

			# unless we have a valid time off ...
			unless ((length($qso[3]) == 4) &&	# check length of time off
				(substr($qso[3],0,2) < 24) &&	# valid hour in Time on
				(substr($qso[3],2,2) < 60)){ 	# valid minute Time on
				$qso[3] = &gettime;				# time off = current time
			} # Time off ready
				
			$qso[1] =					# make date in YYYY-MM-DD format
			substr($qso[1],4,)."-".substr($qso[1],2,2)."-".substr($qso[1],0,2);

			$qso[2] = substr($qso[2],0,2).":".substr($qso[2],2,2).":00";# add seconds, :
			$qso[3] = substr($qso[3],0,2).":".substr($qso[3],2,2).":00";# add seconds, :
			
			my @dxcc = &dxcc($qso[0]);		# get DXCC-array
			my $dxcc = $dxcc[7];			# dxcc prefix
			my $cont = $dxcc[3];			# dxcc continent
			my $ituz = $dxcc[2];			# dxcc itu zone
			my $cqz  = $dxcc[1];			# dxcc CQ zone

			# searching for QSL-INFO in remarks-field:
			if ($qso[12] =~ /(.*)via:(\w+)(.*)/){ # QSL info in remarks field
				$qslinfo = $2;				# save QSL-info
				$qso[12] = $1." ".$3;		# cut qsl-info from remarks field
				$qslinfo =~ tr/[a-z]/[A-Z]/; # make qsl-info uppercase
			}
			
			# searching for different ITUZ in remarks-field:
			# Note: ITU-Zone should be entered as "3" and not "03" e.g.!!
			if ($qso[12] =~ /(.*)ITUZ:(\w+)(.*)/){ 
				my ($a, $b, $c) = ($1, $2, $3);			# save regex results
				# A valid ITU Zone is 01..90
				if (($b =~ /^\d\d$/) && ($b > 0) && ($b < 91)) {	
					$ituz = $b;
					$qso[12] = $a." ".$c;
				}
			}
			
			# searching for different CQZ in remarks-field:
			if ($qso[12] =~ /(.*)CQZ:(\w+)(.*)/){ 
				my ($a, $b, $c) = ($1, $2, $3);			# save regex results
				# A valid CQ Zone is 01..40
				if (($b =~ /^\d\d$/) && ($b > 0) && ($b < 41)) {	
					$cqz = $b;
					$qso[12] = $a." ".$c;
				}
			}
			
			# searching for a STATE in remarks-field:
			if ($qso[12] =~ /(.*)STATE:(\w\w)(.*)/){ 
					$state = $2;
					$qso[12] = $1." ".$3;
			}

			# searching for a IOTA Nr in remarks-field:
			if ($qso[12] =~ /(.*)IOTA:(\w\w-\d\d\d)(.*)/){ 
				my ($a, $b, $c) = ($1, $2, $3);			# save regex results
				# A valid IOTA NR starts with a continent. Check this:
				if (substr($b,0,2) =~ /(EU|AF|AS|OC|NA|SA|AN)/) {
					$iota =$b;
					$qso[12] = $a." ".$c;
				}
			}
			
			# searching for an OPERATOR in remarks-field:
			if ($qso[12] =~ /(.*)OPERATOR:(\w+)(.*)/){ 
					$operator = $2;
					$qso[12] = $1." ".$3;
			}
			
			# searching for a GRID in remarks-field. 4 or 6 letters
			if ($qso[12] =~
				/(.*)GRID:([A-Z]{2}[0-9]{2}[A-Z]{2}|[A-Z]{2}[0-9]{2})(.*)/){ 
					$grid = $2;
					$qso[12] = $1." ".$3;
			}

			# trim remark
			$qso[12] =~ s/\s*$//;

			# we are now ready to save the QSO, but we have to check if it's a
			# new QSO or if we are changing an existing QSO.
			
			if ($editnr) {				# we change an existing QSO 
				$dbh->do("UPDATE log_$mycall SET `CALL`='$qso[0]',
						`DATE`='$qso[1]',
						`T_ON`='$qso[2]', `T_OFF`='$qso[3]', `BAND`='$qso[4]',
						`MODE`='$qso[5]', `QTH`='$qso[6]', `NAME`='$qso[7]',
						`QSLS`='$qso[8]', `QSLR`='$qso[9]', `RSTS`='$qso[10]',
						`RSTR`='$qso[11]', `REM`='$qso[12]', `PWR`='$qso[13]',
						`QSLINFO`='$qslinfo' WHERE NR='$editnr';");
			}
			else {						# new QSO
				$dbh->do("INSERT INTO log_$mycall 
					(`CALL`, `DATE`, `T_ON`, `T_OFF`, `BAND`, `MODE`, `QTH`,
					`NAME`, `QSLS`, `QSLR`, `RSTS`, `RSTR`, `REM`, `PWR`,
					`DXCC`, `PFX`, `CONT`, `QSLINFO`,
					`ITUZ`, `CQZ`, `IOTA`, `STATE`, `QSLRL`, `OPERATOR`, `GRID`)
					VALUES ('$qso[0]', '$qso[1]', '$qso[2]', '$qso[3]', 
							'$qso[4]', '$qso[5]', '$qso[6]', '$qso[7]', 
							'$qso[8]', '$qso[9]', '$qso[10]', '$qso[11]', 
							'$qso[12]', '$qso[13]', '$dxcc', '$pfx', 
							'$cont', '$qslinfo', '$ituz', '$cqz', '$iota',
							'$state', 'N', '$operator', '$grid');");
			}

		
			# voila, we have saved the QSO. Now we check if the callsign's name
			# and QTH info is already contained in the "calls"-table; if not,
			# we save it there. first we cut the callsign down to the homecall
			# only, by splitting it up at every /, then taking the longest
			# part.
			#
			my $call=$qso[0];					# will be the homecall 
			my @call = split(/\//, $call);		# split at every /
			my $length=0;						# length of splitted part
			foreach(@call) {					# chose longest part
				if (length($_) >= $length) { 
							$length = length($_);
							$call = $_;
				}
			}
	
			my $sth = $dbh->prepare("SELECT `CALL` FROM calls WHERE 
									`CALL`='$call';");
			$sth->execute();
			unless ($sth->fetch()) {	# check if callsign not in DB
				if (($qso[7] ne "") || ($qso[6] ne "")) {	# new things to add
					$dbh->do("INSERT INTO `calls` (`CALL`, `NAME`, `QTH`) VALUES
							('$call', '$qso[7]', '$qso[6]');");	
				}
			}

			# until now this only inserts, when both Name and QTH are unknown;
			# it doesn't update when only one part is unknown. needed?
			return 1;			# successfully saved
	}
	else {				# QSO invalid. Check what is wrong, make error msg
			&finderror(@qso);
			return 0;
	}		
}




		
##############################################################################
# readw  reads what the user types into a window, depending on $_[1],
# only numbers, callsign-characters, only letters or (almost) everything
# is allowed. added 0.2.1: new mode for [0-9.] added (for bands).
# $_[2] contains the windownumber, $_[3] the reference to the
# QSO-array and $_[0] the reference to the Input-window-Array.
#
# $_[4] is the reference to $wlog
#
# $_[5] either contains 0 (normal) or a QSO number. If it's a number, it means
# that we are editing an existing  QSO, meaning that we have to call &saveqso
# with the number as additional argument, so it will not save it as a new QSO.
# The variable will be called $editnr.
# 
# $_[6] means overwrite mode if nonzero.
#
# $_[7] is the maximum length of the field.
#
# The things you enter via the keyboard will be checked and if they are
# matching the criterias of $_[1], it will be printed into the window and saved
# in @qso. Editing is possible with arrow keys, delete and backspace. 
#
# If an F-Key is pressed, following things can happen: 
# 1. F2  --> Current QSO is saved into the database,
#            read last 16 QSOs from database, write them into $wlog.
#            delete @qso and the content of all inputfields.
#            return 4. When this is detected, the while-loop where the 
#            inputs are taken (while ($aw == 1)) will be exited and then entered
#            again because $aw is still 1, but then it starts at the callsign
#            field again.
# 2. F3  --> clears out the current QSO.
# 3. F5  --> Reads frequency and mode from the rig
# 3. F9  --> return 2 as next active window $aw. --> $wlog.
# 4. F10 --> returns 3 as next active window --> $wqsos
#
# If a regular entry was made, the return value is 1, because we stay in active
# window 1
##############################################################################

sub readw {
	my $ch;										# the getchar() we read
	my $win = ${$_[0]}[$_[2]];					# get window to modify
	my $input = ${$_[3]}[$_[2]];				# stores what the user entered,
												# init from @qso.
	my $match = "[a-zA-Z0-9\/]";				# default match expression
	my $pos = 0;								# cursor position in the field
	my $strpos = $pos;							# cursor position in the string
	my $wlog = ${$_[4]};						# reference to log-windw
	my $editnr = ${$_[5]};						# reference to editnr 

	my $debug=0;

	my $ovr = $_[6];						# overwrite	
	my $width = $_[7];						# width is fixed

	# The string length $strlen is used to have entries larger than the width,
	# $_[2] is inspected to set the length according to SQL field length.
	my $strlen = $width;
	if ($_[2] == 0) { $strlen = 15; }	  # Call
	elsif ($_[2] == 5) { $strlen = 6; }	  # Mode
	elsif ($_[2] == 6) { $strlen = 15; }  # QTH
	elsif ($_[2] == 7) { $strlen = 15; }  # Name
	elsif ($_[2] == 10) { $strlen = 10; } # RSTs
	elsif ($_[2] == 11) { $strlen = 10; } # RSTr
	elsif ($_[2] == 12) { $strlen = 60; } # Remarks
	elsif ($_[2] == 13) { $strlen = 10; } # PWR
	
	move($win,0,0);							# move cursor to first position
	addstr($win,0,0, $input." "x80);		# pass $input to window,
	refresh($win);

	# For the date, time and band only figures are allowed, 
	# to achieve this, invoke readw with $_[1] = 1
	if ((defined $_[1]) && ($_[1] == "1")) {	# only numbers
		$match = '\d';							# set match expression
	}

	# For the QSL-status only letters are allowed, 
	# to achieve this, invoke readw with $_[1] = 2
	if ((defined $_[1]) && ($_[1] == "2")) {	# only letters
		$match = '[a-zA-Z]';					# set match expression
	}
	
	# For the Name, QTH and Remarks letters, figures and punctuation is allowed 
	# to achieve this, invoke readw with $_[1] = 3
	if ((defined $_[1]) && ($_[1] == "3")) {	 
		$match = '[\w\d!"$%&/()=?.,;:\-@ ]';		# set match expression
	}
	
	#  In the BAND-field, numbers and a decimal point are allowed.
	if ((defined $_[1]) && ($_[1] == "4")) {	 
		$match = '[0-9.]';							# set match expression
	}

	# Now the main loop starts which is waiting for any input from the keyboard
	# which is stored in $ch. If it is a valid character that matches $match,
	# it will be added to the string $input at the proper place.
	#
	# If an arrow key LEFT or RIGHT is entered, the position within the string
	# $input will be changed, considering that it can only be within
	# 0..length($input-1). The position is stored in $pos.
	# 
	# If a control character like a F-Key, Enter or Tab is found, the sub
	# exists and $input is written to @qso, with attached information on which
	# key was pressed, as ||F1 .. ||F10. This way we can switch to the proper
	# window when we get back into the main loop.

	while (1) {								   	# loop infinitely

		$pos-- if ($pos == $width);				# keep cursor in field
		$strpos-- if ($strpos == $strlen);		# stop if string filled

		# If the cursor positions in the field and the string are not the same
		# then give only a partial view of the string.
		if ($strpos > $pos) {
			if (length($input) < $width) {
				$pos = $strpos;					# perfect, it fits again
			}
			addstr($win,0,0, substr($input, $strpos-$pos, )." "x80);
		}
		else {
			addstr($win,0,0, $input." "x80);	# pass $input to window,
		}										# delete all after $input.

		move ($win,0,$pos);						# move cursor to $pos
		refresh($win);							# show new window
		
		$ch = &getch2();

		# We first check if it is a legal character of the specified $match,
		# and if the string will not be too long.
		# if so, it will be added to the string (at the proper position!) 
		if (($ch =~ /^$match$/) && 
			((length($input) < $strlen) || ($strpos < $strlen && $ovr)) 
		) {

			unless ($_[1] == 3) {					# Unless Name, QTH, Remarks
				$ch =~ tr/[a-z]/[A-Z]/;				# make letters uppercase
			}
			# The new character will be added to $input at the right place.
			$strpos++;
			$pos++;

			if ($ovr) {
				$input = substr($input, 0, $strpos-1).$ch.substr($input,
						$strpos > length($input) ? $strpos-1 : $strpos, );
			}
			else {
				$input = substr($input, 0, $strpos-1).$ch.substr($input,
						$strpos-1, );
			}
		} 
		
		# The l/r arrow keys change the position of the cursor to left or right
		# but only within the boundaries of $input.
		
		elsif ($ch eq KEY_LEFT) {
			if ($pos > 0) { $pos-- }
			if ($strpos > 0) { $strpos-- }
		}
		
		elsif ($ch eq KEY_RIGHT) {
			if (($pos < length($input)) && ($pos < $width)) { $pos++ }
			if ($strpos < length($input)) {	$strpos++ }
		}

		elsif ($ch eq KEY_HOME) { # Pos1 key
			$pos = 0;
			$strpos = 0;
		}

		elsif ($ch eq KEY_END) { # End key
			$strpos = length($input);
			if ($strpos >= $strlen) {$strpos = $strlen-1;}
			$pos = $strpos;
			if ($pos >= $width) {$pos = $width-1;}
		}

		elsif (($ch eq KEY_DC) && ($strpos < length($input))) {	# Delete key
			$input = substr($input, 0, $strpos).substr($input, $strpos+1, );
		}
		
		# BACKSPACE. When pressing backspace, the character left of the cursor
		# is deleted, if it exists. For some reason, KEY_BACKSPACE only is true
		# when pressing CTL+H on my system (and all the others I tested); the
		# other tests lead to success, although it's probably less portable.
		# Found this solution in qe.pl by Wilbert Knol, ZL2BSJ. 

		elsif ((($ch eq KEY_BACKSPACE) || (ord($ch)==8) || (ord($ch)==0x7F)) 
				&& ($strpos > 0)) {
				$input = substr($input, 0, $strpos-1).substr($input, $strpos, );
				$strpos--;
				if ($pos > 0) { $pos--; }
		}

		# Space, Tab, keydown and Enter are the keys to go to the next field,
		# except in mode $_[1], where it was already caught in the first
		# pattern match.  If space, tab or newline is found, the sub puts
		# $input into the proper place in the @qso array: ${$_[3]}[$_[2]];
		elsif (($ch =~ /^[ \t\n]$/) || $ch eq KEY_DOWN) {
			${$_[3]}[$_[2]] = $input;				# save to @qso;
			return 1;
		}
		# Arrow-up or Shift-Tab gues to the previous QSO field. Everything
		# else same as above 
		elsif (($ch eq KEY_UP) || ($ch eq '353')) {	# Cursor up or Shift-Tab
			${$_[3]}[$_[2]] = $input;				# save to @qso;
			return 7;								# 6 -> one field back
		}
		
		# If the pressed key was F2, we will save; that is, when the qso array
		# has sufficient information for a good QSO. Then the qso-array 
		# and the input fields are deleted.
		elsif  ($ch eq KEY_F(2)) {					# pressed F2 -> SAVE
			${$_[3]}[$_[2]] = $input;				# save field to @qso
			if (&saveqso(@{$_[3]},$editnr)) {		# save @QSO to DB
				&clearinputfields($_[0],1);			# clear input fields 0..13
				@{$_[3]} = ("","","","","","","","","","","","","","");
				# Now we actualize the display of the last QSOs in the
				# window $wlog.   
				&lastqsos(\$wlog);
				${$_[5]} = 0;					# we finished editing, if we
												# did at all. $editnr = 0
				return 4;						# success, leave readw, new Q
			}	# if no success, we continue in the loop.
		}

		# exit to the MAIN MENU
		elsif ($ch eq KEY_F(1)) {		
			my $k = 'y';

			if ($askme && ${$_[3]}[0] ne '') {
				$k = &askconfirmation("Really go back to the menu? [y/N]", 
					'y|n|\n|\s');
			}

			return 5 if ($k =~ /y/i);			# active window = 5 -> MENU
		}

		# F3 cancels the current QSO and returns to the CALL input field.
		# if $editnr is set (= we edit a QSO), it's set back to 0
		# ask for confirmation if set in config file
		elsif ($ch eq KEY_F(3)) {			# F3 pressed -> clear QSO
			my $k='y';

			if ($askme) {
				$k = &askconfirmation("Really go clear this QSO? [y/N]", 
					'y|n|\n|\s');
			}

			if ($k =~ /y/i) {
				for (0 .. 13) {					# iterate through windows 0-13
					addstr(@{$_[0]}[$_],0,0," "x80);	# clear it
					refresh(@{$_[0]}[$_]);
				}
				foreach (@{$_[3]}) {			# iterate through QSO-array
					$_="";						# clear content
				}
				${$_[5]} = 0;					# editqso = 0
				return 4;						# return 4 -> to window 0 (call)
			}
		
		}

		# F5 -> get frequency and mode from the transceiver
		elsif ($ch eq KEY_F(5)) {			# F5 pressed -> freq/mode from rig

			my ($freq, $mode) = ('80', 'CW');
			if (&queryrig(\$freq, \$mode)) {
		  		${$_[3]}[4] = $freq;
	  			${$_[3]}[5] = $mode;

				addstr(@{$_[0]}[4],0,0,$freq."    ");
				addstr(@{$_[0]}[5],0,0,$mode."    ");
				refresh(@{$_[0]}[4]);
				refresh(@{$_[0]}[5]);
			}
			
			return 4;						# return 4 because we want back to
		}

		# F6 -> open browser with qrz.com info on callsign
		elsif ($ch eq KEY_F(6)) {
			my $lookup = ${$_[3]}[0];
			unless ($lookup) { $lookup = $input };
			system("$browser http://www.qrz.com/callsign\?callsign=$lookup &> /dev/null &");
		}

		# F7 -> go to remote mode for fldigi
		elsif ($ch eq KEY_F(7)) {		
			return 6;						
		}

		# go to log-window $wlog  ($aw = 2)
		elsif ($ch eq KEY_F(9)) {		
			return 2;						
		}

		# go to prev-QSO-window $wqsos  ($aw = 3)
		elsif ($ch eq KEY_F(10)) {		
			return 3;						
		}
		# QUIT YFKlog
		elsif ($ch eq KEY_F(12)) {			# QUIT
			my $k='y';

			if ($askme && ${$_[3]}[0] ne '') {
				$k = &askconfirmation("Really quit YFKlog? [y/N]", 
					'y|n|\n|\s');
			}

			if ($k =~ /y/i) {
				endwin;						# Leave curses mode	
				exit;
			}
		}
	}
}

##############################################################################
# &lastqsos   Prints the last 16 QSOs into the $wlog window. depending on $_[1],
# 16 or 8 QSOs are displayed, with different layout.
##############################################################################

sub lastqsos {
	my $wlog = ${$_[0]};			# reference to $wlog window
	my $nr;							# nr of QSOs to display
	my $y;							# y-position in window
	my $by = " `NR` DESC ";

	if ($logsort eq 'C') {
		$by = " `DATE` DESC, `T_ON` DESC ";
	}
	
	if ($screenlayout == 0) {		# original screen layout, 16 QSOs, small
		$nr = 16;
		$y=15;					# y-position in $wlog
	}
	elsif ($screenlayout == 1) {	# windows above each other, 8 QSOs
		$nr = 8;
		$y=7;					# y-position in $wlog
	}
	
	# Now we fetch the last x QSOs in the database, only CALL, BAND, MODE and
	# date needed.
	my $l = $dbh->prepare("SELECT `CALL`, `BAND`, `MODE`, `DATE`, `T_ON`,
			`NAME`, `QTH`, `RSTS`, `RSTR`, `QSLS`, `QSLR`, `QSLRL` FROM
			log_$mycall
			ORDER BY $by LIMIT $nr");	
	$l->execute();
	# temporary vars
	my ($call, $band, $mode, $date, $time, $name, $qth, $rsts,
			$rstr,$qsls,$qslr, $qslrl);	
	$l->bind_columns(\$call, \$band, \$mode, \$date,\$time, \$name,\$qth,
						\$rsts,\$rstr,\$qsls,\$qslr, \$qslrl);
	while ($l->fetch()) {						# while row available
		# we put the date into DD-MM-YY format from YYYY-MM-DD
		$date = substr($date,8,2).substr($date,4,4).substr($date,2,2); 
		# cut Call, Name, QTH, RSTR, RSTS, mode, if needed
		$call = substr($call,0,12);
		$name = substr($name,0,8);
		$qth = substr($qth,0,13);
		$rstr = substr($rstr,0,3);
		$rsts = substr($rsts,0,3);
		$mode = substr($mode,0,5);

		if ($screenlayout == 0) {
			addstr($wlog,$y,0, sprintf("%-12s%-4s %-5s%-6s",
					   	$call,$band,$mode,$date));	
		}
		elsif ($screenlayout == 1) {
				substr($time,-3,)='';			# remove seconds
			addstr($wlog,$y,0, 
			sprintf("%-12s%-4s %-5s%-4s  %-6s  %-8s  %-13s  %-3s %-3s  %s %s %s  ",
					   	$call,$band,$mode,$time,$date,$name,$qth,$rsts,$rstr,
						$qsls, $qslr, $qslrl));	
		}
		$y--;									# move one row up
	}
	# If there were less than 16 QSOs in the log, the remaining lines have to
	# be filled with spaces 
	if ($y > 0) {
		for $y (0 .. $y) {
			addstr($wlog,$y,0, " "x30) if ($screenlayout == 0);
			addstr($wlog,$y,0, " "x80) if ($screenlayout == 1);
		}
	}
	
	refresh($wlog);
}


##############################################################################
# &callinfo   When a new callsign is entered in the input form, this sub is
# called and it prints
# 1) The Name and QTH (from a separate database table), if available. 
# 2) The DXCC info, prefix, distance and beam heading. Info if new DXCC. 
# 3) The (max.) 16 last QSOs into the $wqsos-window.
# 4) Club info (HSC, etc)
# 5) IF $autoqueryrig = 1, get frequency / band from radio
##############################################################################

sub callinfo {
	my $call = ${$_[0]}[0];		# callsign to analyse
	my $band = ${$_[0]}[4];		# band of the current QSO
	my $dxwin = $_[1];			# window where to print DXCC/Pfx 
	my @wi = @{$_[2]};			# reference to input-windows
	my $wqsos = $_[3];			# qso-b4-window
	my $editnr = $_[4];			# if we edit a QSO, we don't query the RIG
	my $prefix = &wpx($call);	# determine the Prefix
	my $PI=3.14159265;			# PI for the distance and bearing
	my $RE=6371;				# Earth radius
	my $z =180/$PI;				# Just to reduce typing in formular dist/dir
	my $foundlog = 0;

	my $ascdesc = ' ASC ';

	if ($prevsort eq 'D') {
		$ascdesc = ' DESC ';
	}

	if  (defined $prefix) {	# &wpx returns undef when callsign is invalid
		# Now we print all the fields to their appropriate locations, with
		# added whitespaces behind it so any previous entries will be
		# overwritten.  
		my @dxcc = &dxcc($call);	# dxcc array gets filled
		addstr($dxwin, 0,9, $dxcc[0]." " x (25-length($dxcc[0])));
		addstr($dxwin, 0,40, $dxcc[7]." " x (5-length($dxcc[7])));
		addstr($dxwin, 0,51, $prefix." " x (5-length($prefix)));
		addstr($dxwin, 0,61, $dxcc[2]." " x (2-length($dxcc[2])));
		addstr($dxwin, 0,69, $dxcc[1]." " x (2-length($dxcc[1])));
		addstr($dxwin, 1,5, $dxcc[4]." " x (7-length($dxcc[4])));
		addstr($dxwin, 1,19, $dxcc[5]." " x (7-length($dxcc[5])));

		my $lat2 = $dxcc[4];			# to save typing work :-)
		my $lon2 = $dxcc[5];
		
		# g is the "distance angle", 0 .. pi
		my $g = acos(sin($lat1/$z)*sin($lat2/$z)+cos($lat1/$z)*cos($lat2/$z)*
													cos(($lon2-$lon1)/$z));
		# The distance is $g * $RE
		my $dist = $g * $RE;

		# Direction
		my $dir = 0;

		unless ($dist == 0) {
			$dir = acos((sin($lat2/$z)-sin($lat1/$z)*cos($g))/
								(cos($lat1/$z)*sin($g)))*360/(2*$PI);
		}

		# Shortpath
		if (sin(($lon2-$lon1)/$z) < 0) { $dir = 360 - $dir;}
		$dir = 360 - $dir; 
		
		addstr($dxwin, 1,38, sprintf("%-6d",$dist));
		addstr($dxwin, 1,58, sprintf("%3d",$dir));
		
		# now we have to get the home-call to get the name, previous QSOs any
		# maybe (TBD) award data from the station. We split the callsign at
		# every / (if any), and then take the longest part as homecall. of
		# course such exotic calls as KH5K/K1A would get the wrong result but I
		# do not care :)
			
		my @call = split(/\//, $call);
		my $length=0;						# length of splitted part
		foreach(@call) {					# chose longest part
			if (length($_) >= $length) { 
						$length = length($_);
						$call = $_;
			}
		}
	
		# We fetch the name and the qth (if available) from the database.

		my $nq = $dbh->prepare("SELECT NAME, QTH from calls WHERE
				`CALL`='$call'");
		$nq->execute();
		my ($name, $qth);								# temporary vars
		$nq->bind_columns(\$name, \$qth);		# bind references
		if ($nq->fetch()) {								# if name available
			unless (${$_[0]}[7] ne '') {				# and no name in $qso
				${$_[0]}[7] = $name;					# save to @qso
				addstr($wi[7],0,0,"$name");				# put into window
			}
			unless (${$_[0]}[6] ne '') {				# and no QTH in $qso
				${$_[0]}[6] = $qth;						# save to @qso
				addstr($wi[6],0,0,"$qth");				# put into window
			}
			refresh($wi[6]);
			refresh($wi[7]);
			$foundlog = 1;
		}
		
		
		# Now the previous QSOs with the station will be displayed. A database
		# query is made for: CALL (because it might have been something
		# different than the homecall, like PA/DJ1YFK/p, DATE, time, band,
		# mode, QSL sent and QSL-rx. 
		# (TBD maybe it would be worth thinking about adding an additional
		# column for the own call and then specify a list of logs to search in
		# the config file)
	
		# Select all QSOs where the base-callsign is $call (which is the base
		# call of the current QSO)
		
		my $nbr;							# different layouts
		if ($screenlayout == 0) {$nbr=16;}
		if ($screenlayout == 1) {$nbr=8;}

		# First count...
		my $lqcount = $dbh->prepare("SELECT count(*) FROM log_$mycall WHERE
				`CALL` = '$call' OR `CALL` LIKE '\%/$call' OR
				`CALL` LIKE '\%/$call/\%' OR `CALL` LIKE '$call/\%';");
		$lqcount->execute();

		my $count = $lqcount->fetchrow_array();

		my $lq = $dbh->prepare("SELECT `CALL`, `DATE`, `T_ON`, `BAND`, `MODE`,
				`QSLS`, `QSLR`, `NAME`, `QTH`, `RSTS`, `RSTR`, `QSLRL` from
				log_$mycall
				WHERE 	`CALL` = '$call' OR
						`CALL` LIKE '\%/$call' OR
						`CALL` LIKE '\%/$call/\%' OR
						`CALL` LIKE '$call/\%'
				ORDER BY `DATE` $ascdesc, `T_ON` $ascdesc;");
		$lq->execute();	
		my ($lcall, $ldate, $ltime, $lband, $lmode, $lqsls, $lqslr, $lname,
				$lqth, $lrsts, $lrstr, $lqslrl); 
		$lq->bind_columns(\$lcall, \$ldate, \$ltime, \$lband, \$lmode, \$lqsls,
			   	\$lqslr, \$lname, \$lqth, \$lrsts, \$lrstr, \$lqslrl);
		my $y = 0;
		while ($lq->fetch()) {				# more QSOs available
			$ltime = substr($ltime, 0,5);	# cut seconds from time
			$ldate = substr($ldate,8,2).substr($ldate,4,4).substr($ldate,2,2); 
			# cut Call, Name, QTH, RSTR, RSTS, Mode
			$lcall = substr($lcall,0,12);
			$lname = substr($lname,0,8);
			$lqth = substr($lqth,0,13);
			$lrstr = substr($lrstr,0,3);
			$lrsts = substr($lrsts,0,3);
			$lmode = substr($lmode,0,5);
			
			my $line;
			if ($screenlayout == 0) {		
				$line = sprintf("%-14s %-8s %-5s %4s %-4s %1s %1s %1s ", 
				$lcall, $ldate, $ltime, $lband, $lmode, $lqsls, $lqslr,$lqslrl);
			}
			elsif ($screenlayout ==1) {
				$line =	sprintf("%-12s%-4s %-5s%-4s  %-6s  %-8s  %-13s  %-3s %-3s  %s %s %s ",
					   	$lcall,$lband,$lmode,$ltime,$ldate,$lname,$lqth,$lrsts,
						$lrstr, $lqsls, $lqslr, $lqslrl);
			}	

			addstr($wqsos, $y, 0, $line);
			($y < $nbr) ? $y++ : last;			# prints first 16 rows
		}	# all QSOs printed
		for (;$y < $nbr;$y++) {					# for the remaining rows
			addstr($wqsos, $y, 0, " "x80);		# fill with whitespace
		}
		if ($count > ($nbr-1)) {				# more QSOs than fit in window
			my $x;						# x-position of msg, depending on width
			if ($screenlayout == 0) {
				$x = 47;				# TODO maybe with getxy?
			}
			elsif ($screenlayout == 1) {
				$x=77;
			}
					
			addstr($wqsos, ($nbr-2), $x, ($count-$nbr));
			addstr($wqsos, ($nbr-1), $x-1, "more");
		}
		refresh($wqsos);

		# We fetch club membership information from the database ...
		# As of version 0.2.3: Also check other logbooks for the callsign
		# as given in .yfklog for previous QSOs. See .yfktest or MANUAL.

		my $clubline='';				# We will store the club infos here
		
		my $clubs = $dbh->prepare("SELECT `CLUB`, `NR` FROM clubs WHERE
									`CALL`='$call'");
		$clubs->execute();
	
		while (my @a = $clubs->fetchrow_array()) {			# fetch row
			$clubline .= $a[0].":".$a[1]." ";				# assemble string
		}
		# Output will be something like: AGCW:2666 HSC:1754 ...

		# now previous QSOs:

		my $qsoinotherlogs='';

		$checklogs =~ s#/#_#g;
		my @calls = split(/\s+/, "\L$checklogs");

		foreach my $callsign (@calls) {
			my $sth = $dbh->prepare("SELECT `CALL` FROM log_$callsign WHERE 
									`CALL` = '$call' OR
									`CALL` LIKE '\%\/$call' OR
									`CALL` LIKE '\%\/$call\/\%' OR
									`CALL` LIKE '$call\/\%'
									");	# No more regex with SQlite..
			$sth->execute();
			if ($sth->fetch()) {
				$qsoinotherlogs.= "\U$callsign " unless ($callsign eq $mycall);
			}

		}

		if ($qsoinotherlogs ne '') {
			$qsoinotherlogs =~ s#_#/#g;
			$clubline .= 'Wkd as: '.$qsoinotherlogs;
		}

		##########################################
		# Show DXCC bandpoints for the $call, also add to club-line. if new
		# DXCC or bandpoint, give extra notice.

		my $dx = $dbh->prepare("SELECT count(*) from log_$mycall WHERE 
														DXCC='$dxcc[7]';");
		$dx->execute();

		my $newdxcc = $dx->fetchrow_array();

		if ($newdxcc) {				# DXCC already wkd, show bands
			$dx = $dbh->prepare("SELECT `band`, `qslr`, `QSLRL` from
					log_$mycall WHERE 
						DXCC='$dxcc[7]';");

			$dx->execute();

			my %bandhash;
			my @i;

			while (@i = $dx->fetchrow_array()) {
				if ($i[2] eq 'Y') { $i[1] = 'Y' }	# LOTW = paper
				unless(defined($bandhash{$i[0]}) && $bandhash{$i[0]} ne 'N') {
					$bandhash{$i[0]} = $i[1];
				}
			}

			my $j;
			my $string='';

			foreach $j (sort {$a <=> $b} keys %bandhash) {
				$string .= "$j$bandhash{$j} ";
			}

			$string =~ s/Y/C/g;
			$string =~ s/N/W/g;

			$clubline .= $string;

			# bandpoint?

			unless ($string =~ /\b$band()[A-Z]\b/) {
				addstr($dxwin, 1, 65, "New Band!");
			}
			else {
				addstr($dxwin, 1, 65, "         ");
			}
		}
		else {									# NEW DXCC
			addstr($dxwin, 1, 65, "New DXCC!");
		}

		addstr($dxwin, 2, 0, sprintf("%-80s", $clubline));
		refresh($dxwin);
	}

	##########################################################
	# Query rig if autoqueryrig =  1 and NO QSO being edited.
	##########################################################
	if ($autoqueryrig && !$editnr) {
	
		my ($band, $mode) = (${$_[0]}[4] , ${$_[0]}[5]);
		
		&queryrig(\$band, \$mode);
	
		${$_[0]}[4] = $band;
		${$_[0]}[5] = $mode;
	
		addstr($wi[4],0,0,$band."    ");
		addstr($wi[5],0,0,$mode."    ");
		refresh($wi[4]);
		refresh($wi[5]);
	}

	if ($usehamdb && $hamdb) {
		my $results = $hamdb->lookup(uc($call));
		if ($results && $#$results > -1) {
			my $result = $results->[0];	# just get the first

			# assume that if we previously logged them the previous logged name
			# is right.
			if (!$foundlog) {
				my $nm = $result->{'first_name'} . " " . $result->{'last_name'};
				${$_[0]}[7] = $nm;
				addstr($wi[7],0,0,$nm);
				refresh($wi[7]);
			}

			# assume the QTH may have moved though, so use the new one
			my $qth = $result->{'qth'};
			${$_[0]}[6] = $qth;
			addstr($wi[6],0,0,$qth);
			refresh($wi[6]);

			my $remarks = "";

			# remarks

			# class
			if (defined($result->{'operator_class'})) {
				$remarks .= "Cl: $result->{'operator_class'}";
			}

			# GRID
			if (defined($result->{'Grid'})) {
				$remarks .= " GRID:$result->{'Grid'}";
			}

			if (defined($result->{'State'})) {
				$remarks .= " STATE:$result->{'State'}";
			} elsif ($result->{'Addr2'} =~ /[^,],\s*([^,]+)/) {
				$remarks .= " STATE:$1";
			}

			if ($remarks ne '') {
				${$_[0]}[12] = $remarks;
				addstr($wi[12],0,0,$remarks);				
				refresh($wi[12]);
			}
		}
	}
}



##############################################################################
# &getdate;   Uses gmtime() to get the current date  in DDMMYYYY
##############################################################################

sub getdate {
	my @date = gmtime();    	# $date[3] has day, 4 month, 5 year

	# The year is in years from 1900, month is counting from 0 from january.
	# Thus month++ and year += 1900;
	$date[4] += 1;
	if ($date[3] < 10) { $date[3] = "0".$date[3]; } 	# add leading zero
	if ($date[4] < 10) { $date[4] = "0".$date[4]; } 
	my $date = $date[3].$date[4].($date[5] + 1900);	
											
	return $date;	
}

##############################################################################
# &gettime;   Uses gmtime() to get the current UTC / GMT format HHMM
##############################################################################

sub gettime {
	my @date = gmtime();    	# $date[2] has hour, 1 has minutes
	if ($date[1] < 10) { $date[1] = "0".$date[1]; }   # Add 0 if neccessary
	if ($date[2] < 10) { $date[2] = "0".$date[2]; } 
	return $date[2].$date[1];
}

##############################################################################
# splashscreen    returns the splash screen
##############################################################################

sub splashscreen {
		my $yfkver = $_[0];
		return "YFKlog v$yfkver - a general purpose ham radio logbook

Copyright (C) 2005-2008  Fabian Kurz, DJ1YFK

This is free software, and you are welcome to redistribute it
under certain conditions (see COPYING).

YFKlog website: http://fkurz.net/ham/yfklog.html
Your feedback is appreciated.";
}
return 1;

##############################################################################
# &choseqso  This sub lets the OP chose a QSO from the logbook. It displays 16
# QSOs as usual in the $wlog window, the user can select a QSO with the cursor
# keys. The list automatically scrolls up and down after the last or first QSO
# in the window. PgUp and PgDwn jump a page up or down.
# The return value is the NR of the selected QSO, as in the database column NR
##############################################################################

sub choseqso {
	my $wlog = ${$_[0]};			# reference to $wlog window
	my $offset=0;					# offset for DB query. 
	my $aline;						# active line, cursor position.
	my $ch;							# character we get from keyboard
	my $ret=0;						# return value. saves the NR from the
									# database which suits in $aline
	my $goon=1;						# "go on" in the do .. while loop
	my $nbr;						# nr of lines/qsos
	my $y;							# y-position for printing in $wlog
	my $totalcalls=0;				# might be 0, then return

	my $by = " `NR` DESC ";

	if ($logsort eq 'C') {
		$by = " `DATE` DESC, `T_ON` DESC ";
	}

	# set active (highlighted) line according to screen layout
	if ($screenlayout == 0) {
		$aline = 15;
		$nbr = 16;
	}
	elsif ($screenlayout == 1) {
		$aline=7;
		$nbr = 8;
	}

	
# Now we fetch 16/8 QSOs from the database, eventually with an offset when we
# scrolled. only NR, CALL, BAND, MODE and DATE needed.
# a do {..} while construct is used because we need a highlighted line right at
# the start, without any extra key pressed


do  {			# loop and get keyboard input

	# after every keystroke the database query is done again and the active
	# line displayed in another color. unfortunately chgat() does not work on
	# things that have already been sent to the display with refresh(), so only
	# colouring one line while scrolling is not possible. since I was too lazy
	# to save the 16/8 QSOs into some kind of array, I decided to do the query
	# every time again. no performance problems even on my old K6-300.
	
	my $cq = $dbh->prepare("SELECT `NR`, `CALL`, `BAND`, `MODE`, `DATE`,
			`T_ON`, `NAME`, `QTH`, `RSTS`, `RSTR`, `QSLS`, `QSLR`, `QSLRL` FROM
			log_$mycall ORDER BY $by LIMIT $offset, $nbr");	
	$cq->execute();
	
#	my $nrofrows = $cq->execute();

#	if ($nrofrows eq "0E0") { return "i"; }		# nothing, back to log input
	
	# temporary vars
	my ($nr, $call, $band, $mode, $date, $time, $name, $qth, $rsts,
			$rstr,$qsls,$qslr, $qslrl);	
	$cq->bind_columns(\$nr, \$call, \$band, \$mode, \$date,\$time, \$name,
			\$qth,\$rsts,\$rstr,\$qsls,\$qslr, \$qslrl);
	$y = ($nbr-1);
	my $callsthispage=0;						# calls displayed on this page
	while ($cq->fetch()) {						# while row available
		$callsthispage++;
		$totalcalls++;
		# we put the date into DD-MM-YY format from YYYY-MM-DD
		$date = substr($date,8,2).substr($date,4,4).substr($date,2,2);
		# cut Call, Name, QTH, RSTR, RSTS, Mode
		$call = substr($call,0,12);
		$name = substr($name,0,8);
		$qth = substr($qth,0,13);
		$rstr = substr($rstr,0,3);
		$rsts = substr($rsts,0,3);
		$mode = substr($mode,0,5);
		
		if ($y == $aline) {						# highlight line?
			attron($wlog, COLOR_PAIR(1));
			$ret = $nr;							# remember the NR
		}
		if ($screenlayout == 0) {
			addstr($wlog,$y,0, sprintf("%-12s%-4s %-5s%-6s",
				$call,$band,$mode,$date));	 # print formatted
		}
		elsif ($screenlayout ==1) {
			substr($time,-3,)='';			# remove seconds
			addstr($wlog,$y,0, 
			sprintf("%-12s%-4s %-5s%-4s  %-6s  %-8s  %-13s  %-3s %-3s  %s %s %s  ",
					   	$call,$band,$mode,$time,$date,$name,$qth,$rsts,$rstr,
						$qsls, $qslr, $qslrl));	
		}
		
		attron($wlog, COLOR_PAIR(3));
		$y--;									# move one row up
	}
	while ($y > -1) {							# fill remaining lines
		my $width=30;
		if ($screenlayout==1) {$width=80;}
		addstr($wlog,$y,0," "x$width);
		$y--;
	}

	refresh($wlog);

	return "i" unless ($totalcalls);			# no QSOs!

	$ch = &getch2();						# get character from keyboard

	if ($ch eq KEY_DOWN) {				# key down was pressed
		if ($aline < ($nbr-1)) {		# no scrolling needed
			$aline++;
		}
		elsif ($offset != 0) {			# scroll down, when possible (=offset)
		# (when there is an offset, it means we have scrolled back, so we can
		# safely scroll forth again)
				$offset -= $nbr;		# next $nr (16 or 8)
				$aline = 0;				# cursor to highest line
		}
	}
	
	if ($ch eq KEY_UP) {				# key up was pressed
		if (($aline > -1) && 
				($callsthispage>($nbr-$aline))) {		# no scrolling needed
			$aline--;
		}
		elsif ($callsthispage > ($nbr-1)) {	
				$offset += $nbr;		# earlier 16/8
				$aline = ($nbr-1);		# cursor to lowest line
		}
	}

	if (($ch eq KEY_NPAGE) && ($offset != 0)) {		# scroll down 16/8 QSOs
		$aline = 0;						# first line
		$offset -= $nbr;				# next 16/8 QSOs
	}

	elsif (($ch eq KEY_PPAGE) && $callsthispage>7) {# scroll up 16/8 QSOs 
		$aline = ($nbr-1);				# last line
		$offset += $nbr;				# prev 8/16 QSOs
	}
	
	elsif ($ch eq KEY_F(1)) {			# go to the MAIN MENU
		$goon = 0;						# do not go on!
		$ret = "m";						# return value m = Menu
	}
	
	elsif ($ch eq KEY_F(8)) {			# back to inp-window without any action
		$goon = 0;						# do not go on!
		$ret = "i";						# return value i = Input Window
	}
	
	elsif ($ch eq KEY_F(10)) {			# to QSO b4-window without any action
		$goon = 0;
		$ret = "q";						# return value q = QSO Window
	}
	
	elsif ($ch =~ /\s/) {				# we selected a QSO!
		$goon=0;						# get out of the do .. while loop
	}	

	elsif ($ch eq KEY_F(12)) {			# QUIT
		endwin;
		exit;
	}

} while ($goon);			# as long as goon is true, we loop
return $ret;
} # &choseqso ends here

##############################################################################
# &getqso    Gets a number as parameter and returns the @qso array matching to
# the number from the database. Also updates the content of the Inputfields to
# the QSO. This works for fields 0..13 and is designed for the LOG INPUT mode.
# (There is also geteditqso  for the Search/Edit mode).
##############################################################################

sub getqso {
my @qso;					# QSO array
my $q = $dbh->prepare("SELECT `CALL`, `DATE`, `T_ON`, `T_OFF`, `BAND`, `MODE`,
		`QTH`, `NAME`, `QSLS`, `QSLR`, `RSTS`, `RSTR`, `REM`, `PWR` FROM
		log_$mycall WHERE `NR`='$_[0]'");
$q->execute;
@qso = $q->fetchrow_array;
# proper format for the date (yyyy-mm-dd ->  ddmmyyyy)
$qso[1] = substr($qso[1],8,2).substr($qso[1],5,2).substr($qso[1],0,4);
# proper format for the times. hh:mm:ss -> hhmm
$qso[2] = substr($qso[2],0,2).substr($qso[2],3,2);
$qso[3] = substr($qso[3],0,2).substr($qso[3],3,2);

for (my $x=0;$x < 14;$x++) {				# iterate through all input windows 
	addstr(${$_[1]}[$x],0,0,$qso[$x]);		# add new value from @qso.
	refresh(${$_[1]}[$x]);
}

return @qso;
}

##############################################################################
# &chosepqso;   Like &choseqso, but for the $wqsos window, where the Previous
# QSOs are displayed.
##############################################################################

sub chosepqso {
	my $wqsos = ${$_[0]};				# reference to $wqsos window
	my $call = $_[1];					# callsign of the current entry
	my $offset=0;						# offset from first 16
	my $ch;								# character we get from keyboard
	my $ret=0;							# return value
	my $goon=1;							# "go on" in the do .. while loop
	my $aline=0;						# activeline
	my $pos=1;							# the position of the active line, not
										# on the screen but in total from 
										# 1 .. $count. we start at 1.
	my $nbr;							# nr of lines/qsos
	my $totalcalls=0;					# if 0, return i.

	my $ascdesc = ' ASC ';

	if ($prevsort eq 'D') {
		$ascdesc = ' DESC ';
	}



	# set number of QSOs to display at once.
	if ($screenlayout == 0) {
		$nbr = 16;
	}
	elsif ($screenlayout == 1) {
		$nbr = 8;
	}

	# Get the homecall from a call with /, split and take longest part:
	# PA/DJ1YFK/P --> DJ1YFK etc.
	my @call = split(/\//, $call);
	my $length=0;						# length of splitted part
	foreach(@call) {					# chose longest part as homecall
		if (length($_) >= $length) { 
					$length = length($_);
					$call = $_;
		}
	}

	# First we want to know how many QSOs there are...
	my $lq = $dbh->prepare("SELECT count(*) from log_$mycall WHERE 
					 	`CALL` = '$call' OR
						`CALL` LIKE '\%/$call' OR
						`CALL` LIKE '\%/$call/\%' OR
						`CALL` LIKE '$call/\%'");


	$lq->execute();			# number of prev. QSOs in $count
	my $count = $lq->fetchrow_array();

	return 'i' unless ($count);


do {									# we start looping here
	my $lq = $dbh->prepare("SELECT `NR`, `CALL`, `DATE`, `T_ON`, `BAND`, `MODE`,
		   	`QSLS`, `QSLR`, `NAME`, `QTH`, `RSTS`, `RSTR`, `QSLRL` FROM
			log_$mycall WHERE 	`CALL` = '$call' OR
						`CALL` LIKE '\%/$call' OR
						`CALL` LIKE '\%/$call/\%' OR
						`CALL` LIKE '$call/\%'
			 ORDER BY `DATE` $ascdesc, `T_ON` $ascdesc
			LIMIT $offset, $nbr");	
	
	$lq->execute();	

	my ($nr, $fcall, $date, $time, $band, $mode, $qsls, $qslr, $name, $qth,
			$rsts, $rstr, $qslrl); # temp vars
	
	$lq->bind_columns(\$nr,\$fcall,\$date,\$time,\$band,\$mode,\$qsls,\$qslr,
	\$name, \$qth, \$rsts, \$rstr, \$qslrl);
	
	my $y = 0;
	while ($lq->fetch()) {				# more QSOs available
		$totalcalls++;
		$time = substr($time, 0,5);	# cut seconds from time
		$date = substr($date,8,2).substr($date,4,4).substr($date,2,2); 
		# cut Call, Name, QTH, RSTR, RSTS, Mode
		$fcall = substr($fcall,0,12);
		$name = substr($name,0,8);
		$qth = substr($qth,0,13);
		$rstr = substr($rstr,0,3);
		$rsts = substr($rsts,0,3);
		$mode = substr($mode,0,5);
		
		my $line;
		if ($screenlayout == 0) {		
			$line = sprintf("%-14s %-8s %-5s %4s %-4s %1s %1s     ", 
				$fcall, $date, $time, $band, $mode, $qsls, $qslr);
		}
		elsif ($screenlayout ==1) {
			$line =	sprintf("%-12s%-4s %-5s%-4s  %-6s  %-8s  %-13s  %-3s %-3s  %s %s %s  ",
				   	$fcall,$band,$mode,$time,$date,$name,$qth,$rsts,
					$rstr, $qsls, $qslr, $qslrl);
		}	

		if ($y == $aline) {					# highlight line?
			attron($wqsos, COLOR_PAIR(1));	# highlight
			$ret = $nr;						# remember NR
		}
		addstr($wqsos, $y, 0, $line);
		attron($wqsos, COLOR_PAIR(4));
		($y < $nbr) ? $y++ : last;			# prints first 8/16 rows
	}	# all QSOs printed
	
	for (;$y < $nbr;$y++) {					# for the remaining rows
		addstr($wqsos, $y, 0, " "x80);		# fill with whitespace
	}
	refresh($wqsos);

	$ch = &getch2();					# get keyboard input

	if ($ch eq KEY_DOWN) {			# arrow key down
		# we now have to check two things: 1. is the $pos lower than $count?
		# 2. are we at the end of a page and have to scroll?
		if ($pos < $count) {		# we can go down, but on same page?
			if ($aline < ($nbr-1)) {
				$aline++;
				$pos++;
			}
			else {					# we have to scroll!
				$offset += $nbr;	# add offset -> next 8/16 QSOs
				$aline=0;			# go to first line
				$pos++;				# we go one pos further
			}
		}
	}
	
	elsif ($ch eq KEY_UP) {			# arrow key up
		# we now have to check two things: 1. is the $pos over 1 (=lowest)?
		# 2. are we at the start of a page (aline=0) and have to scroll back?
		if ($pos > 1) {			# we can go up, but on same page?
			if ($aline > 0) {	# we stay on same page
				$aline--;
				$pos--;
			}
			else {				# scroll up!
			$offset -= $nbr;	# decrease offset
			$aline=($nbr-1);	# start on lowest line of new page
			$pos--;				# go back one position
			}
		}
	}
	
	elsif ($ch eq KEY_F(1)) {		# go to MAIN MENU
		return "m";
	}

	elsif ($ch eq KEY_F(8)) {		# back to input window
		return "i";
	}
	
	elsif ($ch eq KEY_F(9)) {		# back to input window
		return "l";
	}
	
	elsif ($ch eq KEY_F(12)) {		# QUIT YFKlog
		endwin;
		exit;
	}
	elsif ($ch =~ /\s/) {			# finished!
		return $ret;				# return value was prepared earlier
	}	
	
} while ($goon);		# loop until $goon is false

}

##############################################################################
# entrymask - returns the strings to be printed into the input window $winput 
#             just to make the main program more readable. Also used for the 
#             EDIT and SEARCH fuction
##############################################################################

sub entrymask {
if ($_[0] == 0) {
return 
"Call:               Date:          T on:      T off:      Band:      Mode: ";
}
elsif ($_[0] == 1) {
return "QTH:                Name:           QSLs:   QSLr:   RSTs:         RSTr:         ";
}
elsif ($_[0] == 2) {
		return "Remarks:                                                          PWR:       W  ";
}
elsif ($_[0] == 3) {
	return "DXCC:       PFX:           CONT:     ITUZ:     CQ:     QSLINFO:";
}
else {
	return "IOTA:         STATE:     QSLrL:    OP:         GRID:           QSO Nr: "
}
}

##############################################################################
# fkeyline  - returns the line to be printed into the $whelp window.
##############################################################################

sub fkeyline {
return "F2: Save Q  F3: Clear Q  F8: Input Window  F9: Log window  F10: Prev. QSO Window";
}

##############################################################################
# winfomask  - returns the mask for the $winfo window..
##############################################################################

sub winfomask {
if ($_[0] == 0) {
		return "Country:                          DXCC:       WPX:      ITU:    CQZ:            ";
}
else {
		return "Lat:         Long:          Distance:          Direction:                       ";
}
}

##############################################################################
# selectlist -  Produces a (if needed scrollable) list of items to chose from.
# $_[0] is the reference to the window where the list has to be displayed
# $_[1] is the y position for the list to start  (in curses tradition, y/x)
# $_[2] is the x position for the list to start
# $_[3] is the height of the list
# $_[4] is the width of the list 
# $_[5] is a reference to an array of menu items
# Pressing F1 returns "m" (used to go to the menu), F12 quits.
##############################################################################

sub selectlist {

my $ch;						# keyboard input
my $win = ${$_[0]};			# Window to work in
my $ystart = $_[1];			# y start position 
my $xstart = $_[2];			# x start position 
my $height = $_[3];			# height of the list
my $width = $_[4];			# width of the items
my @items = @{$_[5]};		# list items
my $item;					# a single item
my $y=0;					# y position in the window
my $yoffset=0;				# y offset, in case we scrolled
my $aline=0;				# active line (absolute position in @items) 

# Possibly the number of menu items is lower than the specified height. If this
# is the case, the height is lowered to the number of menu items.
# (On the other hand, if there were more items than height, we have to scroll!)
if ($height > @items) {		# Not enough items to fill the specified height
	$height = @items;		# adjust height
}

# To make the highlighted line look better, we extend all items to the maximum
# length with whitespaces. Of course too long ones will be cut.

for (my $i=0; $i < @items; $i++) {					# iterate through items
	my $l = length($items[$i]);						# length of item
	if ($l < $width) {								# too short
		$items[$i] .= " " x ($width - $l);			# add spaces
	}
	else {											# same length or longer
		$items[$i] = substr($items[$i], 0, $width);	# cut if needed
	}
}


do {

for ($y=$ystart; $y < ($ystart+$height); $y++) {	# go through $y range
	if (($y+$yoffset-$ystart) == $aline) {			# active line
		attron($win, COLOR_PAIR(1));				# highlight it
	}	
	if (defined($items[$y-$ystart+$yoffset])) {		# if line exists
		addstr($win, $y, $xstart, $items[$y-$ystart+$yoffset]);	# print
	}
	else {											# if not
		addstr($win, $y, $xstart, " " x $width);	# fill with spaces
	} 
	attron($win, COLOR_PAIR(2));					# normal colors again
}# end of for();
	
refresh($win);

$ch = getch();

if ($ch eq KEY_DOWN) {			# Arrow down was pressed 
	if ($aline < $#items) {		# not at last position
		# We can savely increase $aline, because we are not yet at the end of the
		# items array. 
		$aline++;
		# now it is possible that we have to scroll. this is the case when  
		if ($y+$yoffset-$ystart ==  $aline) {
			$yoffset += $height;
		}
	}
	elsif ($aline == $#items) {	# at last position
		# We wrap to first line and scroll up.
		$aline = 0;
		$yoffset = 0;
	}
}
elsif ($ch eq KEY_UP) {		# arrow up
	if ($aline > 0) {		# we are not at 0
		# We can savely decrease the $aline position, but maybe we have to scroll
		# up
		$aline--;
		# We have to scroll up if the active line is smaller than the offset..
		if ($yoffset > $aline) {
			$yoffset -= $height;
		}
	}
	elsif ($aline == 0) {		# we are at 0
		# We wrap to the last line and scroll down
		$aline = $#items;
		# To find the offset we divide number of items by height,
		# so just the remainder of the division is showed.
		# Number of items is decreased by 1, because offset starts at 0.
		$yoffset = int((@items - 1)/$height)*$height;
	}
}
elsif ($ch eq KEY_HOME) {		# Pos1 key
	# Go to first line and remove offset
	# same as wrapping to first line
	$aline = 0;
	$yoffset = 0;
}
elsif ($ch eq KEY_END) {		# End key
	# Go to last line and set offset
	# same as wrapping to last line
	$aline = $#items;
	$yoffset = int((@items - 1)/$height)*$height;
}
elsif ($ch eq KEY_F(1)) {			# F1 - Back to main menu
	return "m";
}
elsif ($ch eq KEY_F(12)) {			# F12 - QUIT YFKlog
	endwin();
	exit;
}
elsif (ord($ch) eq '27') {
	$ch = getch();
	if ($ch eq '1') {
		return "m";
	}
}

} until ($ch =~ /\s/);

return $aline;
} # selectlist

##############################################################################
# &askbox    Creates a window in which the user enters any value. 
##############################################################################

sub askbox {
	# We get the parameters ...
	my ($ypos, $xpos, $height, $width, $valid, $text, $str) = @_;
	my $win;				# The window in which we are working
	my $iwin;				# The Input window
	my $ch="";				# we store the keyboard input here

	my $pos=0;				# position of the cursor in the string
	
	$win = &makewindow($height, $width, $ypos, $xpos, 7);		# create askbox
	$iwin = &makewindow(1, $width-4, $ypos + 2, $xpos + 2, 5);	# input window
	
	addstr($win, 0, ($width-length($text))/2, $text);			# put question
	addstr($iwin,0,0, " " x $width);							# clear inputw
	move($iwin, 0,0);											# cursor to 0,0
	refresh($win);												# refresh ...
	refresh($iwin);

	if ($valid eq 'filename') {
		$valid = '[_A-Za-z.0-9\/]';
	}
	elsif ($valid eq 'text') {
		$valid = '[_A-Za-z.0-9\/ ]';
	}

	# Now we start reading from the keyboard, character by character
	# This is mostly identical to &readw;

	curs_set(1);

	while (1) {									# loop until beer is empty
		addstr($iwin, 0,0, $str." "x80);		# put $str in inputwindow
		move ($iwin,0,$pos);					# move cursor to $pos
		refresh($iwin);							# show new window
		$ch = &getch2();							# get character from keyboard

		# We first check if it is a legal character of the specified $match,
		# if so, it will be added to the string (at the proper position!) 
		if ($ch =~ /^$valid$/) {					# check if it's "legal"
			unless(($valid eq '\w') || ($valid eq '[_A-Za-z.0-9\/]')
			|| ($valid eq '[_A-Za-z.0-9\/ ]')) {
				$ch =~ tr/[a-z]/[A-Z]/;				# make letters uppercase
			}

			# Add at proper position..
			$pos++;
			$str = substr($str, 0, $pos-1).$ch.substr($str, $pos-1, );
		} 
		
		# The l/r arrow keys change the position of the cursor to left or right
		# but only within the boundaries of $str.
		
		elsif ($ch eq KEY_LEFT) {					# arrow left was pressed	
			if ($pos > 0) { $pos-- }				# go left if possible
		}
		
		elsif ($ch eq KEY_RIGHT) {					# arrow right was pressed	
			if ($pos < length($str)) { $pos++ }	# go right if possible
		}

		elsif ($ch eq KEY_HOME) { # Pos1 key was pressed, go to first char
			$pos = 0;
		}

		elsif ($ch eq KEY_END) { # End key was pressed, go behind last char
			$pos = length($str);
		}

		elsif (($ch eq KEY_DC) && ($pos < length($str))) {	# Delete key
			$str = substr($str, 0, $pos).substr($str, $pos+1, );
		}
		
		elsif ((($ch eq KEY_BACKSPACE) || (ord($ch)==8) || (ord($ch)==0x7F)) 
				&& ($pos > 0)) {
				$str = substr($str, 0, $pos-1).substr($str, $pos, );
				$pos--;
		}

		elsif ($ch =~ /\s/) {							# finished entering
			delwin($win);
			delwin($iwin);
			return $str;
		}
		
		# Back to main Menu by F1....
		elsif ($ch eq KEY_F(1)) {						# MAIN MENU
			delwin($win);
			delwin($iwin);
			return "m";
		}
		
		# Back to main Menu by F1....
		elsif ($ch eq KEY_F(12)) {						# Quit
			endwin();
			exit;
		}

	} # end of infinite while loop
}


##############################################################################
# toggleqsl -   This sub gets window and either a callsign or the letter "W" as
# parameters. 
#
# If it receives a callsign, it queries the database for QSOs where the 
# callsign matches and displays them in a (if needed) scrollable list.
# Within the list, the user can move up and down with arrow keys and 
# PG-up/down and toggle the QSL-R status of the selected QSO my pressing SPACE
# bar and toggle QSL-S status (for people who 'reply' to incoming cards) 
# with S. 
#
# If no callsign but a "W" is received, a list of all QSOs where the QSLS
# ("QSL sent") status is "Q" (= Queued) is displayed. This mode is for manually
# writing QSL cards. After a QSL was written, SPACEBAR toggles the status
# to "Y" (Yes, QSL written) and back to "Q" if needed.
##############################################################################


sub toggleqsl {
	curs_set(0); 			# no cursor please
	my $win = ${$_[0]};		# reference to $wmain window
	my $call = $_[1];		# callsign to display
	my $details = $_[2];	# show details of QSO?
	my $write="0";			# nonzero, when we are in writing mode
	my $count;				# number of available lines from DB
	my $goon=1;				# we want to go on...
	my $offset=0;			# offset when scrolling the list
	my $aline=0;			# first line is active (highlighted)
	my $ch="";				# char we read from keyboard
	my $chnr=0;				# number (NR) of active line
	my $qslstat;			# QSL status (QSLR or S) of active line
	my $qslstat2;			# same, for QSL-R mode to toggle QSL-S too
	my %changes;			# saves the changes we have made to QSL-R (in
							# receive mode) or QSL-S in write mode
							#  (NR => old value)
	my %changes2;			# same for QSL-S status in QSL-receive mode

	my ($yh, $xw);


# First check if we are in QSL receive or write mode. When write mode, set
# $write to 1
if ($call eq "W") { 
	$write = "1";
	($yh, $xw) = (22 - ($details * 5), 80);	# x,y width of the window
}
else {	# receive
	($yh, $xw) = (22, 80);
	$details = 0;
}

if ($write) {						# QSL Write mode
	# Check if there are any QSLs in the queue...
	my $c = $dbh->prepare("SELECT count(*) from log_$mycall WHERE QSLS='Q'");
	$c->execute();			# number of queued QSLs in $count

	$count = $c->fetchrow_array();

	# When 0 lines are returned, there is no QSL in the queue 
	# we pop out a message and quit. 

	if ($count == 0) { 
			addstr($win, 0,0, " " x ($xw * $yh));			# clear window
			addstr($win, 9, 33, "No QSL queued!");
			refresh($win);
			getch();									# wait for user 
			return 2; 									# return to main menu
	}
}
else {								# QSL receive mode
	# check if there are any QSOs that match with the string
	# we entered...
	my $c = $dbh->prepare("SELECT count(*) from log_$mycall WHERE 
							`CALL` LIKE '\%$call\%';");

	$c->execute() or die "Can't count nr of queued QSLs!";

	$count = $c->fetchrow_array();

	# When 0 lines are returned, there is no QSO to chose
	# we pop out a message and quit. 

	if ($count == 0) { 
			addstr($win, 0,0, " " x ($xw * $yh));			# clear window
			my $msg = "No QSO found matching $call!";
			addstr($win, 9, ($xw-length($msg))/2 , $msg);
			refresh($win);
			getch();									# wait for user 
			return 3; 
	}
}

# We have at least one QSO to display if arrived here....
	
do {									# we start looping here

	# We query the database again, this time we select all the stuff we want to
	# display. When we are in QSL write mode, select where QSLS = Q, else
	# select by CALL. 
	# In the QSL receive mode it will be sorted by date, in QSL write mode by
	# callsign, then date.

	my $lq;	
	
	if ($write) {
		$lq = $dbh->prepare("SELECT
			   	`NR`, `CALL`, `NAME`, `QSLINFO`, `DATE`,
				`T_ON`, `BAND`, `MODE`, `QSLS`, `QSLR`, `PWR`, `QTH`, `RSTS`,
				`RSTR`, `REM`, `DXCC`, `IOTA`, `STATE`, `QSLRL`, `OPERATOR`, `GRID` 
				FROM log_$mycall
				WHERE `QSLS`='Q' OR `QSLS`='X' ORDER BY `CALL`, `DATE`, `T_ON`
				LIMIT $offset, $yh");	
	}
	else {
		$lq = $dbh->prepare("SELECT
			   	`NR`, `CALL`, `NAME`, `QSLINFO`, `DATE`,
				`T_ON`, `BAND`, `MODE`, `QSLS`, `QSLR`, `PWR`, `QTH`, `RSTS`,
				`RSTR`, `REM`, `DXCC`, `IOTA`, `STATE`, `QSLRL`, `OPERATOR`, `GRID` 
				FROM log_$mycall
				WHERE `CALL` LIKE 
				'\%$call\%' ORDER BY `DATE`, `T_ON` LIMIT $offset, $yh");	
	
	}
	
	$lq->execute() or die "Couldn't select log entries!";	# Execute the prepared Query

	# Temporary variables for every retrieved QSO ...
	my ($nr, $fcall, $name, $qsli, $date, $time, $band, $mode, $qsls, $qslr,
			$pwr, $qth, $rsts, $rstr, $rem, $dxcc, $iota, $state, $qslrl, $op,
			$grid);

	$lq->bind_columns(\$nr,\$fcall,\$name,\$qsli,\$date,\$time,\$band,
						\$mode,\$qsls,\$qslr,\$pwr,\$qth, \$rsts, \$rstr,
						\$rem, \$dxcc, \$iota, \$state, \$qslrl, \$op, \$grid);
	
	my $y = 0;							# y-position in $win
	while ($lq->fetch()) {				# more QSOs available
		$time = substr($time, 0,5);		# cut seconds from time
		if ($qsls eq "X") { $qsls = "Y" }		# see below
		my $line=sprintf("%-6s %-12s %-11s%-9s%-8s %-5s %4s %4s %-4s %1s %1s     ",
			$nr, $fcall, $name, $qsli, $date, $time, $pwr, $band, $mode, $qsls, $qslr);
		if ($qsls eq "Y") { $qsls = "X" }
		if ($y == $aline) {					# highlight line?
			$chnr = $nr;					# save number of aline
			# save QSL status, depending on read/write mode. When in receive
			# mode, also save qsl-sent status to toggle it when replying to
			# incoming cards.
			if ($write) { $qslstat = $qsls }
			else {
				$qslstat = $qslr;
				$qslstat2 = $qsls;
			}
			addstr($win, $yh+1, 0, 
				sprintf("Additional QSO details: %6s - %-15s", $nr, $fcall));
			addstr($win, $yh+2, 0, 
				sprintf("RSTs: %-5s  RSTr: %-5s  QTH: %-18s DXCC: %4s IOTA: %-7s"
						, $rsts, $rstr, $qth, $dxcc, $iota));
			addstr($win, $yh+3, 0, 
				sprintf("Power: %-4sW OP: %8s GRID: %-17s LOTW: %s",
						$pwr, $op, $grid, $qslrl));
			addstr($win, $yh+4, 0, sprintf("Rem: %-60s", $rem));
			attron($win, COLOR_PAIR(3));	# highlight
		}
		addstr($win, $y, 0, $line);
		attron($win, COLOR_PAIR(4));
		($y < $yh) ? $y++ : last;			# prints first $yh (22) rows
	}	# all QSOs printed
	
	for (;$y < $yh;$y++) {					# for the remaining rows
		addstr($win, $y, 0, " "x80);		# fill with whitespace
	}

	refresh($win);

	$ch = &getch2();

	# Now start to analyse the input...
	
	# When Space is pressed, it means we toggle the QSL status of the current
	# active QSO, NR saved in $chnr. In case that the user decides NOT to save
	# the changes, we remember all changes that we made in the hash %changes,
	# so they can be restored later.
	# This is neccessary, because the DB is queried every time the cursor
	# moves, so we cannot make changes in a temporary qso-array or so...
	
	if ($ch eq " ") {						# SPACE BAR -> toggle QSL status
		unless (defined $changes{$chnr}) {	# we have NOT saved the original
			$changes{$chnr} = $qslstat;		# save it
		}

		# We want to let the user *toggle* the status, so the change we make
		# depends on the current value.

		if ($write) {								# QSL write mode Q->Y
			# "X" is used instead of "Y" as status, because if it's "Y", the
			# QSO will not appear anymore in the list, when we update the
			# screen... 

			if ($qslstat eq "Q") { $qslstat = "X" }
			elsif ($qslstat eq "X") { $qslstat = "Q"}
			# Update database record...	
			$dbh->do("UPDATE log_$mycall SET QSLS='$qslstat' 
					 								WHERE NR='$chnr';");
		}
		else {										# QSL receive mode N->Y
			if ($qslstat eq "N") { $qslstat = "Y" }
			elsif ($qslstat eq "Y") { $qslstat = "N" }
			$dbh->do("UPDATE log_$mycall SET QSLR='$qslstat' 
					 								WHERE NR='$chnr';");
		}
	} # end of Spacebar handling

	# When pressing "s" in QSL-receive mode, toggle the QSl-sent flag. This is
	# thought to be used for replying to incoming QSLs where no card has been
	# sent. Toggling goes N->Y->Q
	
	elsif (($ch eq "s") && (not $write)) {
		unless (defined $changes2{$chnr}) {	# we have NOT saved the original
			$changes2{$chnr} = $qslstat2;	# save it
		}
		
		if ($qslstat2 eq "N") { $qslstat2 = "X" }
		elsif ($qslstat2 eq "X") { $qslstat2 = "Q" }
		elsif ($qslstat2 eq "Q") { $qslstat2 = "N" }
		$dbh->do("UPDATE log_$mycall SET QSLS='$qslstat2' 
					 								WHERE NR='$chnr';");
	}
	
	# If we want to go down, we also have to ensure that we are not yet at the
	# end of the list. $aline is the position only relative to the window, so
	# we have to compare $aline+$offset+1 agains the $count of QSOs... (+1
	# because $aline starts at 0, $count at 1)
	elsif (($ch eq KEY_DOWN) && (($aline + $offset + 1) < $count)) {
			# We are allowed to go down, but we have to check if we need to
			# scroll or not. Scrolling is needed when $aline is 21.
			if ($aline == ($yh-1)) {
				$aline = 0;				# next page, we start at beginning
				$offset += ($yh-1);			# increase the offset accordingly
			}
			else {						# no scrolling needed
				$aline++;				# increase aline -> one row down
			}	
	}
	# Same story when we want to go up: Make sure that we are not at the
	# beginning of the list.
	elsif (($ch eq KEY_UP) && (($aline + $offset) > 0)) {
			# We are allowed to go up, but we have to check if we need to
			# scroll or not. Scrolling is needed when $aline is 0.
			if ($aline == 0) {
				$aline = ($yh-1);			# next page, we start at beginning
				$offset -= ($yh-1);			# increase the offset accordingly
			}
			else {						# no scrolling needed
				$aline--;				# increase aline -> one row down
			}	
	}

	# PG DOWN is easier: We can scroll DOWN when there are more available
	# lines than currently displayed: $offset+22.
	elsif (($ch eq KEY_NPAGE) && ($offset+$yh < $count)) {
		$offset += ($yh-1);					# adjust offset
		$aline = 0;						# Start again at the first line	
	}
	
	# Same with UP. We can scroll up when $offset > 0
	elsif (($ch eq KEY_PPAGE) && ($offset > 0)) {
		$offset -= ($yh-1);					# adjust offset
		$aline = ($yh-1);					# Start again at the last line	
	}

	# F1 => Back to the main menu. Return 2 for Status.
	elsif ($ch eq KEY_F(1)) {
		my $k = 'y';
		if (keys %changes) {
			$k = &askconfirmation("Really save and go back to menu? [y/N]",
				'y|n|\s|\n');
		}

		if ($k =~ /y/i) {
			# changed QSL sent flags back to Y
			$dbh->do("UPDATE log_$mycall SET QSLS='Y' WHERE QSLS='X';");
			return 2;	
		}
	}
	
	# F2 => We are done. Changes to the DB are saved, we can go back.
	# return 3 -> stay in QSL mode, wait for new callsign WHEN in receive mode
	# return 2 -> back to main menu when in write mode. before change all
	# QSL-sent flags that are "X" to "Y". the X is used temporarily within this
	# sub, because after updating the screen, "Y" would not be displayed
	# anymore...

	elsif ($ch eq KEY_F(2)) {
		$dbh->do("UPDATE log_$mycall SET QSLS='Y' WHERE QSLS='X';");
		if ($write) { 
			return 2; 
		}
		else { return 3 }
	}

	# F3 => Cancel. This means we must restore the original QSL status again.
	# We have saved the changes we made in %changes.
	elsif ($ch eq KEY_F(3)) {
		my $k = 'y';
		if (keys %changes) {
			$k = &askconfirmation("Really cancel changes and go to menu? [y/N]",
				'y|n|\s|\n');
		}

		if ($k =~ /y/i) {
		# Iterate through the hash where the changes were saved and restore it
		# in the database...	
		while ((my $nr, my $qsl) =  each %changes) {
			# Depending on the mode (QSL write or receive), update DB fields
			if ($write) {
				$dbh->do("UPDATE log_$mycall SET QSLS='$qsl' WHERE NR='$nr';");
			}
			else {	
				$dbh->do("UPDATE log_$mycall SET QSLR='$qsl' WHERE NR='$nr';");
			}
		}
		# Same for %changes2, the QSL-S changes while in QSL-R mode (replying)
		while ((my $nr, my $qsl) =  each %changes2) {
			# Depending on the mode (QSL write or receive), update DB fields
			if ($write) {
					# Impossible here :)
			}
			else {	
				$dbh->do("UPDATE log_$mycall SET QSLS='$qsl' WHERE NR='$nr';");
			}
		}
		if ($write) { return 2 }				# write -> Back to main menu
		else { return 3 }						# receive -> QSL rx mode
		} # if $k =~ y
	}

	# F12 -> Exit
	elsif ($ch eq KEY_F(12)) {
		endwin();
		exit;
	}

} while (1);		# loop until end of time 
	

} # end of toggleqsl 


##############################################################################
# &onlinelog     Exports the current log into a ~-separated file for an online
# log.
##############################################################################

sub onlinelog {
	my @qso;			# Every QSO we fetch from the DB will be stored here
	my $nr;				# Number of QSOs that are exported.

	open ONLINELOG, ">$directory/$mycall.log";

	# We query the database for the fields specified in $onlinedata (by default
	# or from the config file).
	
	my $ol = $dbh->prepare("SELECT $onlinedata FROM log_$mycall ORDER BY `DATE`");	
	$ol->execute or die DBI->errstr;		# Execute the query

	while (@qso = $ol->fetchrow_array()) {	# Fetch the selected data into @qso
		my $line = join ('~', @qso);		# assemble lines, ~-separated
		print ONLINELOG $line."\n";			# write to log
		$nr++; 								# increase number of QSOs...
	}
	close ONLINELOG;

return $nr;									# return number of exported QSOs
}


##############################################################################
# preparelabels  -- In this sub the labels are preared.
# They re stored in a hash, where the keys are the callsigns 
# plus a number starting 0, the value contains the raw 
# label, as specified in the .lab file. Every time a call appears in the 
# queue, the next data row is filled.  This hash is called %labels.
# There is a second hash which has the callsign only as key and the current
# key name of the callsign (Callsign + 0,1,2..) in the main hash as value.
# In this way it's possible to handle several cards for one station, when
# the number of QSOs to print surpasses the number of data-lines.
# This second hash is called %calls.
#
# example:  %calls = ("DJ1YFK" => "DJ1YFK1",    # 2nd label for YFK already
#                     "9A7P" => "9A7P0");       # 1st label for 9A7P
#           %labels = ("DJ1YFK0" => "<LaTeX Code>",     # full
#                      "DJ1YFK1" => "<LaTeX Code>",     # not yet..
#                      "9A7P" => "<LaTeX Code>");
# (I am probably too stupid or tired to figure out how to make this
# properly with references).
#
# The number of filled QSO lines in a label is written as the first byte of 
# the <LaTeX Code>.
#
# When the hashes are ready, thwo things need to be done: remove the number 
# of QSOs, replace all unfilled data-lines (MANAGER, DATE3, UTC3 ...) 
# with "-" or delete them (MANAGER).
##############################################################################

sub preparelabels {
	my %calls;					# call hash, see above
	my %labels;					# label hash, see above
	my $labeltype=$_[0];		# filename of the label type
	my $qsos;					# number of QSOs per label
	my $template;				# LaTeX template of a label, read from file
	
# We read the contents of the label file. for this part, only the LaTeX code 
# and the number of QSO lines is needed.
	
	open QSL, $labeltype;						# Open the label file
		while (defined (my $line = <QSL>)) {	# Read line into $line
			if ($line =~ /^% QSOS=(\d)/) {		# QSOs per label
				$qsos = $1;
			}
			elsif ($line =~ /^%/) {}			# comment, skip it
			else {								# must be TeX now.
				$template .= $line;				# add line to label template	
			}
		}
	close QSL;

# Now the log is queried for queued QSLs.. 

	my $queue = $dbh->prepare("SELECT `CALL`, `NAME`, `DATE`, `T_ON`, `BAND`, 
				`MODE`, `RSTS`, `PWR`, `QSLINFO`, `QSLR` FROM log_$mycall WHERE
				`QSLS`='Q' ORDER BY `CALL`, `DATE`, `T_ON`");	

	my $x = $queue->execute();							# Execute Query

	my ($call, $name, $date, $time, $band, $mode, $rst, $pwr, $mgr, $qslr);
	$queue->bind_columns(\$call,\$name,\$date,\$time,\$band,\$mode,
												\$rst,\$pwr,\$mgr, \$qslr);
	
	# Now we are fetching row by row of the data which has to be put into the
	# %labels hash.
	while (my @qso = $queue->fetchrow_array()) {	# @qso to put into QSL hash
		# Firstly, the time format shall be changed to HHMM and the band 
		# should get an additional "m" or "cm"

		$time = substr($time,0,5);				# cut seconds
		if ($band > 1) {
				$band = $band."m";						# add m
		}
		else {
				$band *= 100;							# convert to cm
				$band = $band."cm";						# add cm
		}

		# Change QSL-received information. Y = TNX, N = PSE

		if ($qslr eq 'Y') { $qslr = 'TNX'; }
		else { $qslr = 'PSE';}

		my $scall=$call;				# Altlasten...

		# Check if key $scall already exists in the %calls hash, if not add it
		# if it exists, check if label is full, if so make new one, otherwise
		# go on. (Works with up to 10 labels, but that should be OK :)
		if (exists $calls{$scall}) {						# call exists?
			if (substr($labels{$calls{$scall}},0,1)==$qsos){# label full?
				my $nr = substr($calls{$scall},-1,1);		# nr of labels
				substr($calls{$scall},-1,1) = ($nr+1);		# increase # of lab
				$labels{$calls{$scall}} = "0".$template;	# make new label
			}
		}
		else {									# call does not yet exist..
				$calls{$scall} = $scall."0";	# 1st label for $call
				$labels{$calls{$scall}} = "0".$template;	# create label,0 Qs 
		}

		# now we are ensured that we can write the QSO line to the label hash
		# at $label{$calls{$call}}. OK, that's too much typing. So we make a
		# reference to it; we can easily access the label with $$lr now.

		my $lr = \$labels{$calls{$scall}};
		
		# If it's the first row we write on the label, also the CALL, MANAGER,
		# MYCALL and eventually NAME have to be added:

		if (substr($$lr,0,1) eq "0") {				# first line
			my ($call, $mgr) = ($call, $mgr);		# local copies
			$call =~ s/0/\\O{}/g;					# replace 0 with slashed O
			$mgr =~ s/0/\\O{}/g;					# replace 0 with slashed O
			$$lr =~ s/HISCALL/$call/;				# replace things
			$$lr =~ s/MANAGER/$mgr/;
			$$lr =~ s/MYCALL/\U$mycall/;
			$$lr =~ s/_/\//g;						# _ to /
			$$lr =~ s/NAME/$name/;
			$$lr =~ s/TXPOWER/$pwr/;
		}

		# In every case we have to replace the fields DATE, TIME, BAND, MODE,
		# RST of the current line. The number of the line is the first byte of
		# the label + 1

		my $nr = substr($$lr,0,1);				# Number of QSOs written
		$nr++;									# we write another line
		$$lr =~s/DATE$nr/$date/;				# replace things.
		$$lr =~s/TIME$nr/$time/;
		$$lr =~s/BAND$nr/$band/;
		$$lr =~s/MODE$nr/$mode/;
		$$lr =~s/RST$nr/$rst/;
		$$lr =~s/QSLR$nr/$qslr/;
		substr($$lr,0,1) = $nr;					# increase nr of QSOs on label
	
	}	# end of while for reading log line

# OK, gone through all the lines now and added them to labels. Now delete all
# placeholders for QSO lines which were not used.

foreach my $key (my @k = keys(%labels)) {
	$labels{$key} =~ s/DATE\d&/ &/g;				#	kill placeholders
	$labels{$key} =~ s/&TIME\d&/& &/g;
	$labels{$key} =~ s/&BAND\d&/& &/g;
	$labels{$key} =~ s/&MODE\d&/& &/g;
	$labels{$key} =~ s/&RST\d/& /g;
	$labels{$key} =~ s/&QSLR\d/& /g;
}

return 	%labels;
	
} # end of preparelabels	

##############################################################################
# labeltex     This sub receives a reference to a hash of QSL labels,
# the filename of the labeltype definition and the start label on the paper.
# It returns a compilable LaTeX document which contains all the labels, placed
# according to the label specification, and alphabetically sorted.
##############################################################################

sub labeltex {
	my %labels = %{$_[0]};	# labels
	my @keys;				# keys of the label hash
	my $start=($_[2]-1);	# startlabel where to start printing
	my $lnr;				# label number absolute
	my $latex;				# the string which will contain the latex document
	my $labeltype=$_[1];	# the type of the QSL label
	my $width;				# width of the QSL label in mm
	my $height;				# height of the QSL label in mm
	my $topmargin;			# top margin of the label sheet
	my $leftmargin;			# left margin of the label sheet
	my $rows;				# number of label rows
	my $cols;				# number of label columns
	
# Read label geometry from the definition file
	
	open QSL, $labeltype;						# Open the label file
		while (defined (my $line = <QSL>)) {	# Read line into $line
			if ($line =~ /^% WIDTH=([\d.]+)/) { $width= $1; }
			elsif ($line =~ /^% HEIGHT=([\d.]+)/) { $height= $1; } 
			elsif ($line =~ /^% TOPMARGIN=([\d.]+)/) { $topmargin= $1; } 
			elsif ($line =~ /^% LEFTMARGIN=([\d.]+)/) { $leftmargin= $1; } 
			elsif ($line =~ /^% ROWS=(\d+)/) { $rows= $1; } 
			elsif ($line =~ /^% COLS=(\d+)/) { $cols= $1; } 
		}
	close QSL;

# We start assembling the latex string. First we add the header, which will be
# the same for all labels. I assume that all labels come on A4 paper. The
# header should have all the packages needed.

	$latex .= '\documentclass[a4paper]{article}
	\pagestyle{empty}
	\usepackage{latexsym}
	\usepackage{graphicx}
	\usepackage[margin=0cm, noheadfoot]{geometry}
	\renewcommand{\familydefault}{\sfdefault}
	\setlength{\parindent}{0pt}
	\begin{document}
	\setlength{\unitlength}{1mm}
	\begin{picture}(210,297)'."\n";
	
# The QSL cards should be printed in alphabetical order. The keys of the
# %labels hash are the callsigns plus attached number of label, so they can be
# used to sort. ASCIIbetical sort is OK since there are only [0-9A-Z].

@keys = sort keys(%labels);

# Now iterate through the keys. %labels{$key} is the label to print into the
# document. The information where a label has to be put is saved in $row, 
# $col and $page. Everytime the maximum $row, $col or $row*$col has been
# crossed, a new row/page will be started.

my ($page, $row, $col) = (1,1,1);

# $start specifies at which label printing should start. If the value is
# greater than $rows*$cols, it will be ignored because that would print a whole
# blank page.

unless ($start > ($cols * $rows)) {
while ($start > $cols) {			
		$start-= $cols;							# next row
		$row++;
}
$col += $start-1;							# go to proper column
}

foreach my $key (@keys) {
	$lnr++;									# next label
	$col++;									# next column
	if ($col > $cols) {						# over end of a row
		$col = 1;							# start at 1st column again
		$row += 1;							# increase row
	}
	if ($row > $rows) {						# over rows!
		$row = 1;							# start at first row again
		$page +=1;							# increase page, write to doc.
		$latex .= "\\end{picture}\n\\newpage\n\\begin{picture}(210,297)";
	}

	# Now the position of the label on the sheet has to be calculated from the
	# row and col information. the point we are looking for is the lower left
	# corner of the label.

	my $x = $leftmargin;		# The x position is always shifted my leftmarg
	$x += ($col-1)*$width;		# add the width of the labels
	
	my $y = 297 - $topmargin;	# The y position starts shifted by topmargin
	$y -= ($row)*$height;		# go down by $height * $row

	# first letter in the label code is not needed here, it is the number of
	# QSOs on that label. Put the rest to the $latex variable which will be the
	# full LaTeX source, at the proper position $x, $y.
	$latex .= "\n"."\\put($x,$y){".substr($labels{$key},1,)."}";

}

# All labels are written now. we finish the document. Attach number of labels
# and pages as % comment in the latex file.

	$latex .= "\\end{picture}\n\\end{document}\n\% $lnr $page";

return $latex;				# return the document
	
}	# labeltex ends here

##############################################################################
# emptyqslqueue  - After successfully printing QSL labels, all queued QSLs
# will be marked as sent. return number of updated QSOs.
##############################################################################

sub emptyqslqueue {
	 return	$dbh->do("UPDATE log_$mycall SET QSLS='Y' WHERE QSLS ='Q';");
}

##############################################################################
# adifexport  - Exports the logbook to an ADIF file. The fields CALL, DATE,
# T_ON, T_OFF, BAND, MODE, QTH, NAME, QSLS, QSLR, RSTS, RSTR, REM, PWR, PFX,
# QSLINFO, ITUZ, CQZ, STATE, IOTA, CONT and GRID are exported into their
# appropriate fields.  
# if $_[1] is 'adif', all QSOs are exported
# if $_[1] is 'LOTW', all QSOs where QSLRL = 'N' are exported and set to 'R'
#          for 'Requested'. 
##############################################################################

sub adifexport {
	my $filename = $_[0];				# Where to save the exported data
	my $export = $_[1];					# 'lotw' or 'adi'.
	my $daterange= $_[2];					# 'lotw' or 'adi'.
	my $nr=0;							# number of QSOs exported. return value
	my $sql = 'WHERE ';
	my @q;								# QSOs from the DB..
	
	open ADIF, ">$filename";			# Open ADIF file

	print ADIF "Exported from the logbook of $mycall by YFKlog.\n<eoh>";

	$sql .= " QSLRL = 'N' AND " if ($export eq 'lotw');

	$sql .= $daterange;

	my $adif = $dbh->prepare("SELECT `CALL`, `DATE`, `T_ON`, `T_OFF`, `BAND`,
			`MODE`, `QTH`, `NAME`, `QSLS`, `QSLR`, `RSTS`, `RSTR`, `REM`,
			`PWR`, `PFX`, `CONT`, `QSLINFO`, `CQZ`, `ITUZ`, `IOTA`, `STATE`,
			`OPERATOR`, `GRID` FROM log_$mycall $sql"); 
	
	$adif->execute();

	# Fetching every line into the @qso array, then printing it into the file.
	while (@q = $adif->fetchrow_array()) {
		# increase counter...

		$nr++;
		
		# Change the date-format from YYYY-MM-DD into YYYMMDD
		substr($q[1],4,1) = '';				# delete first hyphen
		substr($q[1],6,1) = '';				# deltete second hyphen

		# change time format from hh:mm:ss to HHMMSS
		substr($q[2],2,1)=''; substr($q[2],4,1)='';	# time on
		substr($q[3],2,1)=''; substr($q[3],4,1)='';	# time off

		# check if band is millimeters, meters or centimeters
		if ($q[4] < 0.01) {							# mm (47GHz and up)
			$q[4] *= 1000;
			$q[4] .= "mm";
		}
		elsif($q[4] < 1) {						# centimeters
			$q[4] *= 100;							# convert to meters
			$q[4] .="cm";							# add cm
		}
		else {										# meters
			$q[4] .="m";
		}
		
		# First print those fields which *have* to exist:
		print ADIF "\n\n<call:".length($q[0]).">$q[0] ";
		print ADIF "<qso_date:".length($q[1]).">$q[1] ";
		print ADIF "<time_on:".length($q[2]).">$q[2] ";
		print ADIF "<time_off:".length($q[3]).">$q[3] ";
		print ADIF "<band:".length($q[4]).">$q[4] ";
		print ADIF "<mode:".length($q[5]).">$q[5] \n";
		print ADIF "<rst_sent:".length($q[10]).">$q[10] ";
		print ADIF "<rst_rcvd:".length($q[11]).">$q[11] ";
		print ADIF "<qsl_sent:".length($q[8]).">$q[8] ";
		print ADIF "<qsl_rcvd:".length($q[9]).">$q[9] ";
		print ADIF "<pfx:".length($q[14]).">$q[14] ";
		print ADIF "<cont:".length($q[15]).">$q[15] ";

		# now the fields which might be empty  
		unless ($q[6] eq '') {				
			print ADIF "<qth:".length($q[6]).">$q[6] ";
		}
		unless ($q[7] eq '') {					
			print ADIF "<name:".length($q[7]).">$q[7] \n";
		}
		unless ($q[12] eq '') {
			print ADIF "<comment:".length($q[12]).">$q[12] ";
		}
		unless ($q[13] eq '') {
			print ADIF "<tx_pwr:".length($q[13]).">$q[13] ";
		}
		unless ($q[16] eq '') {
			print ADIF "<qsl_via:".length($q[16]).">$q[16] ";
		}
		unless ($q[17] eq '') {
			print ADIF "<cqz:".length($q[17]).">$q[17] ";
		}
		unless ($q[18] eq '') {
			print ADIF "<ituz:".length($q[18]).">$q[18] ";
		}
		unless ($q[19] eq '') {
			print ADIF "<iota:".length($q[19]).">$q[19] ";
		}
		unless ($q[20] eq '') {
			print ADIF "<state:".length($q[20]).">$q[20] ";
		}
		unless ($q[21] eq '') {
			print ADIF "<operator:".length($q[21]).">$q[21] ";
		}
		unless ($q[22] eq '') {
			print ADIF "<gridsquare:".length($q[22]).">$q[22] ";
		}
		print ADIF '<eor>';						# QSO done
	} # no more lines to fetch..

	close ADIF;

	$dbh->do("UPDATE log_$mycall set qslrl='R' where qslrl='N'") if 
														($export eq 'lotw');

	return $nr;			# return number of exported QSOs...
}	# end of ADIF export

##############################################################################
# ftpupload  - upload dj1yfk.log to the place specified in the config file
##############################################################################

sub ftpupload {
	# Trying to open a FTP connection
	
	my $ftp = Net::FTP->new($ftpserver, Timeout => 120, Port => $ftpport, 
			Debug => 0, Hash => 0);

	# If the connection fails, undef is returned.. 
	unless (defined $ftp) {
		return "Sorry: $@";
	}
	
	# at this point, the FTP connection is ok, so we log in
	
	$ftp->login($ftpuser, $ftppass) || return "FTP login failed. $!";

	$ftp->cwd($ftpdir);				# change into the log directory

	$ftp->put($directory.'/'.$mycall.'.log') || return "Cannot put $mycall.log, $!";

	$ftp->quit();

	return "Log uploaded successfully to $ftpdir$mycall.log!";	
} # end of ftp upload


##############################################################################
# &adifimport --   This sub reads a file $_[0] after the ADIF
# specifications and writes it into the MySQL database in the format used by
# YFKlog.  Every entry is checked for the minimum neccessary data, callsign,
# date, time_on, band or frequency and mode. Additional information will be
# stored if YFKlog has an appropriate database field. 
# Also the CALLS database, which cointains Name&QTH information will be
# updated if the call is unknown yet..
# TBD  If the <dxcc:> field is available, YFKlog uses it to determine the DXCC,
# otherwise YFKlog's &dxcc; function is used, which slows down the import
# process.  (At the moment: ALWAYS use &dxcc FIXME)
##############################################################################

sub adifimport {

my $win = $_[1];				# Window to print status info..
my $filename=$_[0];				# the ADIF-File
my $fullline;					# We need to put together several lines until 
								# a <eor> occurs
my $field="";					# adif field name
my $content="";					# adif field content
my $am=0;						# adif mode. 1 = read field name, 2 = read
								# length, 3 = read content, 0 = nothing
my $len="";						# length of the field to read.
my @qso;						# array which holds QSO-hashes
my $nr=0;						# number of imported lines
my $err=0;						# number of errors during import
my $errmsg='';					# reason of error
my $war=0;						# number of warnings (unk. fields)
my $ch;							# process adif-file $ch by $ch..
my $header=1;					# while header=1, we are still before <eoh>
my $parsecount=1;

$filename =~ /([^\/]+)$/;
my $basename = $1;

open(ERROR, ">>/tmp/$mycall-import-from-$basename.err");

print ERROR "-"x80;

addstr($win,0,0, "Parsing ADIF-File, that might take a while..."." "x80);
refresh($win);

open ADIF, $filename;

while (my $line = <ADIF>) {

	map {s/\r//g;} ($line);			# cope with DOS linebreaks
		
	# As long as the current position is in the header, we discard the lines
	# This is the case as long has $header is 1; it is set to 0 as soon as a 
	# <eoh> is found.
	if ($header) {							# we are in the header..
		if ($line =~ /<eoh>/i) {		# end of header? 
			$header = 0;
		}
		next;								# process next line
	}

	# Now assemble a full line, containing a full QSO until <eor>	
	unless ($line =~ /<eor>(\s+)?$/i) 		{	# line ends here
		$fullline .= $line;					# add line to full line
	}
	else {									# we have a <eor>-> full line
		$fullline .= $line;
		$fullline =~ s/<eor>//i;	# cut EOR
		$nr++;								# increase line counter
		my $qh = {};						# anonymous qso-hash
		while (($ch = substr($fullline,0,1)) ne "") {	# fullline has a letter
			$fullline = substr($fullline,1,);		# cut first letter
	
			# Now the string $fullline is parsed letter by letter. depending on
			# it's content and the adif mode in which we are, the $ch is either
			# discarded (for <,> and :) or added to either the $field, $length
			# or $content variable.
			# This is a typical ADIF line and the modes in which we are while
			# parsing it:
			#
			# <call:5>DL1AA <date:8>20050401 ...
			#01111122333333011111223333333330... 
			
			# If the character is a "<" AND we are in mode 0, it means a new
			# field definition starts. It's important to check that we are
			# actually in the mode 0 because otherwise a "<" in a comment field
			# would be mistaken for the start of a new field.
			if (($ch eq "<") && ($am == 0)) {		# new field starts
				$field = "";						# delete old field
				$len="";							# delete old length
				$am = 1;							# adifmode = 1 = read field
			}
			# The field name is read. Only allowed characters are letters and
			# underscores. The read character is added to the field-name 
			elsif (($ch =~ /[A-Za-z_]/) && ($am == 1)) {	# read field name
				$field .= $ch;
			}
			# When we are reading the field definition (am = 1) and a colon
			# occurs, it marks the end of the field def and after it the length
			# starts. so we switch to am=2, which is the length mode
			elsif (($ch eq ":") && ($am == 1)) {	# field over, now length
				$am = 2;							# ==> mode 2
			}
			# we are in length-mode, and add every number that comes our way to
			# the $len variable.
			elsif (($ch =~ /\d/) && ($am == 2)) {	# read length;
				$len .= $ch;						# add length
			}
			# we are in length mode and a ">" comes our way, meaning that we
			# have to start reading the content of the field from now on. so
			# switch to mode 3, except when field length is zero. then $am
			# becomes 0 (look for next field to start).
			elsif (($ch eq ">") && ($am == 2)) {	# length over
				if ($len eq '0') { $am = 0; next }  # no length -> read next
				$am = 3;							# read field content
			}
			# last check: we are in mode to read content 
			# within this check we also check if the maximum length has been
			# reaced, if so, we save the information into an array of hashes.
			 
			elsif (($am == 3) && ((length($content)) < $len)) {
				$content .= $ch;
				if (length($content) == $len) { 
					$am = 0;			# field / value pair is done
					# print "$nr: >$field<  --->  >$content<\n";
					$qh->{"\L$field"} = $content;	# fieldname lowercase
					$field="";
					$content="";
				}  
			} # main $ch-processing ends here
		} # while loop to iterate through $fullline ends here
		push @qso, $qh;			# add ref to qso-hash to @qso array.
		addstr($win,0,50, $parsecount." "x80) unless ($parsecount % 100);
		refresh($win) unless ($parsecount % 100);
		$parsecount++;
	} # else -> fullline complete ends here
} # main loop of reading from ADIF

close ADIF;

addstr($win,0,0,"ADIF-file parsed, now importing..."." "x80);
refresh($win);

# Now  go through all QSOs and check if something has to be converted or
# changed and check if the record is complete. Minimum data needed for a QSO
# are: Call, Date, Time_on, Band, Mode.
# An additional key "valid" is added to the QSO hash. It is set to '1' by
# default, and can be set to '0' when one of the neccessary values is invalid.

for my $i ( 0 .. $#qso ) {					# iterate through Array of Hashes
	$qso[$i]{'valid'} = '1';				# this QSO is now valid
	$errmsg = '';

	my @dxcc = &dxcc($qso[$i]{'call'});
	
	# Now check if the minimum neccessary fields are existing...
	# These are CALL,  QSO_DATE, TIME_ON, BAND or FREQ, and MODE.
	# Actually the ADIF specs don't specify this, but everything with less
	# information than this doesn't make any sense to me.
	if (exists($qso[$i]{'call'}) && exists($qso[$i]{'qso_date'}) &&
			exists($qso[$i]{'time_on'}) && (exists($qso[$i]{'band'}) ||
					exists($qso[$i]{'freq'})) && exists($qso[$i]{'mode'})) {
	# minimum needed fields are existing, go on...
		
		# Now check the key/value pairs for compatibility with the database
		# format used by YFKlog and change if needed


		# The CALL and MODE should always be uppercase..

		$qso[$i]{'call'} = "\U$qso[$i]{'call'}";
		$qso[$i]{'call'} =~ s/[^A-Z0-9\/]//g;			# remove rubbish
		$qso[$i]{'mode'} = "\U$qso[$i]{'mode'}";

		# Anything left?
		unless ($qso[$i]{"call"}=~ /^[A-Z0-9\/]{3,}$/) { 
				
				$qso[$i]{'valid'} = '0'; 
				$errmsg .= "callsign invalid, ";
		}

		# change the qso_date field to the proper format YYYY-MM-DD
		# from the current YYYYMMDD
		
		# The date is REQUIRED, so do a crude check if its valid
		unless ($qso[$i]{"qso_date"}=~ /^\d{8,8}$/) { 
				$qso[$i]{'valid'} = '0'; 
				$errmsg .= "date invalid, ";
		}
		
		$qso[$i]{"qso_date"} = substr($qso[$i]{"qso_date"},0,4).'-'.
					substr($qso[$i]{"qso_date"},4,2).'-'.
					substr($qso[$i]{"qso_date"},6,2);

		# rename it to DATE

		$qso[$i]{"date"} = $qso[$i]{"qso_date"};
		delete($qso[$i]{"qso_date"});
		
		# The time format can either be HHMM or HHMMSS. Both have to be
		# converted to HH:MM:SS, for both time_on and time_off.
	
		# Crude check if time is valid (4 or 6 digits)
		unless ($qso[$i]{"time_on"} =~ /^\d{4,6}$/) { 
				$qso[$i]{'valid'} = '0';
				$errmsg .= "time_on invalid, ";
		}

		if (length($qso[$i]{"time_on"}) == 4) {	# we have HHMM => HH:MM:00
				$qso[$i]{"time_on"} = substr($qso[$i]{"time_on"},0,2).':'.
									substr($qso[$i]{"time_on"},2,2).':00';
		}
		elsif (length($qso[$i]{"time_on"}) == 6) {	#  HHMMSS > HH:MM:SS
			$qso[$i]{"time_on"} = substr($qso[$i]{"time_on"},0,2).':'.
								substr($qso[$i]{"time_on"},2,2).':'.
								substr($qso[$i]{"time_on"},4,2);
		}
		# finally rename it to t_on
		$qso[$i]{"t_on"} = $qso[$i]{"time_on"};
		delete($qso[$i]{"time_on"});

		# exactly the same for time_off, if defined:
		if (defined($qso[$i]{"time_off"})) {
			unless ($qso[$i]{"time_off"} =~ /^\d{4,6}$/) { 
					$qso[$i]{'valid'} = '0';
					$errmsg .= "time_off invalid, ";
			}

		if (length($qso[$i]{"time_off"}) == 4) {	# we have HHMM => HH:MM:00
			$qso[$i]{"time_off"} = substr($qso[$i]{"time_off"},0,2).':'.
									substr($qso[$i]{"time_off"},2,2).':00';
		}
		elsif (length($qso[$i]{"time_off"}) == 6) {	#  HHMMSS > HH:MM:SS
			$qso[$i]{"time_off"} = substr($qso[$i]{"time_off"},0,2).':'.
								substr($qso[$i]{"time_off"},2,2).':'.
								substr($qso[$i]{"time_off"},4,2);
		}
			$qso[$i]{"t_off"} = $qso[$i]{"time_off"};
			delete($qso[$i]{"time_off"});
		} # if defined(time off)
		else {	# time_off is not defined, so make it the same as time_on
			$qso[$i]{'t_off'} = $qso[$i]{'t_on'}
		}
		
		# Now check if there is band info. if so, but the M or CM at the end
		# and delete - if available - the 'freq' key. we only need one of them.
			
		if (defined($qso[$i]{"band"})) {				# band info 
		
			# Crude check if band is valid (1 .. 4 digits + (c)m,(C)M)
			unless($qso[$i]{"band"}=~/^[0-9.]{1,7}(c|C)?(m|M)$/) {
					$qso[$i]{'valid'}='0';
					$errmsg .= "band invalid, ";
			}
			
			if ($qso[$i]{"band"} =~ /\d[Mm]$/) {	# actually ends with m/M?
				substr($qso[$i]{"band"},-1,) = '';	# cut it
			}
			else {								# must be CM
				substr($qso[$i]{"band"},-2,) = '';		# cut it
				$qso[$i]{"band"} /=100;					# divide to m
			}
			# now we have a band; if there is a frequency, delete it.
			if (defined($qso[$i]{'freq'})) {
					delete $qso[$i]{'freq'};
			}		
		}
		
		# if there is a frequency tag instead of band, the band has to be
		# determined from it. This works for 160m to 76GHz
		if (defined($qso[$i]{'freq'})) {
			
			my $val = $qso[$i]{'freq'};				# save freq temporarily
			
			if ($val =~ /^(1[.][89]|2[.]0)/) { $qso[$i]{'band'} = '160' } 
			elsif ($val =~ /^[34][.]/) { $qso[$i]{'band'} = '80' } 
			elsif ($val =~ /(^7[.])|(^7$)/) { $qso[$i]{'band'} = '40' } 
			elsif ($val =~ /(^10[.](0|1))|(^10$)/) { $qso[$i]{'band'} = '30' } 
			elsif ($val =~ /(^14[.])|(^14$)/) { $qso[$i]{'band'} = '20' } 
			elsif ($val =~ /^18/) { $qso[$i]{'band'} = '17' } 
			elsif ($val =~ /(^21[.])|(^21$)/) { $qso[$i]{'band'} = '15' } 
			elsif ($val =~ /^24/) { $qso[$i]{'band'} = '12' } 
			elsif ($val =~ /^2(8|9)/) { $qso[$i]{'band'} = '10' } 
			elsif ($val =~ /^5[0-4]/) { $qso[$i]{'band'} = '6' } 
			elsif ($val =~ /^14[4-8]/) { $qso[$i]{'band'} = '2' } 
			elsif ($val =~ /^4[2-5]\d/) { $qso[$i]{'band'} = '0.7' } 
			elsif ($val =~ /^1[23]\d\d/) { $qso[$i]{'band'} = '0.23' } 
			elsif ($val =~ /^2[43]\d\d/) { $qso[$i]{'band'} = '0.13' } 
			elsif ($val =~ /^3\d\d\d/) { $qso[$i]{'band'} = '0.09' } 
			elsif ($val =~ /^5\d\d\d/) { $qso[$i]{'band'} = '0.06' } 
			elsif ($val =~ /^10\d\d\d/) { $qso[$i]{'band'} = '0.03' } 
			elsif ($val =~ /^24\d\d\d/) { $qso[$i]{'band'} = '0.0125' } 
			elsif ($val =~ /^47\d\d\d/) { $qso[$i]{'band'} = '0.006' } 
			elsif ($val =~ /^76\d\d\d/) { $qso[$i]{'band'} = '0.004' } 
			else {								# unknown band ...
					$qso[$i]{'valid'} = '0';
					$errmsg = "freq invalid, ";
			}
							
			delete $qso[$i]{'freq'};			# don't need it anymore
		}	
	
		# RST_RCVD and RST_SENT will be renamed to rstr and rsts

		if (defined($qso[$i]{'rst_sent'})) {
			$qso[$i]{'rsts'} = $qso[$i]{'rst_sent'};
			$qso[$i]{'rsts'} =~ s/[^0-9]//g;
			delete($qso[$i]{'rst_sent'});
		}
		
		if (defined($qso[$i]{'rst_rcvd'})) {
			$qso[$i]{'rstr'} = $qso[$i]{'rst_rcvd'};
			$qso[$i]{'rstr'} =~ s/[^0-9]//g;
			delete($qso[$i]{'rst_rcvd'});
		}

		# Check if a prefix was defined in the adif-file. If not, get it from
		# the &wpx sub.
		unless(defined($qso[$i]{'pfx'})) {
				$qso[$i]{'pfx'} = &wpx($qso[$i]{'call'});
				# Sanity check: May be undef
				unless (defined($qso[$i]{'pfx'})) {	
					$war++;
					print ERROR "Warning: Can't determine prefix of ".
													"$qso[$i]{call}\n";
					$qso[$i]{'pfx'} = '';
				}
		}
		
		# received serial number will be added to the RST field if it
		# exists. If not, create RST field with only serial number in it
		if (defined($qso[$i]{'srx'})) {
			
			if (defined($qso[$i]{'rstr'})) {			# rst-rcvd exists
				$qso[$i]{'rstr'} .=  $qso[$i]{'srx'};	# add it
			}
			else {											# doesnt exist!
				$qso[$i]{'rstr'} =  $qso[$i]{'srx'};	# create it
			}
			delete($qso[$i]{'srx'});				# delete key/value pair
		}

		# same for sent serial number
	
		if (defined($qso[$i]{'stx'})) {
			
			if (defined($qso[$i]{'rsts'})) {
				$qso[$i]{'rsts'} .=  $qso[$i]{'stx'};
			}
			else {
				$qso[$i]{'rsts'} =  $qso[$i]{'stx'};
			}
			delete($qso[$i]{'stx'});				# delete key/value pair
		}			

		# there is no contest_id field in YFKlog, it is saved in the remarks
		# field, if available
		if (defined($qso[$i]{"contest_id"})) {
			unless (defined($qso[$i]{'rem'})) { 			# nothing in REM yet
				$qso[$i]{'rem'} = $qso[$i]{'contest_id'};	# put it in there
			}
			else {										# remarks field exists
				$qso[$i]{'rem'} .= " ".$qso[$i]{'contest_id'}; 
			}
			delete($qso[$i]{'contest_id'});					# delete contest_id 
		}

		# Rename GRIDSQUARE to GRID if it looks valid.

		if (defined($qso[$i]{"gridsquare"})) {
			if ($qso[$i]{"gridsquare"} =~ /^[A-Z]{2}[0-9]{2}/) {
				$qso[$i]{"grid"} = "\U$qso[$i]{'gridsquare'}";
				delete($qso[$i]{'gridsquare'});	
			}
		}
		
		# Comments go into the value for key 'rem'. Note that it might already
		# have a value by contest_id or gridsquare!
		if (defined($qso[$i]{"comment"})) {
			unless (defined($qso[$i]{'rem'})) { 		# nothing in REM yet
				$qso[$i]{'rem'} = $qso[$i]{'comment'};	# put it in there
			}
			else {										# remarks field exists
				$qso[$i]{'rem'} .= " ".$qso[$i]{'comment'}; 
			}
			delete($qso[$i]{'comment'});				# delete comment field 

			if (length($qso[$i]{'rem'}) > 60) {
				$qso[$i]{rem} = substr($qso[$i]{rem}, 0, 60);
			}

		}
		
		# QSL_VIA information from ADIF goes straight into the QSLINFO field
		if (defined($qso[$i]{"qsl_via"})) {
			$qso[$i]{'qslinfo'} = $qso[$i]{"qsl_via"};
			delete($qso[$i]{"qsl_via"});
		}
		
		# Cut Name and QTH if too long.
		if (defined($qso[$i]{name})) {
			if (length($qso[$i]{name}) > 15) {
				$qso[$i]{name} = substr($qso[$i]{name}, 0, 15);
			}
		}

		if (defined($qso[$i]{qth})) {
			if (length($qso[$i]{qth}) > 15) {
				$qso[$i]{qth} = substr($qso[$i]{qth}, 0, 15);
			}
		}

		# TX_PWR from ADIF goes into the PWR field. Since some logbook programs
		# add a "W" (which is agains the adif specs), remove it if neccessary.
		if (defined($qso[$i]{tx_pwr})) {
			$qso[$i]{pwr} = $qso[$i]{tx_pwr};
			$qso[$i]{pwr} =~ s/[^0-9]//g;
			delete($qso[$i]{tx_pwr});
		}
		else {								# no pwr specified in ADIF
			$qso[$i]{pwr} = $dpwr;		# default power from config file
		}
		

		# The DXCC information is not neccessarily included in the ADIF file.
		# It consists of a number, NOT neccessarily following the ARRL
		# conventions, so the corresponding ARRL DXCC has to be fetched from an
		# external database (TBD).
		
		# 	if (defined($qso[$i]{'dxcc'})) {
			# TBD  DXCC lookup in ADIF<->ARRL DB	
			# 
			#} 
		# If no DXCC is given, we try to derive it from the call by the
		# &dxcc() function. Note that this *might* be wrong, that's why we try
		# to use the value from the ADIF file first
		#else {
		# FIXME FIXME FIXME FIXME FIXME FIXME   
		# DXCC info is always taken from cty.dat
		# FIXME FIXME FIXME FIXME FIXME FIXME   

			$qso[$i]{'dxcc'} = $dxcc[7];
			$qso[$i]{'cont'} = $dxcc[3];
		#}

		# Add CONT if not already done
		unless (defined($qso[$i]{'cont'})) {
			$qso[$i]{'cont'} = $dxcc[3];
		}
	
		# Add ITUZ if not already done
		unless (defined($qso[$i]{'ituz'})) {
			$qso[$i]{'ituz'} = $dxcc[2];
		}
		
		# Add CQZ if not already done
		unless (defined($qso[$i]{'cqz'})) {
			$qso[$i]{'cqz'} = $dxcc[1];
		}
		
		# check if QSL_SENT exists. If so, take it, if not use default $dqslsi
		if (defined($qso[$i]{'qsl_sent'})) {
			$qso[$i]{'qsls'} = $qso[$i]{'qsl_sent'};
			delete($qso[$i]{'qsl_sent'});
		}
		else {							# no qsl-sent, so use $dqslsi
			$qso[$i]{'qsls'} = $dqslsi;
		}
		# check if QSL_RCVD exists. If so, take it, if not use "N"
		if (defined($qso[$i]{'qsl_rcvd'})) {
			$qso[$i]{'qslr'} = $qso[$i]{'qsl_rcvd'};
			delete($qso[$i]{'qsl_rcvd'});
		}
		else {							# no qsl-rcvd, set to "N"
			$qso[$i]{'qslr'} = "N";
		}
		
		# made all neccessary changes to the QSO hash 

	} # if (exists $neccessary data) ...
	else {										# the QSO is NOT VALID!
			$qso[$i]{'valid'} = '0';			# set QSO invalid
			$errmsg .= "Basic info missing: Call, Date, Time_on, Band or Freq and Mode. ";  
	}

	# At this point we have either processed the hash in a way that it can be
	# imported (when the value for key 'valid' is 1), or the QSO is not valid
	# If the QSO is valid, we are happy and go on. otherwise the content of the
	# invalid QSO-hash is written to the error-log, so the user knows what went
	# wrong.
	
	if ($qso[$i]{'valid'} eq '0') {					# invalid QSO!
		$err++;										# count up error number
		print ERROR "ERROR: QSO Nr $i was invalid:\n";
		for my $key (sort keys %{$qso[$i]}) {		# iterate through hash keys
			print ERROR "'$key' ==> '$qso[$i]{$key}', ";		# value
		}
		print ERROR "\nPossible Reason: $errmsg \n";
		print ERROR "\nTHIS QSO WAS NOT IMPORTED! \n\n";
	}

	# After every 100 QSOs give a little status output
	
	addstr($win,0,0, "Errors: $err, now importing QSO: ".($i+1).", $qso[$i]{'call'}"." "x80);
	refresh($win) unless (($i+1) % 100);
	
	
} # iterate through AoH, arrives here after every QSO was processed.

addstr($win,0,0, "All QSOs processed, now adding QSOs to database...");
refresh($win);

# Generate SQL for every QSO which is valid (valid => 1). 
#
# Those hash entries which still do not have a corresponding key in the YFKlog
# database <foo:3>bar  ==> $qso[0]{'foo'}=='bar' will NOT be included in the
# SQL string, instead a warning  message will be written into the error file.
# For this reason, a hash table containing all possible field names in the
# database is generated. 

my %fields = ('call' => 1, 'date' => 1, 't_on' => 1, 't_off' => 1,
				'band' => 1, 'mode' => 1, 'qth' => 1, 'name' => 1, 
				'rstr' => 1, 'rsts' => 1, 'operator' => 1, 'grid'=> 1,
				'qsls' => 1, 'qslr' => 1, 'rem' => 1, 'pwr' => 1, 
				'dxcc' => 1, 'pfx' => 1, 'cqz' => 1, 'cont' => 1, 
				'ituz' => 1, 'qslinfo' => 1, 'iota' => 1, 'state' => 1);

for my $i (0 .. $#qso) {					# iterate through Array of Hashes
	my $sql;								# sql-string part one
	my $sqlvalues;							# part two

	if ($qso[$i]{'valid'} eq '0') { next; }	# invalid QSO, don't export!
	delete($qso[$i]{'valid'});				# validity info not needed anymore

	# NB: As of 0.3.0, the SQL string looks like:
	# INSERT INTO log_dj1yfk (call, date, ...) VALUES ('DJ1YFK',
	# '2001-01-01'... ) since SQLite doesn't support the SET x=y syntax.

	$sql= "INSERT INTO log_$mycall (";		# start buildung SQL string
	$sqlvalues = ") VALUES (";

	# Now iterate through hash keys. if its valid, i.e. contained in the
	# %fields hash, it will be added to the SQL string, otherwise written to
	# the error-log. If a ' appears in any field, it has to be escaped.
	for my $key (keys %{$qso[$i]}) {	
		if (defined($fields{$key})) {				# if field is valid
			$qso[$i]{$key} = $dbh->quote($qso[$i]{$key});
			$sql .= "`$key`,";
			$sqlvalues .= "$qso[$i]{$key}, "; 		# add  key-value pair to DB
		}
		else {										# invalid field.
			$war++;
			print ERROR "WARNING: In QSO  $i unknown field: $key =>". 
						" $qso[$i]{$key} IGNORED!\n";
			print ERROR "CALL: $qso[$i]{'call'} DATE: $qso[$i]{'date'}, BAND:".
						"$qso[$i]{'band'}, TIME: $qso[$i]{'t_on'}\n\n";
		}
	}
	
	$sql =~ s/,$//;
	$sqlvalues =~ s/, $/);/;

	$sql .= $sqlvalues;

	# MySQL5 doesn't like CALL, so change it to `CALL`

	$sql =~ s/call=/`CALL`=/gi;

	# Now put the QSO into the database:
	$dbh->do($sql) or die "Insert QSO $sql failed!";

	# Check if the Name and QTH of the callsign is already known in the CALLS
	# table. If not, use Name and QTH from the ADI-file if it exists. Crop all
	# unneccessary stuff from the call (/P etc).

	if (defined($qso[$i]{'name'}) || defined($qso[$i]{'qth'})) {
		my $call = $qso[$i]{'call'};		# The call to crop
		
		$call =~ s/[^A-Z0-9\/]//g;			# remove quotes, if any

		# Split the call at every /, chose longest part. Might go wrong
		# in very rare cases (KH7K/K1A), but I don't care :-) 

		if ($call =~ /\//) {					# dahditditdahdit in call
			my @call = split(/\//, $call);
			my $length=0;                       # length of splitted part
			foreach(@call) {                    # chose longest part
				if (length($_) >= $length) {
					$length = length($_);
					$call = $_;
				}
			}	
		}

		my $sth = $dbh->prepare("SELECT `CALL` FROM `calls` WHERE 
									`CALL`='$call';");
		$sth->execute();
		unless ($sth->fetch()) {		# nothing to fetch -> call is unknown!
			# Add information from ADIF to the database, if QTH/Name is now
			# know, just a empty field.
			unless (defined($qso[$i]{'name'})) {$qso[$i]{'name'}="''";}
			unless (defined($qso[$i]{'qth'})) {$qso[$i]{'qth'}="''";}
			$dbh->do("INSERT INTO calls (`CALL`, `NAME`, `QTH`) VALUES
				('$call',$qso[$i]{'name'},$qso[$i]{'qth'});");
		}
	}
	
}

close ERROR;	


addstr($win,0,0,"Done. Import complete.                                          ");
refresh($win);
return($nr, $err, $war);
	
} # end of adifimport

##############################################################################
# getlogs  --  returns a array of callsigns of all logbooks in the current
# database. Those are tables that start with log_ plus a callsign.
# If the callsign contains a "/" (for example 9A/DJ1YFK), it is replaced with
# an underscore (9a_dj1yfk). The callsign as in the database is always
# lowercase. For a nicer display, in the returned array all callsigns are
# converted back to uppercase and with / instead of _
##############################################################################

sub getlogs {
	my @logs;					# logs in the database
	my $showtables = "SHOW TABLES";

	if ($db  eq 'sqlite') {
		$showtables = "select name from sqlite_master where type='table';"
	}

	my $gl = $dbh->prepare($showtables);
	$gl->execute();

	while(my $l = $gl->fetchrow_array()) {
		if ($l =~ /^log_(.*)$/) {			# a new logbook found
			my $x = $1;						# cannot modify $1, so save to $x
		   	$x=~ s/_/\//g;					# change underscore _ to slash /
			push(@logs, "\U$x");			# add uppercase callsign to the list
		}	
	}

	return @logs;
} # getlogs

##############################################################################
# changemycall  -- changes $mycall (lexical variable with scope within
# yfksubs.pl) to $_[0], from yfk.pl
##############################################################################

sub changemycall {
	$mycall = $_[0];
}

##############################################################################
# &newlogtable   Creates a new logbook table in the database with the name
# "log_\L$_[0]$", for example log_dj1yfk. If the callsign includes a "/", it
# will be converted into a "_" because "/" is not allowed in a table name.
##############################################################################

sub newlogtable {
	my $call = $_[0];					# callsign of the new database

	my $filename = "$prefix/share/yfklog/db_log.sql";
	if ($db eq 'sqlite') {
		$filename = "$prefix/share/yfklog/db_log.sqlite";
	}

	open DB, $filename;				# database definition in this file
	my @db = <DB>;						# read database def. into @db

	# We assume that the callsign in $_[0] is valid, because the &askbox()
	# which produced it only accepted valid callsign-letters.
	# only exception: empty callsign!
	
	if ($call eq '') {
		return "**** Invalid callsign! ****";
	}
	
	$call =~ tr/\//_/;					# convert "/" to "_"
	$call =~ tr/[A-Z]/[a-z]/;			# make call lowercase

	
	# Now check if there is also a table existing with the same name

	unless (&tableexists("log_$call")) {	# If logbook does not yet exist, create it
		my $db = "@db";
		$db =~ s/MYCALL/$call/g;# replace the callsign placeholder	
		$dbh->do($db);			# create it!
		return "Logbook successfully created!";
	}
	else {							# log already existed
		return "Logbook with same name already exists!";
	}	
} # newlogtable

##############################################################################
# &oldlogtable   Erase an old logbook table in the database with the name
# "log_\L$_[0]$", for example log_dj1yfk. If the callsign includes a "/", it
# will be converted into a "_" because "/" is not allowed in a table name.
##############################################################################

sub oldlogtable {
	my $call = $_[0];					# callsign to delete 

	my $filename = "$prefix/share/yfklog/db_log.sql";
	if ($db eq 'sqlite') {
		$filename = "$prefix/share/yfklog/db_log.sqlite";
	}

	open DB, $filename;				# database definition in this file
	my @db = <DB>;						# read database def. into @db

	# We assume that the callsign in $_[0] is valid, because the &askbox()
	# which produced it only accepted valid callsign-letters.
	# only exception: empty callsign!
	
	if ($call eq '') {
		return "**** Invalid callsign! ****";
	}
	
	$call =~ tr/\//_/;					# convert "/" to "_"
	$call =~ tr/[A-Z]/[a-z]/;			# make call lowercase

	
	# Now check if there is a table with an existing name

	if (&tableexists("log_$call")) {	# If logbook does exist, delete it
		my $db = "@db";
#		$db =~ s/MYCALL/$call/g;# replace the callsign placeholder	
		$dbh->do("DROP table log_$call");			# erase it!
		return "Logbook successfully erased!";
	}
	else {							# log already existed
		return "No logbook for this call!";
	}	
} # oldlogtable

##############################################################################
# choseeditqso -  Choses a QSO in the Edit & Search Mode which has to be
# edited. It gets references to the @qso-array with the search criteria, and
# the $weditlog window, where it has to print the output.
##############################################################################

sub choseeditqso {
	my $offset=0;				# offset when scrolling in the list
	my $aline=0;				# active / highlighted line
	my $ch;						# character read from keyboard
	my $ret;					# return number
	my $goon=1;					# becomes 0 when we are done
	my $count;					# number of entries/QSOs matching
	my $pos=$_[2];				# ref position in the QSOs from 1 .. $count

	my $win = ${$_[0]};			# Window where output goes. height = 17
    my $sql;					# SQL string with search criteria
	my $sql2=' AND 1 ';
	my @qso = @{$_[1]};			# search criteria
	
    # Assemble a SQL string which contains the search criteria. First the
    # columns which should be displayed.  
    $sql = "SELECT `NR`, `CALL`, `NAME`, `DATE`, `T_ON`, `BAND`, `MODE`,
	`QSLS`, `QSLR`, `DXCC`, `QSLINFO`, `QSLRL` FROM log_$mycall WHERE `NR` ";
    # The rest of the string now depends on the content of the @qso-array:
    $sql2 = "AND `CALL` LIKE '\%$qso[0]\%' " if $qso[0];
	if ($qso[1]) {
		$sql2 .= "AND DATE = '".substr($qso[1],4,4).'-'.substr($qso[1],2,2).'-'
								.substr($qso[1],0,2)."' ";
	}
    $sql2 .= "AND  `BAND` ='$qso[4]' " if $qso[4];
    $sql2 .= "AND `MODE`='$qso[5]' " if $qso[5];
    $sql2 .= "AND `QTH` LIKE '\%$qso[6]\%' " if $qso[6];
    $sql2 .= "AND `NAME`  LIKE '\%$qso[7]\%' " if $qso[7];
    $sql2 .= "AND `QSLS` = '$qso[8]' " if $qso[8];
    $sql2 .= "AND `QSLR` = '$qso[9]' " if $qso[9];
    $sql2 .= "AND `REM` LIKE '\%$qso[12]\%' " if $qso[12];
    $sql2 .= "AND `PWR`='$qso[13]' " if $qso[13];
    $sql2 .= "AND `DXCC`='$qso[14]' " if $qso[14];
    $sql2 .= "AND `PFX`='$qso[15]' " if $qso[15];
    $sql2 .= "AND `CONT`='$qso[16]' " if $qso[16];
    $sql2 .= "AND `ITUZ`='$qso[17]' " if $qso[17];
    $sql2 .= "AND `CQZ`='$qso[18]' " if $qso[18];
    $sql2 .= "AND `QSLINFO` LIKE '\%$qso[19]\%' " if $qso[19];
    $sql2 .= "AND `IOTA`='$qso[20]' " if $qso[20];
    $sql2 .= "AND `STATE`='$qso[21]' " if $qso[21];
    $sql2 .= "AND `QSLRL`='$qso[23]' " if $qso[23];
    $sql2 .= "AND `OPERATOR`='$qso[24]' " if $qso[24];
    $sql2 .= "AND `GRID`='$qso[25]' " if $qso[25];

	# We have to know how many QSOs are fitting the current search criteria:

	my $eq = $dbh->prepare("SELECT count(*) from log_$mycall where 1 $sql2;");
	$eq->execute();
	$count = $eq->fetchrow_array();
	
	if ($count == 0) { return 0 };		# no QSO to edit-> $editnr = 0.

	# Calculate offset and aline for last cursor position different from 1.

	if ($$pos > 17) {
		$offset = int(($$pos-1) / 17) * 17;
		$aline = $$pos-1 - $offset;
	}
	else {$aline = $$pos-1;}

do {
	my $eq = $dbh->prepare($sql.$sql2." ORDER BY `DATE`, `T_ON` LIMIT $offset, 17;");
	$eq->execute();
	my ($nr, $call, $name, $date, $time, $band, $mode, 			# temp vars
						$qsls, $qslr, $dxcc, $qslinfo, $qslrl);
	$eq->bind_columns(\$nr,\$call,\$name, \$date,\$time,\$band,\$mode,
						\$qsls,\$qslr,\$dxcc,\$qslinfo, \$qslrl);
	
	my $y = 0;					# y cordinate in the window (absolute position)
	while ($eq->fetch()) {		# QSO available
		$time = substr($time, 0,5); 	# cut seconds from time
		my $line = sprintf("%-6s %-14s %-12s %-8s %-5s %4s %-4s %1s %1s %1s %-4s%-9s", 
				$nr, $call, $name, $date, $time, $band, $mode, $qsls, 
				$qslr, $qslrl, $dxcc, $qslinfo);
		if ($y == $aline) {					# highlight line?
			attron($win, COLOR_PAIR(3));	# highlight
			$ret = $nr;						# remember NR
		}
		addstr($win, $y, 0, $line);
		attron($win, COLOR_PAIR(4));		# restore normal color
		($y < 17) ? $y++ : last;			# prints first 16 rows
	}
	for (;$y < 17;$y++) {					# for the remaining rows
		addstr($win, $y, 0, " "x80);		# fill with whitespace
	}
	refresh($win);
		
	$ch = &getch2(); 							# Get keyboard input

	if ($ch eq KEY_DOWN) {					# arrow key down was pressed
		# 1. Can we go down => $$pos < $count?
		# 2. do we have to scroll down? => $aline < 15?
		if ($$pos < $count) {				# we can go down!
			if ($aline < 16) {				# stay on same page
				$aline++;
				$$pos++;
			}
			else {							# scroll down!
				$offset += 17;				# next 17 QSOs from DB!
				$aline=0;					# start at first (highest) line
				$$pos++;
			}
		}
	} # key down

	elsif ($ch eq KEY_UP) {					# arrow key down was pressed
		# 1. Can we go up => $$pos > 1?
		# 2. do we have to scroll up? => $aline = 0?
		if ($$pos > 1) {						# we can go up!
			if ($aline > 0) {				# stay on same page
				$aline--;
				$$pos--;
			}
			else {							# scroll up!
				$offset -= 17;				# next 17 QSOs from DB!
				$aline=16;					# start at lowest line
				$$pos--;
			}
		}
	} # key up

	elsif ($ch eq KEY_NPAGE) {				# scroll a full page down
		# can we scroll? are there more QSOs than fit on the current page?
		if (($$pos-$aline+17) < $count) {
			$offset += 17;					# scroll a page = 17 lines
			$$pos += (17- $aline);			# consider $aline!	
			$aline=0;
		}
	}

	elsif ($ch eq KEY_PPAGE) {				# scroll a full page up
		# can we scroll?
		if (($$pos-$aline) > 17) {
			$offset -= 17;					# scroll a page = 17 lines
			$$pos -= ($aline+1);				# consider $aline!	
			$aline=16;
		}
	}

	elsif ($ch eq KEY_HOME) {	# go to first qso
		$$pos = 1;
		$aline = 0;
		$offset = 0;
	}

	elsif ($ch eq KEY_END) {	# go to last qso
		$$pos = $count;
		$offset = int(($count-1) / 17) * 17;
		$aline = $count-1 - $offset;
	}
	elsif ($ch eq KEY_F(1)) {				# F1 -> Back to main menu
		return 'm';
	}
	
	elsif ($ch eq KEY_F(3)) {				# F3 -> Cancel search
		return 'c';
	}

	elsif ($ch eq KEY_F(12)) {				# F12 -> Exit, QRT
		endwin();
		exit;
	}

	elsif ($ch =~ /\s/) { 					# Chose this QSO for editing
		return $ret;
	}

} while ($goon);		# loop until goon = 0  (erm, it never changes?)
		
} # choseeditqso

##############################################################################
# &geteditqso;   Returns an array with the full information of QSO specified
# in $_[0]. Afterwards updates the inputfields.
##############################################################################

sub geteditqso {
my @qso;					# QSO array
my $q = $dbh->prepare("SELECT `CALL`, `DATE`, `T_ON`, `T_OFF`, `BAND`, `MODE`,
		`QTH`, `NAME`, `QSLS`, `QSLR`, `RSTS`, `RSTR`, `REM`, `PWR`, `DXCC`,
		`PFX`, `CONT`, `ITUZ`, `CQZ`, `QSLINFO`, `IOTA`, `STATE`, `NR`,
		`QSLRL`, `OPERATOR`, `GRID` FROM log_$mycall WHERE `NR`='$_[0]'");
$q->execute;
@qso = $q->fetchrow_array;
# proper format for the date (yyyy-mm-dd ->  ddmmyyyy)
$qso[1] = substr($qso[1],8,2).substr($qso[1],5,2).substr($qso[1],0,4);
# proper format for the times. hh:mm:ss -> hhmm
$qso[2] = substr($qso[2],0,2).substr($qso[2],3,2);
$qso[3] = substr($qso[3],0,2).substr($qso[3],3,2);

for (my $x=0;$x < 26;$x++) {				# iterate through all input windows 
	addstr(${$_[1]}[$x],0,0,$qso[$x]);		# add new value from @qso.
	refresh(${$_[1]}[$x]);
}

return @qso;
} # &geteditqso;

##############################################################################
# &editw  reads what the user types into a window, depending on $_[1],
# only numbers, callsign-characters, only letters or (almost) everything
# is allowed. new: as of 0.2.1 also a mode for reading [0-9.] (band info!)
# $_[2] contains the windownumber, $_[3] the reference to the
# QSO-array and $_[0] the reference to the Input-window-Array.
#
# $_[4] == 1 means overwrite
# $_[5] is the length of the field
#
#  (Note that this sub is mostly identical to &readw; except for F-key
#  handling)
#
# The things you enter via the keyboard will be checked and if they are
# matching the criterias of $_[1], it will be printed into the window and saved
# in @qso. Editing is possible with arrow keys, delete and backspace. 
# 
#
# If an F-Key is pressed, following things can happen: 
# 0. F1  --> Back to the main menu. $status = 2
# 1. F2  --> Current QSO is saved into the database,
#            delete @qso and the content of all inputfields.
# 2. F3  --> clears out the current @qso-array. New search.
# 3. F5  --> return 2 as next active window $aw. --> scroll list
#
# If a regular entry was made, the return value is 1, because we stay in active
# window 1
##############################################################################

sub editw {
	my $ch;										# the getchar() we read
	my $win = ${$_[0]}[$_[2]];					# get window to modify
	my $input = ${$_[3]}[$_[2]];				# stores what the user entered,
												# init from @qso.
	my $match = "[a-zA-Z0-9\/]";				# default match expression
	my $pos = 0;								# cursor position in the field
	my $strpos = $pos;							# cursor position in the string
	
	my $debug=0;

	my $ovr = $_[4];
	my $width = $_[5];

	# The string length $strlen is used to have entries larger than the width,
	# $_[2] is inspected to set the length according to SQL field length.
	my $strlen = $width;
	if ($_[2] == 0) { $strlen = 15; }	  # Call
	elsif ($_[2] == 5) { $strlen = 6; }	  # Mode
	elsif ($_[2] == 6) { $strlen = 15; }  # QTH
	elsif ($_[2] == 7) { $strlen = 15; }  # Name
	elsif ($_[2] == 10) { $strlen = 10; } # RSTs
	elsif ($_[2] == 11) { $strlen = 10; } # RSTr
	elsif ($_[2] == 12) { $strlen = 60; } # Remarks
	elsif ($_[2] == 13) { $strlen = 10; } # PWR
	
	move($win,0,0);							# move cursor to first position
	addstr($win,0,0, $input." "x80);		# pass $input to window,
	refresh($win);

	# For the date, time and band only figures are allowed, 
	# to achieve this, invoke editw with $_[1] = 1
	if ((defined $_[1]) && ($_[1] == "1")) {	# only numbers
		$match = '\d';							# set match expression
	}

	# For the QSL-status only letters are allowed, 
	# to achieve this, invoke editw with $_[1] = 2
	if ((defined $_[1]) && ($_[1] == "2")) {	# only letters
		$match = '[a-zA-Z]';					# set match expression
	}
	
	# For the Name, QTH and Remarks letters, figures and punctuation is allowed 
	# to achieve this, invoke editw with $_[1] = 3
	if ((defined $_[1]) && ($_[1] == "3")) {	 
		$match = '[\w\d!"$%&/()=?.,;:\-@ ]';		# set match expression
	}
	
	# Band info needs numbers and decimal point
	if ((defined $_[1]) && ($_[1] == "4")) {	 
		$match = '[0-9.]';							# set match expression
	}

	# Now the main loop starts which is waiting for any input from the keyboard
	# which is stored in $ch. If it is a valid character that matches $match,
	# it will be added to the string $input at the proper place.

	while (1) {									# loop infinitely
	
		$pos-- if ($pos == $width);				# keep cursor in window
		$strpos-- if ($strpos == $strlen);		# stop if string filled

		# If the cursor positions in the field and the string are not the same
		# then give only a partial view of the string.
		if ($strpos > $pos) {
			if (length($input) < $width) {
				$pos = $strpos;					# perfect, it fits again
			}
			addstr($win,0,0, substr($input, $strpos-$pos, )." "x80);
		}
		else {
			addstr($win,0,0, $input." "x80);	# pass $input to window,
		}										# delete all after $input.

		move ($win,0,$pos);						# move cursor to $pos
		refresh($win);							# show new window
		
		$ch = &getch2;							# wait for a character
	
		# We first check if it is a legal character of the specified $match,
		# if so, it will be added to the string (at the proper position!) 
		if (($ch =~ /^$match$/) &&
			 ((length($input) < $strlen) || ($strpos < $strlen && $ovr))
		) {
			unless ($_[1] == 3) {					# Unless Name, QTH, Remarks
				$ch =~ tr/[a-z]/[A-Z]/;				# make letters uppercase
			}
			# The new character will be added to $input at the right place.
			$strpos++;
			$pos++;
		
			if ($ovr) {
				$input = substr($input, 0, $strpos-1).$ch.substr($input,
						$strpos > length($input) ? $strpos-1 : $strpos, );
			}
			else {
				$input = substr($input, 0, $strpos-1).$ch.substr($input,
						$strpos-1, );
			}	
		} 
		
		# The l/r arrow keys change the position of the cursor to left or right
		# but only within the boundaries of $input.
		
		elsif ($ch eq KEY_LEFT) {					# arrow left was pressed	
			if ($pos > 0) { $pos-- }				# go left if possible
			if ($strpos > 0) { $strpos-- }
		}
		
		elsif ($ch eq KEY_RIGHT) {					# arrow right was pressed	
			if (($pos < length($input)) && ($pos < $width)) { $pos++ }
			if ($strpos < length($input)) {	$strpos++ }# go right if possible
		}

		elsif ($ch eq KEY_HOME) { # Pos1 key
			$pos = 0;
			$strpos = 0;
		}

		elsif ($ch eq KEY_END) { # End key
			$strpos = length($input);
			if ($strpos >= $strlen) {$strpos = $strlen-1;}
			$pos = $strpos;
			if ($pos >= $width) {$pos = $width-1;}
		}

		elsif (($ch eq KEY_DC) && ($strpos < length($input))) {	# Delete key
			$input = substr($input, 0, $strpos).substr($input, $strpos+1, );
		}
		
		# BACKSPACE. When pressing backspace, the character left of the cursor
		# is deleted, if it exists. For some reason, KEY_BACKSPACE only is true
		# when pressing CTL+H on my system (and all the others I tested); the
		# other tests lead to success, although it's probably less portable.
		# Found this solution in qe.pl by Wilbert Knol, ZL2BSJ. 

		elsif ((($ch eq KEY_BACKSPACE) || (ord($ch)==8) || (ord($ch)==0x7F)) 
				&& ($strpos > 0)) {
				$input = substr($input, 0, $strpos-1).substr($input, $strpos, );
				$strpos--;
				if ($pos > 0) { $pos--; }
		}
		
		# Space, Tab and Enter are the keys to go to the next field, except in
		# mode $_[1], where it was already caught in the first pattern match.
		# If space, tab or newline is found, the sub puts $input into the
		# proper place in the @qso array: ${$_[3]}[$_[2]];
		elsif ($ch =~ /^[ \t\n]$/) {				# Space, Tab or Newline
			${$_[3]}[$_[2]] = $input;				# save to @qso.return 0;
			return 1;
		}
		# If the pressed key was F2, we will save; that is, when the qso array
		# has sufficient information for a good QSO. Then the qso-array 
		# and the input fields are deleted.
		# This only works when $qso[22] = NR is not 0, which means that we
		# are not editing a QSO but getting search criteria.
		elsif  ($ch eq KEY_F(2) && ${$_[3]}[22]) {	# pressed F2 -> SAVE
			${$_[3]}[$_[2]] = $input;				# save field to @qso
			if (&updateqso(\@{$_[3]})) {			# save changes in @qso to DB
				&clearinputfields($_[0],2);			# clear input fields 0..22
				for (0 .. 25) {	${$_[3]}[$_] = ''; }	# clear @qso.
				return 0;							# success, leave editw
			}	# if no success, we continue in the loop.
		}

		# exit to the MAIN MENU
		elsif ($ch eq KEY_F(1)) {		
			return 'm';						# -> MENU!
		}

		# F3 clears the current QSO and returns to the CALL input field.
		elsif ($ch eq KEY_F(3)) {			# F3 pressed -> clear QSO
			for (0 .. 25) {					# iterate through windows 0-13
				addstr(@{$_[0]}[$_],0,0," "x80);	# clear it
				refresh(@{$_[0]}[$_]);
			}
			for (0 .. 25) {	${$_[3]}[$_] = ''; }	# clear @qso.
			return 0;						# return 0 (= go back to callsign) 
		}
		
		# F4 --> delete the QSO, but first ask if really wany to delete it.
		# Then delete it and clear all fields, like with F3.
		elsif  ($ch eq KEY_F(4) && ${$_[3]}[22]) {	# pressed F4 -> delete QSO
			my $answer = &askbox(7,0,4,80,'\w', 
			"Are you sure you want to delete the above QSO *permanently*?  (yes/no)", '');
			if ($answer eq 'm') { return 2 }		# menu
			elsif ($answer eq 'yes') {				# yes, delete! 
				$dbh->do("DELETE from log_$mycall WHERE NR='${$_[3]}[22]'");
				for (0 .. 25) {						# iterate through windows
					addstr(@{$_[0]}[$_],0,0," "x80);	# clear it
					refresh(@{$_[0]}[$_]);
				}
				for (0 .. 25) {	${$_[3]}[$_] = ''; }	# clear @qso.
				return 0;					# return 0 (= go back to callsign) 
			};
			
		}
		
		# F5 -> We want to search the DB for the given criteria...
		elsif ($ch eq KEY_F(5)) {		
			${$_[3]}[$_[2]] = $input;		# save field to @qso
			return 2;						 
		}

		# QUIT YFKlog
		elsif ($ch eq KEY_F(12)) {			# QUIT
			my $k='y';

			if ($askme && ${$_[3]}[0] ne '') {
				$k = &askconfirmation("Really quit YFKlog? [y/N]", 
					'y|n|\n|\s');
			}

			if ($k =~ /y/i) {
				endwin;					   	# Leave curses mode	
				exit;
			}
		}
	}
}  # &editw;


##############################################################################
# &updateqso  Updates the changes made to a QSO in the Search&Edit mode 
# into the database. The QSO is checked for validity of the fields.
##############################################################################

sub updateqso {
	my @qso = @{$_[0]};					# QSO array (0 .. 25)

	$qso[1] = substr($qso[1],0,8);		# cut date and times if needed
	$qso[2] = substr($qso[2],0,4);
	$qso[3] = substr($qso[3],0,4);

	# Now we have to check if it is a valid entry
	if ((&wpx($qso[0]) ) &&				# check for a valid callsign
		(length($qso[1]) == 8) &&		# check if date has proper length
		(substr($qso[1],0,2) < 32) &&	# sane day (of course not in all months)
		(substr($qso[1],2,2) < 13) &&	# valid month
		(substr($qso[1],4,) > 1900) &&	# :-)
		(length($qso[2]) == 4) &&		# check length of time on
		(substr($qso[2],0,2) < 24) &&	# valid hour in Time on
		(substr($qso[2],3,2) < 60) &&	# valid minute Time on
		($qso[4] ne '') &&				# band has some info
		($qso[5] ne '') &&				# mode has some info
		($qso[8] ne '') &&				# QSL sent
		($qso[9] ne '') && 				# QSL rxed
		($qso[16] =~ /^(AS|EU|AF|NA|SA|OC|AN)$/) &&	# continent
		(($qso[17] > 0) && ($qso[17] < 91)) &&		# ITU Zone
		(($qso[18] > 0) && ($qso[18] < 41)) &&		# CQ Zone
		($qso[20] =~ /(^$qso[16]-\d\d\d$)|(^$)/)&&	# valid or no IOTA
		($qso[21] =~ /^([A-Z]{1,2})?$/)				# "valid" state
		# RST, PWR not checked, will be 599 / 0 by default in the database,
		) {								# VALID ENTRY!  update into database

			$qso[1] =						# put date in YYYY-MM-DD format
			substr($qso[1],4,)."-".substr($qso[1],2,2)."-".substr($qso[1],0,2);
			$qso[2] = substr($qso[2],0,2).":".substr($qso[2],2,2).":00";# add seconds, :
			$qso[3] = substr($qso[3],0,2).":".substr($qso[3],2,2).":00";# add seconds, :

			# we are now ready to save the QSO
			$dbh->do("UPDATE log_$mycall SET `CALL`='$qso[0]', `DATE`='$qso[1]',
						`T_ON`='$qso[2]', `T_OFF`='$qso[3]', `BAND`='$qso[4]',
						`MODE`='$qso[5]', `QTH`='$qso[6]', `NAME`='$qso[7]',
						`QSLS`='$qso[8]', `QSLR`='$qso[9]', `RSTS`='$qso[10]',
						`RSTR`='$qso[11]', `REM`='$qso[12]', `PWR`='$qso[13]',
						`DXCC`='$qso[14]', `PFX`='$qso[15]', `CONT`='$qso[16]',
						`ITUZ`='$qso[17]', `CQZ`='$qso[18]',
						`QSLINFO`='$qso[19]', `IOTA`='$qso[20]',
						`STATE`='$qso[21]', `QSLRL`='$qso[23]', `OPERATOR` =
						'$qso[24]', `GRID` = '$qso[25]'
						WHERE `NR`='$qso[22]';");
			return 1;			# successfully saved
	}
	else {
			&finderror(@qso);
			return 0;			# No success, QSO not complete!
	}		
} # updateqso

##############################################################################
# checkdate  --  checks if $_[0] is a valid date in YYYY-MM-DD format
# returns 1 when valid.
##############################################################################

sub checkdate {
	my $date = $_[0];				# the date we want to check
	
	unless ($date =~ /^\d{4,4}-(\d\d)-(\d\d)$/) { return 0; }	# crude check 	
	# $1 is the month and $2 the day. We assume that any
	# year is valid.
	
	unless (($1 < 13) && ($1 != 0)) { return 0; }		# month 0 or 13+
	unless (($1 < 32) && ($1 != 0)) { return 0; }		# day 0 or 32+

	# OK, if we get until here, the date is valid.
	return 1;	
}



##############################################################################
# awards  -- gets a date-range (valid SQL string) and returns a hash, where
# keys are ham bands, as specified in $bands in the config file, and values are
# the numbers of $_[1] entities/zones etc worked on that band. 
# NOTE: hashes etc are called ..dxcc.. but of course the same is also used for
# WPX, CQZ, IOTA, STATEs
##############################################################################

sub awards {
	my $daterange = $_[0];						# SQL String with date range
	my $awardtype = $_[1];
	my @bands = split(/\s+/, $_[6]);	# Generate list of Bands for awards
	my @modes = split(/\s+/, $_[7]);	# modes to query
	my $custom = $_[8];	
	my %result;						# key=band, value=dxccs  WORKED 
	my %resultcp;					# key=band, value=dxccs CFMED paper QSLs
	my %resultcl;					# key=band, value=dxccs CFMED LOTW QSLs
	my %resultc;					# key=band, value=dxccs CFMED combined
	my %abdxcc;						# allband DXCCs combined. 'dxcc'->0/1
	my %abdxcccp;					# same, but QSL received/confirmed 
	my %abdxcccl;					# same, but LOTW received/confirmed 
	my %abdxccc;					# same, but QSL|LOTW received/confirmed 
	my %sumdxcc;					# "DL"->"160 20 15 10"  worked
	my %sumdxccc;					# "DL"->"160"  cfmed combined
	my %sumdxcccp;					# "DL"->"160"  cfmed paper
	my %sumdxcccl;					# "DL"->"160"  cfmed lotw

	foreach (@bands) {				# reset results to 0 for all bands
		$result{$_} = 0;
		$resultc{$_} = 0;
		$resultcp{$_} = 0;
		$resultcl{$_} = 0;
	}

	my $rband = 'BAND';
	if ($db ne 'sqlite') {
		$rband = 'round(BAND,4)';
	}

	# create mode string for the IN statement
	my $modes = "'" . join("','", @modes) . "'";

foreach my $band (@bands) {
	my %dxccc;			#  hash to check if the entity is new and CONFIRMED
	my %dxcccp;			#  hash to check if the entity is new and paper QSLed
	my %dxcccl;			#  hash to check if the entity is new and LOTW QSLed
	my %dxcc;			#  hash to check if the current entity is new.

	my ($sth, $dx, $qslr, $qslrl);
	if ($custom) {
		$sth = $dbh->prepare("SELECT REM, QSLR, QSLRL  FROM
				log_$mycall WHERE $rband='$band' AND MODE IN ($modes)
				AND $daterange AND REM LIKE \"%$custom:%\"");
		$sth->execute() or die "Error, couldn't select ($custom)!";
		$sth->bind_columns(\$dx, \$qslr, \$qslrl);
	}
	else {
		$sth = $dbh->prepare("SELECT $awardtype, QSLR, QSLRL  FROM
				log_$mycall WHERE $rband='$band' AND $daterange
				AND MODE IN ($modes)");

		$sth->execute() or die "Error selecting $awardtype from log_$mycall!";
		$sth->bind_columns(\$dx,\$qslr, \$qslrl);
	}


	while ($sth->fetch()) {						# go through all QSOs
		if ($custom) {
			if ($dx =~ /$custom:(.+?)(\s|$)/) {		# $dx == remarks field here
				$dx = $1;
			}
			else {
				next;
			}
		}

		if ($dx eq '') { next; }				# no entry for this award type
		$dx =~ s/[A-Za-z]{2}$// if ($awardtype eq 'GRID');
		
		unless (defined($dxcc{$dx})) {			# DXCC not in hash -> new DXCC
			$result{$band}++;					# increase counter
			$dxcc{$dx} = 1;						# mark as worked in dxcc hash
			$sumdxcc{$dx} .= $band.' ';			# save band for overall stats
			unless (defined($abdxcc{$dx})) {	# new DXCC over all bands?
				$abdxcc{$dx} = 1;				# mark it worked
			}
		}

		# Paper QSL

		if (!defined($dxcccp{$dx}) && ($qslr eq 'Y')) {	# paper QSL-received
			$resultcp{$band}++;							# increase counter
			$dxcccp{$dx} =1;
			$sumdxcccp{$dx} .= $band.' ';		# save band for overall stats
			unless (defined($abdxcccp{$dx})) {	# new DXCC overall bands cfmed
				$abdxcccp{$dx} = 1;				# mark it confirmed!
			}
		}

		# LOTW QSL

		if (!defined($dxcccl{$dx}) && ($qslrl eq 'Y')) {	# LOTW QSL-received
			$resultcl{$band}++;							# increase counter
			$dxcccl{$dx} =1;
			$sumdxcccl{$dx} .= $band.' ';		# save band for overall stats
			unless (defined($abdxcccl{$dx})) {	# new DXCC overall bands cfmed
				$abdxcccl{$dx} = 1;				# mark it confirmed!
			}
		}

		# Combined

		if (!defined($dxccc{$dx}) && (($qslr eq 'Y')||($qslrl eq 'Y'))) {
			$resultc{$band}++;
			$dxccc{$dx} =1;
			$sumdxccc{$dx} .= $band.' ';
			unless (defined($abdxccc{$dx})) {
				$abdxccc{$dx} = 1;
			}
		}


	}
} # foreach band

# now include the overall number into the result hash
$result{'All'} = scalar(keys(%abdxcc));
$resultc{'All'} = scalar(keys(%abdxccc));
$resultcp{'All'} = scalar(keys(%abdxcccp));
$resultcl{'All'} = scalar(keys(%abdxcccl));

# Create a HTML-output of the full award score.
open HTML, ">$directory/$mycall-$awardtype.html";

# Generate Header and Table header
my $string = "$awardtype Status for ". uc(join('/', split(/_/, $mycall))) .
	" in " . join(', ', @modes);
print HTML "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">";
print HTML "<html>\n<head>\n<title>" . $string . "</title>\n</head>\n";
print HTML "<body>\n<h1>" . $string . "</h1>\n";
print HTML "Produced with YFKlog.\n<table border=1 summary=\"$awardtype\">
<tr><th>$awardtype</th>";

# Table heades for each band....
foreach my $band (@bands) {
	print HTML "<th> $band </th>";
}
print HTML "</tr>\n";

# For each of the worked DXCCs add W, C or nothing..
foreach my $key (sort keys %sumdxcc) {
	$string = "<tr><td bgcolor=\"#FFFFFF\"><strong>$key</strong></td>";

	$sumdxccc{$key} .= '';						# to make it defined for sure
	$sumdxcccp{$key} .= '';						# to make it defined for sure
	$sumdxcccl{$key} .= '';						# to make it defined for sure

	# qsl state: green - all qsl, yellow - band missing, red - all missing
	my $qsl_state = '';
	# TODO Maybe use stuff like "CL"?
	# now create a table cell for each band. either empty (not worked), W or C
	foreach my $band (@bands) {
		if ($sumdxcccp{$key} =~ /(^| )$band( |$)/) {		# band w/paper QSL
			$string .= "<td> C </td>";
			if ( $qsl_state eq '' ) {$qsl_state = "green";}
			elsif ( $qsl_state eq "red" ) {$qsl_state = "yellow";}
		}
		elsif ($sumdxcccl{$key} =~ /(^| )$band( |$)/) {		# band w/LOTW QSL
			$string .= "<td> L </td>";
			if ( $qsl_state eq '' ) {$qsl_state = "green";}
			elsif ( $qsl_state eq "red" ) {$qsl_state = "yellow";}
		}
		elsif ($sumdxcc{$key} =~/(^| )$band( |$)/) {		# band worked!
			$string .= "<td> W </td>";
			if ( $qsl_state eq '' ) {$qsl_state = "red";}
			elsif ( $qsl_state eq "green" ) {$qsl_state = "yellow";}
		}
		else {											# not worked
			$string .= "<td>&nbsp;</td>";
		}
	}	
	if ( $qsl_state eq "green" ) {$string =~ s/#FFFFFF/#00FF00/;}
	elsif ( $qsl_state eq "yellow" ) {$string =~ s/#FFFFFF/#FFFF00/;}
	elsif ( $qsl_state eq "red" ) {$string =~ s/#FFFFFF/#FF0000/;}

print HTML $string."\n";
}

# Summary line for WORKED
print HTML "<tr><td>wkd: $result{'All'} </td>";
foreach my $band (@bands) {
	print HTML "<td> $result{$band} </td>"
}
print HTML "</tr>\n";

# Summary line for CONFIRMED overall
print HTML "<tr><td>cfm: $resultc{'All'} </td>";
foreach my $band (@bands) {
	print HTML "<td> $resultc{$band} </td>"
}
print HTML "</tr>\n";

# Summary line for CONFIRMED QSL
print HTML "<tr><td>QSL: $resultcp{'All'} </td>";
foreach my $band (@bands) {
	print HTML "<td> $resultcp{$band} </td>"
}

print HTML "</tr>\n";
# Summary line for CONFIRMED LOTW
print HTML "<tr><td>LOTW: $resultcl{'All'} </td>";
foreach my $band (@bands) {
	print HTML "<td> $resultcl{$band} </td>"
}
print HTML "</tr>\n</table>\n</body>\n</html>\n";

close HTML;


# Return the local hashes to the main program.
%{$_[2]} = %result;
%{$_[3]} = %resultc;
%{$_[4]} = %resultcp;
%{$_[5]} = %resultcl;

return 0;
}

###############################################################################
# statistics  -- create  QSO by BAND, QSO by continent statistics 
###############################################################################

sub statistics {
	my $type = $_[0];			# Band, Continent...?
	my $wmain = ${$_[1]};		# window
    my $daterange = $_[2];		# SQL String with date range
	my @bands = split(/\s+/, $_[3]);
	my @modes = split(/\s+/, $_[4]);

	my %result;					# '160'(m) -> '666' (QSOs);
								# or 'EU' -> '3242', 'AF' -> '234'...
	my $maxqsos=0;				# band/continent with max QSOs
	my $totalqsos=0;			# number of total QSOs for percentage
	
	# create strings for the IN statement
	my $bands = join(',', @bands);
	my $modes = "'" . join("','", @modes) . "'";

	my $sth = $dbh->prepare("SELECT $type FROM log_$mycall WHERE $daterange
					and BAND in ($bands) and MODE in ($modes)");
	$sth->execute();
	my $type_item;
	$sth->bind_columns(\$type_item);	
	while ($sth->fetch()) {						# go through ALL QSOs
		$result{$type_item}++;					# Add QSO to the item...
	}	

	# Create a HTML-output of the full award score.
	open HTML, ">$directory/$mycall-$type.html";
	
	# Generate Header and Table header
	my $string = "$type Statistics for ". uc(join('/', split(/_/, $mycall))) .
		" in " . join(', ', @modes);
	print HTML "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\">";
	print HTML "<html>\n<head>\n<title>" . $string . "</title>\n</head>\n";
	print HTML "<body>\n<h1>" . $string . "</h1>\n";
	print HTML "Produced with YFKlog.\n 
	<table border=\"0\" summary=\"$type\">\n";
	
	# Check nr of total QSOs and band with most QSOs.
	foreach my $key (keys %result) {
		if (($result{$key} > $maxqsos)) {
			$maxqsos = $result{$key};
		}
		$totalqsos += $result{$key};
	}
		
	# Now we know the maximum number of QSOs, so we can normalize the
	# results and make a nice printout plus HTML code.
	my $y = 5;
	foreach my $key (sort {if($a=~/^\d+$/){$a <=> $b} else{$a cmp $b}} 
			keys %result)	{
		$y++;
		addstr($wmain, $y, 10, "$key ");
	  	attron($wmain, COLOR_PAIR(2));
		print HTML "<tr><td>$key</td><td>";			
		my $len = int(($result{$key}/$maxqsos)*40);	# length of bar
		if (($len == "0") and ($result{$key} > 0)) {	# at least one
				$len = 1;								# if QSO was made
	   	}
		print HTML "<img src=\"p.png\" width=".(int(($result{$key}/$maxqsos)
				*400)+1)." height=20 alt=bar></td>";
		addstr($wmain, $y, 15, " "x$len);				# print bar
	  	attron($wmain, COLOR_PAIR(4));
		my $percent = sprintf("%.2f", 100*$result{$key}/$totalqsos);
		addstr($wmain, $y, 16+$len, 					# Add nr,percentage 
				$result{$key}.' = '.$percent.'%' );
		print HTML "<td>$result{$key} = $percent%</td></tr>\n";
	}
		print HTML "<tr><th>Total:</th><td></td><th>$totalqsos = 100%</th>\n";
		print HTML "</tr>\n</table>\n</body>\n</html>\n";
		close HTML;
	return 0;
}




###############################################################################
# editdb  -- Edits the entry (NAME/QTH) of a call ($_[0]) in the "calls" 
# database. $_[1] -> main window
# Returns: 12  when properly saved/edited
#           2  when pressing F1
###############################################################################

sub editdb {
	my $call = $_[0];
	my $win = ${$_[1]};
	my @nameqth = ('','');
	my @wi;				# Windows to edit Name/QTH inside...
	my $stat;			# Status   1: edit name  2: edit QTH
    addstr($win,0,0, ' 'x(80*22));            # blue background
	
	my $sth = $dbh->prepare("SELECT `NAME`, `QTH` FROM `calls` WHERE `CALL`=
			'$call'");
	$sth->execute();
	@nameqth  = $sth->fetchrow_array();
	
	unless (defined($nameqth[0]) || defined($nameqth[1])) {
		addstr($win, 10, 23, "$call does not exist in the database.");
		curs_set(0);
    	refresh($win);
		getch;
		curs_set(1);
		return 12;
	}
	addstr($win, 5, 23, "Editing database information for $call");
	addstr($win, 8, 30, "Name:");
	addstr($win, 9, 30, "QTH:");
    refresh($win);
	
	# Create windows to be be used as editor-windows.
	$wi[0] = &makewindow(1,8,9,38,5);
	$wi[1] = &makewindow(1,13,10,38,5);
	my $wi = \@wi;							# reference to windows.
	addstr($wi[0], 0,0, $nameqth[0]." "x80);
	addstr($wi[1], 0,0, $nameqth[1]." "x80);
	refresh($wi[0]);refresh($wi[1]);

	while (1) {		# keep editing
			$stat = &editdbw($wi, 0, 0, \@nameqth);		# EDIT name window
			if ($stat == 1) { 			# main menu
				return 2;				# $status = 2 -> menu.
			}
			elsif ($stat == 2) {		# &savedbedit
				&savedbedit(0,$call,@nameqth);	# save
				return 12;
			}
			elsif ($stat == 3) {
				&savedbedit(1, $call);			# delete
				return 12;
			}
			$stat = &editdbw($wi, 0, 1, \@nameqth);		# EDIT QSO window
			if ($stat == 1) { 			# main menu
				return 2;				# $status = 2 -> menu.
			}
			elsif ($stat == 2) {		# &savedbedit
				&savedbedit(0,$call,@nameqth);	# save
				return 12;
			}
			elsif ($stat == 3) {
				&savedbedit(1, $call);			# delete
				return 12;
			}
	}
	
} # end of editdb

##############################################################################
# &editdbw   reading fields/windows for editing the "calls" database.
#
#  (Note: this sub is mostly identical to &readw; except for F-key
#  handling)
#
# If an F-Key is pressed, following things can happen: 
# 0. F1  --> Back to the main menu.                       return 1
# 1. F2  --> Current Name/QTH is saved into the database,        2
# 2. F3  --> Deletes the current callsign from the db            3
##############################################################################

sub editdbw {
	my $ch;										# the getchar() we read
	my $win = ${$_[0]}[$_[2]];					# get window to modify
	my $input = ${$_[3]}[$_[2]];				# stores what the user entered,
												# init from @qso.
	my $match = '[\w\d!"$%&/()=?.,;:\-@ ]';		# default match expression
	my $pos = 0;								# cursor position in the string
	move($win,0,0);							# move cursor to first position

	# Now the main loop starts which is waiting for any input from the keyboard
	# which is stored in $ch. If it is a valid character that matches $match,
	# it will be added to the string $input at the proper place.
	#
	# If an arrow key LEFT or RIGHT is entered, the position within the string
	# $input will be changed, considering that it can only be within
	# 0..length($input-1). The position is stored in $pos.
	# 
	# If a control character like a F-Key, Enter or Tab is found, the sub
	# exists and $input is written to @qso, with attached information on which
	# key was pressed, as ||F1 .. ||F10. This way we can switch to the proper
	# window when we get back into the main loop.

	while (1) {										# loop infinitely
		addstr($win,0,0, $input." "x80);		# pass $input to window,
												# delete all after $input.
		move ($win,0,$pos);						# move cursor to $pos
		refresh($win);							# show new window
		
		$ch = &getch2();							# wait for a character
	

		# We first check if it is a legal character of the specified $match,
		# if so, it will be added to the string (at the proper position!) 
		if (($ch =~ /^$match$/)) {					# check if it's "legal"

			# The new character will be added to $input at the right place.
			$pos++;
			$input = substr($input, 0, $pos-1).$ch.substr($input, $pos-1, );
		}

		# The l/r arrow keys change the position of the cursor to left or right
		# but only within the boundaries of $input.
		
		elsif ($ch eq KEY_LEFT) {					# arrow left was pressed	
			if ($pos > 0) { $pos-- }				# go left if possible
		}
		
		elsif ($ch eq KEY_RIGHT) {					# arrow right was pressed	
			if ($pos < length($input)) { $pos++ }	# go right if possible
		}

		elsif (($ch eq KEY_DC) && ($pos < length($input))) {	# Delete key
			$input = substr($input, 0, $pos).substr($input, $pos+1, );
		}

		elsif ((($ch eq KEY_BACKSPACE) || (ord($ch)==8) || (ord($ch)==0x7F)) 
				&& ($pos > 0)) {
				$input = substr($input, 0, $pos-1).substr($input, $pos, );
				$pos--;
		}

		# Tab and Enter are the keys to go to the next field, 
		# if tab or newline is found, the sub puts $input into the
		# proper place in the @nameqth array: ${$_[3]}[$_[2]];
		elsif ($ch =~ /^[\t\n]$/) {					# Space, Tab or Newline
			${$_[3]}[$_[2]] = $input;				# save , return 1
			return 0;
		}
		# F2 -> save the entry. no validation check made.
		elsif  ($ch eq KEY_F(2)) {					# pressed F2 -> SAVE
			${$_[3]}[$_[2]] = $input;				# save field to @nameqth
			return 2;
		}

		# exit to the MAIN MENU
		elsif ($ch eq KEY_F(1)) {		
			return 1;						# -> MENU!
		}

		# F3 deletes the current db entry
		elsif ($ch eq KEY_F(3)) {			# F3 pressed -> delete
			return 3;
		}
	
		# QUIT YFKlog
		elsif ($ch eq KEY_F(12)) {			# QUIT
			endwin;							# Leave curses mode	
			exit;
		}
	}
}  # &editdbw;


###############################################################################
# savedbedit   --   Saves changes to the "calls" database (name/QTH)
# &savedbedit(0,$call,@nameqth) --> save it
# &savedbedit(1,$call) --> delete entry with "call".
###############################################################################
sub savedbedit {
	if ($_[0] == 1) {
		$dbh->do("delete from `calls` where `CALL` = '$_[1]'")
	}
	if ($_[0] == 0) {
		$dbh->do("update `calls` set `name`='$_[2]', `QTH`='$_[3]' where `call`='$_[1]' ");
	}
}

################################################################################
# lotwimport   --   Reads a lotwreport.adi from the ARRL Logbook Of The World
# and updates the appropriate logbooks. YFKlog has a special database field
# 'QSLRL' for LOTW QSLs. In ADIF-Export, this field will be merged with the
# normal QSLR field. 
# Depending on the lotwdetails variable (in .yfklog), either only the QSL
# status will be updated, or also CQ-Zone, IOTA, STATE etc..
################################################################################

sub lotwimport {
	my ($filename, $win) = @_;
	my $logs='';
	my $line;
	my ($nr, $match, $updated, $nf) = (0,0,0,0);

	my ($stncall, $call, $band, $mode, $qsodate, $time, $qslr); 	# standard
	my ($cont, $cqz, $ituz, $iota, $grid, $state, $cnty);			# details
	# TBD DXCC with ARRL number...

	addstr($win,0,0," "x80);
	refresh($win);

	# Check for which calls we can update the database:
	my $showtables = "SHOW TABLES";

	if ($db  eq 'sqlite') {
		$showtables = "select name from sqlite_master where type='table';"
	}

	my $gl = $dbh->prepare($showtables);
	$gl->execute();

	while (my $x = $gl->fetchrow_array()) {
		if ($x =~ /log_/) { $logs .= "$x "; }
	}
	
	$logs =~ s/log_//g;
	$logs =~ s#_#/#g;		# there are now some tables which are not logs,
	$logs = uc($logs);		# but they will not likely match a callsign...

	open LOG, "$filename";

	$filename =~ /([^\/]+)$/;
	my $basename = $1;
	open ERROR, ">/tmp/$mycall-LOTW-update-from-$basename.err";

	# Only continue if real lotwreport file.. 
	while ($line = <LOG>) {
		last if ($line =~ /ARRL Logbook of the World Status Report/) 
	}

	while ($line = <LOG>) {
		if ($line =~ /STATION_CALLSIGN:\d+>([A-Z0-9\/]+)/) {
			$stncall = $1;
		}
		elsif ($line =~ /CALL:\d+>([A-Z0-9\/]+)/) {
			$call = $1;
		}
		elsif ($line =~ /BAND:\d+>(\w+)/) {
			$band = $1;
		}
		elsif ($line =~ /MODE:\d+>(\w+)/) {
			$mode = $1;
		}
		elsif ($line =~ /QSO_DATE:\d+>(\d+)/) {
			$qsodate = $1;
		}
		elsif ($line =~ /TIME_ON:\d+>(\d+)/) {
			$time = $1;
		}
		elsif ($line =~ /QSL_RCVD:\d+>([A-Z]+)/) {
			$qslr = $1;
		}
		elsif ($line =~ /CONT:\d+>([A-Z]+)/) {
			$cont = $1;
		}
		elsif ($line =~ /CQZ:\d+>(\d+)/) {
			$cqz= $1;
		}
		elsif ($line =~ /ITUZ:\d+>(\d+)/) {
			$ituz= $1;
		}
		elsif ($line =~ /IOTA:\d+>([A-Z0-9-]+)/) {
			$iota= $1;
		}
		elsif ($line =~ /GRIDSQUARE:\d+>(\w+)/) {
			$grid= $1;
		}
		elsif ($line =~ /STATE:\d+>(\w+)/) {
			$state= $1;
		}
		elsif ($line =~ /<eor>/) {
			addstr($win,0,0,"Updating record $nr...   ") if ($nr =~ /0$/);
		   	refresh($win);
			$nr++;
			if ($qslr =~ /Y/) {						# update
				# check if a log table exists..
				unless($logs =~ /(^| )$stncall( |$)/) {
					$nf++;
					print ERROR "$stncall QSO with $call at $qsodate $time".
							" on $band / $mode not found in log!\n";
				}
				else {
					my $update = "QSLRL='Y'";

					if ($lotwdetails) {
						$update .= ", CONT='$cont'" if $cont;
						$update .= ", CQZ='$cqz'" if $cqz;
						$update .= ", ITUZ='$ituz'" if $ituz;
						$update .= ", IOTA='$iota'" if $iota;
						$update .= ", GRID='$grid'" if $grid;	
						$update .= ", STATE='$state'" if $state;
					}


					if ($band =~ /([0-9.]+)cm$/i) {
						$band = $1/100;				# cm -> m
					}
					else {
						substr($band, -1,) = '';	# remove m
					}


					$qsodate =~ s/(\d{4})(\d{2})(\d{2})/$1-$2-$3/g;
					$time =~ s/(\d{2})(\d{2})(\d{2})/$1:$2/g;		# cut secs
					$stncall =~ s#/#_#g; $stncall = lc($stncall);

					my $rband = 'round(`band`, 4)';
					if ($db eq 'sqlite') { $rband = 'band'; };

					my $sth = $dbh->prepare("update log_$stncall set $update
					where `call`='$call' and $rband = '$band' and
					mode='$mode' and date='$qsodate' and t_on like '$time%';");

					my $rows = $sth->execute();
		
					if ($rows == 0) {
						print ERROR "$stncall QSO with $call at $qsodate $time".
							" on $band / $mode not found in log!\n";
						$nf++;
					}
					else {
						$match++;
					}

				}
			}
			$stncall=$call=$band=$mode=$qsodate=$time=$qslr=
			$cont=$cqz=$ituz=$iota=$grid=$state=$cnty='';	# ;-)
		}

	} #while ($line ..)

close ERROR;

return ($nr, $match, $nf);
}

###############################################################################
# databaseupgrade -- check for the YFKlog version which created the database.
#
# 1) Check for the existence of the table "YFKconfig". If existant,
#    read version number from it and update accordingly.
# 2) If the table "YFKconfig" doesn't exist, create it, and do all updates from
#    version 0.1.0 to the current one
###############################################################################

sub databaseupgrade {
my $oldversion = "10";				# We assume the worst case, version 0.1.0
my $version = $main::yfkver;
$version =~ s/[.]//g;

if ($_[0] == 1) {					# only if called during normal run..
	erase();
	move(0,0);						# for optical reasons.
	printw "Reinitializing database...\n";
}


if ($db eq 'sqlite') { $oldversion = 25; }

printw "\n\nUsing '$dbname'\@'$db'. Looking for neccessary databases...\n";

# YFKconfig
unless (&tableexists('YFKconfig')) {
	$dbh->do("create table YFKconfig 
					( `Name` varchar(50), `Value` varchar(50));") or die
			"Unable to create Table YFKconfig!";

	$dbh->do("insert into YFKconfig (`Name`, `Value`) VALUES 
					('version', '0');") or die "Unable to set".
											"version in table YFKconfig!";
}
else {
	printw "'YFKconfig' table found...\n";
}

# CALLS
unless (&tableexists('calls')) {
	open CALLS, "$prefix/share/yfklog/db_calls.sql";
	my @calls = <CALLS>;
	close CALLS;

	$dbh->do("@calls") or die 
					"Couldn't create calls table from db_calls.sql";
	printw "Created 'calls' table from db_calls.sql\n";
}
else {
	printw "'calls' table found...\n";
}

# CLUBS

unless (&tableexists('clubs')) {
	open CLUBS, "$prefix/share/yfklog/db_clubs.sql";
	my @clubs = <CLUBS>;
	close CLUBS;

	$dbh->do("@clubs") or die 
					"Couldn't create clubs table from db_clubs.sql";
	printw "Created 'clubs' table from db_clubs.sql\n";
}
else {
	printw "'clubs' table found...\n";
}

# MYCALL

unless (&tableexists("log_$mycall")) {
	my $logtable = "$prefix/share/yfklog/db_log.sql";

	if ($db eq 'sqlite') { $logtable = "$prefix/share/yfklog/db_log.sqlite"; }

	open LOG, $logtable;
	my @log = <LOG>;
	close LOG;

	my $log = "@log";
	$log =~ s/MYCALL/$mycall/g;

	$dbh->do($log) or die 
					"Couldn't create log table $mycall from $logtable";
	printw "Created log table $mycall from $logtable\n";
}
else {
	printw "Log table $mycall found...\n";
}

# Get a list of all logs....

my @logs;

my $showtables = "SHOW TABLES;";

if ($db eq 'sqlite') {
	$showtables = "select name from sqlite_master where type='table';";
}

my $gl = $dbh->prepare($showtables);
$gl->execute();

my $l;
while($l = $gl->fetchrow_array()) {
	if ($l =~ /log_/) {
			push @logs, $l;
	}
}


printw "\nChecking Database version.\n";

if (&tableexists('YFKconfig')) {
	my $bla = $dbh->prepare("SELECT Value from YFKconfig where
												Name = 'version'");
	$bla->execute;
	$oldversion = $bla->fetchrow_array();
	printw "DB: $oldversion\n";
	$oldversion =~ s/[.]//g;
}

if ($db eq 'sqlite') { $oldversion = 25 unless $oldversion > 25};

if ($oldversion < 23) {			# Update to 0.2.3 database
	printw "\nUpdating the Database from Version < 0.2.3.\n\nWhen updating from YFKlog 0.1.0, run 'yfk-fixdxcc.pl'.\n";


	foreach $l (@logs) {
		$dbh->do("ALTER TABLE $l MODIFY BAND FLOAT;");
		printw "Updated table $l: band->float";

		# MySQL 4 doesn't allow 'WHERE Field=....' yet :-(
		my $res = $dbh->prepare("SHOW COLUMNS from $l;");

		$res->execute();

		my $hasqslrl=0;
		while (my @tmp = $res->fetchrow_array()) {
			if ($tmp[0] =~ /QSLRL/i) {
				$hasqslrl=1;
				last;
			}
		}

		unless ($hasqslrl) {
			$dbh->do("alter table $l add qslrl char(1) not
												null default 'N';") or die
										"$hasqslrl $l";
			printw ", qslrl added";
		}

		printw ".\n";
	} #foreach log

	# update config table


	printw "Database upgraded to Version 0.2.3 now.\n";

	$oldversion = 23;

} # here we are up to date with YFKlog 0.2.3.

# Upgrade from Version 0.2.3 to 0.2.4. Nothing really to do.
if ($oldversion < 24) {
	$dbh->do("update YFKconfig set `Value` = '0.2.4' where
	`Name` = 'version';") or die "Unable to set version in table YFKconfig!";
	printw "Updated DB from 0.2.3 to 0.2.4.\n";
}

# Upgrade from Version 0.2.4 to 0.2.5. Add fields GRID and OPERATOR.
if ($oldversion < 25) {
	foreach $l (@logs) {
		my $res = $dbh->prepare("SHOW COLUMNS from $l;");
		$res->execute();
		my $hasgrid=0;
		my $hasoperator=0;
		while (my @tmp = $res->fetchrow_array()) {
			if ($tmp[0] =~ /OPERATOR/i) {
				$hasoperator = 1;
			}
			elsif ($tmp[0] =~ /GRID/i) {
				$hasgrid = 1;
			}
		}

		printw "Added fields: ";
		unless ($hasgrid) {
			$dbh->do("alter table $l add `GRID` varchar(6) not
				null default '';") or die "Failed to add GRID to table $l";
			printw " GRID ";
		}
		unless ($hasoperator) {
			$dbh->do("alter table $l add `OPERATOR` varchar(8) not
				null default '';") or die "Failed to add OPERATOR to table $l";
			printw " OPERATOR ";
		}
		printw " (none) " unless ($hasgrid || $hasoperator);
		printw "to $l\n";

	} 
	$dbh->do("update YFKconfig set `Value` = '0.2.5' where
	`Name` = 'version';") or die "Unable to set version in table YFKconfig!";
	printw "Updated DB from 0.2.4 to 0.2.5.\n";
}

# Upgrade from Version 0.2.5 to 0.3.5. Nothing really to do.
if ($oldversion < 35) {
	$dbh->do("update YFKconfig set `Value` = '0.3.5' where
	`Name` = 'version';") or die "Unable to set version in table YFKconfig!";
	printw "Updated DB to 0.3.5.\n";
}

printw "All up to date!\n\nPress any key to continue.\n";
refresh();

}



###############################################################################
# xplanet - generate a marker file for xplanet with all worked and needed DXCC
# countries. Worked = green, Needed = Red.
#
# Uses cty.dat to find available DXCC countries, then retrieves all worked ones
# from the database.
###############################################################################

sub xplanet {
	my $modes = "'" . join("','", split(/\s+/, $_[0])) . "'"; # modes to query
	my $line;
	my %dxcc;		# keys: DXCCs, Values: Green=worked, Red=needed
	my %lat;		# latitides and longitudes for each DXCC
	my %lon;
	my ($pfx, $lat, $lon);
	
	open CTY, "$prefix/share/yfklog/cty.dat" or die "Cannot find cty.dat!\n";
	while ($line = <CTY>) {
		chomp($line);
		next unless ($line =~ /^[A-Z]/);			# no data lines pse
		$line =~ s/ //g;							# remove spaces
		
		$pfx = (split(/:/, $line))[-1];			# DXCC prefix
		$lat = (split(/:/, $line))[-4];				# 
		$lon  = (split(/:/, $line))[-3];			#
	

		next if (!defined($pfx) || ($pfx =~ /[*]/));	# remove WAEs
		$pfx =~ s/\///g;							# remove /
		
		$lat{$pfx} = $lat;
		$lon{$pfx} = $lon;
		$dxcc{$pfx} = "Red";
	}
	close CTY;

	my $sth = $dbh->prepare("SELECT DXCC, QSLR, QSLRL FROM log_$mycall
							WHERE MODE in ($modes)");
	$sth->execute() or die "Execute failed!";
	
	my ($dx,$qslr, $qslrl);
	$sth->bind_columns(\$dx,\$qslr, \$qslrl) or die "Bind failed!";

	while ($sth->fetch()) {
		next unless (defined($dxcc{$dx}));		# just in case..
		next if ($dxcc{$dx} eq 'Green');		# already confirmed
		if (($qslr eq 'Y') || ($qslrl eq 'Y')) {
			$dxcc{$dx} = 'Green';
		}
		else {
			$dxcc{$dx} = 'Yellow';
		}
	}

	open EARTH, ">$directory/$mycall-earth";

	# special sorting to put green on top of yellow and red
	foreach (sort {if ($dxcc{$a} eq 'Red') {return -1;}
				   elsif ($dxcc{$b} eq 'Red') {return 1;}
				   else {return $dxcc{$b} cmp $dxcc{$a}}} keys %dxcc) {
		print EARTH $lat{$_}." ".(-1*$lon{$_}).' "'.$_.'" color='.$dxcc{$_}."\n";
	}
	close EARTH;

}

###############################################################################
# queryrig, queries Hamlib $rig frequency and mode. 
# $_[0,1] are references to the band/mode respectively.
# as of 0.3.6, hamlib's rigctld is used.
###############################################################################

sub queryrig {

	my ($freq, $mode);

	my $sock = new IO::Socket::INET ( PeerAddr => 'localhost', 
			PeerPort => $hamlibtcpport, Proto => 'tcp');

	return 0 unless $sock;

	print $sock "f\n";
	$freq = <$sock>;
	chomp($freq);
	
	print $sock "m\n";
	$mode = <$sock>;
	chomp($mode);

	if ($mode eq 'CWR') {
		$mode = 'CW';
	}
	elsif ($mode eq 'USB' || $mode eq 'LSB') {
		$mode = 'SSB';
	}

	$freq = &freq2band($freq/1000);
			
	${$_[0]} = $freq;
	${$_[1]} = $mode;

	return 1;		# success
}


###############################################################################
# tableexists. returns 1 if the table in $_[0] exists, 0 if not.
###############################################################################

sub tableexists {
	my $table = shift;

	my $showtables = "SHOW TABLES FROM $dbname LIKE '$table';";

	if ($db eq 'sqlite') {
		$showtables = "select count(*) from sqlite_master where type='table' and ".
										"name = '$table';";
	}

	my $exists = $dbh->prepare($showtables) or die "Error!";
	$exists->execute();

	if ($exists->fetchrow_array()) {
		return 1;
	}
	else {
		return 0;
	}
} #tableexists

###############################################################################
# changeconfig  -- replaces $_[0] in the config file with $_[1]
###############################################################################

sub changeconfig {
	open CONFIG, "$ENV{HOME}/.yfklog/config" or die "Can't find config file!\n";
	my @cfg = <CONFIG>;
	my $changed=0;
	close CONFIG;

	foreach (@cfg) {
		if ($_ =~ s/$_[0]/$_[1]/i) {
			$changed = 1;
		}
	}

	# If the value wasn't defined in the config file before, it must be added.

	unless ($changed) {	
		push(@cfg, "# Added by YFKlog:\n");
		push(@cfg, $_[1]."\n");
	}

	open CONFIG, ">$ENV{HOME}/.yfklog/config" or die "Can't write to config!\n";
	print CONFIG @cfg;
	close CONFIG;

}

###############################################################################
# jumpfield -- determines the next field number. As of 0.3.2, the order of the
# fields in the main entry form can be varied freely.
###############################################################################

sub jumpfield {
	my $current = $_[0];		# current field (1..14, fixed order)
	my $direction = $_[1];		# may be 'n' for next or 'p' for previous
	my $nextfieldname = 'CALL';

	# representation of the fields in the program 
	my @fields = ('NULL', 'CALL', 'DATE', 'TON', 'TOFF', 'BAND',
				'MODE', 'QTH', 'NAME', 'QSLS', 'QSLR',
				'RSTS', 'RSTR', 'REM', 'PWR');

	my %fields = ('CALL' => 1, 'DATE' => 2, 'TON' => 3, 'TOFF' => 4, 'BAND' =>5,
				'MODE'=> 6, 'QTH' => 7, 'NAME' => 8, 'QSLS' => 9, 'QSLR' => 10,
				'RSTS' => 11, 'RSTR' => 12, 'REM' => 13, 'PWR' => 14);

	# @fieldorder = ('CALL', 'DATE'...);

	my $currentfield = $fields[$current];	# Name of the current field.

	for (0..$#fieldorder) {
		if ($fieldorder[$_] eq $currentfield) {
			if ($direction eq 'n') {
				if (defined($fieldorder[$_+1])) {
					$nextfieldname = $fieldorder[$_+1];
				}
				else {
					$nextfieldname = $fieldorder[0];
				}
			}
			else {
				$nextfieldname = $fieldorder[$_-1];	#negative index -> last el
			}
			
		}
	}

	# convert to a field number
	return $fields{$nextfieldname};

}


# Asks for a confirmation in a new window, at the bottom of the screen.

sub askconfirmation {
	my $k;
	my ($question, $regex) = @_;
	my $win = &makewindow(1,80,23,0,6);

	curs_set(0);

	addstr($win, 0, 0, $question." "x80);
	refresh($win);
	do { 
		$k = getch();
	} until ($k =~ /$regex/i);

	delwin($win);

	touchwin($main::whelp);
	refresh($main::whelp);
	
	curs_set(1);

	return $k;
}




# finderror
# input: QSO-array
# output: error message why the QSO is invalid, in a window at the bottom

sub finderror {
	my @qso = @_;
	my $err;
	my $mode = 'log';

	unless (&wpx($qso[0])) {
		$err .= "Call (doesn't have a valid prefix), ";
	}

	unless ((length($qso[1]) == 8) &&		
		(substr($qso[1],0,2) < 32) &&
		(substr($qso[1],2,2) < 13) &&
		(substr($qso[1],4,) > 1900)) {
		$err .= "Date (format: DDMMYYYY), ";
	}

	unless ((length($qso[2]) == 4) &&	
		(substr($qso[2],0,2) < 24) &&
		(substr($qso[2],3,2) < 60)) {
		$err .= "Time on (HHMM), ";
	}
	
	if ($qso[3] eq '') { $qso[3] = 1212 };
	unless ((length($qso[3]) == 4) &&	
		(substr($qso[3],0,2) < 24) &&
		(substr($qso[3],3,2) < 60)) {
		$err .= "Time off (HHMM), ";
	}

	if ($qso[4] eq '' || $qso[4] =~ /^[.]*$/) {
		$err .= "Band (must not be empty), ";
	}

	if ($qso[5] eq '')	{
		$err .= "Mode (must not be empty), ";
	}

	if ($qso[8] eq '')	{
		$err .= "QSLs (must not be empty), ";
	}

	if ($qso[9] eq '')	{
		$err .= "QSLr (must not be empty), ";
	}

	# When called from updateqso, we have a few more values to check.
	if (defined($qso[16])) {
		$mode = 'edit';

		unless ($qso[16] =~ /^(AS|EU|AF|NA|SA|OC|AN)$/) {
			$err .= "Continent (must AS, EU, AF, NA, SA, OC, AN), ";
		}

		unless 	(($qso[17] > 0) && ($qso[17] < 91)) {
			$err .= "ITU Zone (1-90), ";
		}
	
		unless 	(($qso[17] > 0) && ($qso[17] < 41)) {
			$err .= "CQ Zone (1-40), ";
		}
	
		unless ($qso[20] =~ /(^$qso[16]-\d\d\d$)|(^$)/) {
			$err .= "IOTA (format: XX-nnn), ";
		}

		unless ($qso[21] =~ /^([A-Z]{1,2})?$/) {
			$err .= "State (format: XX), ";
		}

	}

	my $win = &makewindow(8,80,7,0,6);
	addstr($win, 0, 0, " "x500);
	addstr($win, 0, 0, "Error! Following fields have invalid values:");
	addstr($win, 2, 0, "$err QSO cannot be saved. Press any key to go back to the QSO..");
	curs_set(0);
	refresh($win);
	getch;
	delwin($win);

	if ($mode eq 'log') {
		touchwin($main::wlog);
		refresh($main::wlog);
	}
	else {
		touchwin($main::weditlog);
		refresh($main::weditlog);
	}
	curs_set(1);
	
}

###############################################################################
# receive_qso: Listens to a QSO coming from fldigi. Same format as xlog uses.
###############################################################################

sub receive_qso {
my @qso;
my %month = ('Jan' => '01', 'Feb' => '02', 'Mar' => '03', 'Apr' => '04', 'May'
		=> '05', 'Jun' => '06', 'Jul' => '07', 'Aug' => '08', 'Sep' => '09',
		'Oct' => '10', 'Nov' => '11', 'Dec' => '12');
my $id = msgget(1238, 0666 | IPC_CREAT);

if (msgrcv($id, my $rcvd, 1024, 0, 0 | IPC_NOWAIT)) {
	msgctl ($id, IPC_RMID, 0);
	substr($rcvd, 0, 4) = '';
	my @rx = split(chr(1), $rcvd);

	my %qh = ();	
	foreach (@rx) {
		my ($key, $value) = split(/:/, $_);
		$qh{$key} = $value if($value);
	}

	# See which values we have, fill the others with defaults. Minimum required
	# is a callsign, the rest can be defaults.

	if (defined($qh{call})) {
		$qso[0] = uc($qh{call});
	}
	else {
		return 0;
	}

	if (defined($qh{date})) {
		my @k = split(/\s+/, $qh{date});
		$qso[1] = $k[0].$month{$k[1]}.$k[2];
	}
	else {
		$qso[1] = &getdate();
	}

	if (defined($qh{time})) {
		$qso[2] = $qh{time};
	}
	else {
		$qso[2] = &gettime;
	}

	if (defined($qh{endtime})) {
		$qso[3] = $qh{endtime};
	}
	else {
		$qso[3] = &gettime;
	}

	if (defined($qh{mhz})) {
		if ($qh{mhz} eq 'HAMLIB') {
			my ($freq, $mode);
			&queryrig(\$freq, \$mode);
			$qso[4] = &freq2band($freq);
		}
		else {
			$qso[4] = &freq2band(1000*$qh{mhz});
		}
	}
	else {
		$qso[4] = $dband;
	}

	if ($qso[4] == 0) {
		$qso[4] = $dband;
	}

	if (defined($qh{mode})) {
		$qso[5] = $qh{mode};
		$qso[5] =~ s/^BPSK/PSK/g;
	}
	else {
		$qso[5] = $dmode;
	}

	if (defined($qh{tx})) {
		$qso[10] = $qh{tx};
		$qso[10] =~ s/[^0-9]//g;
	}
	else {
		$qso[10] = '599';
	}
	
	if (defined($qh{rx})) {
		$qso[11] = $qh{rx};
		$qso[11] =~ s/[^0-9]//g;
	}
	else {
		$qso[11] = '599';
	}

	if (defined($qh{name})) {
		$qso[7] = $qh{name};
		if (length($qso[7]) > 15) {
			substr($qso[7], 15, ) = '';
		}
	}
	else {
		$qso[7] = '';
	}

	if (defined($qh{qth})) {
		$qso[6] = $qh{qth};
		if (length($qso[6]) > 15) {
			substr($qso[6], 15, ) = '';
		}
	}
	else {
		$qso[6] = '';
	}

	if (defined($qh{notes})) {
		$qso[12] = $qh{notes};
		if (length($qso[12]) > 60) {
			substr($qso[12], 60, ) = '';
		}
	}
	else {
		$qso[12] = '';
	}

	if (defined($qh{power})) {
		$qso[13] = $qh{power};
	}
	else {
		$qso[13] = $dpwr;
	}

	if (defined($qh{locator})) {
		$qso[12] .= "GRID:\U$qh{locator} ";
	}

	$qso[8] = $dqsls;
	$qso[9] = 'N';

	if (&saveqso(@qso)) {
		return "Received QSO ($qso[0]) from $qh{program}.         ";
	}
	else {
		return "Error: Received invalid QSO.";
	}


}

	return 0;
}

sub freq2band {
		my $freq = shift;

		if (($freq >= 1800) && ($freq <= 2000)) { $freq = "160"; }
		elsif (($freq >= 3500) && ($freq <= 4000)) { $freq = "80"; }
		elsif (($freq >= 7000) && ($freq <= 7300)) { $freq = "40"; }
		elsif (($freq >=10100) && ($freq <=10150)) { $freq = "30"; }
		elsif (($freq >=14000) && ($freq <=14350)) { $freq = "20"; }
		elsif (($freq >=18068) && ($freq <=18168)) { $freq = "17"; }
		elsif (($freq >=21000) && ($freq <=21450)) { $freq = "15"; }
		elsif (($freq >=24890) && ($freq <=24990)) { $freq = "12"; }
		elsif (($freq >=28000) && ($freq <=29700)) { $freq = "10"; }
		elsif (($freq >=50000) && ($freq <=54000)) { $freq = "6"; }
		elsif (($freq >=144000) && ($freq <=148000)) { $freq = "2"; }
		else {
			$freq = 0;
		}

		return $freq;

}

###############################################################################
# qslstatistics
#
###############################################################################
sub qslstatistics {
	my $win = $_[0];
	my ($total, $sent, $received, $queued, $lotwsent, $lotwreceived);
	my ($rate, $lotwrate, $call);

	$call = lc($mycall);

	my $qsl = $dbh->prepare("SELECT count(*) from log_$call");
	$qsl->execute;
	$total = $qsl->fetchrow_array();
	$qsl = $dbh->prepare("SELECT count(*) from log_$call where qsls = 'Y'");
	$qsl->execute;
	$sent = $qsl->fetchrow_array();
	$qsl = $dbh->prepare("SELECT count(*) from log_$call where qslr = 'Y'");
	$qsl->execute;
	$received = $qsl->fetchrow_array();
	$qsl = $dbh->prepare("SELECT count(*) from log_$call where qsls = 'Q'");
	$qsl->execute;
	$queued = $qsl->fetchrow_array();
	$qsl = $dbh->prepare("SELECT count(*) from log_$call where qslrl= 'R'");
	$qsl->execute;
	$lotwsent = $qsl->fetchrow_array();
	$qsl = $dbh->prepare("SELECT count(*) from log_$call where qslrl= 'Y'");
	$qsl->execute;
	$lotwreceived = $qsl->fetchrow_array();

	$lotwsent += $lotwreceived;

	if ($sent) {
		$rate = int(1000 * $received / $sent);
	}
	else {
		$rate = 0;
	}
	if ($lotwsent) {
		$lotwrate = int (1000* $lotwreceived / $lotwsent);
	}
	else {
		$lotwrate = 0;
	}

	addstr($win, 7, 25,         "          QSL         LOTW");
	addstr($win, 8, 25,         "--------------------------");
	addstr($win, 9, 25, sprintf("sent   %6d       %6d  ", $sent,
					$lotwsent));
	addstr($win, 10, 25, sprintf("rcvd   %6d       %6d  ", 
					$received, $lotwreceived));
	addstr($win, 11, 25, sprintf("queued %6d ", $queued));
	addstr($win, 12, 25, sprintf("--------------------------"));
	addstr($win, 13,25, sprintf("Rate    %4s%%        %4s%%", $rate/10,
					$lotwrate/10));


	refresh($win);

}


# getch2: Same as curses function getch, except that it returns sequences of
# ESC-n as KEY_F(n);

sub getch2 {

	my $ch = getch();

	# ESC-n instead of F-Keys
	if (ord($ch) == 27) {
		$ch = getch();
		# Double ESC is like F3
		if (ord($ch) == 27) {
			$ch = KEY_F(3);
		}
		elsif ($ch =~ /^\d$/) {
			if ($ch eq '0') {
				$ch = KEY_F(10);
			}
			else {
				$ch = KEY_F($ch);
			}
		}
	}

	return $ch;
}




return 1;

# Local Variables:
# tab-width:4
# End: **
