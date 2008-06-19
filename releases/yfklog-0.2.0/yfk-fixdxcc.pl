#!/usr/bin/perl -w

# Fixing the DXCC status of YFKlog 0.1.0 for use with Version 0.2.0 and later
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
use DBI;
use Curses;


require "yfksubs.pl";

# We load the default values for some variables that can be changed in .yfklog

my $dbserver = "localhost";						# Standard MySQL server
my $dbport = 3306;								# standard MySQL port	
my $dbuser = "";								# DB username
my $dbpass = "";								# DB password
my $dbname = "";								# DB name
my $mycall = '';

open CONFIG, ".yfklog" or die "Cannot open configuration file. Please make sure
it is in the current directory. Error: $!";

while (defined (my $line = <CONFIG>))   {			# Read line into $line
	if ($line =~ /^dbserver=(.+)/) {				# We read the MySQL Server
			$dbserver= $1;
	}
	elsif ($line =~ /^dbport=(.+)/) {				# We read the Server's port
			$dbport = $1;
	}
	elsif ($line =~ /^mycall=(.+)/) {				# We read the own call
			$mycall = $1;
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
}

close CONFIG;	# Configuration read. Don't need it any more.

## We connect to the Database now...
my $dbh = DBI->connect("DBI:mysql:$dbname;host=$dbserver", $dbuser, $dbpass) 
		or die "Could not connect to Database: " . DBI->errstr;

system ('clear');
print "yfk-fixdxcc.pl -- Fixing the DXCC status of a database of yfklog-0.1.0

In YFKlog-0.1.0, the DXCC information for some QSOs was wrong, due to some
little bugs. This can be fixed with this little script.

PLEASE BACK UP YOUR DATA BEFORE YOU CONTINUE! You can either export your whole
log as ADIF or do a mysqldump of your log, like this:

mysqldump -p DBNAME log_yourcall

where DBNAME is the name of the database, as specified in .yfklog (in your case
$dbname) and yourcall is the name of the table, usually your call, as specified
in .yfklog (in this case your default is $mycall, but there might be different
tables for different calls!).

In your database the following logbook tables were created:
";
my %logs;                   # logs in the database

my $gl = $dbh->prepare("SHOW TABLES;");
$gl->execute();

while(my $l = $gl->fetchrow_array()) {
	if ($l =~ /^(log_.*)$/) {           # a new logbook found
		$logs{$1} = 1;
		print " $1 ";
	}
}

print "

The default logbook is log_$mycall.

Pse enter the logbook (incl log_) which you want to fix. [log_$mycall] ";
my $logbook = <>;

chomp $logbook;

if ($logbook eq '') { $logbook = "log_$mycall"};

system("clear ");

unless (defined($logs{$logbook})) {
		print "Sorry, the logbook you selected does not exist!\n"; exit;
}	

print "You selected $logbook ... now checking for any malformed DXCC entries.

First changing malformed WAE entries in the DXCC field to proper DXCC...

";
my $nr = $dbh->do("UPDATE $logbook SET DXCC='TA' WHERE DXCC='*TA1' ");
print $nr . " times changed *TA1 to TA\n";
$nr = $dbh->do("UPDATE $logbook SET DXCC='OE' WHERE DXCC='*4U1' ");
print $nr . " times changed *4U1V to OE\n";
$nr = $dbh->do("UPDATE $logbook SET DXCC='GM' WHERE DXCC='*GM/' ");
print $nr . " times changed *GM/s to GM\n";
$nr = $dbh->do("UPDATE $logbook SET DXCC='I' WHERE DXCC='*IG9' ");
print $nr . " times changed *IG9 to I\n";
$nr = $dbh->do("UPDATE $logbook SET DXCC='I' WHERE DXCC='*IT9' ");
print $nr . " times changed *IT9 to I\n";
$nr = $dbh->do("UPDATE $logbook SET DXCC='JW' WHERE DXCC='*JW/' ");
print $nr . " times changed *JW/b to JW\n";

print "
Now removing any slashes out of the DXCC fields. In some cases, the DXC info
might have been lost since the DXCC field is only 4 chars wide and for example
VP8/* becomes VP8/. Because of that, the DXCC is retrieved again with the new
DXCC functions of yfklog 0.2.0.
";

my $slash = $dbh->prepare("SELECT NR, CALL, DXCC from $logbook 
		WHERE DXCC REGEXP '/'");
$slash->execute();
my ($nr, $call, $dxcc);
$slash->bind_columns(\$nr, \$call, \$dxcc);

my $counter = 0;

while ($slash->fetch()) {
print "$nr $call $dxcc   --> changed DXCC to ";
my @dxcc = &dxcc($call);
print "$dxcc[7] \n";
$dbh->do("UPDATE $logbook set DXCC='$dxcc[7]' WHERE NR='$nr'");
$counter++;
}	

print "

changed $counter DXCCs with slashes inside.

That's all! DXCC statistics should be more accurate now. You can run this
script again if you want to change another logbook.
";


















