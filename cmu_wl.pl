#!/usr/bin/perl

my $iface = "wlan0";
my $ESSID = "CMU";

use strict;
use warnings;

sub INT_handler
{
  print "Goodbye\n";
  system("dhclient", "-x");
  system("killall", "dhclient");
  system("start", "network-manager");
  exit(0);
};
$SIG{'INT'} = 'INT_handler';

system("stop", "network-manager");
system("ifconfig", $iface, "up");
if ( ($?>>8) != 0 )
{
  die("could not enable $iface");
}

my @chanl = [];
my $ts = 0;
my $needaddr = 1;

while(1)
{
  my $iwc;
  while(1)
  {
    $iwc = `iwconfig $iface`;
    if ($iwc !~ m/ESSID:"([^"]*).*?Link Quality=([0-9]*)/mgs)
    {
      last;
    }
#    if ($2 < 30)
#    {
#      last;
#    }
    my $sid = $1;
    my $lq = $2;
    if ($needaddr)
    {
      system("ping -q -c1 -W1 8.8.8.8 >/dev/null 2>/dev/null");
      if ( ($?>>8)!=0 )
      {
        system("dhclient", "-x");
        system("killall", "dhclient");
        eval {
          local $SIG{ALRM} = sub { die "alarm\n" }; # NB: \n required
          alarm 5;
          system("dhclient", "-v", "wlan0");
          alarm 0;
        };
        if ($@) {
          die unless $@ eq "alarm\n";   # propagate unexpected errors
          # timed out
        }
      }
      $needaddr = 0;
    }
    print "Associated to $sid, signal strength $lq. Monitoring...\n";
    sleep(1);
  }
  print "$iwc\n";
  $needaddr = 1;

  if (($#chanl <= 0) && ($ts + 30 < time()))
  {
    $ts = time();
    
    my $iwl = `iwlist $iface scan`;
    if ( ($?>>8) != 0 )
    {
      die("Error running AP scan");
    }
    
    my %chans;
    while($iwl =~ /Channel:([0-9]*).*?Quality=([0-9]*).*?ESSID:"([^"]*)/mgs)
    {
      print "CH: $1  Q: $2  E: $3\n";
      if ($3 eq $ESSID)
      {
        $chans{$1}[0] += $2;
        $chans{$1}[1] += 1;
      }
    }
    foreach my $ch (keys %chans)
    {
      $chans{$ch} = $chans{$ch}[0] / $chans{$ch}[1];
#      print "$ch : $chans{$ch}\n"
    }

    @chanl = sort { $chans{$b} <=> $chans{$a} } keys %chans ;
#    print $_ ."\n" foreach @chanl;
    
#    print $#chanl."\n";
  }

  if ($#chanl >= 0)
  {
    print "Associating to $ESSID on channel $chanl[0]\n";
    
    system("iwconfig", $iface, "essid", $ESSID, "ap", "any", "channel", $chanl[0]);
    if ( ($?>>8) != 0 )
    {
      die("Error setting up $iface");
    }
  
    splice(@chanl, 0, 1);    
  }
  else
  {
    print "Could not find an AP\n";
  }
  
## should i change this to check for ESSID: off/any (?)
  my $sttm = time();
  while($sttm + 5 > time())
  {
    sleep(1);
    $iwc = `iwconfig $iface`;
    if ($iwc =~ m/ESSID:"([^"]*).*?Link Quality=([0-9]*)/mgs)
    {
      last;
    }
  }
}
