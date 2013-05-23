#!/usr/bin/perl
use lib '../lib';
use Web::Reactor;
use Data::Dumper;

my $reo = new Web::Reactor SESS_VAR_DIR => '/tmp/re/var';

my $idu = $reo->sess_create( 'USER', 64 );
my $idp = $reo->sess_create( 'PAGE',  8 );

$reo->sess_save( 'USER', $idu, { ID_USER => '$idu' } );
$reo->sess_save( 'PAGE', $idp, { ID_PAGE => '$idp' } );

print Dumper( 'USER' x 10, $idu, $reo->sess_load( $idu ) );
print Dumper( 'PAGE' x 10, $idp, $reo->sess_load( $idp ) );

my $dir = '1234567890';
print Dumper( $reo->{ 'REO_SESS' }->_split_dir_components( $dir, 3, 3 ) );
print Dumper( $reo->{ 'REO_SESS' }->_key_to_fn( 'PAGE', '1234567890', 'abcdefgh', 'zxcvbn') );
