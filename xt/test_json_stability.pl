#!/usr/bin/perl
##############################################################################
##
##  JSON encoding stability test
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
##
##  checks whether encoding the same, unmodified perl structure to JSON gives
##  the same text every time, and whether merely READING values out of the
##  structure changes what the next encoding produces.
##
##  every JSON instance here has canonical(1) enabled, so hash keys are always
##  sorted and key order never contributes to a difference; whatever differs
##  is a real change in how a value is represented.
##
##  usage:
##
##    perl xt/test_json_stability.pl        -- TAP on stdout
##
##  reads which change the output are expected for a few cases (a number used
##  as a string is encoded as a string afterwards) and are marked TODO, so the
##  file passes while still listing them. which reads stringify is a property
##  of perl and the JSON backend; the flags in @READS match perl 5.40 with
##  JSON::XS 4.04, an unexpected pass or fail on another version is a finding.
##
##############################################################################
use strict;

use Test::More;
use JSON;
use Storable qw( dclone );

my $JSON = JSON->new->utf8->canonical( 1 );

diag( "JSON backend: " . JSON->backend . " " . JSON->backend->VERSION . ", canonical(1)" );

##############################################################################
##
##  the structure: 3 levels, hashes and arrays, numbers, strings, numeric
##  strings, floats, unicode, undef, empty containers
##

sub make_data
{
  return {
         'user' => {
                   'id'      => 42,
                   'name'    => "Cade",
                   'city'    => "\x{421}\x{43E}\x{444}\x{438}\x{44F}", # Sofia in Cyrillic
                   'score'   => 3.25,
                   'zip'     => "1000",                                # numeric looking string
                   'active'  => 1,
                   'note'    => undef,
                   'tags'    => [ 'admin', 'dev', 'ops' ],
                   'limits'  => { 'daily' => 100, 'monthly' => 3000, 'ratio' => 0.5 },
                   },
         'page' => {
                   'name'    => 'admin/users',
                   'visits'  => [ 3, 7, 11, 13 ],
                   'history' => [
                                { 'at' => 1790754115, 'pn' => 'main',  'ok' => 1 },
                                { 'at' => 1790754200, 'pn' => 'users', 'ok' => 0 },
                                ],
                   'empty_h' => {},
                   'empty_a' => [],
                   },
         # $n is taken before "k$_" and "v$_" stringify $_, so the numbers here
         # start as plain numbers; copying $_ itself after the interpolation
         # would carry the string flag along and encode as "1", "2", ...
         'link' => {
                   map { my $n = $_ + 0; ( "k$_" => { 'n' => $n, 's' => "v$_", 'l' => [ $n, $n * 2 ] } ) } 1..12
                   },
         };
}

# compare two JSON texts, on mismatch show only the region around the first
# difference instead of both full texts
sub same
{
  my ( $got, $want, $name ) = @_;
  return 1 if ok( $got eq $want, $name );
  diag( "   want: " . snip( $want, $got ) );
  diag( "   got:  " . snip( $got, $want ) );
  return 0;
}

##############################################################################
##
##  section 1 -- repeated encoding of the same unmodified structure
##

{
my $data  = make_data();
my @texts = map { $JSON->encode( $data ) } 1 .. 10;

is( scalar( grep { $_ eq $texts[0] } @texts ), 10, "10 encodings of the same unmodified structure are identical" );
}

##############################################################################
##
##  section 2 -- equal content in a different hash
##
##  a copy, or the structure decoded back from its own JSON (which is exactly
##  what a session loaded from disk is), has the same content but its own
##  hash key order; canonical output must not see that
##

{
my $data = make_data();

my $orig  = $JSON->encode( $data );
my $copy  = $JSON->encode( dclone( $data ) );
my $round = $JSON->encode( $JSON->decode( $orig ) );

same( $copy,  $orig, "a deep copy encodes identically" );
same( $round, $orig, "a decode/encode round trip encodes identically" );
is_deeply( $JSON->decode( $round ), $JSON->decode( $orig ), "round trip content is equal" );

my $round2 = $JSON->encode( $JSON->decode( $round ) );
same( $round2, $orig, "a second round trip still encodes identically" );

# Storable (dclone, freeze/thaw) keeps one representation of a dual valued
# scalar: a number that was used as a string comes out of a copy as a plain
# number again, so the copy encodes differently from the original
my $dual = { 'n' => 7 };
my $l = "n=$dual->{n}"; # string use, n now also carries its string form
TODO:
  {
  local $TODO = 'expected: dclone drops the string form of a stringified number';
  same( $JSON->encode( dclone( $dual ) ), $JSON->encode( $dual ), "a stringified number survives dclone unchanged" );
  }
}

##############################################################################
##
##  section 3 -- reading values out of the structure
##
##  every read runs on a fresh structure: encode, read, encode again, compare.
##  a read that changes the next encoding is reported with the before and
##  after text of the differing part
##

my @READS = (
  # name, code, changes_output (documented JSON::XS behaviour)
  [ 'hash key exists',                sub { exists $_[0]{ 'user' }{ 'limits' }{ 'daily' } },               0 ],
  [ 'keys of a nested hash',          sub { my @k = keys %{ $_[0]{ 'link' } } },                           0 ],
  [ 'iterate every level with each',  sub { while( my ( $k, $v ) = each %{ $_[0]{ 'user' } } ) { } },      0 ],
  [ 'array length',                   sub { scalar @{ $_[0]{ 'page' }{ 'visits' } } },                     0 ],
  [ 'string compared as string',      sub { $_[0]{ 'user' }{ 'name' } eq 'Cade' },                        0 ],
  [ 'string length',                  sub { length $_[0]{ 'user' }{ 'city' } },                            0 ],
  [ 'number compared as number',      sub { $_[0]{ 'user' }{ 'id' } == 42 },                               0 ],
  [ 'number used in arithmetic',      sub { my $x = $_[0]{ 'user' }{ 'limits' }{ 'daily' } + 1 },          0 ],
  [ 'float compared as number',       sub { $_[0]{ 'user' }{ 'score' } > 3 },                              0 ],
  [ 'numeric string used as number',  sub { $_[0]{ 'user' }{ 'zip' } + 0 },                                0 ],
  [ 'array element as number',        sub { my $s = 0; $s += $_ for @{ $_[0]{ 'page' }{ 'visits' } } },   0 ],
  [ 'undef tested with defined',      sub { defined $_[0]{ 'user' }{ 'note' } },                           0 ],
  [ 'missing key read (no create)',   sub { my $x = $_[0]{ 'user' }{ 'nope' } },                           0 ],
  [ 'float interpolated',             sub { my $l = "score $_[0]{user}{score}" },                          0 ],
  [ 'number compared as string',      sub { $_[0]{ 'user' }{ 'id' } eq '42' },                             1 ],
  [ 'number interpolated in a log',   sub { my $l = "user [$_[0]{user}{id}] visits [@{ $_[0]{page}{visits} }]" }, 1 ],
  [ 'number passed to sprintf %s',    sub { sprintf "%s", $_[0]{ 'page' }{ 'history' }[0]{ 'at' } },       1 ],
  [ 'number used as a hash key',      sub { my %h = ( $_[0]{ 'link' }{ 'k3' }{ 'n' } => 1 ) },             1 ],
  [ 'deep missing key autovivifies',  sub { my $x = $_[0]{ 'page' }{ 'nope' }{ 'deeper' } },               1 ],
);

for my $r ( @READS )
  {
  my ( $what, $code, $changes ) = @$r;

  my $data   = make_data();
  my $before = $JSON->encode( $data );
  $code->( $data );
  my $after  = $JSON->encode( $data );

  TODO:
    {
    local $TODO = 'expected: this read changes how the value is encoded' if $changes;
    same( $after, $before, "unchanged after [$what]" );
    }
  }

##############################################################################
##
##  section 4 -- all reads together, then repeated encoding again
##
##  the structure is read in every way above, then encoded 10 more times: the
##  post-read encodings must agree with each other even where they differ from
##  the pre-read one, i.e. the drift happens once, not on every encoding
##

{
my $data   = make_data();
my @before = map { $JSON->encode( $data ) } 1 .. 5;
$_->[1]->( $data ) for @READS;
my @after  = map { $JSON->encode( $data ) } 1 .. 10;

is( scalar( grep { $_ eq $before[0] } @before ), 5,  "all encodings before the reads agree" );
is( scalar( grep { $_ eq $after[0]  } @after  ), 10, "all encodings after the reads agree with each other" );

my $only_safe = make_data();
my $b = $JSON->encode( $only_safe );
$_->[1]->( $only_safe ) for grep { ! $_->[2] } @READS;
same( $JSON->encode( $only_safe ), $b, "all non-stringifying reads together leave the encoding unchanged" );

TODO:
  {
  local $TODO = 'expected: the stringifying reads change the encoding';
  same( $after[0], $before[0], "encoding after all reads equals the one before" );
  }

is_deeply( $JSON->decode( $after[0] ), fold( $JSON->decode( $before[0] ), $JSON->decode( $after[0] ) ),
           "content is the same apart from numbers turned into strings and autovivified keys" );

# the drifted text survives a round trip unchanged: once a number is stored as
# a string it stays a string, decoding it does not turn it back
same( $JSON->encode( $JSON->decode( $after[0] ) ), $after[0], "the drifted encoding is stable across a round trip" );
}

##############################################################################

done_testing();

##############################################################################
##
##  helpers
##

# the part of $a around its first difference from $b, for readable diagnostics
sub snip
{
  my ( $a, $b ) = @_;
  my $i = 0;
  $i++ while $i < length( $a ) and $i < length( $b ) and substr( $a, $i, 1 ) eq substr( $b, $i, 1 );
  my $from = $i > 30 ? $i - 30 : 0;
  return ( $from ? '...' : '' ) . substr( $a, $from, 70 ) . '...';
}

# $want with every scalar that $got holds as the same value in string form
# replaced by that string, and every key $got gained added: lets the content
# check ignore exactly the two documented kinds of drift
sub fold
{
  my ( $want, $got ) = @_;

  if( ref $want eq 'HASH' and ref $got eq 'HASH' )
    {
    my %r = map { ( $_ => fold( $want->{ $_ }, $got->{ $_ } ) ) } keys %$want;
    exists $r{ $_ } or $r{ $_ } = $got->{ $_ } for keys %$got;
    return \%r;
    }
  if( ref $want eq 'ARRAY' and ref $got eq 'ARRAY' )
    {
    return [ map { fold( $want->[ $_ ], $got->[ $_ ] ) } 0 .. $#$want ];
    }
  return $got if defined $want and defined $got and ! ref $want and ! ref $got and $want eq $got;
  return $want;
}

###EOF########################################################################
