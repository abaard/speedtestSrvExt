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

require 'ap_common.pl';

use Socket;
use Sys::Syslog qw(:DEFAULT setlogsock);

my $usage		= "$0 [rcvPort=port] [debug=(on|off)] [dropPID=FILE]\n";

$default{port}		= 23456;
my @I_am		= split(/\//,$0);
my $I_am		= $I_am[$#I_am];		if ($I_am =~ /^(\S+)\.pl.*$/) {$I_am = $1}
$default{PIDfile}	= "/tmp/${I_am}.pid";
my $rcvPort		= $default{port};
my $dropPID		= $default{PIDfile};
eval "\$$1=\$2" while $ARGV[0] =~ /^(\w+)=(.*)/ && shift;

my $vhost		= "0.0.0.0";
my ($proto, $rcvLen)	= ("udp", 9999);

my %statusMsg;
my $suUser		= "wifimgr";
my $ageLimit		= 60;			# lookups are considered stale after 60 seconds
my $maxSubprocs		= 10;
my %syslogConf		= (facility	=> "daemon",
			   level	=> "debug",
			   options	=> "cons,pid",);

my @FHstate		= (available, taken, lookupMacAddr, lookupBasicData, lookupXtraData, lookupAPdata);
my %statusMsg		= ("overload"	=> "status=OVERLOAD\n",
			   "notfound"	=> "status=notFound\n",);
$debug{udp}		= $true;
$debug{error}		= $true;
$debug{proglog}		= $false;
$debug{fileop}		= $false;
$debug{logging}		= $true;
if	($debug eq "on")	{foreach my $type (keys %debug) {$debug{$type}=$true}}
elsif	($debug eq "off")	{foreach my $type (keys %debug) {$debug{$type}=$false}}

my $APuser	= "apuser";
my $APlist	= "aplist";
my $IP2MAC	= "STA_IP2MAC.pl";
my $SU		= "su";

######################

my @loggedMsgs;

sub accessAllowed {
  return ($_[0] =~ /^(127\.0\.0\.1|129\.242\.10\.193|129\.242\.(3|4|6|237)\.)/);
}

sub dbug {
  my ($tag,$msg,$lNo) = @_;
  if ($debug{$tag}) {print "$tag[$lNo]: $msg\n"}
}

sub freeFHno {
  for (my $i=1; $i<=$maxSubprocs; $i++) {
    if ($state[$i] eq "available") {
      $state[$i] = "taken";			# unnecessary
      return($i);
  } }
  return($false);				# none available
}

sub resetSelect {
  $rin = "";
  vec($rin, fileno(S), 1) = 1;
  for (my $i=1; $i<=$maxSubprocs; $i++) {
    if ($state[$i] ne "available") {
      vec($rin, fileno($FHname[$i]), 1) = 1;
} } }

sub logData {
  my ($tag,$msg) = @_;
  dbug(logging, "logData($tag $msg)", __LINE__);
  syslog($syslogConf{level}, "$tag $msg");
  push(@loggedMsgs, "$tag $msg");
}

######################

if ($dropPID) {open(F,">$dropPID") || warn "unable to drop PID to $dropPID; $!\n"; print F "$$\n"; close(F)}
if (($rcvPort < 1024) && ($< != 0)) {
  warn "port<1024 requires 'root', binding to port $default{port} instead\n";
  $rcvPort = $default{port};
}
openlog($I_am, $syslogConf{options}, $syslogConf{facility});

for (my $i=1; $i<=$maxSubprocs; $i++) {
  $FHname[$i]	= "FH$i";
  $state[$i]	= "available";
}

socket(S,PF_INET,SOCK_DGRAM,getprotobyname($proto)) || die "socket; $!\n";
bind(S,sockaddr_in($rcvPort, pack("C4",split(/\./,$vhost)))) || die "bind ($vhost,$rcvPort); $!\n";
resetSelect();

while ($nfound = select($rout=$rin,undef,undef,undef)) {
  dbug(proglog, "select, \$nfound=$nfound", __LINE__);
  while ($nfound > 0) {
    dbug(proglog, "looping, \$nfound=$nfound", __LINE__);
    if (vec($rout,fileno(S),1)) {
      my $buffer = "";
      my $hisaddr = recv(S, $buffer, $rcvLen, 0) || die "recv; $!\n";
      my ($srcport,$srchost) = sockaddr_in($hisaddr);
      my $srchostIP = join(".",unpack("C4",$srchost));
      if ($buffer =~ /^ping$/i) {
        send(S, "alive\n", 0, $hisaddr);
        dbug(udp, "ping -> alive", __LINE__);
 #    } elsif (!accessAllowed($srchostIP)) {
      # NOOP
      } elsif ($buffer =~ /^activity report$/i) {
        dbug(udp, "activity report requested", __LINE__);
        foreach my $msg (@loggedMsgs) {send(S, "$msg\n", 0, $hisaddr)}
        @loggedMsgs = ();
      } elsif ($buffer =~ /^(IP=)?((\d{1,3}\.){3}\d{1,3})[\s;]*(.*)$/) {
        my $IPinfoReq = $2;
        $clientData{$IPinfoReq} = $4;
        dbug(udp, "from $srchostIP/$srcport: $IPinfoReq, data=$clientData{$IPinfoReq}; " . localtime(time()), __LINE__);
        my $age = time() - $wifiDataTS{$IPinfoReq};
        if ($buffered{$IPinfoReq} && ($age < $ageLimit)) {
          send(S, "$buffered{$IPinfoReq}\n", 0, $hisaddr);
          dbug(udp, "\tsending (buffered,\$age=${age}s): $buffered{$IPinfoReq}", __LINE__);
          if ($clientData{$IPinfoReq}) {
            if ($wifiData{$IPinfoReq} =~ /Retry:/) {		# it's been logged recently, log only ext (speedtest) data
              logData("ext:", "$MAC{$IPinfoReq} $clientData{$IPinfoReq}");
            } else {
              my $FHno = freeFHno();
              if (!$FHno) {
                logData("ext:",	"$MAC{$IPinfoReq} $clientData{$IPinfoReq}");
                logData("client:","$wifiData{$IPinfoReq}");
              } else {
                $FHno{$IPinfoReq} = $FHno;
                $IP[$FHno] = $IPinfoReq;
                my $MAC = $MAC{$IPinfoReq};	# from previous lookup; not stale, as $buffered{$IPinfoReq} isn't
                my $CMD = (($>==0) ? "$SU $suUser -c '$APuser -idrl $MAC'" : "$APuser -idrl $MAC");
                dbug(fileop, "open($FHname[$FHno], \"$CMD |\")", __LINE__);
                open($FHname[$FHno], "$CMD |") || dbug(error, "open($FHname[$FHno], \"$CMD |\") failed; $!", __LINE__);
                $state[$FHno] = "lookupXtraData";
  #             $requestor[$FHno] = $hisaddr;		# not necessary, nothing more to send
                resetSelect();
          } } }
        } else {
          my $FHno = freeFHno();
          if (!$FHno) {
            send(S, $statusMsg{overload}, 0, $hisaddr);
            dbug(udp, "\tsending: $statusMsg{overload}", __LINE__);
          } else {
            $FHno{$IPinfoReq} = $FHno;
            $IP[$FHno] = $IPinfoReq;
            my $CMD = (($>==0) ? "$SU $suUser -c '$IP2MAC $IPinfoReq'" : "$IP2MAC $IPinfoReq");
            dbug(fileop, "open($FHname[$FHno], \"$CMD |\")", __LINE__);
            open($FHname[$FHno], "$CMD |") || dbug(error, "open($FHname[$FHno], \"$CMD |\") failed; $!", __LINE__);
            $state[$FHno] = "lookupMacAddr";
            $requestor[$FHno] = $hisaddr;
            resetSelect();
      } } }
    } else {
      for (my $i=1; $i<=$maxSubprocs; $i++) {
        if (vec($rout,fileno($FHname[$i]),1)) {
          my ($n,$nRead,$buf,$buffer) = (0,0,"","");
          while ($n = sysread($FHname[$i], $buf, $rcvLen)) {$buffer .= $buf; $nRead += $n}
          $buffer = (split(/[\r\n]+/,$buffer))[0];			# first line only, stripped for crlf
          while ($buffer =~ /^(.*)\s$/) {$buffer=$1}			# remove trailing spaces
          $buffer = join(" ", split(/\s+/,$buffer));			# remove redundant white space
          dbug(fileop, "sysread($nRead): $buffer", __LINE__);
          dbug(fileop, "close($FHname[$i])", __LINE__);
          close($FHname[$i]) || dbug(error, "close($FHname[$i]) failed; $!", __LINE__);
          dbug(proglog, "\tstate=$state[$i]", __LINE__);
          if ($state[$i] eq "lookupMacAddr") {
            if ($buffer =~ /^(([\da-f]{2}:){5}[\da-f]{2})$/) {
              my $MAC = $MAC{$IP[$i]} = $buffer;
              my $CMD = (($>==0) ? "$SU $suUser -c '$APuser -bul $MAC'" : "$APuser -bul $MAC");
              dbug(fileop, "open($FHname[$i], \"$CMD |\")", __LINE__);
              open($FHname[$i], "$CMD |") || dbug(error, "open($FHname[$i], \"$CMD |\") failed; $!", __LINE__);
              $state[$i] = "lookupBasicData";
            } else {							# MAC addr of $IPinfoReq no found
              send(S, $statusMsg{notfound}, 0, $requestor[$i]);
              dbug(udp, "\tsending: $statusMsg{notfound}", __LINE__);
              $state[$i] = "available";
            }
          } elsif ($state[$i] eq "lookupBasicData") {
            $wifiData{$IP[$i]} = $buffer;
            my $IPinfoReq = $IP[$i];
            $buffered{$IPinfoReq} = "";
            my (%tv,@f) = ((),());
            foreach my $f (split(/\s+/, $buffer)) {
              if    ($f =~ /^([\da-f]{2}:){5}[\da-f]{2}$/)	{$tv{MAC}=$f}
              elsif ($f =~ /^Up=(.+)$/)				{$tv{uptime}=$1}
              elsif ($f =~ /^\( *(-?\d*dBm)\/ *(-?\d*dB)\)$/)	{($tv{RSSI},$tv{SNR})	= ($1,$2)}
              elsif ($f =~ /-rw\d*$/i)				{$tv{AP}=$f}
              elsif ($f =~ /^dot11([a-z]+)(\d*)$/)		{($tv{PHY},$tv{band})	= ($1,$2)}
              elsif ($f =~ /^\(m?([^,]*),s*(\d*)\)$/)		{($tv{MCS},$tv{SS})	= ($1,$2)}
              else {push(@f,$f)}
            }
            if ($tv{PHY}) {$tv{PHY} .= " (" . (($tv{band}==24) ? "2.4" : $tv{band}) . "GHz)"; delete($tv{band})}
            foreach my $val (@f) {
              if ($val =~ /$mySSIDs/oi) {
                $tv{SSID} = $val;
                last;
            } }
            if (!$tv{SSID}) {$tv{SSID} = (($f[1]) ? $f[1] : $f[0])}
            my $msg;
            foreach my $tag (sort keys %tv) {$msg .= "$tag=$tv{$tag}; "}
            chop($msg);
            send(S, "$msg\n", 0, $requestor[$i]);
            dbug(udp, "\tsending: $msg", __LINE__);
            $buffered{$IPinfoReq} = $msg;
            $wifiDataTS{$IPinfoReq} = time();
            if ($clientData{$IPinfoReq}) {
              my $MAC = $MAC{$IP[$i]};
              my $CMD = (($>==0) ? "$SU $suUser -c '$APuser -idrl $MAC'" : "$APuser -idrl $MAC");
              dbug(fileop, "open($FHname[$i], \"$CMD |\")", __LINE__);
              open($FHname[$i], "$CMD |") || dbug(error, "open($FHname[$i], \"$CMD |\") failed; $!", __LINE__);
              $state[$i] = "lookupXtraData";
            } else {
              $state[$i] = "available";
            }
          } elsif ($state[$i] eq "lookupXtraData") {
            my (%seen, $APname);
            foreach my $word (split(/\s+/,$wifiData{$IP[$i]})) {
              $seen{$word}++;
              if ($word =~ /-rw\d*$/i) {$APname = $word}
            }
            foreach my $word (split(/\s+/,$buffer)) {
              next if ($seen{$word});
              $wifiData{$IP[$i]} .= " $word";
            }
            my $CMD = (($>==0) ? "$SU $suUser -c '$APlist -mpx $APname'" : "$APlist -mpx $APname");
            dbug(fileop, "open($FHname[$i], \"$CMD |\")", __LINE__);
            open($FHname[$i], "$CMD |") || dbug(error, "open($FHname[$i], \"$CMD |\") failed; $!", __LINE__);
            $state[$i] = "lookupAPdata";
          } elsif ($state[$i] eq "lookupAPdata") {
            my $IPinfoReq = $IP[$i];
            logData("ext:",	"$MAC{$IP[$i]} $clientData{$IP[$i]}");
            logData("client:",	"$wifiData{$IP[$i]}");
            logData("AP:",	"$MAC{$IP[$i]} $buffer");
          # undef($clientData{$IPinfoReq});	# NO! may cause incomplete log lines if two identical rapid requests
            undef($FHno{$IPinfoReq});
            $state[$i] = "available";
          } else {
            dbug(proglog, "how did we ever get here???", __LINE__);
            $state[$i] = "available";
          }
          resetSelect();
          last;
    } } }
    $nfound--;
} }
closelog();

__END__

Program logic:
(1) Receive IP address on UDP port, e.g. "129.242.115.34" (without the quotes)
(2) Use local scripts to lookup data pertaining to the IP addr, from the WiFi infrastructure;
	(a) MAC address (from IP), and (b) RSSI and other comm.info
(3) Send WiFi info back to requestor
(4) If extra data is trailing the IP address request, e.g "129.242.115.34 xtradata",
	then some additional WiFi info is looked up, and all WiFi info is logged together with the xtradata (to syslog)

