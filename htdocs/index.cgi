#!/usr/bin/perl
use strict;
use Web::Reactor;

my $ROOT = "/opt/reactor";

my %cfg = (
          'APP_NAME'       => 'demo',
          'APP_ROOT'       => "$ROOT/demo/",
          'LIB_DIRS'       => [ "$ROOT/demo/lib/" ],
          'HTML_DIRS'      => [ "$ROOT/demo/html/" ], 
          'SESS_VAR_DIR'   => "$ROOT/demo/var/sess/",
          'REO_ACTS_CLASS' => 'Web::Reactor::Actions::Alt',
          'LANG'           => 'bg',
          'DEBUG'          => 4,
          );

eval { new Web::Reactor( %cfg )->run(); };
if( $@ )
  {
  print STDERR "REACTOR CGI EXCEPTION: $@";
  print "content-type: text/html\n\nsystem is temporary unavailable";
  }
