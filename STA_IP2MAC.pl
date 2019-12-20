#!/usr/bin/env perl

use DB_File;
use File::Basename;
use Cwd;
use FindBin qw($Bin);
FindBin::again();
BEGIN {
  my %INC;
  foreach my $dirname (@INC) {$INC{$dirname}++}
  foreach my $dirname (dirname(__FILE__), $Bin, dirname($0), "/usr/local/scripts", "/usr/local/bin", getcwd()) {
    next if ($INC{$dirname});
    next unless (-d $dirname);
    push(@INC, $dirname);
    $INC{$dirname}++;
} }

require 'AP_common.pl';

my $usage	= "usage: $0 <IP>\n(returns MAC address if IP is currently associated to WiFi)\n";

my $APLIST	= "/usr/local/scripts/APlist";

die $usage unless ($IP = $ARGV[0]);

my $OID = "AIRESPACE-WIRELESS-MIB::bsnMobileStationByIpMacAddress.$IP";
my $MAC;
open(LIST, "$APLIST WLC|") || die "unable to run $APLIST; $!\n";
while (<LIST>) {
  chomp;
  $MAC = snmpget($_, $OID, 0);
  last if ($MAC);
}
close(LIST);

print convertTo($MAC,MAC), "\n" if ($MAC);

