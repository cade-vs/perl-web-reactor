#!/usr/bin/perl
use strict;
use lib '../lib';
use lib 'lib';
use Web::Reactor;
use Data::Dumper;
use File::Temp qw( tempdir );

# creates, saves and loads USER and PAGE sessions in a Filesystem storage

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

my $reo = Web::Reactor->new( \%env, { APP_NAME => 'demo', APP_ROOT => $root, SESS_VAR_DIR => "$root/var" } );
my $ses = $reo->__ses();

my $user = $ses->create( 'USER' );
my $page = $ses->create( 'PAGE', $user->{ ':SID' }, 8 );

$user->{ 'ID_USER' } = $user->{ ':SID' };
$page->{ 'ID_PAGE' } = $page->{ ':SID' };

$ses->save( $user );
$ses->save( $page );

print Dumper( 'USER' x 10, $ses->load( 'USER', $user->{ ':SID' } ) );
print Dumper( 'PAGE' x 10, $ses->load( 'PAGE', $page->{ ':SID' }, $user->{ ':SID' } ) );

print Dumper( $ses->_split_dir_components( '1234567890', 3, 3 ) );
print Dumper( $ses->_key_to_fn( { READONLY => 1 }, @{ $ses->compose_key_from_sid( 'PAGE', $page->{ ':SID' }, $user->{ ':SID' } ) } ) );
