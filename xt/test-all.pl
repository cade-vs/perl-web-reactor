#!/usr/bin/perl
##############################################################################
##
##  Web::Reactor test runner
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
##
##  runs every test_*.pl in t/ one after another, in name order, and stops
##  at the first one that exits non-zero, reporting its file name and status.
##
##  usage:
##
##    perl xt/test-all.pl              -- from the distribution root
##    cd xt && perl test-all.pl        -- from inside xt/
##    perl xt/test-all.pl -v           -- show each test's full output
##    perl -I/path/to/lib xt/test-all.pl
##                                     -- extra include dirs are passed to the tests
##
##  exit status is 0 when all tests pass, otherwise the failing test's status.
##
##############################################################################
use strict;
use File::Basename;
use File::Spec;

my $VERBOSE = grep { $_ eq '-v' } @ARGV;

# t/ lives next to xt/, whichever directory this is run from
my $T_DIR = File::Spec->catdir( dirname( __FILE__ ), '..', 't' );

opendir( my $dh, $T_DIR ) or die "cannot read test directory [$T_DIR]: $!\n";
my @tests = sort grep { /^test_.*\.pl$/ } readdir( $dh );
closedir( $dh );

die "no test_*.pl files found in [$T_DIR]\n" unless @tests;

# pass our own -I dirs on, so a test lib given to the runner reaches the tests
my @inc = map { "-I$_" } grep { ! ref } @INC[ 0 .. $#INC ];
@inc = grep { $_ ne '-I.' } @inc;

my $n = 0;
for my $test ( @tests )
  {
  $n++;
  my $fn = File::Spec->catfile( $T_DIR, $test );

  print "[$n/" . scalar( @tests ) . "] $test ... ";

  my $out = '';
  if( $VERBOSE )
    {
    print "\n";
    system( $^X, @inc, $fn );
    }
  else
    {
    $out = qx( $^X @inc "$fn" 2>&1 );
    }
  my $status = $? >> 8;
  my $signal = $? & 127;

  if( $status == 0 and ! $signal )
    {
    my ( $plan ) = $out =~ /^1\.\.(\d+)/m;
    print "ok" . ( $plan ? " ($plan tests)" : '' ) . "\n";
    next;
    }

  print "FAILED\n\n";
  print "$out\n" unless $VERBOSE;
  print "*** test [$test] failed"
      . ( $signal ? " (killed by signal $signal)" : " (exit status $status)" )
      . ", stopping here, " . ( scalar( @tests ) - $n ) . " test(s) not run\n";
  exit( $status || 1 );
  }

print "\nall " . scalar( @tests ) . " test(s) passed\n";
exit 0;

###EOF########################################################################
