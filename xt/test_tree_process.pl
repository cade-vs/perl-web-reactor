#!/usr/bin/perl
##############################################################################
##
##  Web::Reactor::Preprocessor::Tree process() minimal test
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
##
##  smallest possible call of Web::Reactor::Preprocessor::Tree::process():
##  one reactor, one hold value, one tag, one assertion. no files, no HTTP.
##
##  usage: perl xt/test_tree_process_min.pl
##
##############################################################################
use strict;

use lib '../lib'; # when run from inside xt/
use lib 'lib';    # when run from the distribution root

use File::Temp qw( tempdir );

use Web::Reactor::Reflex;

# reactor subclasses must live under Web::Reactor:: (see Base::__set_reo)
package Web::Reactor::TestMin;
our @ISA = ( 'Web::Reactor::Reflex' );
sub log {} # silence

package main;

my $reo = Web::Reactor::TestMin->new(
          {
          'REQUEST_METHOD'  => 'GET',
          'QUERY_STRING'    => '',
          'psgi.url_scheme' => 'https',
          'psgi.input'      => \*STDIN,
          'psgi.errors'     => \*STDERR,
          },
          {
          'APP_NAME' => 'testmin',
          'APP_ROOT' => tempdir( CLEANUP => 1 ),
          'LANG'     => 'en',
          } );

$reo->html_hold_set( foo => '123' );

# is( $reo->pre->process( 'main', 'a[<$$foo>]b' ), 'a[123]b', 'process() replaces a hold tag' );

print $reo->pre->process( 'main', 'a[<$$$$foo>]b' );


print "\n\n\n";
###EOF########################################################################
