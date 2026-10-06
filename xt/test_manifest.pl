#!/usr/bin/perl
##############################################################################
##
##  MANIFEST and Makefile.PL consistency test
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
##
##  runs from any directory. checks that every MANIFEST file exists, that
##  every module, demo file, test and htdocs file is listed, and that
##  Makefile.PL lists the modules the library uses from outside the
##  distribution
##
##############################################################################
use strict;
use Test::More;
use File::Find;
use Module::CoreList;
use File::Basename;

# all paths below are relative to the distribution root
chdir( dirname( __FILE__ ) . '/..' ) or die "cannot chdir to the distribution root\n";

my %manifest;
open( my $fh, '<', 'MANIFEST' ) or die "cannot open MANIFEST\n";
while( <$fh> )
  {
  s/\s+$//;
  s/^\s+//;
  next if $_ eq '' or /^#/;
  my ( $file ) = split /\s+/;
  $manifest{ $file }++;
  }
close( $fh );

ok( -e $_, "MANIFEST file [$_] exists" ) for sort keys %manifest;

my @need;
find( { no_chdir => 1, wanted => sub { push @need, $File::Find::name if -f and /\.pm$/ } }, 'lib' );
find( { no_chdir => 1, wanted => sub { push @need, $File::Find::name if -f } }, 'htdocs' );
find( { no_chdir => 1, wanted => sub { push @need, $File::Find::name if -f } }, 'demo' ); # the POD says the demo is in the tarball
push @need, glob( 't/*.pl' );
ok( $manifest{ $_ }, "[$_] is in MANIFEST" ) for sort @need;

open( $fh, '<', 'Makefile.PL' ) or die "cannot open Makefile.PL\n";
my $mpl = do { local $/; <$fh> };
close( $fh );

# module used by the library => distribution which Makefile.PL must list
my %dist = ( 'Crypt::PRNG' => 'CryptX' );
my %used;
for my $pm ( grep { /\.pm$/ } @need ) # lib/ and demo/lib/ modules
  {
  open( my $ph, '<', $pm ) or die "cannot open [$pm]\n";
  my $in_pod;
  while( <$ph> )
    {
    last if /^__END__/;
    $in_pod = 1 if /^=\w/;   # POD examples may "use" modules the code does not
    $in_pod = 0 if /^=cut/;
    next if $in_pod;
    next unless /^\s*use\s+([A-Z][\w:]+)/;
    my $m = $1;
    if( $m =~ /^Web::Reactor\b/ )
      {
      # our own modules must exist, in lib/ or in the demo's lib/
      ( my $f = "$m.pm" ) =~ s{::}{/}g;
      ok( -e "lib/$f" || -e "demo/lib/$f", "[$m] used in [$pm] exists" );
      next;
      }
    next if Module::CoreList::is_core( $m ); # core modules need no listing
    $used{ $m } ||= $pm;
    }
  close( $ph );
  }

for my $m ( sort keys %used )
  {
  my $d = $dist{ $m } // $m;
  # a listed module also covers its sub-modules from the same distribution
  my $listed = grep { $d eq $_ or $d =~ /^\Q$_\E::/ } ( $mpl =~ /'([\w:]+)'\s*=>/g );
  ok( $listed, "Makefile.PL lists [$d] for [$m] used in [$used{ $m }]" );
  }

done_testing();
