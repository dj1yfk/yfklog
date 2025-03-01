#!/usr/bin/perl -w

# YFKlog - upgrade from 0.7.0 to 1.0.0
#
# Script to upgrade the database of YFKlog from the "old" format
# (used from versions 3.5.0 / 2008-01-31 to 0.7.0, 2024-09-26)
# to the new format where all logs are stored in one common table
# with a `mycall` field rather than separate tables called log_$call.

use strict;
use DBI;

our $dbh;
my $oldversion;

if (-f './yfk' && -f './yfksubs.pl' && -f 'THANKS') {
    # we're in the source directory, source the local copy
    require "./yfksubs.pl";    
} else {
    require "/usr/share/yfklog/yfksubs.pl";    
}
import yfksubs;

&readsubconfig;
&connectdb;


print "Checking version of YFKlog...";

if (&tableexists('YFKconfig')) {
    my $r = $yfksubs::dbh->prepare("SELECT Value from YFKconfig where Name = 'version'");
    $r->execute;
    $oldversion = $r->fetchrow_array();
    print "DB: $oldversion\n";
}
else {
    print "Cannot find database with YFKconfig table...\n";
    exit();
}

if (substr($oldversion, 0, 1) eq "1") {
    print "Database already updated to YFKlog version 1.x.x - version indicates: $oldversion";
    print "Checking tables: ";
    my @logs = &getlogs_old();
    print "Logs: @logs\n";
    exit();
}

if ($oldversion ne "0.3.5") {
    print "Looks like you are running a very old version, that has not been upgraded to the database scheme from 0.3.5.\n";
    print "Please install YFKlog 0.7.0 first and let it perform the required upgrades. Then run this update script.\n";
    exit();
}

print "Checking logs to be migrated to 1.x.x database scheme...\n";

my @logs = &getlogs_old();

print "Found the following logs:\n";
foreach (@logs) {
    my $c = lc($_);
    $c =~ s/\//_/g;
    my $r = $yfksubs::dbh->prepare("SELECT count(*) from log_$c;");
    $r->execute;
    printf("%-20s  %6d\n", $c, $r->fetchrow_array());
}

print "Convert these logs to a common table (yfklogtbl) now? (y/n)";

my $reply = <>;

unless ($reply =~ /y/) {
    print "Exit..\n";
    exit();
}

print "Creating table yfklogtbl";

my $filename = "db_log.sql"; # "/usr/share/yfklog/db_log.sql";
#if ($db eq 'sqlite') {
#    $filename = "/usr/share/yfklog/db_log.sqlite";
#}

open DB, $filename;
my @db = <DB>;

unless (&tableexists("yfklogtbl")) {
    my $db = "@db";
    print "$db\n";
    $yfksubs::dbh->do($db);            # create it!
    print "Table successfully created!";
}
else {
    print "Table already existed! Please clean up/delete manually and proceed.\n";
    #    exit();
}    

print "Inserting all QSLs, log by log...\n";

foreach (@logs) {
    my $log = lc($_);
    my $mycall = uc($log);
    $mycall =~ s/_/\//g;
    $log =~ s/\//_/g;
    print "\n\nReading log $log... (mycall: $mycall)";
    my @qsos;
    my $query = "SELECT `CALL`, DATE, T_ON, T_OFF, BAND, MODE, QTH, NAME, QSLS, QSLR, QSLRL, RSTS, RSTR, REM, PWR, DXCC, PFX, CONT, ITUZ, CQZ, QSLINFO, IOTA, STATE, GRID, OPERATOR, \"$mycall\" from log_$log";
    print ".. $query .. \n";;
    my $r = $yfksubs::dbh->prepare($query);
    $r->execute;
    while (my @q = $r->fetchrow_array()) {
        push @qsos, \@q;
    };
    print " done (".$#qsos." QSOs). Inserting into new table: ";


    my $query_start = "insert into yfklogtbl (`CALL`, DATE, T_ON, T_OFF, BAND, MODE, QTH, NAME, QSLS, QSLR, QSLRL, RSTS, RSTR, REM, PWR, DXCC, PFX, CONT, ITUZ, CQZ, QSLINFO, IOTA, STATE, GRID, OPERATOR, MYCALL) values ";

    my @qsos_sql;
    foreach my $q (@qsos) {
        my @qso = @{$q};
        my @out;
        foreach (@qso) {
            push @out, $yfksubs::dbh->quote($_);
        }
        push @qsos_sql, "(".join(",", @out).")";
    }

    # insert in chunks of 1000 QSOs
    while (scalar(@qsos_sql)) {
        my @kq = splice(@qsos_sql, 0, 1000);
        $query = $query_start . join(",", @kq);
        $yfksubs::dbh->do($query);
    }
    
    print "done!\n";

}


my $r = $yfksubs::dbh->prepare("update YFKconfig set Value = '1.0.0' where Name = 'version'");
$r->execute;

