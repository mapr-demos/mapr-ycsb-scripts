#!/usr/bin/perl

#this script when given a directory of ycsb.out and ycsb.stat files in the usual YCSB format (see below)
#processes them as follows:
#for ycsb.out files 
#  itcombines the results together and converts to TSV format.
#  when combining we add ops/sec but average together averages = since we have the # of ops
#  we can do this accurately by weighting the values as we combine them.
#for ycsb.stat files
#  it simply adds up the ops/sec numbers
# the output here is specifically designed to be imported into a spreadsheet also provided


#loop over all passed in directory and combine their stats

#my $env_from_script = `. env.sh; env`;
my $FNB = `grep FILENAME_BASE env.sh | cut -f 2 -d= | tr -d \\\" | tr -d \\\'`;
chomp $FNB;
if (length($FNB) < 1) {
	die 'must set FILENAME_BASE in env.sh';
}

$dir = $ARGV[0];
print "processing files in directory $dir";
$outfilename=$dir . "/" . $FNB . "summary.tsv";
$out2filename=$dir . "/" . $FNB . "statssummary.txt";
print "writing output to $outfilename and $out2filename\n";
open(OUT, '>', $outfilename) or die "Could not open file '$outfilename'!";
open(OUT2, '>', $out2filename) or die "Could not open file '$out2filename'!";


#first process the ycsb.out files and extract the 10 second stats
#sample line I'm trying to convert to TSV:
#2016-05-17 02:06:26:338 540 sec: 1350822 operations; 2233.9 current ops/sec; est completion in 57 minutes [INSERT: Count=22338, Max=759807, Min=1286, Avg=5816.41, 90=6975, 99=28543, 99.9=218367, 99.99=740863] 

#NOTE: older versions of YCSB used this format - I've left the commented out lines for reference
#   20 sec: 150 operations; 201.61 current ops/sec; [UPDATE AverageLatency(us)=227656.38] [READ-MODIFY-WRITE AverageLatency(us)=250.22] [READ AverageLatency(us)=282824.87] [SCAN AverageLatency(us)=317355.36] 

#there is a minor problem here in that the script uses the time reported which should always be a unit of 10 seconds
#but sometimes the YCSB client clocks drift a bit and you'll get a +/- one second (say 111 instead of 110) and
#that messes up how the values across clients are combined. The script rounds the time to the nearest factor
#of 10. That's fine for all results but the very end as the clients don't stop at the same time so the
#last result is potentially meaningless.
my @typeordered;
$typesfound = 0;
$maxsec = 0;
my %summary;

#construct all possible latency types array
push(@typeordered, "UPDATE_AVG" );
push(@typeordered, "UPDATE_MAX" );
push(@typeordered, "UPDATE_MIN" );
push(@typeordered, "UPDATE_90" );
push(@typeordered, "UPDATE_99" );

push(@typeordered, "READ-MODIFY-WRITE_AVG" );
push(@typeordered, "READ-MODIFY-WRITE_MAX" );
push(@typeordered, "READ-MODIFY-WRITE_MIN" );
push(@typeordered, "READ-MODIFY-WRITE_90" );
push(@typeordered, "READ-MODIFY-WRITE_99" );

push(@typeordered, "READ_AVG" );
push(@typeordered, "READ_MAX" );
push(@typeordered, "READ_MIN" );
push(@typeordered, "READ_90" );
push(@typeordered, "READ_99" );

push(@typeordered, "SCAN_AVG" );
push(@typeordered, "SCAN_MAX" );
push(@typeordered, "SCAN_MIN" );
push(@typeordered, "SCAN_90" );
push(@typeordered, "SCAN_99" );

push(@typeordered, "INSERT_AVG" );
push(@typeordered, "INSERT_MAX" );
push(@typeordered, "INSERT_MIN" );
push(@typeordered, "INSERT_90" );
push(@typeordered, "INSERT_99" );

opendir(D, $dir) || die "Can't open directory $dir";
$grepstr = $FNB . '.out' . '.*';
@files = grep (/^$grepstr/, readdir(D));
foreach (@files) {
  $filename=$dir . "/" . $_;
  print "processing file $filename\n";
  open(IN, $filename) or die "Can't open: '$filename'!";

  while ( my $string = <IN> ) {
    my $stats;
#   print $string;
   $string2 = $string;
#   works with older YCSB (0.1.x)
#   if ($string =~ /\s([0-9]+)\ssec:\s([0-9]+)\soperations; ([0-9\.]+)\scurrent ops.*AverageLatency.*/g ) {
#   works with newer YCSB (0.7.x and later)
   if ($string =~ /\s([0-9]+)\ssec:\s([0-9]+)\soperations; ([0-9\.]+)\scurrent ops.*Avg.*/g ) {
      #round to nearest unit of 10 seconds. Not using Math::Round to limit dependencies
      $sec=$1;
      #print "sec = " . $sec . "\n";
      $rem=$sec % 10;
      if ( $rem > 4 ) {
        $sec = $sec + 10 - $rem;
      } else {
        $sec = $sec - $rem;
      }
      #print "rounded sec = " . $sec . "\n";

      #$sec= nearest(10, $1);
      $ops=$2;
      $opspersec=$3;

      $prevops = $summary{$sec}{ops};
      $summary{$sec}{ops} += $ops;
      $summary{$sec}{opspersec} += $opspersec;
#      print "sec =" . $sec . ",ops =" . $ops . ", opspersec =" .  $opspersec . "\n";
#   works with older YCSB (0.1.x)
#      while ($string2 =~ /([A-Z\-]+)\sAverageLatency\(us\)=([0-9\.]+)\]/g) {
#   works with newer YCSB (0.7.x and later)
      while ($string2 =~ /([A-Z-:]+):\sCount=([0-9]+),\sMax=([0-9]+),\sMin=([0-9]+),\sAvg=([0-9\.]+),\s90=([0-9]+),\s99=([0-9]+),/g) {
	# collect all the descriptive stuff and a postfix
	# for each column header
	my @latencies = (
	[ "_MAX", $3 ],
	[ "_MIN", $4 ],
	[ "_AVG", $5 ],
	[ "_90", $6 ],
	[ "_99", $7 ] );
        $latencyType=$1;
        $count=$2;
#   intentionally ignore values where count is small as there appears to be a YCSB reporting bug in 0.9

        print $latencyType . " " . $count . "\n";
        if ($count < 10) {
          print "ignoring suspiciously low internal count for " . $latencyType . ":" . $count . "\n";
        } else {
	  foreach $entref (@latencies) {
	    @thisl = @$entref;
	    $pf = $thisl[0];
	    $l = $thisl[1];
	    $curType = $latencyType . $pf;
	    print "recording type $curType value $l\n";
            $prevlatency = $summary{$sec}{$curType};
            $summary{$sec}{$curType} = (($ops * $l) + ($prevops * $prevlatency))/($ops + $prevops);
          }
        }
      }
  
      #$summary{$sec} = $stats;
      if ($sec > $maxsec) {
        $maxsec = $sec;
      } 
#      $typesfound = 1;
    }
  }
}

# okay, now let's print some stuff out
@sorted_time = sort { $a <=> $b } keys %summary;

# try to discard common outliars (first and last element)
#shift @sorted_time;
#pop @sorted_time;


  print OUT "sec\tops/sec";
  foreach (@typeordered) {
    print OUT "\t" . $_;
  }
  print OUT "\n";
  for $sec (@sorted_time) {
    print OUT $sec . "\t" . int($summary{$sec}{opspersec} + 0.5);
    foreach (@typeordered) {
     print OUT "\t" . int ($summary{$sec}{$_} + 0.5);
    }
    print OUT "\n";
  }

#now process the stats files looking for the Throughput
#lines like this:
# [OVERALL], Throughput(ops/sec), 11840.626911003217


opendir(D, $dir) || die "Can't open directory $dir";
$grepstr = $FNB . '.stats' . '.*';
@files = grep (/^$grepstr/, readdir(D));
foreach (@files) {
  $filename=$dir . "/" . $_;
  print "processing file $filename\n";
  open(IN, $filename) or die "Can't open: '$filename'!";

  while ( my $string = <IN> ) {
    my $stats;
#   print $string;
   $string2 = $string;
    if ($string =~ /\[OVERALL\]\,\sThroughput.*\s([0-9\.]+).*/g ) {

      $throughput += $1;
    }
  }
}

$throughput = int($throughput + 0.5);
print OUT2 "Throughput (ops/sec): " . $throughput;
print OUT2 "\n";
print "Throughput (ops/sec): " . $throughput;
print "\n";

#references
# http://www.troubleshooters.com/codecorn/littperl/perlreg.htm#SimpleStringComparisons
# http://perl.livejournal.com/138466.html?nojs=1&thread=1089762
# http://stackoverflow.com/questions/14041814/how-to-sort-hash-in-perl
# http://perlmaven.com/perl-hashes
