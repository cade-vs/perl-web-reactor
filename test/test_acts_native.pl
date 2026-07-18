#!/usr/bin/perl
##
##  Smoke test for the native action dispatcher.
##  The dispatcher (Web::Reactor::Actions::Native) needs a live Web::Reactor
##  object, so build one and call actions through $reo->act->call().
##  'test' resolves to Web::Reactor::Actions::Core::test, which is
##  self-contained (returns a string, ignores the request context).
##
use strict;
use warnings;
use lib '../lib';
use File::Path qw( make_path );
use Web::Reactor;
use Data::Dumper;

my $var_dir = '/tmp/re/var';
make_path( $var_dir );

my %env = (
          REQUEST_SCHEME => 'http',
          REMOTE_ADDR    => '127.0.0.1',
          );

my %cfg = (
          APP_NAME               => 'demo',
          LIB_DIRS               => [ '../lib', '../demo/lib' ],
          SESS_VAR_DIR           => $var_dir,
          DISABLE_SECURE_COOKIES => 1,
          );

my $reo = Web::Reactor->new( \%env, \%cfg );

print $reo->act->call( 'test' ), "\n";
