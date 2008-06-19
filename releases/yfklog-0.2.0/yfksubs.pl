#!/usr/bin/perl -w

# Several subroutines for yfklog, a amateur radio logbook software 
# 
# Copyright (C) 2005  Fabian Kurz, DJ1YFK
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

use strict;
use POSIX;				# needed for acos in distance/direction calculation

# We load the default values for some variables that can be changed in .yfklog

my $lidadditions="^QRP\$|^LGT\$";
my $csadditions="(^P\$)|(^M{1,2}\$)|(^AM\$)";
my $dbserver = "localhost";						# Standard MySQL server
my $dbport = 3306;								# standard MySQL port	
my $dbuser = "";								# DB username
my $dbpass = "";								# DB password
my $dbname = "";								# DB name
my $onlinedata = "CALL, DATE, BAND, MODE";		# Fields for online search log
my $ftpserver = "127.0.0.1";					# ftp for online log / backup
my $ftpport   = "21";							# ftp server port
my $ftpuser   = "";								# ftp user
my $ftppass   = "";								# ftp passwd
my $ftpdir    = "log/";							# ftp directory
my $mycall    = "L1D";							# too stupid to set it? :-))
my $dpwr      = "100";							# default PWR
my $dqslsi    = "N";							# def. QSL-s for import
my $lat1      = "52";							# Latitude of own station
my $lon1      = "-8";							# Longitude of own station

# We read the configuration file .yfklog.

open CONFIG, ".yfklog" or die "Cannot open configuration file. Please make sure
it is in the current directory. Error: $!";

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
			$ftpserver= $1;
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
	elsif ($line =~ /^lat=(.+)/) {					# Own latitude
			$lat1= $1;
	}
	elsif ($line =~ /^lon=(.+)/) {					# Own longitude
			$lon1= $1;
	}

}

close CONFIG;	# Configuration read. Don't need it any more.

## We connect to the Database now...
my $dbh = DBI->connect("DBI:mysql:$dbname;host=$dbserver", $dbuser, $dbpass) 
		or die "Could not connect to Database: " . DBI->errstr;

# Now we read cty.dat from K1EA, or exit when it's not found.
# NOTE This was oroginally implemented in the &dxcc sub, making
# ADIF import very slow because it would have to read this file
# every time a QSO is imported. 

open DXCC, "cty.dat" or die "Error reading cty.dat country file: $!";    
my %dxcc;			# DXCC hash
my $key;       	 	# This will temporarily store the key
my $value;     	 	# This will temporarily store the value
	
while (my $line = <DXCC>) {             # Read line into $line
    if ($line =~ /^\w/) {               # New country starts
            if ($key && $value) {       # When old DXCC exists, 
                $dxcc{$key} = $value;   # save it to hash 
            }
            $value = "";                # delete old value
            $key = $line;               # New hash-key will be this line
    }
    else {                              # No new DXCC, but prefixes
        $value .= $line;                # attach prefix-line to value
    }
} # while ends here, all lines read and stored in hash

close DXCC;					# good bye


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
  my ($prefix,$a,$b,$c);
  
  # First check if the call is in the proper format, A/B/C where A and C
  # are optional (prefix of guest country and P, MM, AM etc) and B is the
  # callsign. Only letters, figures and "/" is accepted, no further check if the
  # callsign "makes sense".
    
if ($_[0] =~ /^((\d|[A-Z])+\/)?((\d|[A-Z]){3,})(\/(\d|[A-Z])+)?$/) {
   
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
# If this happens, the zone information is saved in the %zone hash (key = DXCC,
# value = zones) and before the DXCC-Array is returned checked and (if a 
# different zone is stored) changed in the array.
#
# This sub checks the callsign against this list and the DXCC in which 
# the best match (most matching characters) appear. This is needed because for 
# example the CTY file specifies only "D" for Germany, "D4" for Cape Verde.
# Also some "unusual" callsigns which appear to be in wrong DXCCs will be 
# assigned properly this way, for example Antarctic-Callsigns.
# 
# The list is read into a hash table, the key contains the line with the 
# country-information, the value contains all possible prefixes and zone
# information.
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
#    my %dxcc;     		# DXCC hash, key = country info, value = prefixes
#		NEW: %dxcc hash created at the start of program, no need to read it
#				again and again.				
    my $bestmatch=""; 	# Best matching DXCC (~ Key) so far
    my $bestcount=0;	# Number of characters that matched
    my @prefixes;   	# Prefixes for each DXCC will go here
    my $testpfx;    	# Prefix to test
    my $callsign;   	# this will be the callsign or part of it) to test
    my $zones;      	# temporary zones
    my %zones;      	# saves zones if differ from regular, key is DXCC string
                    	# will be used instead of regular zones at the end
	my @dxcc;			# returned array with DXCC information
   

	

# Now we check if the callsign includes a slash, because that could change the
# DXCC. For example PA/DJ1YFK is not a problem, but DJ1YFK/TF is, so it neds to
# be changed to the corresponding prefix, TF0 to get the DXCC. There is one
# exception that I am aware of, which is OH/DJ1YFK which would be changed to
# OH0 and get Aland islands which is wrong. Thus there is a small check for OH/
# and /OH[1-9]? first.
# Also 3D2- and FO0-Calls are troublesome, because those are not always
# unambiguosly assigned to a DXCC. When they match 3D2C or 3D2R or 3D2../R,
# they will be assigned to a matching DXCC, if not, they'll be Fiji, unless
# they apear as full calls in the list.
# KH5K is also troublesome, so if a call contains it, no matter what else, it
# will be assigned to Kingman Reef. Same with Kure KH7K.
# Finally, FR-Calls can be from different DXCCs, depending on their first
# letter of the suffix. cty.dat has this as FR/G, FR/T etc, which will be
# changed to ^FR\dG, ^FR\dT etc. later during the check. 


if ($_[0] =~ /(^OH\/)|(\/OH[1-9]?$)/) {    # non-Aland prefix!
    $callsign = "OH";                      # make callsign OH = finland
}
elsif ($_[0] =~ /(^3D2R)|(^3D2.+\/R)/) { # seems to be from Rotuma
    $callsign = "3D2RR";                 # will match with Rotuma
}
elsif ($_[0] =~ /^3D2C/) {               # seems to be from Conway Reef
    $callsign = "3D2CR";                 # will match with Conway
}
elsif ($_[0] =~ /KH5K/) {                # seems to be from Kingman Reef
    $callsign = "KH5K";                  # will match with Kingman!
}
elsif ($_[0] =~ /KH7K/) {                # seems to be from Kure
    $callsign = "KH7K";                  # will match with Kure
}
elsif ($_[0] =~ /\//) {                  # check if the callsign has a "/"
    $callsign = &wpx($_[0],1);           # use the wpx prefix instead, which may
                                         # intentionally be wrong, see &wpx!
}
else {                                   # else: normal callsign
           $callsign = $_[0];            # use it for checking!
}

while (($key, $value) = each %dxcc) {    # iterate through hash table
    if ($key && $value) {                             # valid key/value pair
        $value =~ s/\s//g;                            # remove whitespaces
        @prefixes = split(/[,;]/, $value);            # split prefixes
        foreach $testpfx (@prefixes) {                # iterate through prefixes
            $testpfx =~ s/^(\w+)([\[\(].+)/$1/g;      # remove zones, if any
            undef $zones;                             # remove old zone info
            if (defined $2) {                         # When zones cropped
                $zones = $2;                          # remember zone
            }
            $testpfx =~ s/FR\/([A-Z])/FR\\d$1/g;      # special FRs, see above
            if ($callsign =~ /^$testpfx/) {           # if call matches a prefix
                if (length($&) > $bestcount) {        # better than prev. match
                    $zones{$key} = $zones if defined $zones; # save Z if differs
                    $bestmatch = $key;                # save best DXCC key
                    $bestcount = length($&);          # save how many matched
                }
            }
        }
    }
} # while ends here, all DXCCs checked, best DXCC in $bestmatch

# Possibly there was no DXCC matching at all, for example for a callsign like
# QQ1ABC. In this case an array with questionmarks is returned

unless ($bestmatch eq "") {
@dxcc = split(/\s*:\s*/, $bestmatch);   # Put the dxcc information into an
                                           # array by splitting, cut off white 
                                           # space also

if (defined $zones{$bestmatch}) {          # there is a different zone saved
    $zones{$bestmatch} =~ /(\((\d+)\))?(\[(\d+)\])?/;  # WAZ in $2, ITU in $4 
    $dxcc[1] = $2 if defined $2;
    $dxcc[2] = $4 if defined $4;
}
}
else {										# not a valid DXCC.
return qw/? ? ? ? ? ? ? ?/;
}

# cty.dat has special entries for WAE countries which are not separate DXCC
# countries. Those start with a "*", for example *TA1. Those have to be changed
# to the proper DXCC. Since there are opnly a few of them, it is hardcoded in
# here.

if ($dxcc[7] =~ /^\*/) {							# WAE country!
	if ($dxcc[7] eq '*TA1') { $dxcc[7] = "TA" }		# Turkey
	if ($dxcc[7] eq '*4U1V') { $dxcc[7] = "OE" }	# 4U1VIC is in OE..
	if ($dxcc[7] eq '*GM/s') { $dxcc[7] = "GM" }	# Shetlands
	if ($dxcc[7] eq '*IG9') { $dxcc[7] = "I" }		# African Italy
	if ($dxcc[7] eq '*IT9') { $dxcc[7] = "I" }		# Sicily
	if ($dxcc[7] eq '*JW/b') { $dxcc[7] = "JW" }	# Bear Island

}

# CTY.dat uses "/" in some DXCC names, but I prefer to remove them, for example
# VP8/s ==> VP8s etc.

$dxcc[7] =~ s/\///g;

return @dxcc; 

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
# $_[1] -> when 1, clear windows 0..13, when 2 clear windows 0..21
# This is needed because in LOGGING mode only the first 14 windows are used
##########################################################################

sub clearinputfields {
	my @wi = @{$_[0]};  				# Input windows
	my $num;							# number of QSOs to delete..
	
	if ($_[1] == 1) { $num = 14 }
	else { $num = 23 }

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
	else { $num = 18 }

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
# the same applies for ITU, CQZ and IOTA. Those can be entered in the REMarks
# field like ITU:34 CQZ:33 IOTA:EU-038  (with hyphen!). These parts will be cut
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
	my @qso = (shift,shift,shift,shift,shift,shift,shift,shift,shift,shift,
			shift,shift,shift,shift);   # get the @qso array 
	my $editnr = shift;					# QSO we edit

	# Now we have to check if it is a valid entry
	if (( my $pfx = &wpx($qso[0]) ) &&		# check for a callsign, return PFX
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
				(substr($qso[3],3,2) < 60)){ 	# valid minute Time on
				$qso[3] = &gettime;				# time off = current time
			} # Time off ready
				
			$qso[1] =					# make date in YYYY-MM-DD format
			substr($qso[1],4,)."-".substr($qso[1],2,2)."-".substr($qso[1],0,2);
			$qso[2] = $qso[2]."00";			# add seconds
			$qso[3] = $qso[3]."00";			# add seconds
			my @dxcc = &dxcc($qso[0]);		# get DXCC-array
			my $dxcc = $dxcc[7];			# dxcc prefix
			my $cont = $dxcc[3];			# dxcc continent
			my $ituz = $dxcc[2];			# dxcc itu zone
			my $cqz  = $dxcc[1];			# dxcc CQ zone

			# searching for QSL-INFO in remarks-field:
			if ($qso[12] =~ /(.*)via:(\w+)(.*)/){ # QSL info in remarks field
				$qslinfo = $2;				# save QSL-info
				$qso[12] = $1." ".$3;		# cut qsl-info from remarks field
			}
			
			# searching for different ITUZ in remarks-field:
			# FIXME ITU-Zone should be entered as "3" and not "03" e.g.!!
			if ($qso[12] =~ /(.*)ITUZ:(\w+)(.*)/){ 
				my ($a, $b, $c) = ($1, $2, $3);			# save regex results
				# A valid ITU Zone is 01..90
				if (($b =~ /^\d\d$/) && ($b > 0) && ($b < 91)) {	
					$ituz = $b;
					$qso[12] = $a." ".$c;
				}
			}
			
			# searching for different CQZ in remarks-field:
			# FIXME same as ITUZ
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

			# we are now ready to save the QSO, but we have to check if it's a
			# new QSO or if we are changing an existing QSO.
			# TBD (?): When editing QSO, also take new ITU, CQZ, IOTA etc into
			# account? .. I think it's not needed. Can be done in EDIT/SEARCH
			# mode...
			
			if ($editnr) {				# we change an existing QSO
				$dbh->do("UPDATE log_$mycall SET CALL='$qso[0]', DATE='$qso[1]',
						T_ON='$qso[2]', T_OFF='$qso[3]', BAND='$qso[4]',
						MODE='$qso[5]', QTH='$qso[6]', NAME='$qso[7]',
						QSLS='$qso[8]', QSLR='$qso[9]', RSTS='$qso[10]',
						RSTR='$qso[11]', REM='$qso[12]', PWR='$qso[13]'
						WHERE NR='$editnr';");
			}
			else {						# new QSO
				$dbh->do("INSERT INTO log_$mycall 
					(CALL, DATE, T_ON, T_OFF, BAND, MODE, QTH, NAME, QSLS,
					QSLR, RSTS, RSTR, REM, PWR, DXCC, PFX, CONT, QSLINFO,
					ITUZ, CQZ, IOTA, STATE)
					VALUES ('$qso[0]', '$qso[1]', '$qso[2]', '$qso[3]', 
							'$qso[4]', '$qso[5]', '$qso[6]', '$qso[7]', 
							'$qso[8]', '$qso[9]', '$qso[10]', '$qso[11]', 
							'$qso[12]', '$qso[13]', '$dxcc', '$pfx', 
							'$cont', '$qslinfo', '$ituz', '$cqz', '$iota',
							'$state');");
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
	
			my $sth = $dbh->prepare("SELECT CALL FROM calls WHERE 
									CALL='$call';");
			$sth->execute();
			unless ($sth->fetch()) {	# check if callsign not in DB
				if (($qso[7] ne "") || ($qso[6] ne "")) {	# new things to add
					$dbh->do("INSERT INTO calls (CALL, NAME, QTH) VALUES
							('$call', '$qso[7]', '$qso[6]');");	
				}
			}

			# until now this only inserts, when both Name and QTH are unknown;
			# it doesn't update when only one part is unknown. FIXME later.
			return 1;			# successfully saved
	}
	else {
			return 0;			# No success, QSO not complete!
	}		
}




		
##############################################################################
# readw  reads what the user types into a window, depending on $_[1],
# only numbers, callsign-characters, only letters or (almost) everything
# is allowed. $_[2] contains the windownumber, $_[3] the reference to the
# QSO-array and $_[0] the reference to the Input-window-Array.
#
# $_[4] is the reference to $wlog
#
# $_[5] either contains 0 (normal) or a QSO number. If it's a number, it means
# that we are editing an existing  QSO, meaning that we have to call &saveqso
# with the number as additional argument, so it will not save it as a new QSO.
# The variable will be called $editnr.
# 
# The things you enter via the keyboard will be checked and if they are
# matching the criterias of $_[1], it will be printed into the window and saved
# in @qso. Editing is possible with arrow keys, delete and backspace. delete
# acts like backspace when the cursor is at the end of the line.
# 
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
	my $pos = 0;								# cursor position in the string
	my $wlog = ${$_[4]};						# reference to log-windw
	my $editnr = ${$_[5]};						# reference to editnr 
	
	my $debug=0;
	
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
		
		$ch = getch;							# wait for a character
		
		# We first check if it is a legal character of the specified $match,
		# if so, it will be added to the string (at the proper position!) 
		if (($ch =~ /^$match$/)) {					# check if it's "legal"
			unless ($_[1] == 3) {					# Unless Name, QTH mode
				$ch =~ tr/[a-z]/[A-Z]/;				# make letters uppercase
			}
			# The new character will be added to $input. $input is split into 2
			# parts, the part before $pos and the part after $pos, the new
			# character is placed in between. (Of course the 2nd part can be 
			# empty)
			$pos++;
			(my $part1, my $part2) = ("","");	# init cos one might be undef!
			if (($pos > 0) and (length($input) > 0)) {  # first part exists
				$part1 = substr($input, 0, $pos-1);
			}
			if (($pos < length($input)) and (length($input) > 1)) {
				$part2 = substr($input, $pos-1,);
			}
			$input = $part1.$ch.$part2;					# combine all
		} 
		
		# The l/r arrow keys change the position of the cursor to left or right
		# but only within the boundaries of $input.
		
		elsif ($ch eq KEY_LEFT) {					# arrow left was pressed	
			if ($pos > 0) { $pos-- }				# go left if possible
		}
		
		elsif ($ch eq KEY_RIGHT) {					# arrow right was pressed	
			if ($pos < length($input)) { $pos++ }	# go right if possible
		}

		# Pressing DELETE deletes the character at the current cursor position
		# and shifts the part to the right of it back. If the cursor is at the
		# very right of the line, it acts like a BACKSPACE

		elsif ($ch eq KEY_DC) {						# Delete key pressed
			# See if something is there to delete and if we are not at the end
			if ((length($input) > 0) && ($pos   < length($input))) {
				# Split $input into two parts, see earlier
				(my $part1, my $part2) = ("","");
				if (($pos > 0) and (length($input) > 0)) {  
					$part1 = substr($input, 0, $pos);
				}
				if (($pos < length($input)) and (length($input) > 1)) {
					$part2 = substr($input, $pos+1,);
				}
				$input = $part1.$part2;					# combine all
			} 
			# Check for backspace mode, if so, cut off last char and pos--
			elsif (($pos == length($input)) && ($pos != 0)) {
				$pos--;											# go back
				$input = substr($input, 0, length($input) -1);	# cut last char
			}
		}
		
		# BACKSPACE. When pressing backspace, the character left of the cursor
		# is deleted, if it exists. For some reason, KEY_BACKSPACE only is true
		# when pressing CTL+H on my system (and all the others I tested); the
		# other tests lead to success, although it's probably less portable.
		# Found this solution in qe.pl by Wilbert Knol, ZL2BSJ. 

		elsif (($ch eq KEY_BACKSPACE) || (ord($ch)==8) || (ord($ch)==0x7F)) {
			# check if something can be deleted 
			if (($pos != 0) && (length($input) > 0)) {
				# Split $input into two parts, see earlier
				(my $part1, my $part2) = ("","");
				if (($pos > 0) and (length($input) > 0)) {  
					$part1 = substr($input, 0, $pos-1);
				}
				if (($pos < length($input)) and (length($input) > 1)) {
					$part2 = substr($input, $pos,);
				}
				$input = $part1.$part2;					# combine all
				$pos--;									# cursor to left
			}
		}
						
		
		# Space, Tab and Enter are the keys to go to the next field, except in
		# mode $_[1], where it was already caught in the first pattern match.
		# If space, tab or newline is found, the sub puts $input into the
		# proper place in the @qso array: ${$_[3]}[$_[2]];
		elsif ($ch =~ /^[ \t\n]$/) {				# Space, Tab or Newline
			${$_[3]}[$_[2]] = $input;				# save to @qso;
			return 1;
		}
		# Arrow-up gues to the previous QSO field. Everything else same as
		# above MUMU
		elsif ($ch eq KEY_UP) {						# Cursor up
			${$_[3]}[$_[2]] = $input;				# save to @qso;
			return 6;								# 6 -> one field back
		}
		
		# If the pressed key was F2, we will save; that is, when the qso array
		# has sufficient information for a good QSO. Then the qso-array 
		# and the input fields are deleted.
		elsif  ($ch eq KEY_F(2)) {					# pressed F2 -> SAVE
			${$_[3]}[$_[2]] = $input;				# save field to @qso
			if (&saveqso(@{$_[3]},$editnr)) {		# save @QSO to DB
				&clearinputfields($_[0],1);			# clear input fields 0..13
				@{$_[3]} = ("","","","","","","","","","","","","","");
				# Now we actualize the display of the last 16 QSOs in the
				# window $wlog.   
				&last16(\$wlog);
				${$_[5]} = 0;					# we finished editing, if we
												# did at all. $editnr = 0
				return 4;						# success, leave readw, new Q
			}	# if no success, we continue in the loop.
		}

		# exit to the MAIN MENU
		elsif ($ch eq KEY_F(1)) {		
			return 5;							# active window = 5 -> MENU!
		}

		# F3 cancels the current QSO and returns to the CALL input field.
		# if $editnr is set (= we edit a QSO), it's set back to 0
		elsif ($ch eq KEY_F(3)) {			# F3 pressed -> clear QSO
			for (0 .. 13) {					# iterate through windows 0-13
				addstr(@{$_[0]}[$_],0,0," "x80);	# clear it
				refresh(@{$_[0]}[$_]);
			}
			foreach (@{$_[3]}) {			# iterate through QSO-array
				$_="";						# clear content
			}
			${$_[5]} = 0;					# editqso = 0
			return 4;						# return 4 because we want back to
											# window 0 (call)
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
			endwin;							# Leave curses mode	
			exit;
		}
	}
}

##############################################################################
# &last16   Prints the last 16 QSOs into the $wlog window
##############################################################################

sub last16 {
	my $wlog = ${$_[0]};			# reference to $wlog window
	# Now we fetch the last 16 QSOs in the database, only CALL, BAND, MODE and
	# date needed.
	my $l16 = $dbh->prepare("SELECT CALL, BAND, MODE, DATE 
				FROM log_$mycall ORDER BY NR DESC LIMIT 16");	
	$l16->execute();
	my ($call16, $band16, $mode16, $date16);	# temporary vars
	$l16->bind_columns(\$call16, \$band16, \$mode16, \$date16);
	my $y=15;									# y-position in $wlog
	while ($l16->fetch()) {						# while row available
		# we put the date into DD-MM-YY format from YYYY-MM-DD
		$date16 = substr($date16,8,2).substr($date16,4,4).substr($date16,2,2); 
		addstr($wlog,$y,0, sprintf("%-12s%-4s %-5s%-6s",
				$call16,$band16,$mode16,$date16));	 # print formatted
		$y--;									# move one row up
	}
	# If there were less than 16 QSOs in the log, the remaining lines have to
	# be filled with spaces 
	if ($y > 0) {
		for $y (0 .. $y) {
			addstr($wlog,$y,0, " "x30);
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
##############################################################################

sub callinfo {
	my $call = ${$_[0]}[0];		# callsign to analyse
	my $band = ${$_[0]}[4];		# band of the current QSO
	my $dxwin = $_[1];			# window where to print DXCC/Pfx 
	my @wi = @{$_[2]};			# reference to input-windows
	my $wqsos = $_[3];			# qso-b4-window
	my $prefix = &wpx($call);	# determine the Prefix
	my $PI=3.14159265;			# PI for the distance and bearing
	my $RE=6371;				# Earth radius
	my $z =180/$PI;				# Just to reduce typing in formular dist/dir

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
		my $dir = acos((sin($lat2/$z)-sin($lat1/$z)*cos($g))/
								(cos($lat1/$z)*sin($g)))*360/(2*$PI);
		# Shortpath
		if (sin(($lon2-$lon1)/$z) < 0) { $dir = 360 - $dir;}
		$dir = 360 - $dir; 
		
		addstr($dxwin, 1,38, sprintf("%-6d",$dist));
		addstr($dxwin, 1,58, sprintf("%3d",$dir));

		# Find out if the DXCC is new or a new bandpoint. $dxcc[7] is the DXCC
		# of the station which we are working right now.

		my $dx = $dbh->prepare("SELECT NR from log_$mycall WHERE 
														DXCC='$dxcc[7]';");
		my $newdxcc = $dx->execute();

		unless ($newdxcc eq '0E0') {			# DXCC already worked
			# Might still be new on this band..
			$dx = $dbh->prepare("SELECT NR from log_$mycall WHERE 
										DXCC='$dxcc[7]' AND BAND='$band';");
			my $newbandpoint = $dx->execute();
			if ($newbandpoint eq '0E0') {		# New bandpoint!
				addstr($dxwin, 1, 70, "New Band!");
			}
			else {								# Nothing new at all
				addstr($dxwin, 1, 70, '         ');
			}
		}
		else {									# NEW DXCC
			addstr($dxwin, 1, 70, "New DXCC!");
		}
		
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
				CALL='$call'");
		$nq->execute();
		my ($name, $qth);								# temporary vars
		$nq->bind_columns(\$name, \$qth);		# bind references
		if ($nq->fetch()) {								# if name available
			${$_[0]}[7] = $name;						# save to @qso
			addstr($wi[7],0,0,"$name");					# put into window
			${$_[0]}[6] = $qth;							# save to @qso
			addstr($wi[6],0,0,"$qth");					# put into window
			refresh($wi[6]);							# refresh windows
			refresh($wi[7]);
		}
		
		# We fetch club membership information from the database ...

		my $clubline='';				# We will store the club infos here
		
		my $clubs = $dbh->prepare("SELECT CLUB, NR FROM clubs WHERE
									CALL='$call'");
		$clubs->execute();
	
		while (my @a = $clubs->fetchrow_array()) {			# fetch row
			$clubline .= $a[0].":".$a[1]." ";				# assemble string
		}
		# Output will be something like: AGCW:2666 HSC:1754 ...

		addstr($dxwin, 2, 0, sprintf("%-80s", $clubline));
		refresh($dxwin);
		
		# Now the previous QSOs with the station will be displayed. A database
		# query is made for: CALL (because it might have been something
		# different than the homecall, like PA/DJ1YFK/p, DATE, time, band,
		# mode, QSL sent and QSL-rx. 
		# (TBD maybe it would be worth thinking about adding an additional
		# column for the own call and then specify a list of logs to search in
		# the config file)
	
		# Select all QSOs where the base-callsign is $call (which is the base
		# call of the current QSO)
		my $lq = $dbh->prepare("SELECT CALL, DATE, T_ON, BAND, MODE, QSLS, QSLR 
			from log_$mycall WHERE CALL REGEXP '^(.*/)?$call(/.*)?\$' ORDER BY
			DATE, T_ON;");
		my $count = $lq->execute();			# number of prev. QSOs in $count
		my ($lcall, $ldate, $ltime, $lband, $lmode, $lqsls, $lqslr); # temp vars
		$lq->bind_columns(\$lcall, \$ldate, \$ltime, \$lband, \$lmode, \$lqsls, \$lqslr);
		my $y = 0;
		while ($lq->fetch()) {				# more QSOs available
			$ltime = substr($ltime, 0,5);	# cut seconds from time
			my $line = sprintf("%-14s %-8s %-5s %4s %-4s %1s %1s     ", $lcall,
					$ldate, $ltime, $lband, $lmode, $lqsls, $lqslr);
			addstr($wqsos, $y, 0, $line);
			($y < 16) ? $y++ : last;			# prints first 16 rows
		}	# all QSOs printed
		for (;$y < 16;$y++) {					# for the remaining rows
			addstr($wqsos, $y, 0, " "x50);		# fill with whitespace
		}
		if ($count> 15) {						# more QSOs than fit in window
			addstr($wqsos, 14, 47, ($count-16));
			addstr($wqsos, 15, 46, "more");
		}
		refresh($wqsos);
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
		return "YFKlog v0.1 - a general purpose ham radio logbook

Copyright (C) 2005  Fabian Kurz, DJ1YFK

This program is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 2 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc., 59
Temple Place - Suite 330, Boston, MA 02111-1307, USA. 


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
# FIXME?  There is only a check that it's not possible to scroll over the end
# of the list, but it's possible to go to "negative" QSO numbers. in this case
# 0 QSOs are returned from the database and nothing new is displayed, but the
# $offset is increased. this doesn't really cause any problem, though.
##############################################################################

sub choseqso {
	my $wlog = ${$_[0]};			# reference to $wlog window
	my $offset=0;					# offset for DB query. 
	my $aline=15;					# active line, cursor position.
	my $ch;							# character we get from keyboard
	my $ret=0;						# return value. saves the NR from the
									# database which suits in $aline
	my $goon=1;						# "go on" in the do .. while loop

# Now we fetch 16 QSOs from the database, eventually with an offset when we
# scrolled. only NR, CALL, BAND, MODE and DATE needed.
# a do {..} while construct is used because we need a highlighted line right at
# the start, without any extra key pressed

do  {			# loop and get keyboard input

	# after every keystroke the database query is done again and the active
	# line displayed in another color. unfortunately chgat() does not work on
	# things that have already been sent to the display with refresh(), so only
	# colouring one line while scrolling is not possible. since I was too lazy
	# to save the 16 QSOs into some kind of array, I decided to do the query
	# every time again. no performance problems even on my old K6-300.
		
	my $cq = $dbh->prepare("SELECT NR, CALL, BAND, MODE, DATE 
				FROM log_$mycall ORDER BY NR DESC LIMIT $offset, 16");	
	$cq->execute();
	my ($nr, $call, $band, $mode, $date);	# temporary vars
	$cq->bind_columns(\$nr, \$call, \$band, \$mode, \$date);
	my $y=15;						# y-position for printing in $wlog
	while ($cq->fetch()) {						# while row available
		# we put the date into DD-MM-YY format from YYYY-MM-DD
		$date = substr($date,8,2).substr($date,4,4).substr($date,2,2); 
		if ($y == $aline) {						# highlight line?
			attron($wlog, COLOR_PAIR(1));
			$ret = $nr;							# remember the NR
		}
		addstr($wlog,$y,0, sprintf("%-12s%-4s %-5s%-6s",
				$call,$band,$mode,$date));	 # print formatted
		attron($wlog, COLOR_PAIR(3));
		$y--;									# move one row up
	}
	refresh($wlog);
	
	$ch = getch;						# get character from keyboard

	if ($ch eq KEY_DOWN) {				# key down was pressed
		if ($aline < 15) {					# no scrolling needed
			$aline++;
		}
		elsif ($offset != 0) {			# scroll down, when possible (=offset)
		# (when there is an offset, it means we have scrolled back, so we can
		# safely scroll forth again)
				$offset -= 16;			# next 16
				$aline = 0;				# cursor to highest line
		}
	}
	
	if ($ch eq KEY_UP) {				# key up was pressed
		if ($aline > 0) {				# no scrolling needed
			$aline--;
		}
		else {							# we can always scroll up... :-/ FIXME?
				$offset += 16;			# earlier 16
				$aline = 15;			# cursor to lowest line
		}
	}

	if (($ch eq KEY_NPAGE) && ($offset != 0)) {		# scroll down 16 QSOs
		$aline = 0;						# first line
		$offset -= 16;					# next 16 QSOs
	}

	elsif ($ch eq KEY_PPAGE) {			# scroll up 16 QSOs (always! FIXME?)
		$aline = 15;					# last line
		$offset += 16;					# prev 16 QSOs
	}
	
	elsif ($ch eq KEY_F(1)) {			# go to the MAIN MENU
		$goon = 0;						# do not go on!
		$ret = "m";						# return value i = Input Window
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
my $q = $dbh->prepare("SELECT CALL, DATE, T_ON, T_OFF, BAND, MODE, QTH,
				NAME, QSLS,QSLR, RSTS, RSTR, REM, PWR FROM log_$mycall 
				WHERE NR='$_[0]'");
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
	my $lq = $dbh->prepare("SELECT NR from log_$mycall WHERE 
							CALL REGEXP '^(.*/)?$call(/.*)?\$';");

	my $count = $lq->execute();			# number of prev. QSOs in $count

	# When 0 lines are returned, there is no QSO to chose, so we return
	# "i", which means to go back to the input window.

	if ($count == 0) { return "i"; }
	
do {									# we start looping here
	my $lq = $dbh->prepare("SELECT NR, CALL, DATE, T_ON, BAND, MODE, QSLS, QSLR 
				FROM log_$mycall WHERE CALL REGEXP '^(.*/)?$call(/.*)?\$' ORDER
				BY DATE, T_ON LIMIT $offset, 16");	
	
	$lq->execute();	

	my ($nr, $fcall, $date, $time, $band, $mode, $qsls, $qslr); # temp vars
	
	$lq->bind_columns(\$nr,\$fcall,\$date,\$time,\$band,\$mode,\$qsls,\$qslr);
	
	my $y = 0;
	while ($lq->fetch()) {				# more QSOs available
		$time = substr($time, 0,5);	# cut seconds from time
		my $line = sprintf("%-14s %-8s %-5s %4s %-4s %1s %1s     ", $fcall,
			$date, $time, $band, $mode, $qsls, $qslr);
		if ($y == $aline) {					# highlight line?
			attron($wqsos, COLOR_PAIR(1));	# highlight
			$ret = $nr;						# remember NR
		}
		addstr($wqsos, $y, 0, $line);
		attron($wqsos, COLOR_PAIR(4));
		($y < 16) ? $y++ : last;			# prints first 16 rows
	}	# all QSOs printed
	
	for (;$y < 16;$y++) {					# for the remaining rows
		addstr($wqsos, $y, 0, " "x50);		# fill with whitespace
	}
	refresh($wqsos);

	$ch = getch();					# get keyboard input
	
	if ($ch eq KEY_DOWN) {			# arrow key down
		# we now have to check two things: 1. is the $pos lower than $count?
		# 2. are we at the end of a page and have to scroll?
		if ($pos < $count) {		# we can go down, but on same page?
			if ($aline < 15) {
				$aline++;
				$pos++;
			}
			else {					# we have to scroll!
				$offset += 16;		# add offset -> next 16 QSOs
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
			$offset -= 16; 		# decrease offset
			$aline=15;			# start on lowest line of new page
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
"Call:               Date:           T on:      T off:      Band:      Mode: ";
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
	return "IOTA:         STATE:     Editing QSO Nr: "
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

if (($ch eq KEY_DOWN) && ($aline < $#items)) {	# Arrow down was pressed 
												# and not at last position
	# We can savely increase $aline, because we are not yet at the end of the
	# items array. 
	$aline++;
	# now it is possible that we have to scroll. this is the case when  
	if ($y+$yoffset-$ystart ==  $aline) {
			$yoffset += $height;
	}
}
elsif (($ch eq KEY_UP) && ($aline > 0)) {		# arrow up, and we are not at 0
	# We can savely decrease the $aline position, but maybe we have to scroll
	# up
	$aline--;
	# We have to scroll up if the active line is smaller than the offset..
	if ($yoffset > $aline) {
			$yoffset -= $height;
	}
}
elsif ($ch eq KEY_F(1)) {			# F1 - Back to main menu
	return "m";
}
elsif ($ch eq KEY_F(12)) {			# F12 - QUIT YFKlog
	endwin();
	exit;
}

} until ($ch =~ /\s/);

return $aline;
} # selectlist

##############################################################################
# &askbox    Creates a window in which the user enters any value. 
##############################################################################

sub askbox {
	# We get the parameters ...
	my ($ypos, $xpos, $height, $width, $valid, $text) = @_;
	my $win;				# The window in which we are working
	my $iwin;				# The Input window
	my $ch="";				# we store the keyboard input here
	my $str="";				# the string that we are reading
	my $pos=0;				# position of the cursor in the string
	
	$win = &makewindow($height, $width, $ypos, $xpos, 1);		# create askbox
	$iwin = &makewindow(1, $width-4, $ypos + 2, $xpos + 2, 5);	# input window
	
	addstr($win, 0, ($width-length($text))/2, $text);			# put question
	addstr($iwin,0,0, " " x $width);							# clear inputw
	move($iwin, 0,0);											# cursor to 0,0
	refresh($win);												# refresh ...
	refresh($iwin);

	# Now we start reading from the keyboard, character by character
	# This is mostly identical to &readw;
	
	while (1) {						# loop until beer is empty
		addstr($iwin, 0,0, $str." "x80);		# put $str in inputwindow
		move ($iwin,0,$pos);					# move cursor to $pos
		refresh($iwin);							# show new window
		$ch = getch();							# get character from keyboard

		# We first check if it is a legal character of the specified $match,
		# if so, it will be added to the string (at the proper position!) 
		if (($ch =~ /^$valid$/)) {					# check if it's "legal"
			unless($valid eq '\w') {				# unless read filename
				$ch =~ tr/[a-z]/[A-Z]/;				# make letters uppercase
			}
				
			# The new character will be added to $str. $str is split into 2
			# parts, the part before $pos and the part after $pos, the new
			# character is placed in between. (Of course the 2nd part can be 
			# empty)
			$pos++;
			(my $part1, my $part2) = ("","");	# init cos one might be undef!
			if (($pos > 0) and (length($str) > 0)) {  # first part exists
				$part1 = substr($str, 0, $pos-1);
			}
			if (($pos < length($str)) and (length($str) > 1)) {
				$part2 = substr($str, $pos-1,);
			}
			$str= $part1.$ch.$part2;					# combine all
		} 
		
		elsif ($ch eq KEY_LEFT) {					# arrow left was pressed	
			if ($pos > 0) { $pos-- }				# go left if possible
		}
		
		elsif ($ch eq KEY_RIGHT) {					# arrow right was pressed	
			if ($pos < length($str)) { $pos++ }	# go right if possible
		}

		# Pressing DELETE deletes the character at the current cursor position
		# and shifts the part to the right of it back. If the cursor is at the
		# very right of the line, it acts like a BACKSPACE

		elsif ($ch eq KEY_DC) {						# Delete key pressed
			# See if something is there to delete and if we are not at the end
			if ((length($str) > 0) && ($pos < length($str))) {
				# Split $str into two parts, see earlier
				(my $part1, my $part2) = ("","");
				if (($pos > 0) and (length($str) > 0)) {  
					$part1 = substr($str, 0, $pos);
				}
				if (($pos < length($str)) and (length($str) > 1)) {
					$part2 = substr($str, $pos+1,);
				}
				$str= $part1.$part2;					# combine all
			} 
			# Check for backspace mode, if so, cut off last char and pos--
			elsif (($pos == length($str)) && ($pos != 0)) {
				$pos--;											# go back
				$str= substr($str, 0, length($str) -1);	# cut last char
			}
		}
		
		# BACKSPACE. When pressing backspace, the character left of the cursor
		# is deleted, if it exists. For some reason, KEY_BACKSPACE only is true
		# when pressing CTL+H on my system (and all the others I tested); the
		# other tests lead to success, although it's probably less portable.
		# Found this solution in qe.pl by Wilbert Knol, ZL2BSJ. 

		elsif (($ch eq KEY_BACKSPACE) || (ord($ch)==8) || (ord($ch)==0x7F)) {
			# check if something can be deleted 
			if (($pos != 0) && (length($str) > 0)) {
				# Split $str into two parts, see earlier
				(my $part1, my $part2) = ("","");
				if (($pos > 0) and (length($str) > 0)) {  
					$part1 = substr($str, 0, $pos-1);
				}
				if (($pos < length($str)) and (length($str) > 1)) {
					$part2 = substr($str, $pos,);
				}
				$str= $part1.$part2;					# combine all
				$pos--;									# cursor to left
			}
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

# First check if we are in QSL receive or write mode. When write mode, set
# $write to 1
if ($call eq "W") { $write = "1" }

if ($write) {						# QSL Write mode
	# Check if there are any QSLs in the queue...
	my $c = $dbh->prepare("SELECT NR from log_$mycall WHERE QSLS='Q'");
	$count = $c->execute();			# number of queued QSLs in $count

	# When 0 lines are returned, there is no QSL in the queue 
	# we pop out a message and quit. 

	if ($count == 0) { 
			addstr($win, 0,0, " " x (80 * 22));			# clear window
			addstr($win, 9, 33, "No QSL queued!");
			refresh($win);
			getch();									# wait for user 
			return 2; 									# return to main menu
	}
}
else {								# QSL receive mode
	# check if there are any QSOs that match with the string
	# we entered...
	my $c = $dbh->prepare("SELECT NR from log_$mycall WHERE 
							CALL REGEXP '$call';");

	$count = $c->execute();			# number of QSOs in $count

	# When 0 lines are returned, there is no QSO to chose
	# we pop out a message and quit. 

	if ($count == 0) { 
			addstr($win, 0,0, " " x (80 * 22));			# clear window
			my $msg = "No QSO found matching $call!";
			addstr($win, 9, (80-length($msg))/2 , $msg);
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

	my $lq;					# Database handle.. strange name, eh?
	
	if ($write) {
		$lq = $dbh->prepare("SELECT NR, CALL, NAME, QSLINFO, DATE, T_ON, BAND, 
				MODE, QSLS, QSLR, PWR FROM log_$mycall WHERE QSLS='Q' OR 
				QSLS='X' ORDER BY CALL, DATE, T_ON LIMIT $offset, 22");	
	}
	else {
		$lq = $dbh->prepare("SELECT NR, CALL, NAME, QSLINFO, DATE, T_ON, BAND, 
				MODE, QSLS, QSLR, PWR FROM log_$mycall WHERE CALL REGEXP 
				'$call' ORDER BY DATE, T_ON LIMIT $offset, 22");	
	
	}
	
	$lq->execute();					# Execute the prepared Query

	# Temporary variables for every retrieved QSO ...
	my ($nr, $fcall, $name, $qsli, $date, $time, $band, $mode, $qsls, $qslr,
			$pwr);

	$lq->bind_columns(\$nr,\$fcall,\$name,\$qsli,\$date,\$time,\$band,
						\$mode,\$qsls,\$qslr,\$pwr);
	
	my $y = 0;							# y-position in $win
	while ($lq->fetch()) {				# more QSOs available
		$time = substr($time, 0,5);		# cut seconds from time
		if ($qsls eq "X") { $qsls = "Y" }		# see below
		my $line=sprintf("%-6s %-12s %-11s%-9s%-8s %-5s %4s %4s %-4s %1s %1s        ",
			$nr, $fcall, $name, $qsli, $date, $time, $pwr, $band, $mode, $qsls, $qslr);
		if ($qsls eq "Y") { $qsls = "X" }
		if ($y == $aline) {					# highlight line?
			attron($win, COLOR_PAIR(1));	# highlight
			$chnr = $nr;					# save number of aline
			# save QSL status, depending on read/write mode. When in receive
			# mode, also save qsl-sent status to toggle it when replying to
			# incoming cards.
			if ($write) { $qslstat = $qsls }
			else {
				$qslstat = $qslr;
				$qslstat2 = $qsls;
			}
		}
		addstr($win, $y, 0, $line);
		attron($win, COLOR_PAIR(4));
		($y < 22) ? $y++ : last;			# prints first 22 rows
	}	# all QSOs printed
	
	for (;$y < 22;$y++) {					# for the remaining rows
		addstr($win, $y, 0, " "x80);		# fill with whitespace
	}
	refresh($win);

	$ch = getch();							# we read from keyboard

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
			if ($aline == 21) {
				$aline = 0;				# next page, we start at beginning
				$offset += 21;			# increase the offset accordingly
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
				$aline = 21;			# next page, we start at beginning
				$offset -= 21;			# increase the offset accordingly
			}
			else {						# no scrolling needed
				$aline--;				# increase aline -> one row down
			}	
	}

	# PG DOWN is easier: We can scroll DOWN when there are more available
	# lines than currently displayed: $offset+22.
	elsif (($ch eq KEY_NPAGE) && ($offset+22 < $count)) {
		$offset += 21;					# adjust offset
		$aline = 0;						# Start again at the first line	
	}
	
	# Same with UP. We can scroll up when $offset > 0
	elsif (($ch eq KEY_PPAGE) && ($offset > 0)) {
		$offset -= 21;					# adjust offset
		$aline = 21;					# Start again at the last line	
	}

	# F1 => Back to the main menu. Return 2 for Status. Note that the changes
	# are saved when going back to the menu.. FIXME ? ..
	elsif ($ch eq KEY_F(1)) {
		# changed QSL sent flags back to Y
		$dbh->do("UPDATE log_$mycall SET QSLS='Y' WHERE QSLS='X';");
		return 2;	
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
# FIXME FIXME  file location $mycall.log now.. just for testing
##############################################################################

sub onlinelog {
	my @qso;			# Every QSO we fetch from the DB will be stored here
	my $nr;				# Number of QSOs that are exported.

	open ONLINELOG, ">$mycall.log";

	# We query the database for the fields specified in $onlinedata (by default
	# or from the config file).
	
	my $ol = $dbh->prepare("SELECT $onlinedata FROM log_$mycall ORDER BY DATE");	
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
	
	open QSL, $labeltype;		# Open the label file
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

	my $queue = $dbh->prepare("SELECT CALL, NAME, DATE, T_ON, BAND, 
				MODE, RSTS, PWR, QSLINFO FROM log_$mycall WHERE QSLS='Q'  
				ORDER BY CALL, DATE, T_ON");	

	my $x = $queue->execute();							# Execute Query

#	if ($x eq "0E0") {						# Oops, no QSOs to print!
#		return();							# return nothing
#	}
	
	my ($call, $name, $date, $time, $band, $mode, $rst, $pwr, $mgr);
	$queue->bind_columns(\$call,\$name,\$date,\$time,\$band,\$mode,
														\$rst,\$pwr,\$mgr);
	
	# Now we are fetching row by row of the data which has to be put into the
	# %labels hash.
	while (my @qso = $queue->fetchrow_array()) {	# @qso to put into QSL hash
		# Firstly, the time format shall be changed to HHMM and the band 
		# should get an additional "m"

		$time = substr($time,0,5);				# cut seconds
		$band = $band."m";						# add meters

		# $scall is the "sort call". Usually it's the same as the call, but if
		# there is a QSLINFO, it will replaced by it. $scall is the key for the
		# hash.
        # XXX XXX This was changed again, because like this, QSOs for different
		# stations but the same manager got mixed on one card. For now, the
		# sortcall is always the call. Maybe something to fix later, but since
		# the number of cards with QSL-manager is usually low, it should be OK
		# not to sort after them... Well, maybe for version 0.3.0 XXX XXX XXX  
		my $scall=$call;					# set sortcall to call.

#		if ($mgr) {							# There is a manager
#			$scall = $mgr;					# sort after manager call
#		}

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
			$$lr =~ s/NAME/$name/;
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
	my $start=$_[2];		# startlabel where to start printing
	my $lnr;				# label number absolute
	my $latex;				# the string which will contain the latex document
	my $labeltype=$_[1];	# the type of the QSL label
	my $width;				# width of the QSL label in mm
	my $height;				# height of the QSL label in mm
	my $topmargin;			# top margin of the label sheet
#	my $bottommargin;		# bottom margin of the label sheet
	my $leftmargin;			# left margin of the label sheet
#	my $rightmargin;		# right margin of the label sheet
	my $rows;				# number of label rows
	my $cols;				# number of label columns
	
# Read label geometry from the definition file
	
	open QSL, $labeltype;						# Open the label file
		while (defined (my $line = <QSL>)) {	# Read line into $line
			if ($line =~ /^% WIDTH=(\d+)/) { $width= $1; }
			elsif ($line =~ /^% HEIGHT=(\d+)/) { $height= $1; } 
			elsif ($line =~ /^% TOPMARGIN=(\d+)/) { $topmargin= $1; } 
#			elsif ($line =~ /^% BOTTOMMARGIN=(\d+)/) { $bottommargin= $1; } 
#			elsif ($line =~ /^% RIGHTMARGIN=(\d+)/) { $rightmargin= $1; } 
			elsif ($line =~ /^% LEFTMARGIN=(\d+)/) { $leftmargin= $1; } 
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
while ($start > 3) {			
		$start-= 3;							# next row
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
# QSLINFO, ITUZ, CQZ, STATE, IOTA and CONT are exported into their appropriate 
# fields.  
# TODO Specify export range (date, nr?)
##############################################################################

sub adifexport {
	my $filename = $_[0];				# Where to save the exported data
	my $nr=0;							# number of QSOs exported. return value
	my @q;								# QSOs from the DB..
	
	open ADIF, ">$filename";			# Open ADIF file

	print ADIF "Exported from $mycall 's logbook by YFKlog.\n<eoh>";
	
	my $adif = $dbh->prepare("SELECT CALL, DATE, T_ON, T_OFF, BAND, MODE, QTH,
			NAME, QSLS, QSLR, RSTS, RSTR, REM, PWR, PFX, CONT, QSLINFO, CQZ,
			ITUZ, IOTA, STATE FROM
			log_$mycall"); 
	
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

		# First print those fields which *have* to exist:
		print ADIF "\n\n<call:".length($q[0]).">$q[0] ";
		print ADIF "<qso_date:".length($q[1]).">$q[1] ";
		print ADIF "<time_on:".length($q[2]).">$q[2] ";
		print ADIF "<time_off:".length($q[3]).">$q[3] ";
		print ADIF "<band:".(length($q[4])+1).">$q[4]m ";		# NB: added m
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
		print ADIF '<eor>';						# QSO done
	} # no more lines to fetch..

	close ADIF;

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

	$ftp->put($mycall.'.log') || return "Cannot put $mycall.log, $!";

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
my $war=0;						# number of warnings (unk. fields)
my $ch;							# process adif-file $ch by $ch..
my $header=1;					# while header=1, we are still before <eoh>

open(ERROR, ">> $mycall-import-from-$filename.err");

print ERROR "-"x80;

open ADIF, $filename;

while (my $line = <ADIF>) {
	
	# As long as the current position is in the header, we discard the lines
	# This is the case as long has $header is 1; it is set to 0 as soon as a 
	# <eoh> is found.
	if ($header) {							# we are in the header..
		if ($line =~ /<[Ee][Oo][Hh]>/) {	# end of header? FIXME schoener??
			$header = 0;
		}
		next;								# process next line
	}

	# Now assemble a full line, containing a full QSL until <eor>	
	unless ($line =~ /<[Ee][Oo][Rr]>$/) {	# line ends here
		$fullline .= $line;					# add line to full line
	}
	else {									# we have a <eor>-> full line
		$fullline .= $line;
		$fullline =~ s/<[eE][Oo][Rr]>$//;	# cut EOR
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
	} # else -> fullline complete ends here
} # main loop of reading from ADIF

close ADIF;


# Now  go through all QSOs and check if something has to be converted or
# changed and check if the record is complete. Minimum data needed for a QSO
# are: Call, Date, Time_on, Band, Mode.
# An additional key "valid" is added to the QSO hash. It is set to '1' by
# default, and can be set to '0' when one of the neccessary values is invalid.

for my $i ( 0 .. $#qso ) {					# iterate through Array of Hashes
	$qso[$i]{'valid'} = '1';				# this QSO is now valid

	# Perform DXCC lookup for every callsign.
	# FIXME This is very slow.. improve the dxcc sub!!
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
		$qso[$i]{'mode'} = "\U$qso[$i]{'mode'}";
		
		# change the qso_date field to the proper format YYYY-MM-DD
		# from the current YYYYMMDD
		
		# The date is REQUIRED, so do a crude check if its valid
		# TBD Check if the date is really valid? -- Takes additional time
		# though...
		unless ($qso[$i]{"qso_date"}=~ /^\d{8,8}$/) { $qso[$i]{'valid'} = '0'; }
		
		$qso[$i]{"qso_date"} = substr($qso[$i]{"qso_date"},0,4).'-'.
					substr($qso[$i]{"qso_date"},4,2).'-'.
					substr($qso[$i]{"qso_date"},6,2);

		# rename it to DATE

		$qso[$i]{"date"} = $qso[$i]{"qso_date"};
		delete($qso[$i]{"qso_date"});
		
		# The time format can either be HHMM or HHMMSS. Both have to be
		# converted to HH:MM:SS, for both time_on and time_off.
	
		# Crude check if time is valid (4 or 6 digits)
		unless ($qso[$i]{"time_on"} =~ /^\d{4,6}$/) { $qso[$i]{'valid'} = '0';
	   
		printw $qso[$i]{"time_on"};
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
		
		# Now check if there is band info. if so, cut "m" at the end
			
		if (defined($qso[$i]{"band"})) {				# band info -> cut 'm'
			
			# Crude check if band is valid (1 .. 4 digits + m,M or not)
			unless($qso[$i]{"band"}=~/^\d{1,4}(m|M)?$/) {$qso[$i]{'valid'}='0';}
			
			if ($qso[$i]{"band"} =~ /[Mm]$/) {	# actually ends with m/M?
				substr($qso[$i]{"band"},-1,) = '';	# cut it
			}
		}
		
		# if there is a frequency tag instead of band, the band has to be
		# determined from it. FIXME band data now hardcoded, but should be read
		# from the config file?
		if (defined($qso[$i]{'freq'})) {
			
			my $val = $qso[$i]{'freq'};				# save freq temporarily
			
			if ($val =~ /^(1.[89]|2.0)/) { $qso[$i]{'band'} = '160' } 
			elsif ($val =~ /^[34]./) { $qso[$i]{'band'} = '80' } 
			elsif ($val =~ /(^7.)|(^7$)/) { $qso[$i]{'band'} = '40' } 
			elsif ($val =~ /(^10.(0|1))|(^10$)/) { $qso[$i]{'band'} = '30' } 
			elsif ($val =~ /(^14.)|(^14$)/) { $qso[$i]{'band'} = '20' } 
			elsif ($val =~ /^18/) { $qso[$i]{'band'} = '17' } 
			elsif ($val =~ /(^21.)|(^21$)/) { $qso[$i]{'band'} = '15' } 
			elsif ($val =~ /^24/) { $qso[$i]{'band'} = '12' } 
			elsif ($val =~ /^2(8|9)/) { $qso[$i]{'band'} = '10' } 
			elsif ($val =~ /^5[0-4]/) { $qso[$i]{'band'} = '6' } 
			elsif ($val =~ /^14[4-8]/) { $qso[$i]{'band'} = '2' } 
			elsif ($val =~ /^4[2-5]\d/) { $qso[$i]{'band'} = '70' } 
			
			delete $qso[$i]{'freq'};			# don't need it anymore
		}	
	
		# RST_RCVD and RST_SENT will be renamed to rstr and rsts

		if (defined($qso[$i]{'rst_sent'})) {
			$qso[$i]{'rsts'} = $qso[$i]{'rst_sent'};
			delete($qso[$i]{'rst_sent'});
		}
		
		if (defined($qso[$i]{'rst_rcvd'})) {
			$qso[$i]{'rstr'} = $qso[$i]{'rst_rcvd'};
			delete($qso[$i]{'rst_rcvd'});
		}

		# Check if a prefix was defined in the adif-file. If not, get it from
		# the &wpx sub.
		unless(defined($qso[$i]{'pfx'})) {
				$qso[$i]{'pfx'} = &wpx($qso[$i]{'call'});
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
		# Comments go into the value for key 'rem'. Note that it might already
		# have a value by contest_id!
		if (defined($qso[$i]{"comment"})) {
			unless (defined($qso[$i]{'rem'})) { 		# nothing in REM yet
				$qso[$i]{'rem'} = $qso[$i]{'comment'};	# put it in there
			}
			else {										# remarks field exists
				$qso[$i]{'rem'} .= " ".$qso[$i]{'comment'}; 
			}
			delete($qso[$i]{'comment'});				# delete comment field 
		}
		
		# QSL_VIA information from ADIF goes straight into the QSLINFO field
		if (defined($qso[$i]{"qsl_via"})) {
			$qso[$i]{'qslinfo'} = $qso[$i]{"qsl_via"};
			delete($qso[$i]{"qsl_via"});
		}
		
		# TX_PWR from ADIF goes straight into the PWR field
		if (defined($qso[$i]{"tx_pwr"})) {
			$qso[$i]{'pwr'} = $qso[$i]{"tx_pwr"};
			delete($qso[$i]{"tx_pwr"});
		}
		else {								# no pwr specified in ADIF
			$qso[$i]{'pwr'} = $dpwr;		# default power from config file
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
		print ERROR "\nTHIS QSO WAS NOT IMPORTED! \n\n";
	}

	# After every QSO give a little status output
	
	addstr($win,0,0, "Errors: $err, now importing QSO: ".($i+1).", $qso[$i]{'call'}"." "x80);
	refresh($win);
	
	
} # iterate through AoH, arrives here after every QSO was processed.

# Generate SQL for every QSO which is valid (valid => 1). 
#
# Those hash entries which still do not have a corresponding key in the YFKlog
# database <foo:3>bar  ==> $qso[0]{'foo'}=='bar' will NOT be included in the
# SQL string, instead an error message will be written into the error file.
# For this reason, a hash table containing all possible field names in the
# database is generated. TODO : Read this from the database! 

my %fields = ('call' => 1, 'date' => 1, 't_on' => 1, 't_off' => 1,
				'band' => 1, 'mode' => 1, 'qth' => 1, 'name' => 1, 
				'rstr' => 1, 'rsts' => 1,
				'qsls' => 1, 'qslr' => 1, 'rem' => 1, 'pwr' => 1, 
				'dxcc' => 1, 'pfx' => 1, 'cqz' => 1, 'cont' => 1, 
				'ituz' => 1, 'qslinfo' => 1, 'iota' => 1, 'state' => 1);

for my $i (0 .. $#qso) {					# iterate through Array of Hashes
	my $sql;								# sql-string
	
	if ($qso[$i]{'valid'} eq '0') { next; }	# invalid QSO, don't export!
	delete($qso[$i]{'valid'});				# validity info not needed anymore

	$sql= "INSERT INTO log_$mycall SET ";	# start buildung SQL string
	
	# Now iterate through hash keys. if its valid, i.e. contained in the
	# %fields hash, it will be added to the SQL string, otherwise written to
	# the error-log.
	for my $key (keys %{$qso[$i]}) {	
		if (defined($fields{$key})) {				# if field is valid
			$sql .= "$key='$qso[$i]{$key}', "; 	# add  key-value pair to DB
		}
		else {										# invalid field.
			$war++;
			print ERROR "WARNING: In QSO  $i unknown field: $key =>". 
						" $qso[$i]{$key} IGNORED!\n";
			print ERROR "CALL: $qso[$i]{'call'} DATE: $qso[$i]{'date'}, BAND:".
						"$qso[$i]{'band'}, TIME: $qso[$i]{'t_on'}\n\n";
		}
	}
	# there is ", " too much and a ";" too few at the end
	$sql =~ s/, $/;/;							# remove ", ", add ;
	
	# Now put the QSO into the database:
	$dbh->do($sql);

	# Check if the Name and QTH of the callsign is already known in the CALLS
	# table. If not, use Name and QTH from the ADI-file if it exists. Crop all
	# unneccessary stuff from the call (/P etc).

	if (defined($qso[$i]{'name'}) || defined($qso[$i]{'qth'})) {
		my $call = $qso[$i]{'call'};		# The call to crop
		
		# Split the call at every /, chose longest part. Might go wrong
		# in very rare cases (KH7K/K1A), but I don't care :-) 

		if ($call =~ /\//) {				# dahditditdahdit in call
			my @call = split(/\//, $call);
			my $length=0;                       # length of splitted part
			foreach(@call) {                    # chose longest part
				if (length($_) >= $length) {
					$length = length($_);
					$call = $_;
				}
			}	
		}

		my $sth = $dbh->prepare("SELECT CALL FROM calls WHERE 
									CALL='$call';");
		$sth->execute();
		unless ($sth->fetch()) {		# nothing to fetch -> call is unknown!
			# Add information from ADIF to the database, if QTH/Name is now
			# know, just a empty field.
			unless (defined($qso[$i]{'name'})) {$qso[$i]{'name'}=''}
			unless (defined($qso[$i]{'qth'})) {$qso[$i]{'qth'}=''}
			$dbh->do("INSERT INTO calls (CALL, NAME, QTH) VALUES
				('$call','$qso[$i]{'name'}','$qso[$i]{'qth'}');");
		}
	}
	
}

print ERROR "-"x80;   # to make the output a bit more readable. maybe.
close ERROR;	

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
		
	my $gl = $dbh->prepare("SHOW TABLES;");
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
	open DB, "db_log.sql";				# database definition in this file
	my @db = <DB>;						# read database def. into @db

	# We assume that the callsign in $_[0] is valid, because the &askbox()
	# which produced it only accepted valid callsign-letters.
	
	$call =~ tr/\//_/;					# convert "/" to "_"
	$call =~ tr/[A-Z]/[a-z]/;			# make call lowercase

	
	# Now check if there is also a table existing with the same name
	my $exists = $dbh->do("SHOW TABLES FROM $dbname LIKE 'log_$call';");

	if ($exists eq "0E0") {			# If logbook does not yet exist, create it
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
	my $pos=1;					# position in the QSOs from 1 .. $count
	
	my $win = ${$_[0]};			# Window where output goes. height = 17
    my $sql;					# SQL string with search criteria
	my @qso = @{$_[1]};			# QSO array (local cpy)
	
    # Assemble a SQL string which contains the search criteria. First the
    # columns which should be displayed.  
    $sql = "SELECT NR, CALL, NAME, DATE, T_ON, BAND, MODE, QSLS, QSLR,".
            "DXCC, QSLINFO FROM log_$mycall WHERE NR ";
    # The rest of the string now depends on the content of the @qso-array:
    $sql .= "AND CALL REGEXP '$qso[0]' " if $qso[0];
	#$sql .= "AND DATE REGEXP '$qso[1]' " if $qso[1]; # FIXME
	#$sql .= "AND T_ON REGEXP '$qso[2]' " if $qso[2]; # FIXME
	#$sql .= "AND T_OFF REGEXP '$qso[3]' " if $qso[3]; # FIXME
	# DATE>='...' and DATE<='...' ..
    $sql .= "AND BAND REGEXP '$qso[4]' " if $qso[4];
    $sql .= "AND MODE  REGEXP '$qso[5]' " if $qso[5];
    $sql .= "AND QTH REGEXP '$qso[6]' " if $qso[6];
    $sql .= "AND NAME  REGEXP '$qso[7]' " if $qso[7];
    $sql .= "AND QSLS REGEXP '$qso[8]' " if $qso[8];
    $sql .= "AND QSLR REGEXP '$qso[9]' " if $qso[9];
    $sql .= "AND RSTS REGEXP '$qso[10]' " if $qso[10];
    $sql .= "AND RSTR REGEXP '$qso[11]' " if $qso[11];
    $sql .= "AND REM REGEXP '$qso[12]' " if $qso[12];
    $sql .= "AND PWR REGEXP '$qso[13]' " if $qso[13];
    $sql .= "AND DXCC REGEXP '$qso[14]' " if $qso[14];
    $sql .= "AND PFX REGEXP '$qso[15]' " if $qso[15];
    $sql .= "AND CONT REGEXP '$qso[16]' " if $qso[16];
    $sql .= "AND ITUZ REGEXP '$qso[17]' " if $qso[17];
    $sql .= "AND CQZ REGEXP '$qso[18]' " if $qso[18];
    $sql .= "AND QSLINFO REGEXP '$qso[19]' " if $qso[19];
    $sql .= "AND IOTA REGEXP '$qso[20]' " if $qso[20];
    $sql .= "AND STATE REGEXP '$qso[21]' " if $qso[21];

	# We have to know how many QSOs are fitting the current search criteria:
	my $eq = $dbh->prepare($sql);
	$count = $eq->execute();
	if ($count eq "0E0") { return 0 };		# no QSO to edit-> $editnr = 0.
	
do {
	my $eq = $dbh->prepare($sql. "ORDER BY DATE, T_ON LIMIT $offset, 17");
	$eq->execute();
	my ($nr, $call, $name, $date, $time, $band, $mode, 			# temp vars
						$qsls, $qslr, $dxcc, $qslinfo);
	$eq->bind_columns(\$nr,\$call,\$name, \$date,\$time,\$band,\$mode,
						\$qsls,\$qslr,\$dxcc,\$qslinfo);
	
	my $y = 0;					# y cordinate in the window (absolute position)
	while ($eq->fetch()) {		# QSO available
		$time = substr($time, 0,5); 	# cut seconds from time
		my $line = sprintf("%-6s %-14s %-12s %-8s %-5s %4s %-4s %1s %1s %-4s %-9s", 
				$nr, $call, $name, $date, $time, $band, $mode, $qsls, 
				$qslr, $dxcc, $qslinfo);
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
		
	$ch = getch(); 							# Get keyboard input

	if ($ch eq KEY_DOWN) {					# arrow key down was pressed
		# 1. Can we go down => $pos < $count?
		# 2. do we have to scroll down? => $aline < 15?
		if ($pos < $count) {				# we can go down!
			if ($aline < 16) {				# stay on same page
				$aline++;
				$pos++;
			}
			else {							# scroll down!
				$offset += 17;				# next 17 QSOs from DB!
				$aline=0;					# start at first (highest) line
				$pos++;
			}
		}
	} # key down

	elsif ($ch eq KEY_UP) {					# arrow key down was pressed
		# 1. Can we go up => $pos > 1?
		# 2. do we have to scroll up? => $aline = 0?
		if ($pos > 1) {						# we can go up!
			if ($aline > 0) {				# stay on same page
				$aline--;
				$pos--;
			}
			else {							# scroll up!
				$offset -= 17;				# next 17 QSOs from DB!
				$aline=16;					# start at lowest line
				$pos--;
			}
		}
	} # key up

	elsif ($ch eq KEY_NPAGE) {				# scroll a full page down
		# can we scroll? are there more QSOs than fit on the current page?
		if (($pos-$aline+17) < $count) {
			$offset += 17;					# scroll a page = 17 lines
			$pos += (17- $aline);			# consider $aline!	
			$aline=0;
		}
	}

	elsif ($ch eq KEY_PPAGE) {				# scroll a full page up
		# can we scroll?
		if (($pos-$aline) > 17) {
			$offset -= 17;					# scroll a page = 17 lines
			$pos -= ($aline+1);				# consider $aline!	
			$aline=16;
		}
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
my $q = $dbh->prepare("SELECT CALL, DATE, T_ON, T_OFF, BAND, MODE, QTH,
				NAME, QSLS,QSLR, RSTS, RSTR, REM, PWR, DXCC, PFX, CONT, ITUZ,
				CQZ, QSLINFO, IOTA, STATE, NR FROM log_$mycall 
				WHERE NR='$_[0]'");
$q->execute;
@qso = $q->fetchrow_array;
# proper format for the date (yyyy-mm-dd ->  ddmmyyyy)
$qso[1] = substr($qso[1],8,2).substr($qso[1],5,2).substr($qso[1],0,4);
# proper format for the times. hh:mm:ss -> hhmm
$qso[2] = substr($qso[2],0,2).substr($qso[2],3,2);
$qso[3] = substr($qso[3],0,2).substr($qso[3],3,2);

for (my $x=0;$x < 23;$x++) {				# iterate through all input windows 
	addstr(${$_[1]}[$x],0,0,$qso[$x]);		# add new value from @qso.
	refresh(${$_[1]}[$x]);
}

return @qso;
} # &geteditqso;

##############################################################################
# &editw  reads what the user types into a window, depending on $_[1],
# only numbers, callsign-characters, only letters or (almost) everything
# is allowed. $_[2] contains the windownumber, $_[3] the reference to the
# QSO-array and $_[0] the reference to the Input-window-Array.
#
#  (Note that this sub is mostly identical to &readw; except for F-key
#  handling)
#
# The things you enter via the keyboard will be checked and if they are
# matching the criterias of $_[1], it will be printed into the window and saved
# in @qso. Editing is possible with arrow keys, delete and backspace. delete
# acts like backspace when the cursor is at the end of the line.
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
	my $pos = 0;								# cursor position in the string
	
	my $debug=0;
	
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

	# I originally used while($ch = getch), but it stops when enter a Zero.
	# while (1) seems bad to me. Any suggestions?
	while (1) {										# loop infinitely
	
		addstr($win,0,0, $input." "x80);		# pass $input to window,
												# delete all after $input.
		move ($win,0,$pos);						# move cursor to $pos
		refresh($win);							# show new window
		
		$ch = getch;							# wait for a character
		
		# We first check if it is a legal character of the specified $match,
		# if so, it will be added to the string (at the proper position!) 
		if (($ch =~ /^$match$/)) {					# check if it's "legal"
			unless ($_[1] == 3) {					# Unless Name, QTH mode
				$ch =~ tr/[a-z]/[A-Z]/;				# make letters uppercase
			}
			# The new character will be added to $input. $input is split into 2
			# parts, the part before $pos and the part after $pos, the new
			# character is placed in between. (Of course the 2nd part can be 
			# empty)
			$pos++;
			(my $part1, my $part2) = ("","");	# init cos one might be undef!
			if (($pos > 0) and (length($input) > 0)) {  # first part exists
				$part1 = substr($input, 0, $pos-1);
			}
			if (($pos < length($input)) and (length($input) > 1)) {
				$part2 = substr($input, $pos-1,);
			}
			$input = $part1.$ch.$part2;					# combine all
		} 
		
		# The l/r arrow keys change the position of the cursor to left or right
		# but only within the boundaries of $input.
		
		elsif ($ch eq KEY_LEFT) {					# arrow left was pressed	
			if ($pos > 0) { $pos-- }				# go left if possible
		}
		
		elsif ($ch eq KEY_RIGHT) {					# arrow right was pressed	
			if ($pos < length($input)) { $pos++ }	# go right if possible
		}

		# Pressing DELETE deletes the character at the current cursor position
		# and shifts the part to the right of it back. If the cursor is at the
		# very right of the line, it acts like a BACKSPACE

		elsif ($ch eq KEY_DC) {						# Delete key pressed
			# See if something is there to delete and if we are not at the end
			if ((length($input) > 0) && ($pos   < length($input))) {
				# Split $input into two parts, see earlier
				(my $part1, my $part2) = ("","");
				if (($pos > 0) and (length($input) > 0)) {  
					$part1 = substr($input, 0, $pos);
				}
				if (($pos < length($input)) and (length($input) > 1)) {
					$part2 = substr($input, $pos+1,);
				}
				$input = $part1.$part2;					# combine all
			} 
			# Check for backspace mode, if so, cut off last char and pos--
			elsif (($pos == length($input)) && ($pos != 0)) {
				$pos--;											# go back
				$input = substr($input, 0, length($input) -1);	# cut last char
			}
		}
		
		# BACKSPACE. When pressing backspace, the character left of the cursor
		# is deleted, if it exists. For some reason, KEY_BACKSPACE only is true
		# when pressing CTL+H on my system (and all the others I tested); the
		# other tests lead to success, although it's probably less portable.
		# Found this solution in qe.pl by Wilbert Knol, ZL2BSJ. 

		elsif (($ch eq KEY_BACKSPACE) || (ord($ch)==8) || (ord($ch)==0x7F)) {
			# check if something can be deleted 
			if (($pos != 0) && (length($input) > 0)) {
				# Split $input into two parts, see earlier
				(my $part1, my $part2) = ("","");
				if (($pos > 0) and (length($input) > 0)) {  
					$part1 = substr($input, 0, $pos-1);
				}
				if (($pos < length($input)) and (length($input) > 1)) {
					$part2 = substr($input, $pos,);
				}
				$input = $part1.$part2;					# combine all
				$pos--;									# cursor to left
			}
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
				for (0 .. 22) {	${$_[3]}[$_] = ''; }	# clear @qso.
				return 0;							# success, leave editw
			}	# if no success, we continue in the loop.
		}

		# exit to the MAIN MENU
		elsif ($ch eq KEY_F(1)) {		
			return 'm';						# -> MENU!
		}

		# F3 clears the current QSO and returns to the CALL input field.
		elsif ($ch eq KEY_F(3)) {			# F3 pressed -> clear QSO
			for (0 .. 22) {					# iterate through windows 0-13
				addstr(@{$_[0]}[$_],0,0," "x80);	# clear it
				refresh(@{$_[0]}[$_]);
			}
			for (0 .. 22) {	${$_[3]}[$_] = ''; }	# clear @qso.
			return 0;						# return 0 (= go back to callsign) 
		}
		
		# F4 --> delete the QSO, but first ask if really wany to delete it.
		# Then delete it and clear all fields, like with F3.
		elsif  ($ch eq KEY_F(4) && ${$_[3]}[22]) {	# pressed F4 -> delete QSO
			my $answer = &askbox(7,0,4,80,'\w', 
			"Are you sure you want to delete the above QSO *permanently*?  (yes/no)");
			if ($answer eq 'm') { return 2 }		# menu
			elsif ($answer eq 'yes') {				# yes, delete! 
				$dbh->do("DELETE from log_$mycall WHERE NR='${$_[3]}[22]'");
				for (0 .. 22) {						# iterate through windows
					addstr(@{$_[0]}[$_],0,0," "x80);	# clear it
					refresh(@{$_[0]}[$_]);
				}
				for (0 .. 22) {	${$_[3]}[$_] = ''; }	# clear @qso.
				return 0;					# return 0 (= go back to callsign) 
			};
			
		}
		
		# F5 -> We want to search the DB for the give criteria...
		elsif ($ch eq KEY_F(5)) {		
			${$_[3]}[$_[2]] = $input;		# save field to @qso
			return 2;						 
		}

		# QUIT YFKlog
		elsif ($ch eq KEY_F(12)) {			# QUIT
			endwin;							# Leave curses mode	
			exit;
		}
	}
}  # &editw;


##############################################################################
# &updateqso  Updates the changes made to a QSO in the Search&Edit mode 
# into the database. The QSO is checked for validity of the fields.
##############################################################################

sub updateqso {
	my @qso = @{$_[0]};					# QSO array (0 .. 22)

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
		($qso[21] =~ /^([A-Z]{2,2})?$/)				# "valid" state
		# RST, PWR not checked, will be 599 / 0 by default in the database,
		) {								# VALID ENTRY!  update into database

			$qso[1] =						# put date in YYYY-MM-DD format
			substr($qso[1],4,)."-".substr($qso[1],2,2)."-".substr($qso[1],0,2);
			$qso[2] = $qso[2]."00";			# add seconds
			$qso[3] = $qso[3]."00";			# add seconds

			# we are now ready to save the QSO
			
			$dbh->do("UPDATE log_$mycall SET CALL='$qso[0]', DATE='$qso[1]',
						T_ON='$qso[2]', T_OFF='$qso[3]', BAND='$qso[4]',
						MODE='$qso[5]', QTH='$qso[6]', NAME='$qso[7]',
						QSLS='$qso[8]', QSLR='$qso[9]', RSTS='$qso[10]',
						RSTR='$qso[11]', REM='$qso[12]', PWR='$qso[13]',
						DXCC='$qso[14]', PFX='$qso[15]', CONT='$qso[16]',
						ITUZ='$qso[17]', CQZ='$qso[18]', QSLINFO='$qso[19]',
						IOTA='$qso[20]', STATE='$qso[21]'
						WHERE NR='$qso[22]';");
			return 1;			# successfully saved
	}
	else {
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
	my $bands = '160 80 40 30 20 17 15 12 10';  # FIXME from .yfklog
	my @bands = split(/ /, $bands); # Generate list of Bands for awards
	my %result;						# key=band, value=dxccs  WORKED DXCCs
	my %resultc;					# key=band, value=dxccs  CONFIRMED DXCCs
	my %abdxcc;						# allband DXCCs combined. 'dxcc'->0/1
	my %abdxccc;					# same, but QSL received/confirmed 
	my %sumdxcc;					# "DL"->"160 20 15 10"  worked
	my %sumdxccc;					# "DL"->"160"  cfmed

	# TBD The data structure sucks, should be done with 'twodimensional' hash,
	# which has DXCC and BAND as keys. later.......
	
	foreach (@bands) {				# reset results to 0 for all bands
		$result{$_} = 0;
		$resultc{$_} = 0;
	}

foreach my $band (@bands) {
	my %dxccc;			#  hash to check if the entity is new and CONFIRMED
	my %dxcc;			#  hash to check if the current entity is new.
	my $sth = $dbh->prepare("SELECT $awardtype, QSLR FROM log_$mycall WHERE 
								BAND='$band' AND $daterange");
	$sth->execute();
	my ($dx,$qslr);
	$sth->bind_columns(\$dx,\$qslr);	
	while ($sth->fetch()) {						# go through all QSOs	
		if ($dx eq '') { next; }				# no entry for this award type
		unless (defined($dxcc{$dx})) {			# DXCC not in hash -> new DXCC
			$result{$band}++;					# increase counter
			$dxcc{$dx} = 1;						# mark as worked in dxcc hash
			$sumdxcc{$dx} .= $band.' ';			# save band for overall stats
			unless (defined($abdxcc{$dx})) {	# new DXCC over all bands?
				$abdxcc{$dx} = 1;				# mark it worked
			}
		}
		if (!defined($dxccc{$dx}) && ($qslr eq 'Y')) {	# QSL-received
			$resultc{$band}++;							# increase counter
			$dxccc{$dx} =1;
			$sumdxccc{$dx} .= $band.' ';		# save band for overall stats
			unless (defined($abdxccc{$dx})) {	# new DXCC overall bands cfmed
				$abdxccc{$dx} = 1;				# mark it confirmed!
			}
		}
	}
} # foreach band

# now include the overall number into the result hash
$result{'All'} = scalar(keys(%abdxcc));
$resultc{'All'} = scalar(keys(%abdxccc));

# Create a HTML-output of the full award score.
open HTML, ">$mycall-$awardtype.html";

# Generate Header and Table header
print HTML "<h1>$awardtype Status for \U$mycall</h1>\n";
print HTML "Produced with YFKlog. \n <table border=1>
<tr><th>DXCC</th>";

# Table heades for each band....
foreach my $band (@bands) {
	print HTML "<th> $band </th>";
}
print HTML "</tr>\n";

# For each of the worked DXCCs add W, C or nothing..
foreach my $key (sort keys %sumdxcc) {
	my $string = "<tr><td><strong>$key</strong></td>";
	$sumdxccc{$key} .= '';						# to make it defined for sure

	# now create a table cell for each band. either empty (not worked), W or C
	foreach my $band (@bands) {
		if (index($sumdxccc{$key},$band) != -1) {		# band confirmed!
			$string .= "<td> C </td>";
		}
		elsif (index($sumdxcc{$key}, $band) != -1) {		# band worked!
			$string .= "<td> W </td>";
		}
		else {											# not worked
			$string .= "<td>&nbsp;</td>";
		}
	}	

print HTML $string."\n";
}

# Summary line for WORKED
print HTML "<tr><td>wkd: $result{'All'} </td>";
foreach my $band (@bands) {
	print HTML "<td> $result{$band} </td>"
}
print HTML "</tr>\n";

# Summary line for CONFIRMED
print HTML "<tr><td>cfm: $resultc{'All'} </td>";
foreach my $band (@bands) {
	print HTML "<td> $resultc{$band} </td>"
}
print HTML "</tr>\n";
print HTML "</table>";

close HTML;


# Return the local hashes to the main program.
%{$_[2]} = %result;
%{$_[3]} = %resultc;

return 0;
}

###############################################################################
# statistics  -- create  QSO by BAND or QSO by YEAR statistics.
# $_[0] = "BAND" or TODO "YEAR"
###############################################################################

sub statistics {
	my $type = $_[0];
	my %stat;					# '160'(m) -> '666' (QSOs), or '1999' -> '123'
	
	my $sth = $dbh->prepare("SELECT BAND FROM log_$mycall WHERE 1");
	$sth->execute();
	my $band;
	$sth->bind_columns(\$band);	
	while ($sth->fetch()) {					# go through ALL QSOs
		$stat{$band}++;						# Add QSO to the band...
	}	

	return %stat;	
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
	
	my $sth = $dbh->prepare("SELECT NAME, QTH FROM calls WHERE CALL='$call'");
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
		
		$ch = getch;							# wait for a character
		
		# We first check if it is a legal character of the specified $match,
		# if so, it will be added to the string (at the proper position!) 
		if (($ch =~ /^$match$/)) {					# check if it's "legal"
			# The new character will be added to $input. $input is split into 2
			# parts, the part before $pos and the part after $pos, the new
			# character is placed in between. (Of course the 2nd part can be 
			# empty)
			$pos++;
			(my $part1, my $part2) = ("","");	# init cos one might be undef!
			if (($pos > 0) and (length($input) > 0)) {  # first part exists
				$part1 = substr($input, 0, $pos-1);
			}
			if (($pos < length($input)) and (length($input) > 1)) {
				$part2 = substr($input, $pos-1,);
			}
			$input = $part1.$ch.$part2;					# combine all
		} 
		
		# The l/r arrow keys change the position of the cursor to left or right
		# but only within the boundaries of $input.
		
		elsif ($ch eq KEY_LEFT) {					# arrow left was pressed	
			if ($pos > 0) { $pos-- }				# go left if possible
		}
		
		elsif ($ch eq KEY_RIGHT) {					# arrow right was pressed	
			if ($pos < length($input)) { $pos++ }	# go right if possible
		}

		# Pressing DELETE deletes the character at the current cursor position
		# and shifts the part to the right of it back. If the cursor is at the
		# very right of the line, it acts like a BACKSPACE

		elsif ($ch eq KEY_DC) {						# Delete key pressed
			# See if something is there to delete and if we are not at the end
			if ((length($input) > 0) && ($pos   < length($input))) {
				# Split $input into two parts, see earlier
				(my $part1, my $part2) = ("","");
				if (($pos > 0) and (length($input) > 0)) {  
					$part1 = substr($input, 0, $pos);
				}
				if (($pos < length($input)) and (length($input) > 1)) {
					$part2 = substr($input, $pos+1,);
				}
				$input = $part1.$part2;					# combine all
			} 
			# Check for backspace mode, if so, cut off last char and pos--
			elsif (($pos == length($input)) && ($pos != 0)) {
				$pos--;											# go back
				$input = substr($input, 0, length($input) -1);	# cut last char
			}
		}
		
		# BACKSPACE. When pressing backspace, the character left of the cursor
		# is deleted, if it exists. For some reason, KEY_BACKSPACE only is true
		# when pressing CTL+H on my system (and all the others I tested); the
		# other tests lead to success, although it's probably less portable.
		# Found this solution in qe.pl by Wilbert Knol, ZL2BSJ. 

		elsif (($ch eq KEY_BACKSPACE) || (ord($ch)==8) || (ord($ch)==0x7F)) {
			# check if something can be deleted 
			if (($pos != 0) && (length($input) > 0)) {
				# Split $input into two parts, see earlier
				(my $part1, my $part2) = ("","");
				if (($pos > 0) and (length($input) > 0)) {  
					$part1 = substr($input, 0, $pos-1);
				}
				if (($pos < length($input)) and (length($input) > 1)) {
					$part2 = substr($input, $pos,);
				}
				$input = $part1.$part2;					# combine all
				$pos--;									# cursor to left
			}
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
		$dbh->do("delete from calls where CALL = '$_[1]'")
	}
	if ($_[0] == 0) {
		$dbh->do("update calls set name='$_[2]', QTH='$_[3]' where call='$_[1]' ");
	}
}

















return 1;

#  Just to test and debug.

while (1) {
        chomp(my $line = <STDIN> );
if (my $prefix =  &wpx("\U$line")) {

my @dxcc =  &dxcc("\U$line");

print "Main Prefix:    $dxcc[7]\n";
print "Country Name:   $dxcc[0]\n";
print "WAZ Zone:       $dxcc[1]\n";
print "ITU Zone:       $dxcc[2]\n";
print "Continent:      $dxcc[3]\n";
print "Latitude:       $dxcc[4]\n";
print "Longitude:      $dxcc[5]\n";
print "UTC shift:      $dxcc[6]\n";
        
print "\nPrefix after WPX rules: $prefix\n\n";
}
}
