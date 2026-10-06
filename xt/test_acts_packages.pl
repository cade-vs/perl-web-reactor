#!/usr/bin/perl
##############################################################################
##
##  Web::Reactor application machinery
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
##
##  demo script: the Actions::Packages loader with a throw-away app
##
##############################################################################
use strict;
use lib '../lib';
use lib 'lib';
use Web::Reactor;
use Data::Dumper;
use File::Temp qw( tempdir );

# calls the Core 'test' action through the Packages action loader

my $root = tempdir( CLEANUP => 1 );

my %env = (
          REQUEST_METHOD  => 'GET',
          REQUEST_URI     => '/',
          QUERY_STRING    => '',
          SERVER_NAME     => 'localhost',
          SERVER_PORT     => 443,
          SERVER_PROTOCOL => 'HTTP/1.1',
          REMOTE_ADDR     => '127.0.0.1',
          'psgi.version'    => [ 1, 1 ],
          'psgi.url_scheme' => 'https',
          'psgi.errors'     => \*STDERR,
          );

my %cfg = (
          APP_NAME      => 'demo',
          APP_ROOT      => $root,
          REO_ACT_CLASS => 'Web::Reactor::Actions::Packages',
          );

my $reo = Web::Reactor->new( \%env, \%cfg );

print $reo->act->call( 'test' ), "\n";
