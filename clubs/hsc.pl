#!/usr/bin/perl -w

# yfktest script to import HSC member data
# see http://fkurz.net/ham/yfklog/doc/#clubs

system("wget http://hsc.dj1yfk.de/db/hsc_list_n1mm.txt -O hsc.txt");

$sql = "delete from clubs where `club`='HSC';\n";

$sql .= "insert into clubs (`club`, `call`, `nr`) VALUES \n";

my @out;
open HSC, "hsc.txt";
while ($line = <HSC>) {
    $line =~ s/(\r\n)//g;
    if ($line =~ /^[A-Z0-9]/) {
        my @a = split(/,/, $line);
        push @out, "('HSC', '$a[0]', '$a[1]')";
    }
}
close HSC;

$sql .= join(",\n", @out);
$sql .= ";";

open HSC, ">hsc.sql";
print HSC $sql;
close HSC;

print "Saved to hsc.sql ($#out records).\n";
