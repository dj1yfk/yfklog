#!/usr/bin/perl -w

# identation looks best with tw=4

# yfklog - a general purpose ham radio logbook
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

use strict;   	        # No shabby code beyond this point :)
use DBI;				# Database interface
use Curses;	
use Net::FTP;			# upload of online log or backup

require "yfksubs.pl";	# Read the subs for dxcc, wpx parsing etc

our $yfkver = '0.3.1';	# Program Version

# Here we give some variables their default values. Some of them will be
# changed later when reading the config-file .yfklog.

my $mycall;				# will be the callsign of the active log
my $dband="80";			# default band 80m. 3525kHz precisely :-)
my $bands = '160 80 40 30 20 17 15 12 10 2';    # bands for award purposes
my $dmode="CW";			# of course we want CW as default mode
my $dpwr ="100";		# life is too long for QRO
my $dqsls="Q";			# default QSL sent: Q = put in queue
my $dqslr="N";			# default QSL recvd: N - No
my $workcall = "";		# The station we are currently working
my $status="2";			# status: 1: Logging (default), 2: menu  3: QSL mode
my @wi;					# contains the windows inside the input-window
						# 0 Callsign, 1  Date, 2 time on, 3 time off
						# 4 QRG, 5 Mode, 6 QTH, 7 Name, 8 QSL-TX, 9 QSL-RX
						# 10 RSTs, 11 RSTr, 12 Remarks, 13 PWR
my @qso = ("","","","",	# Data of the current QSO which is read from input.
"","","","","","","",""	# 0 Callsign, 1  Date, 2 time on, 3 time off
,"","");				# 4 QRG, 5 Mode, 6 QTH, 7 Name, 8 QSL-TX, 9 QSL-RX
						# 10 RSTs, 11 RSTr, 12 Remarks, 13 PWR
my $qso = \@qso;		# QSO reference
my $editnr=0;			# the QSO which we are editing. 0 = no QSO is edited nw
my $screenlayout=0;		# screen layout - 0 or 1 

open CONFIG, ".yfklog" or die "Cannot open configuration file. Please make sure
it is in the current directory. Error: $!";

while (defined (my $line = <CONFIG>)) {			# Read line into $line
	if ($line =~ /^mycall=(.+)/) { $mycall= "\L$1"; }
	if ($line =~ /^dband=(.+)/)  { $dband= $1; }				
	if ($line =~ /^awardbands=(.+)/)  { $bands = $1; }				
	if ($line =~ /^dmode=(.+)/)  { $dmode= $1; }				
	if ($line =~ /^dpwr=(.+)/)   { $dpwr= $1; }				
	if ($line =~ /^dqsls=(.+)/)   { $dqsls = $1; }				
	if ($line =~ /^dqslr=(.+)/)   { $dqslr = $1; }				
	if ($line =~ /^screenlayout=(.+)/)   { $screenlayout = $1; }				
	if ($line =~ /^screenlayout=(.+)/)   { $screenlayout = $1; }				
}
close CONFIG;

initscr;					# we go into curses mode
noecho; 					# keyboard input will not be echoed
keypad(1);					# enable keys like F1, F2,.. cursor keys etc
unless (has_colors) {		# we need colors, if not available, die
	die "No colors"; }
start_color;				# got colors!
curs_set(0);				# cursor invisible

printw &splashscreen($yfkver);

# if needed, update the database to the current version, create log tables,
# etc.

&databaseupgrade();

getch;						# Wait for key to remove splashscreen

# Now the main windows will be generated: 
# In every case visible are the windows $whead (the top line, which will show
# status information) and $whelp (the bottom line which will show short help
# instructions).

# For LOGGING MODE there are 4 windows: The top window is the input mask
# called $winput. Below is $winfo where information about the worked station is
# displayed (DXCC, country name, WPX, Zones, Distance and bearing..). Then the
# window splits up and there are $wlog and $wqsos next to each other. $wlog
# shows the log, $wqsos shows previous QSOs with the station you are currently
# working.

# The windows have a fixed width and height and assume a 80x24 terminal.
# However if you use a larger terminal, no problems should occur.

init_pair(1, COLOR_BLACK, COLOR_YELLOW);	# First we initialise some colors
init_pair(2, COLOR_BLUE, COLOR_GREEN);		
init_pair(3, COLOR_BLUE, COLOR_CYAN);	
init_pair(4, COLOR_WHITE, COLOR_BLUE);
init_pair(5, COLOR_WHITE, COLOR_BLACK);	


# GENERAL WINDOWS, always visible
my $whead  = &makewindow(1,80,0,0,2);		# head window
my $whelp  = &makewindow(1,80,23,0,2);		# help window

# LOGGING MODE WINDOWS  ($status = 1)
my $winput = &makewindow(3,80,1,0,1);		# Input Window
my $winfo  = &makewindow(3,80,4,0,2);		# DXCC/Info Window

# depending on $screenlayout, the windows for previous QSOs and the recent
# logbook are either next to each other or on top of each other.

my ($wlog, $wqsos);

if ($screenlayout==0) {						# original YFKlog style
	$wlog   = &makewindow(16,30,7,0,3);		# Logbook
	$wqsos  = &makewindow(16,50,7,30,4);		# prev. QSOs window
}
elsif ($screenlayout==1) {						# more info, smaller windows
	$wlog   = &makewindow(8,80,7,0,3);		# Logbook
	$wqsos  = &makewindow(8,80,15,0,4);		# prev. QSOs window
}

# EDIT / SEARCH MODE WINDOWS ($status = 10)
my $wedit      = &makewindow(5,80,1,0,1);		# Edit Window
my $weditlog   = &makewindow(17,80,6,0,4);		# Search results


# Inside the input-window, the input fields will also be defined as single
# windows, so it will be easy to fill them with data. These are stored in the
# array @wi (windows input).
# The first 14 are used in the log entry in the normal logging mode, another 8
# windows are only used when editing QSOs in the "Search and Edit" function.
# There you can change ALL fields which are stored in the database, which is
# not possible in the normal QSO entry mask (because it's hardly needed and
# only eats up screen space).

$wi[0] = &makewindow(1,12,1,6,5);			# Input Window: Call
$wi[1] = &makewindow(1,8,1,26,5);			# Input Window: Date
$wi[2] = &makewindow(1,4,1,42,5);			# Input Window: T on
$wi[3] = &makewindow(1,4,1,54,5);			# Input Window: T off
$wi[4] = &makewindow(1,4,1,65,5);			# Input Window: Band
$wi[5] = &makewindow(1,4,1,76,5);			# Input Window: Mode
$wi[6] = &makewindow(1,13,2,5,5);			# Input Window: QTH
$wi[7] = &makewindow(1,8,2,26,5);			# Input Window: Name
$wi[8] = &makewindow(1,1,2,42,5);			# Input Window: QSLs
$wi[9] = &makewindow(1,1,2,50,5);			# Input Window: QSLr
$wi[10] = &makewindow(1,7,2,58,5);			# Input Window: RSTs 
$wi[11] = &makewindow(1,7,2,72,5);			# Input Window: RSTr 
$wi[12] = &makewindow(1,56,3,9,5);			# Input Window: Remarks
$wi[13] = &makewindow(1,4,3,72,5);			# Input Window: Power

$wi[14] = &makewindow(1,4,4,6,5);			# Edit  Window: DXCC
$wi[15] = &makewindow(1,8,4,17,5);			# Edit  Window: PFX
$wi[16] = &makewindow(1,2,4,33,5);			# Edit  Window: CONT
$wi[17] = &makewindow(1,2,4,43,5);			# Edit  Window: ITUZ
$wi[18] = &makewindow(1,2,4,51,5);			# Edit  Window: CQZ
$wi[19] = &makewindow(1,8,4,64,5);			# Edit  Window: QSLINFO
$wi[20] = &makewindow(1,6,5,6,5);			# Edit  Window: IOTA
$wi[21] = &makewindow(1,2,5,21,5);			# Edit  Window: STATE
$wi[22] = &makewindow(1,7,5,72,5);			# Window: NR of QSO
$wi[23] = &makewindow(1,1,5,32,5);			# Edit  Window: QSLRL
$wi[24] = &makewindow(1,6,5,39,5);			# Edit  Window: OPERATOR
$wi[25] = &makewindow(1,6,5,53,5);			# Edit  Window: GRID
my  $wi = \@wi;			# Window reference

# GENERAL purpose Window all over the screen, except top and bottom lines
my $wmain = &makewindow(22,80,1,0,4);		# Input Window


##############################################################################
# MAIN PROGRAM LOOP
# This is the outer loop of the program. Depending on $status, it choses
# between: Log-Input mode ($status = 1), Main menu ($status = 2), QSL-mode
# ($status = 3)  TBD TO BE CONTINUED
##############################################################################

while (1) {				# Loop infinitely;  most outer loop.


##############################################################################
# LOGGING MODE  ($status = 1)
# While the status is 1, we are in logging mode. This means that the windows
# are initialized with proper content and refreshed. Then the logging process
# starts.
##############################################################################

while ($status == 1) {	
my $aw=1;				# Active Window during main logging loop. 1 = $winput, 
						# 2 = $wlog, 3 = $wqsos
my $af=1;				# Active field within $winput (Call, Date...)
						
# The text which does not change during the log-session is written:
addstr($whead, 0,0, "YFKlog v$yfkver - Logging Mode - Active Logbook: \U$mycall");
addstr($winput, 0,0, &entrymask(0));			# creates the input entry mask
addstr($winput, 1,0, &entrymask(1));
addstr($winput, 2,0, &entrymask(2));
addstr($whelp, 0,0, &fkeyline());				# help line (F-keys)
addstr($winfo, 0,0, &winfomask(0));				# Country: ITU: CQZ: etc.
addstr($winfo, 1,0, &winfomask(1));
addstr($winfo, 2,0, " "x80);
addstr($wqsos, 0,0, " "x666);					# prev qsos window delete

&lastqsos(\$wlog);					# Print last 8/16 QSOs into $wlog window

refresh($winfo);
refresh($whead);
refresh($whelp);
refresh($winput);
refresh($wqsos);

##############################################################################
# Main Loop.  Starts in (F8) $winput (1), F9  goes to $wlog (2) and then F10 
# to $wqsos (3) (previous QSOs). $aw is the active window. 
##############################################################################

&qsotofields($qso,$wi,1);				# fills 14 input field with QSO array

# Now we loop infinitely until we get out of logging mode ($status==1)	
while (1) {

##############################################################################
# LOGGING INPUT  WINDOW    $aw = 1
##############################################################################

if ($aw == 5) {							# we leave logging mode and go to menu!
	$aw = 1;							# for the next time when we come here
	$status = 2;						# we go to the menu!
	last;								# leave this loop.
}
		
if ($aw == 4) {	$aw = 1; }				# we restarted the input window
				
$af = 1;								# start in 1st field (call)
while ($aw == 1) {						# We are in the logging Window
	curs_set(1);						# Make the cursor visible
	$workcall = $qso[0];				# The call we are working right now,
										# so we can change DXCC etc if it
										# changes

if ($af == 1) {							# READ CALLSIGN FIELD
	$aw = &readw($wi,0,0,$qso,\$wlog,	# Read callsign. See details in sub.
			\$editnr);
	if ($aw == 1) {						# All OK, next field
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK, stay in $aw=1
		$af = 14; $aw = 1;
	}
	# When a new callsign is entered, the DATE, TIME ON, Band, Mode, QSL and
	# PWR fields are automatically filled like specified in the config file
	if ($qso[0] ne $workcall) {			# callsign has been changed!
		if ($qso[1] eq "") {				# No date yet entered?
			$qso[1] = &getdate;				# set $qso[1] to current date 
		}
		if ($qso[2] eq "") {				# No time entered so far
			$qso[2] = &gettime;				# set $qso[2] to current GMT
			addstr($wi[2],0,0,$qso[2]);		# write into window
			refresh($wi[2]);				# display changes
		}
		if ($qso[4] eq "") {$qso[4] = $dband};	# initialize default band
		if ($qso[5] eq "") {$qso[5] = $dmode};	# initialize default mode
		if ($qso[8] eq "") { 				# QSL sent, default Q = Queue
			$qso[8] = $dqsls; }				# but to make QSL-writing/printing 
											# mode correct, use "Y" for Yes,
											# (sent) "Q" for "put in Queue" 
											# and "N" for no.
		if ($qso[9] eq "") { $qso[9] = $dqslr; }	# QSL received, default N
		if ($qso[10] eq "") { 				# RST sent to 59(9)
				if ($dmode =~ /CW|RTTY|PSK/) {$qso[10] = "599";}
				else {$qso[10] = "59"; }
		}
		if ($qso[11] eq "") { 				# RST rcvd to 59(9)
				if ($dmode =~ /CW|RTTY|PSK/) {$qso[11] = "599";}
				else {$qso[11] = "59";}
		}
		if ($qso[13] eq "") {$qso[13] = $dpwr; }	
		for(my $c=0;$c < 14;$c++) { 					# Refresh all windows
			addstr($wi[$c],0,0,$qso[$c]);
			refresh($wi[$c]) 
		}
		&callinfo($qso,$winfo,$wi,$wqsos, $editnr);	# print name, dxcc, prev QSOs... 
	} # new call ends here
} # end of $af = 1
elsif ($af == 2) {
	$aw = &readw($wi,1,1,$qso,\$wlog,	# Read Date ($_[1] -> only numbers)
			\$editnr);
	if ($aw == 1) {						# Normal exit. next field!
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af = 1; $aw=1;
	}
} # end of $af=2
elsif ($af == 3) {
	$aw=&readw($wi,1,2,$qso,\$wlog, 	# Read Time On ($_[1] -> only numbers)
			\$editnr);
	if ($aw == 1) {						# Normal exit. next field!
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=3
elsif ($af == 4) {
	$aw = &readw($wi,1,3,$qso,\$wlog, 	# Read T off ($_[1] -> only numbers)
			\$editnr);
	if ($aw == 1) {						# Normal exit. next field!
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=4
elsif ($af == 5) {
	$aw=&readw($wi,4,4,$qso,\$wlog, 	# Read band ($_[1] -> numbers and .)
			\$editnr);
	$dband=$qso[4] if $qso[4] ne "";	# next QSO will be on same band
	if ($aw == 1) {						# Normal exit. next field!
		$af++; 
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=5
elsif ($af == 6) {
	$aw=&readw($wi,0,5,$qso,\$wlog, 		# Read mode
			\$editnr);
	$dmode=$qso[5] if $qso[5] ne "";		# next QSO will be on same mode
	if ($aw == 1) {						# Normal exit. next field!
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=6
elsif ($af == 7) {
	$aw=&readw($wi,3,6,$qso,\$wlog, 			# read QTH
			\$editnr);
	if ($aw == 1) {						# Normal exit. next field!
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=7
elsif ($af == 8) {
	$aw=&readw($wi,3,7,$qso,\$wlog, 			# read Name
			\$editnr);
	if ($aw == 1) {						# Normal exit. next field!
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=8
elsif ($af == 9) {
	$aw=&readw($wi,2,8,$qso,\$wlog, 	# read QSLsent. All letters allowed,
			\$editnr);
	if ($aw == 1) {						# Normal exit. next field!
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=9

elsif ($af == 10) {
	$aw=&readw($wi,2,9,$qso,\$wlog,		# QSL received
		\$editnr);
	if ($aw == 1) {						# Normal exit. next field!
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=10

elsif ($af == 11) {
	$aw=&readw($wi,1,10,$qso,\$wlog, 	# rst sent (and optional serial)
		\$editnr);
	if ($aw == 1) {						# Normal exit. next field!
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=11

elsif ($af == 12) {
	$aw=&readw($wi,1,11,$qso,\$wlog, 	# rst received
		\$editnr);
	if ($aw == 1) {						# Normal exit. next field!
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=12
elsif ($af == 13) {
	$aw=&readw($wi,3,12,$qso,\$wlog, 	# Remarks
			\$editnr);
	if ($aw == 1) {						# Normal exit. next field!
		$af++;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=13

elsif ($af == 14) {
	$aw=&readw($wi,1,13,$qso,\$wlog, 	# Power
			\$editnr);
	$dpwr=$qso[13] if ($qso[13] ne '');		# next QSO will be with same PWR
	if ($aw == 1) {						# Normal exit. next field!
		$af=1;
	}
	elsif ($aw < 6) {					# to another window or restart in $aw=1
		next;							# (when $aw=4)
	}
	elsif ($aw == 6) {					# One window BACK
		$af--; $aw=1;
	}
} # end of $af=13
} # end of loop for input mode ($aw = 1)

##############################################################################
# Chose QSO in the Log Window, then edit.   $wlog,  $aw == 2
##############################################################################

while ($aw == 2) {
	curs_set(0);						# Make the cursor invisble

	# choseqso lets the OP scroll in the log and select a QSO. The return value
	# is the number of the QSO as in the NR column in the database
	$editnr = &choseqso(\$wlog);

	# $nr contains either the number of the QSO to fetch OR a "i" or "q" to
	# indicate the next window:

	if ($editnr eq "i")	{				# back to input window
		$aw = 1;						# $active window = 1, input window
		$editnr = 0;					# we don't edit anything
	} 
	elsif ($editnr eq "q"){				# previous QSO window
		$aw = 3;
		$editnr = 0;					# we don't edit anything
	}
	elsif ($editnr eq "m"){				# go to MAIN MENU
		$aw = 5;
		$editnr = 0;					# we don't edit anything
	}
	else {							# if we get here, we have a QSO number
	
	# now we fetch the info for the selected QSO from the database and save it
	# into the @qso-array. when we save the QSO
	# again in $aw = 1, it will not be saved as a new QSO but it will alter the
	# existing QSO because &saveqso; checks for an existing $editnr

	&clearinputfields($wi,1);				# deletes all input fields
	@qso = &getqso($editnr,$wi);
	&callinfo($qso,$winfo,$wi,$wqsos, $editnr);
	$aw = 1;
	}
}	# end of loop for log-window ($wlog, $aw = 2)


##############################################################################
# Chose QSO in the prev-QSOs-Window, then edit.   $wqsos,  $aw == 3
##############################################################################

while ($aw == 3) {
	curs_set(0);						# Make the cursor invisble
	$editnr = &chosepqso(\$wqsos,$qso[0]);

	if ($editnr eq "i")	{				# back to input window
		$aw = 1;						# $active window = 1, input window
		$editnr = 0;					# we don't edit anything
	} 
	elsif ($editnr eq "l"){				# log window
		$aw = 2;
		$editnr = 0;					# we don't edit anything
	}
	elsif ($editnr eq "m")	{			# back to the main menu
		$aw = 5;						# $active window = 5, -> MAIN MENU
		$editnr = 0;					# we don't edit anything
	} 
	else {								# we have a QSO number now!
	
	# proceed like before.
	
	&clearinputfields($wi,1);				# deletes all input fields
	@qso = &getqso($editnr,$wi);			# put QSO number $editnr in @qso
	&callinfo($qso,$winfo,$wi,$wqsos,$editnr);		# show callinfo
	$aw = 1;								# go to edit window
	}
} # end of $aw == 3

} # end of main logging  loop

} # end of $status == 1 logging loop

##############################################################################
# MAIN MENU MODE $status = 2
##############################################################################

while ($status == 2) {	
    attron($wmain, COLOR_PAIR(4));
	curs_set(0);						# Make the cursor invisble
	my $choice;							# Choice from the main menu

	# These are the menu items to chose from in the main menu.
	my @menuitems = ("Logging Mode      - Enter QSOs here", 
    "Search and Edit   - Searching and Editing QSOs.",
    "QSL write mode    - Displays a list of queued QSL cards to write",
    "QSL print mode    - Prints queued QSL cards into a pdf-File",
    "QSL enter mode    - Quickly mark QSOs as 'QSL-received'",
    "ADIF Import       - Import QSOs to current logbook",
    "ADIF Export       - Export QSOs in ADIF Format",
	"Update Onlinelog  - Update the online searchable log",
    "Logbook config    - Change active Logbook or create new one",
    "Awards/Statistics - DXCC, WAZ, WPX, IOTA etc. plus statistics",
    "Edit Name/QTH DB  - Edit the database used to save Names and QTHs",
    "Import from LOTW  - Read LOTW report and update the confirmations",
    "Export to LOTW    - Generate ADIF file of QSOs not uploaded yet"
    );
		
	addstr($whead, 0,0, "YFKlog v$yfkver - Main Menu - Active Logbook: \U$mycall".
		" " x 30);
	addstr($whelp, 0,0, "Use the cursor keys to chose. F12 exits."." " x 70);
	refresh($whead);						
	refresh($whelp);						
	addstr($wmain, 0,0, " " x (80*22));			# empty
	refresh($wmain);

	# A (scrollable) list appears, where you can select any menu item. It
	# returns the number of the item.
	$choice = &selectlist(\$wmain, 2, 5, 20, 70, \@menuitems);

	# This is a bit chaotic. Every Menu item has a correspondent main program
	# status ($status), but there is no relation between their numbers.

	if ($choice eq "m") {			# F1 - > stay in menu
	}								# do nothing
	elsif ($choice == 0) {			# To logging mode
		$status = 1;				# Set main status
	}
	elsif ($choice == 4) {			# QSL receive mode
		$status = 3;				# main status 3
	}
	elsif ($choice == 7) {			# Update Online Log
		$status = 4;				# main status 4
	}
	elsif ($choice == 2) {			# QSL write mode
		$status = 5;				# main status 5
	}
	elsif ($choice == 3) {			# QSL Print mode
		$status = 6;				# main status 6
	}
	elsif ($choice == 6) {			# ADIF export
		$status = 7;				# main status 7
	}
	elsif ($choice == 1) {			# Search and Edit Mode
		$status = 8;
	}
	elsif ($choice == 5) {			# ADIF IMPORT
		$status = 9;
	}
	elsif ($choice == 8) {			# Log config mode
		$status = 10;
	}
	elsif ($choice == 9) {			# AWARD mode
		$status = 11;
	}
	elsif ($choice == 10) {			# Name/QTH editor
		$status = 12;
	}
	elsif ($choice == 11) {			# LOTW  import
		$status = 13;
	}
	elsif ($choice == 12) {			# LOTW export
		$status = 14;
	}
	
} # end of $status == 2, Main menu


##############################################################################
# QSL RECEIVE MODE  $status = 3
# In this mode you enter a callsign or a part of it, and all matching QSOs
# are shown in a list. On this list you can toggle the QSL-received flags
# quickly by pressing space-bar. F2 saves, F3 cancels, F1 goes back to the menu
# and F12 exits
##############################################################################

while ($status == 3) {	
	my $qslcall= "";					# The callsign from which we got a QSL
	my $validc = "[a-zA-Z0-9\/]";		# valid characters for the callsign
	attron($wmain, COLOR_PAIR(4));
	curs_set(1);						# Make the cursor visble
	addstr($whead, 0,0, "YFKlog v$yfkver - QSL-Receive mode - Active Logbook: \U$mycall"." " x 30);
	addstr($whelp, 0,0, "Enter a call and select QSOs. F1 Main menu  F2 Save  F3 Cancel  F12 Exit"." " x 70);
	refresh($whead);						
	refresh($whelp);						
	addstr($wmain, 0,0, " " x (80*22));			# empty
	refresh($wmain);

	# We now ask for the callsign to search for...
	$qslcall = &askbox(10,20,4,40,$validc,"Enter a callsign (3+ letters)", '');

	# $qslcall now has the callsign to search for. 
	# if the value is "m" (produced by F1) or it's empty, we go back to the
	# main menu.
	
	if (($qslcall eq "m") or ($qslcall eq "")) {
			$status = 2;					# status = 2 -> Menu
	}
	# We check if at least 3 letters were entered. There are no calls shorter
	# than this, and 2 or 1 call would return too many QSOs. 
	elsif (length($qslcall) > 2)  {			
		addstr($wmain, 0,0, " " x (80*23));				# wipe out window
	
		# Now we are ready to call &toggleqsl which will query the database for
		# the callsign(fragment) entered and let the user toggle the
		# QSL-received status of the QSOs.
		# The return value says what we do next: If F1 is pressed, back to the
		# main Menu (return 2), else stay in the QSL receive mode (return 3).
	
		addstr($whelp, 0,0, "F1: Menu  F2: Save  F3: Cancel  SPACE: Toggle QSL-R S: Toggle QSL-S "." " x 70);
		refresh($whelp);

		$status = &toggleqsl(\$wmain, $qslcall);
	
		refresh($wmain);
	}
	
} # end of $status = 3, QSL receiving mode


##############################################################################
# UPDATE ONLINE LOG    Updates the online log.
# Writes the log info in ~-separated format into a file on the local
# machine, and optinally uploads the log via FTP.
# The colums of the exported data are specified in the configfile variable
# "onlinedata".
# FIXME always exports the whole log. 
##############################################################################

while ($status == 4) {	
	my $nr;								# Number of QSOs exported.
	my $choice;							# choice where to save the log.
	my $ftp;							# return value of &ftpupload
	my @menuitems =	 
	("FTP         - Upload via FTP to the machine specified in the config file",
	 "local       - Save it in $mycall.log");
	
	attron($wmain, COLOR_PAIR(4));
	curs_set(0);						# Make the cursor invisble
	addstr($whead, 0,0, "YFKlog v$yfkver - Updating Online Log - Active Logbook: \U$mycall"." " x 30);
	addstr($whelp, 0,0, "Update in progress ..."." " x 70);
	refresh($whead);						
	refresh($whelp);						
	addstr($wmain, 0,0, " " x (80*22));			# empty
	refresh($wmain);

	$nr = &onlinelog();

	addstr($wmain, 5, 5, "$nr QSOs exported to the online log");
	addstr($wmain, 6, 5, "Please select where to store the online-log file.");
	refresh($wmain);

	$choice = &selectlist(\$wmain, 8, 3, 20, 74, \@menuitems);

	if ($choice eq "m") {			# User pressed F1->back to menu
		$status = 2;				# Menu status
		last;						# leave while loop
	}
	elsif ($choice == 0) {			# Save FTP
		$ftp = &ftpupload;			# upload log. return success or error msg
		attron($wmain, COLOR_PAIR(4));				# fucked up by selectlist
		addstr($wmain, 0,0, " " x (80*22));			# empty
		addstr($wmain, 10,20, $ftp);				# show what ftpupload ret
		refresh($wmain);
	}

	$status = 2;					# FIXME Back to the Menu. Upload goes here
	
	getch();	

	
} # end of $status = 4, update of online log
	
##############################################################################
# QSL WRITE MODE  $status = 5
# A list of all QSOs where the QSL-Sent flag is "Q" = Queued is shown.
# On this list you can toggle the QSL-sent flags
# quickly by pressing space-bar. F2 saves, F3 cancels, F1 goes back to the menu
# and F12 exits
##############################################################################

while ($status == 5) {
	attron($wmain, COLOR_PAIR(4));
	curs_set(1);						# Make the cursor visble
	
	# change text in head and help lines ...
	addstr($whead, 0,0, "YFKlog v$yfkver - QSL-Write-mode - Active Logbook: \U$mycall"." " x 30);
	addstr($whelp, 0,0, "F1: Main Menu  F2: Save  F3: Cancel  SPACE: Toggle QSL status"." " x 70);
	refresh($whelp);
	refresh($whead);

	# In toggleqsl all the work is done. It displays all queued QSOs and lets
	# you toggle them. It returns the status, which should be 2 for the main
	# menu.

	$status = &toggleqsl(\$wmain, "W");
} # end of QSL write mode, $status==5

##############################################################################
# QSL Print mode.  In this mode all QSLs marked to be in QSL queue (QSLS = Q)
# will be printed into a LaTeX file which will be compiled into a pdf and then
# the user can print it labels. Arbitrary label sizes are possible; currently
# thre is a template for Zweckform 3475/3490, sized 70x36mm supplied.
##############################################################################

while ($status == 6) {
	my $labeltype;				# Saves filename of the label type we use.
	my @menuitems;				# Label sizes to chose from
	my %printlabels;			# will store all the labels to be printed
	my $tex;					# will store the full LaTeX document
	my $filename;				# file name where the QSLs will be saved
	my $startlabel;				# number of label where we start...
	
	attron($wmain, COLOR_PAIR(4));
	curs_set(0);						# Make the cursor invisble
	# change text in head and help lines ...
	addstr($whead, 0,0, "YFKlog v$yfkver - QSL-Print-mode - Active Logbook: \U$mycall"." " x 30);
	addstr($whelp, 0,0, "Please select the label size. F1 exits."." " x 70);
	addstr($wmain, 0,0, " "x(80*22));
	addstr($wmain, 3,5, "All QSLs marked as queued will be printed. Please ". 
			"select a label size.");
	refresh($whelp);
	refresh($wmain);
	refresh($whead);

	# Now looking in the current directory for label files (.lab). Those will
	# be stored in an array
	
	my @labeltypes = <*.lab>;			# array has all label files

	# Every label-file is opened and the first line which contains the
	# description is read. The descriptions are stored into the @menuitems
	# array, plus the filename.
	
	my $a = 0;									# counter
	foreach my $lab (@labeltypes) {				# go through all label files
		open LAB, "$lab";
		my $labeldescription = <LAB>;			# first line contains descr
		$labeldescription =~ /^% (.+)$/;		# get the description.
		$labeldescription = $1;
		$menuitems[$a] = "$labeldescription ($lab)";
		close LAB;
		$a++;
	}
	
	# Show a selectable list of the menu items and let the user select one
	$labeltype = &selectlist(\$wmain, 10,10,$a+1,60, \@menuitems);
	attron($wmain, COLOR_PAIR(4));		# selectlist fucks up attribs FIXME

	if ($labeltype eq "m") {			# User pressed F1 -> back to main menu!
		$status = 2;					# Set $status = 2 -> Menu
		last;							# exit while loop
	}
	
	# We don't want a number but the filename of the style file, so we select
	# it from the menuitems string, which looks like:
	# "Label description (filename.lab)" - we only need the filename 

	$menuitems[$labeltype] =~ /.+\((\w+\.lab)\)/;
	$labeltype = $1; 

	# Now ask the user at which label to start. If you printed a few labels on
	# a sheet before, it would be a pity to throw the remaining labels away. 
	# If a value larger than the number of labels on one page is entered, it's
	# disregarded.
	# TODO maybe save the value of the last printed label, then next time when
	# printing automatically continue from that position.
	
	$startlabel =
			&askbox(10,10,5,60,"\\d","Enter start label! (Default is 1)", '');

	if ($startlabel eq "m") {			# back to the menu...
		$status = 2;
		last;
	}
	elsif ($startlabel eq '') {			# default start at 1 (= 1st label)
		$startlabel = 1;
	}
	
	# &preparelabels returns a hash with the LaTeX sourcecode for all labels to
	# be printed (QSLS=Q). 

	%printlabels = &preparelabels($labeltype);

	unless (%printlabels) {						# If there are no QSOs to print
		addstr($wmain, 0,0, " "x(80*22));
		addstr($wmain, 10,28, "No QSL Cards in queue!");
		refresh($wmain);
		getch();
		$status = 2;							# back to main menu
		last;									 
	}
	
	# All labels are in %printlabels, in alphabetical order. The next step is
	# to put them together in a LaTeX doument, it is done by &makelabels.
	# You can specify a start-label number for the first page, which is
	# useful to use up pages where only the first few labels have been printed

    $tex = &labeltex(\%printlabels, $labeltype, $startlabel);

	# the number of exported labels and pages will be shown

	addstr($wmain, 0,0, " " x (80*22));			# delete window
	
	$tex =~ /(\d+) (\d+)$/;
	
	addstr($wmain, 5,23, "Generated $1 labels on $2 pages(s).");

	$filename = "qsl-$mycall-".&getdate;		# assemble filename for labels
	
	open TEX, ">$filename.tex";					# save the LaTeX document
 		print TEX $tex;
 	close TEX;
	
	addstr($wmain, 6,15, "Written to $filename.tex, now compiling..");
	refresh($wmain);
	
	system("pdflatex $filename.tex > /dev/null");		# compile the document
	addstr($wmain, 8,16, "Done! You can now open the file");
	addstr($wmain, 9,25, "$filename.pdf");
	addstr($wmain, 10,16, "in your favourite PDF Viewer and print it.");
	addstr($wmain, 11,16, "If you're happy with the results, chose OK, then ");
	addstr($wmain, 12,16, "the QSL status of the processed QSOs will be");
	addstr($wmain, 13,16, "set to \"Y\".");
	refresh($wmain);

	my @items = ("  OK", "Cancel");			# Items for selction
	my $choice;								# Choice variable...
	
	$choice = &selectlist(\$wmain, 15,37,2,6, \@items);

	if ($choice eq "0") {					# OK, update log!
		# update QSLS=Q to QSLS=Y...
		my $nr = &emptyqslqueue;			# returns nr of QSOs..
		addstr($wmain, 19,16, "$nr QSOs updated. Press any key to continue!");
		refresh($wmain);
		getch();
	}

	$status = 2;							# back to the main menu	
		
} # end of QSL Printing mode, $status==6

##############################################################################
# ADIF EXPORT MODE  $status = 7
# LOTW ADIF export mode, $status = 14
##############################################################################

while (($status == 7) || ($status == 14)) {
	my $filename;				# filename for the adif/lotw file
	my $nr;						# number of exported QSOs	
	my ($date1, $date2, $daterange) = ('','','1');
	
	attron($wmain, COLOR_PAIR(4));
	curs_set(1);						# Make the cursor visble
	
	# change text in head and help lines ...
	
	addstr($whead, 0,0, "YFKlog v$yfkver - ADIF Export mode - Active Logbook: \U$mycall"." " x 30) if ($status == 7);
	
	addstr($whead, 0,0, "YFKlog v$yfkver - LOTW Export mode - Active Logbook: \U$mycall"." " x 30) if ($status == 14);
	
	addstr($whelp, 0,0, "Enter a filename to export. F1: Main Menu  F12: Exit"." " x 70);
	addstr($wmain,0,0," "x(80*22));			# clear main window
	refresh($whelp);
	refresh($wmain);
	refresh($whead);

	# Now ask the user for the name of the file. Allow all \w characters.
	$filename= 
	&askbox(10, 15, 4, 50, '\w', "Enter a filename (default $mycall.adi).", '');
	curs_set(0);						# Make the cursor invisble
	
	if ($filename eq 'm') {				# go back to the menu
		$status = 2;
		last;							# go out of while loop
	}
	elsif ($filename eq "") {			# no filename -> default
		$filename = $mycall.'.adi';
	}
	else {								# add extension 
	$filename .= '.adi';
	}

	erase($wmain);
	addstr($wmain,0,0, ' 'x(80*22));

	# Ask for a date range...
	addstr($wmain, 2,17, 'If you like to specify a date-range, enter the');
	addstr($wmain, 3,16, 'start date now. Otherwise leave the field empty.');
	addstr($whelp, 0,0, 'Specify a date range ..'.' 'x50);
	refresh($wmain);
	refresh($whelp);
   	
	curs_set(1);						# cursor visible	
	$date1 = &askbox(6, 15, 4, 50, '[0-9-]', 
								"Specify start date (YYYY-MM-DD):", '');

	unless ($date1 eq '') {			# We have a start date, so ask for end date
		$date2 = &askbox(12, 15, 4, 50, '[0-9-]', 
								"Specify stop date (YYYY-MM-DD):", '');

		# Verify that the dates are valid. If not, back to main menu.
		unless (&checkdate($date1) && &checkdate($date2)) {
			addstr($wmain, 18,29, 'Sorry, invalid date(s)!');
			addstr($whelp, 0,0, 'Press any key to go back to the menu.'.' 'x50);
			refresh($wmain);
			refresh($whelp);
			$status = 2;
			getch();
			last;
		}
		# if the dates are valid, build a SQL String to put into the
		# database-query.
		else {
			$daterange = "DATE >= '$date1' AND DATE <= '$date2'";
		}
	}	

	# Export the log to $filename
	$nr = &adifexport($filename, 'adif', $daterange) if ($status == 7); 
	$nr = &adifexport($filename, 'lotw', $daterange) if ($status == 14); 

	addstr($wmain,0,0, ' ' x (80*22));			# clear main window
	addstr($wmain,10,24,"$nr QSOs exported to $filename");
	addstr($wmain,11,22,"LOTW status updated to 'Requested'.") if ($status==14);
	addstr($wmain,12,17,"Sign $filename with tqsl and upload to LOTW!") if ($status==14);
	refresh($wmain);

	getch();
	

	
	$status = 2;
} # end ADIF export mode, $status==7

##############################################################################
# SEARCH AND EDIT MODE  $status == 8
##############################################################################

while ($status == 8) {
	my @qso;			# This array will store a QSO while editing...
	my @sqso;			# This array will store the search criteria in the same
						# format as a @qso.
	for (0 .. 25) {		# initialize the array, so it is not undef
		$qso[$_] = '';
		$sqso[$_] = '';
	}

# The @qso-array: 0=call 1=date 2=t_on 3=t_off 4=band 5=mode 6=QTH 7=name
# 8=QSLS 9=QSLR 10=RSTS 11=RSTR 12=REMarks 13=PWR 14=DXCC 15=PFX 16=CONT
# 17=ITUZ 18=CQZ 19=QSLINFO 20=IOTA 21=STATE 22=NR 23=QSLRL, 24=OP, 25=GRID
	
	my $aw=1;			# The ActiveWindow. This can be 1 = $wedit or 2 =
						# $weditlog
	my $editnr=0;		# the number of the QSO which is currently edited.
	
	attron($wmain, COLOR_PAIR(4));
	addstr($whead, 0,0, "YFKlog v$yfkver - Search and Edit Mode - Active Logbook: \U$mycall");
	erase($wedit);
	addstr($wedit,0,0, ' 'x(80*5));
	addstr($wedit, 0,0, &entrymask(0));		# creates the input entry mask
	addstr($wedit, 1,0, &entrymask(1));
	addstr($wedit, 2,0, &entrymask(2));
	addstr($wedit, 3,0, &entrymask(3));
	addstr($wedit, 4,0, &entrymask(4));
	erase($weditlog);
	addstr($weditlog,0,0, ' 'x(80*22));
	refresh($weditlog);
	refresh($whelp);
	refresh($wedit);
	&clearinputfields($wi, 2);

while (1) {		# outer loop around  while ($aw = x) 
		
##############################################################################
# $aw = 1  --  Editing the @qso-array in the $wi-windows.
##############################################################################

while ($aw == 1) {
	curs_set(1);						# Make the cursor visble
	addstr($whelp, 0,0, 'F1: Menu  F2: Save changes  F3: Cancel  F4: Delete QSO  F5: Search'.' 'x30);
	refresh($whelp);
	$aw = &editw($wi,0,0,\@qso); 	# Edit call
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,1,1,\@qso); 	# edit date (no fuction FIXME)
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,1,2,\@qso); 	# edit time_on (no function FIXME)
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,1,3,\@qso); 	# edit time_off (FIXME)
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,4,4,\@qso); 	# edit band
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,0,5,\@qso); 	# edit mode
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,3,6,\@qso); 	# edit qth
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,3,7,\@qso); 	# edit name
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,2,8,\@qso); 	# edit QSLs
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,2,9,\@qso); 	# edit QSLr
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,1,10,\@qso); 	# edit RSTs
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,1,11,\@qso); 	# edit RSTr
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,3,12,\@qso); 	# edit Remarks
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,1,13,\@qso); 	# edit PWR
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,0,14,\@qso); 	# edit DXCC
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,0,15,\@qso); 	# edit PFX
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,0,16,\@qso); 	# edit CONT
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,1,17,\@qso); 	# edit ITUZ
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,1,18,\@qso); 	# edit CQZ
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,0,19,\@qso); 	# edit QSLINFO
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,3,20,\@qso); 	# edit IOTA
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,0,21,\@qso); 	# edit STATE
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,0,23,\@qso); 	# edit QSLRL
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,0,24,\@qso); 	# edit OPERATOR
	if ($aw ne '1' ) { last; }
	$aw = &editw($wi,0,25,\@qso); 	# edit GRID
	if ($aw ne '1' ) { last; }
}

if ($aw eq 'm') {						# back to menu
	$status = 2;
	last;								# break out from while (1) loop
}
elsif ($aw == 0) {						# back to callsign => $aw=1
	$aw = 1;
}

##############################################################################
# $aw = 2  --  Scrolling through the logbook; only display QSOs that are
# matching the search criteria entered and saved in @qso.
##############################################################################

while ($aw == 2) {
	curs_set(0);						# Make the cursor invisble
	addstr($whelp, 0,0, 'F1: Main  F3: Cancel, new Search  SPACE/ENTER: Edit QSO'.' 'x30);
	refresh($whelp);

	# We have selected search criteria in the QSO-array. Now display a
	# scrollable list with only the matching QSOs. The user selects one QSO,
	# the number of the QSO (as in the NR field in the database) is returned.
	$editnr = &choseeditqso(\$weditlog, \@qso);	

	if ($editnr eq 'm') { 				# back to MAIN MENU
		$status = 2;
		last;
	}
	# cancel search (c) or no entries found (0).
	elsif (($editnr eq 'c') || ($editnr == 0)) {
		for (0 .. 25) {					# clear the search field
			$qso[$_] = '';
		}
		$aw = 1;						# back to entering mode
	}
	else {
		# get the QSO from the database and put the content into the edit
		# fields / windows.
		&clearinputfields($wi, 2);
		@qso = &geteditqso($editnr,\@wi);
	}
	$aw = 1;				# lets edit this entry
} # $aw=2

} # outer loop around while ($aw = x)

} # end of Search and Edit mode, $status == 8

##############################################################################
# ADIF IMPORT  MODE  $status == 9
##############################################################################

while ($status == 9) {
	my @adifiles = <*.adi>;			# all ADIF-files in the current directory
	push(@adifiles, <*.ADI>);		# all ADIF-files in the current directory
	my $adifile;
	my $nr;							# nr of imported QSOs
	my $err;						# nr of errors during import
	my $war;						# nr of warnings during import

	attron($wmain, COLOR_PAIR(4));
	addstr($whead, 0,0, "YFKlog v$yfkver - ADIF Import Mode - Active Logbook: \U$mycall");
	addstr($whelp, 0,0, 'Select a ADIF file from the current directory or F1 to quit');
	erase($wmain);
	addstr($wmain,0,0, ' 'x(80*22));			# blue background
	addstr($wmain, 2,10, 'Select a ADIF file from the current directory to import!');
	refresh($wmain);
	refresh($whead);
	refresh($whelp);

	# If there are more than 20 ADIF files in the list, we make it scrollable,
	# with a fixed height of 20.
	my $y = scalar(@adifiles);
	if ($y > 15) { $y = 15; }

	$adifile = &selectlist(\$wmain, 4,30, $y ,20, \@adifiles);

	if ($adifile eq 'm') {			# F1 pressed, go back to the menu
		$status = 2;
		last;
	}
	else {							# we want to import $adifiles[$adifile]
		 ($nr, $err, $war) = &adifimport($adifiles[$adifile],$whelp);
	}

	attron($wmain, COLOR_PAIR(4));		# selectlist fucks up attribs FIXME
	erase($wmain);
	addstr($wmain,0,0, ' 'x(80*22));			# blue background

	if ($nr > 0) {									# OK, QSOs imported
		addstr($wmain,  8,20, "QSOs processed: $nr. Successfull: ".($nr-$err));
		addstr($wmain, 11,6, "Errors: $err. See detailed information in ".
				"$mycall-import-from-$adifiles[$adifile].err") if $err;
		addstr($wmain, 12,5, "Warnings: $war. See detailed information in ".
			   "$mycall-import-from-$adifiles[$adifile].err") if $war;
	}
	else {			# No QSOs imported, probably wrong linebreaks in file.
		addstr($wmain,  7,10, "No QSOs imported. Possibly this file doesn't meet the ADIF");
		addstr($wmain,  8,10, "specifications. Make sure there the header is terminated");
		addstr($wmain,  9,10, "with <eoh>. If you think the file is OK, contact author.");
	}
		refresh($wmain);

	getch();

	$status = 2;				# back to main menu

} # end of $status = 9, ADIF Import Mode


##############################################################################
# LOG CONFIG  MODE  $status == 10
##############################################################################

while ($status == 10) {
	
	my @logs;				# all log_{call}-tables in the database	
	my $choice;				# logbook which is chosen
	
	attron($wmain, COLOR_PAIR(4));
	addstr($whead, 0,0, "YFKlog v$yfkver - Log Config Mode - Active Logbook: \U$mycall");
	addstr($whelp, 0,0, 'Chose one of the logs or create a new one ..'.' 'x50);
	erase($wmain);
	addstr($wmain,0,0, ' 'x(80*22));			# blue background
	addstr($wmain, 2,18, 'Select an existing logbook or create a new log!');
	refresh($wmain);
	refresh($whead);
	refresh($whelp);

	@logs = &getlogs();						# get list of logbooks
	push(@logs, " Create new Logbook ");	# add option to make new one
	@logs = sort @logs;
	# After dorting, the " Create new Logbook " entry will be at the first
	# position because it starts with a whitespace. This is needed because the
	# case of creating a new logbook has to be treated different.

	# If there are more than 15 logs in the list, we make it scrollable,
	# with a fixed height of 15.
	my $y = scalar(@logs);
	if ($y > 15) { $y = 15; }

	$choice = &selectlist(\$wmain, 4,30, $y ,20, \@logs);
	
	# Now check what the user chosed: If it is the first entry, a new database
	# has to be created. Otherwise only the $mycall has to be changed.

	if ($choice eq "m") {			# F1 pressed -> back to main menu
		$status = 2;
		last;
	}
	elsif ($choice == 0) {					# first item -> create new log
		curs_set(1);  						# cursor visible
		# Ask for the name of the new logbook.
		my $new = &askbox(10, 15, 4, 50, '[a-zA-Z0-9/]', 
						"Enter a name (callsign) for a new logbook:", '');
		curs_set(0);  						# cursr invisible
		my $msg = &newlogtable($new);
		addstr($wmain, 15, (40-(length($msg." ($new)")/2)), $msg." ($new)");
		if ($msg =~ /successfully/) {		# new call OK
			$mycall = "\L$new";				# take it as MYCALL
			$mycall =~ s/\//_/g;			# / -> _
			&changemycall($mycall);			# change $mycall also in yfksubs.pl
		}
		refresh($wmain);
		getch();
	}
	else {								# change $mycall to selected log
		$mycall = $logs[$choice];		# Callsign is here
		$mycall =~ s/\//_/g;			# change / to _
		$mycall =~ tr/[A-Z]/[a-z]/;		# make letters lowercase
		&changemycall($mycall);			# change $mycall also in yfksubs.pl
	}
	
	$status = 2;		
} # end of $status = 10, logbook config

##############################################################################
# AWARD MODE  -  Calculates score for DXCC, WPX, WAZ, IOTA
##############################################################################

while ($status == 11) {
	my ($date1,$date2);				# start and stop date for award range
	my $daterange='1';				# SQL string with start and end date
	my %result= ('a'=>'b');			# DXCCs, WAZ, etc. for each band.
	my %resultc = ('a'=>'b');		# same, but CFMed
	my %resultcp = ('a'=>'b');		# same, Paper QSL received
	my %resultcl = ('a'=>'b');		# same, LOTW received
	
	attron($wmain, COLOR_PAIR(4));
	addstr($whead, 0,0, "YFKlog v$yfkver - Award Mode - Active Logbook: \U$mycall");
	addstr($whelp, 0,0, 'Select an award to generate statistics for ..'.' 'x50);
	erase($wmain);
	addstr($wmain,0,0, ' 'x(80*22));			# blue background
	refresh($wmain);
	refresh($whead);
	refresh($whelp);

	# Menu Items
	my  @menu = ('DXCC', 'PFX', 'CQZ', 'IOTA', 'STATE', 'GRID',
			'QSO / Bands', 'QSO / Continent', 'QSO / Mode', 'Xplanet'
		);

	# Let the user select one of the awards
	my $choice = &selectlist(\$wmain, 4,30, 10 ,20, \@menu);
	attron($wmain, COLOR_PAIR(4));

	erase($wmain);
	addstr($wmain,0,0, ' 'x(80*22));

	if ($choice ne '9') {		# not for the Xplenet markers
	# Ask for a date range...
	addstr($wmain, 2,17, 'If you like to specify a date-range, enter the');
	addstr($wmain, 3,16, 'start date now. Otherwise leave the field empty.');
	addstr($whelp, 0,0, 'Specify a date range ..'.' 'x50);
	refresh($wmain);
	refresh($whelp);
   	
	curs_set(1);						# cursor visible	
	$date1 = &askbox(6, 15, 4, 50, '[0-9-]', 
								"Specify start date (YYYY-MM-DD):", '');

	unless ($date1 eq '') {			# We have a start date, so ask for end date
		$date2 = &askbox(12, 15, 4, 50, '[0-9-]', 
								"Specify stop date (YYYY-MM-DD):", '');

		# Verify that the dates are valid. If not, back to main menu.
		unless (&checkdate($date1) && &checkdate($date2)) {
			addstr($wmain, 18,29, 'Sorry, invalid date(s)!');
			addstr($whelp, 0,0, 'Press any key to go back to the menu.'.' 'x50);
			refresh($wmain);
			refresh($whelp);
			$status = 2;
			getch();
			last;
		}
		# if the dates are valid, build a SQL String to put into the
		# database-query.
		else {
			$daterange = "DATE >= '$date1' AND DATE <= '$date2'";
		}
	} # if choice ne 8

	erase($wmain);
	addstr($wmain,0,0, ' 'x(80*22));

	addstr($wmain, 2,17, 'The following bands will be considered, as set');
	addstr($wmain, 3,16, 'in .yfklog. You can add or remove bands now.');
	addstr($whelp, 0,0, 'Specify bands ..'.' 'x50);
	refresh($wmain);
	refresh($whelp);

	curs_set(1);
	$bands = &askbox(6, 15, 4, 50, '[0-9. ]', "Limit to bands:", $bands);
	
	} # if ($choice ne 9)

	curs_set(0);						# cursor invisible	

	addstr($wmain,0,0, ' 'x(80*22));		# clear window	
	addstr($wmain, 2, 25, "$menu[$choice] Statistics for \U$mycall");
	addstr($whelp, 0,0, "$menu[$choice] statistics".' 'x50);
	refresh($whelp);

	# Now we make the queries, dependend on the AWARD type we chose in $choice
	# There are different general award types. The easiest are DXCC, WAZ, WAS,
	# IOTA etc, where the query method is always the same, only the database
	# field is different. In the menu, those are choices 0 .. 4.
	 
	my $filename;
	if ($choice <= 5 ) {
		
		# The result hash has bands as keys and nr of dxcc/iotas etc as 
		# values.
		&awards($daterange,$menu[$choice], \%result, \%resultc, \%resultcp,
				\%resultcl, $bands);
		addstr($wmain, 5, 20, "Band    Wkd   Cfmd    QSL    LOTW");
		my $y = 5;
		# Since "All" is not numeric and fucks up the sorting, we change it to
		# 9999 instead and change later. 
		($result{'9999'}, $resultc{'9999'}) = ($result{'All'}, $resultc{'All'});
		($resultcp{'9999'},$resultcl{'9999'})=($resultcp{'All'},$resultcl{'All'});

		delete $result{'All'}; delete $resultc{'All'};
		delete $resultcp{'All'}; delete $resultcl{'All'};

		foreach my $key (sort {$a <=> $b} keys %result) {
#				if ($key eq '9999') { next; }		# All=9999 comes last!
				$y++;
				addstr($wmain, $y, 20, 
						sprintf("%-4s     %-4s   %-4s   %-4s   %-4s" ,
								$key, $result{$key}, $resultc{$key},
								$resultcp{$key}, $resultcl{$key}));
		}
		addstr($wmain, $y, 20, 
						sprintf("%-4s     %-4s   %-4s" ,"All", $result{'9999'},
								$resultc{'9999'},
								$resultcp{'9999'}, $resultcl{'9999'}));

		addstr($wmain, $y+2,15, "Created detailled HTML-summary at $mycall-$menu[$choice].html");
	}

	# For QSO / Continent and QSO / Band other queries have to be made...
	elsif ($choice =~ /[678]/) {
		if ($choice eq "6") {
			&statistics("BAND", \$wmain, $daterange, $bands);	# result: BAND -> nr of QSOs
			$filename="BAND";
		}
		elsif ($choice eq "7") {
			&statistics("CONT", \$wmain, $daterange, $bands);	# result: CONTINET ->nr of QSOs
			$filename="CONT";
		}
		elsif ($choice eq "8") {
			&statistics("MODE", \$wmain, $daterange, $bands);	# result: MODE ->nr of QSOs
			$filename="MODE";
		}
		addstr($wmain, 20,15, "Created detailled HTML-summary at $mycall-$filename.html");
	}
	elsif ($choice eq '9') {		# Generate Marker file for xplanet
			&xplanet();
			addstr($wmain, 8,23, "Output file $mycall-earth written.");
	}

	# Statistics printed, wait for keystroke to go back to the menu
	refresh($wmain);
	getch();
	
	$status = 2;		# back to menu
} # AWARD mode

##############################################################################
# Name and QTH database editor
##############################################################################

while ($status == 12) {
	my $call;			# The callsign to edit.
	attron($wmain, COLOR_PAIR(4));
	addstr($whead, 0,0, "YFKlog v$yfkver - Name/QTH DB Editor - Active Logbook: \U$mycall");
	addstr($whelp, 0,0, 'Enter the callsign to edit.  F1: Menu  F12: Quit'.' 'x50);
	erase($wmain);
	addstr($wmain,0,0, ' 'x(80*22));			# blue background
	refresh($wmain);
	refresh($whead);
	refresh($whelp);

	curs_set(1);						# cursor visible	
	$call= &askbox(10, 30, 4, 20, '[a-zA-Z0-9]', "Enter a callsign:", '');
	# Edit the entry; returns 2 when the user wants to go back to the menu,
	# otherwise 12. When the call is "m", go back to menu directly.
	unless ($call eq "m" || $call =~ /^[A-Z0-9]{0,2}$/) {
		addstr($whelp, 0,0, 'F1: Back to menu  F2: Save  F3: Delete entry'.' 'x50);
		refresh($whelp);
		$status = &editdb($call, \$wmain);
	}
	else {
		$status = 2;
	}
}



##############################################################################
# LOTW IMPORT  MODE  $status == 13
##############################################################################

while ($status == 13) {
	my @adifiles = <*.adi>;			# all ADIF-files in the current directory
	push(@adifiles, <*.ADI>);		# all ADIF-files in the current directory
	my $lotwfile;
	my ($nr, $match, $updated, $nf);

	attron($wmain, COLOR_PAIR(4));
	addstr($whead, 0,0, "YFKlog v$yfkver - LOTW Report Mode - Active Logbook: \U$mycall");
	addstr($whelp, 0,0, 'Select a lotw-report file from the current directory or F1 to quit');
	erase($wmain);
	addstr($wmain,0,0, ' 'x(80*22));			# blue background
	addstr($wmain, 2,10, 'Select a LOTW file from the current directory to import!');
	refresh($wmain);
	refresh($whead);
	refresh($whelp);

	# If there are more than 20 ADIF files in the list, we make it scrollable,
	# with a fixed height of 20.
	my $y = scalar(@adifiles);
	if ($y > 15) { $y = 15; }

	$lotwfile = &selectlist(\$wmain, 4,30, $y ,20, \@adifiles);

	if ($lotwfile eq 'm') {			# F1 pressed, go back to the menu
		$status = 2;
		last;
	}
	else {							# we want to import $adifiles[$adifile]
		 ($nr,$match,$nf) = &lotwimport($adifiles[$lotwfile],$whelp)
	}

	attron($wmain, COLOR_PAIR(4));
	erase($wmain);
	addstr($wmain,0,0, ' 'x(80*22));			# blue background

	if ($nr > 0) {									# OK, QSOs imported
		addstr($wmain,  8,25, "QSOs processed: $nr. Matches: $match. ");
		addstr($wmain, 10,28, "Not found: $nf.");
		addstr($wmain, 13,5, "See $mycall-LOTW-update-from-$adifiles[$lotwfile].err for QSLs that were not found.") if $nf;

	}
	else {			# Nothing
		addstr($wmain,  7,10, "No QSLs imported. Possibly this file doesn't meet the LOTW");
		addstr($wmain,  8,10, "specifications. ");
		addstr($wmain,  9,10, "If you think the file is OK, contact author.");
	}
		refresh($wmain);

	getch();

	$status = 2;				# back to main menu

} # end of $status = 13, LOTW import













} # end of MAIN PROGRAM LOOP

endwin;

