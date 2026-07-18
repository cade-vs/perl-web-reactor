#!/usr/bin/perl
##
##  Smoke test for the filesystem session storage backend.
##  Current API: $reo->ses->create/save/load, plus the private
##  _split_dir_components / _key_to_fn helpers on the session object.
##
use strict;
use warnings;
use lib '../lib';
use File::Path qw( make_path );
use Web::Reactor;
use Data::Dumper;

my $var_dir = '/tmp/re/var';
make_path( $var_dir );

# minimal PSGI-ish env; http scheme is allowed only with DISABLE_SECURE_COOKIES
my %env = (
          REQUEST_SCHEME => 'http',
          REMOTE_ADDR    => '127.0.0.1',
          );

my %cfg = (
          APP_NAME               => 'test',
          SESS_VAR_DIR           => $var_dir,
          DISABLE_SECURE_COOKIES => 1,
          );

my $reo = Web::Reactor->new( \%env, \%cfg );
my $ses = $reo->ses();

my $idu = $ses->create( 'USER', 64 );
my $idp = $ses->create( 'PAGE',  8 );

$ses->save( 'USER', $idu, { ID_USER => $idu } );
$ses->save( 'PAGE', $idp, { ID_PAGE => $idp } );

print Dumper( 'USER' x 10, $idu, $ses->load( 'USER', $idu ) );
print Dumper( 'PAGE' x 10, $idp, $ses->load( 'PAGE', $idp ) );

# storage-path helpers live on the Filesystem session object
print Dumper( $ses->_split_dir_components( '1234567890', 3, 3 ) );
print Dumper( $ses->_key_to_fn( { READONLY => 1 }, 'PAGE', '1234567890', 'abcdefgh', 'zxcvbn' ) );
