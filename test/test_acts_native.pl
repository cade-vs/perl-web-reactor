#!/usr/bin/perl
use lib '../lib';
use Web::Reactor;
use Data::Dumper;
use Web::Reactor::Acts::Native;

my %opt = (
          APP_NAME  => 'demo',
          LIB_PATHS => [ qw(
                         /home/cade/pro/reactor/demo/lib/
                         ) ],
          );

my $rea = new Web::Reactor::Acts::Native %opt;

print $rea->call( 'test' );
