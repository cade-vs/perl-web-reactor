#!/usr/bin/perl
##############################################################################
##
##  Web::Reactor application machinery
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com> <cade@bis.bg> <cade@cpan.org>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
##
##  single-file test utility for Web::Reactor (the stateful layer)
##
##  usage:
##
##    cd t && perl test_reactor.pl      -- run, TAP output on stdout
##    perl t/test_reactor.pl            -- same, from the distribution root
##    perl t/test_reactor.pl -v         -- also pass reactor log() to stderr
##
##  Core and Reflex (render, portray, response api, crypto, translations,
##  page and action dispatch) have their own tests, test_reactor_core.pl and
##  test_reactor_reflex.pl. this one covers what Web::Reactor adds: session
##  storage, cookie/user/page/link sessions, login and logout, the session
##  state cache, args and forwards, params, the HTML helpers which need a
##  live reactor, Web::Reactor::Base and the distribution files (MANIFEST,
##  Makefile.PL).
##
##  everything runs against a throw-away application tree created under a
##  temporary directory, nothing outside of it is touched.
##
##############################################################################
use strict;

use lib '../lib'; # when run from inside t/
use lib 'lib';    # when run from the distribution root

use Test::More;
use File::Temp qw( tempdir );
use File::Path qw( make_path );
use File::Basename qw( dirname );
use Data::Tools;
use Data::Dumper;

my $VERBOSE = grep { $_ eq '-v' } @ARGV;

##############################################################################
##
##  test application class
##
##  must live under Web::Reactor:: (see Web::Reactor::Base::__set_reo).
##  LOG collects everything the object logs, HOOK lets a test run code at the
##  start of the dispatch, from render_page() or render_action(), after
##  process_request() has set up and saved the sessions.
##

our @LOG;

package Web::Reactor::TestReactor;
our @ISA = ( 'Web::Reactor' );

sub log
{
  my $self = shift;
  my $msg  = join '', @_;
  push @LOG, $msg;
  print STDERR "$msg\n" if $VERBOSE;
}

sub render_page
{
  my $self = shift;

  $self->{ 'HOOK' }->( $self ) if $self->{ 'HOOK' } and ! $self->{ 'HOOK_DONE' }++;

  return $self->SUPER::render_page( @_ );
}

sub render_action
{
  my $self = shift;

  $self->{ 'HOOK' }->( $self ) if $self->{ 'HOOK' } and ! $self->{ 'HOOK_DONE' }++;

  return $self->SUPER::render_action( @_ );
}

package main;

##############################################################################
##
##  section 1 -- loading all modules
##

my @MODULES = qw(
                Web::Reactor
                Web::Reactor::Base
                Web::Reactor::Utils
                Web::Reactor::Core
                Web::Reactor::Reflex
                Web::Reactor::Actions
                Web::Reactor::Actions::Files
                Web::Reactor::Actions::Packages
                Web::Reactor::Preprocessor
                Web::Reactor::Preprocessor::Tree
                Web::Reactor::Sessions
                Web::Reactor::Sessions::Filesystem
                Web::Reactor::HTML::Utils
                Web::Reactor::HTML::Layout
                Web::Reactor::HTML::Form
                Web::Reactor::HTML::Tab
                );

require_ok( $_ ) for @MODULES;

Web::Reactor::HTML::Utils->import();
Web::Reactor::HTML::Layout->import();

ok( $Web::Reactor::VERSION, "Web::Reactor::VERSION is set [$Web::Reactor::VERSION]" );

isa_ok( 'Web::Reactor',                       'Web::Reactor::Reflex',       'Web::Reactor'         );
isa_ok( 'Web::Reactor::Reflex',               'Web::Reactor::Core',         'Reflex'               );
isa_ok( 'Web::Reactor::Sessions::Filesystem', 'Web::Reactor::Sessions',     'Sessions::Filesystem' );
isa_ok( 'Web::Reactor::Sessions',             'Web::Reactor::Base',         'Sessions'             );
isa_ok( 'Web::Reactor::Actions::Files',       'Web::Reactor::Actions',      'Actions::Files'       );
isa_ok( 'Web::Reactor::Actions::Packages',    'Web::Reactor::Actions',      'Actions::Packages'    );
isa_ok( 'Web::Reactor::Preprocessor::Tree',   'Web::Reactor::Preprocessor', 'Preprocessor::Tree'   );
isa_ok( 'Web::Reactor::HTML::Form',           'Web::Reactor::Base',         'HTML::Form'           );

##############################################################################
##
##  section 2 -- throw-away application tree
##

my $APP_ROOT = tempdir( 'web-reactor-test-XXXXXX', TMPDIR => 1, CLEANUP => 1 );

sub put
{
  my ( $rel, $text ) = @_;
  my $fn = "$APP_ROOT/$rel";
  ( my $dir = $fn ) =~ s{/[^/]+$}{};
  make_path( $dir ) unless -d $dir;
  file_save( $fn, $text ) or die "cannot write [$fn]";
}

put( 'html/default/main/index.html',     'MAIN[<$greet>][<&hello>][<#part>]' );
put( 'html/default/other/index.html',    'OTHER' );
put( 'html/default/login/index.html',    'LOGIN' );
put( 'html/default/eexpired/index.html', 'EXPIRED' );
put( 'html/default/einvalid/index.html', 'INVALID' );
put( 'html/default/part.html',           'PART' );

put( 'actions/hello.pm', <<'ACT' );
package reactor::actions::hello;
use strict;

sub main
{
  my $reo  = shift;
  my %args = @_;

  my $ha = $args{ 'HTML_ARGS' } || {};

  return 'HELLO' . ( $ha->{ 'WHO' } ? ":$ha->{ 'WHO' }" : '' );
}

1;
ACT

make_path( "$APP_ROOT/var" );

##############################################################################
##
##  section 3 -- environment / config helpers
##

sub make_env
{
  my %over = @_;

  return {
         'REQUEST_SCHEME'   => 'https',
         'REQUEST_METHOD'   => 'GET',
         'REQUEST_URI'      => '/app/',
         'QUERY_STRING'     => '',
         'REMOTE_ADDR'      => '10.0.0.1',
         'REMOTE_PORT'      => 33333,
         'HTTP_USER_AGENT'  => 'Web-Reactor-Test/1.0',
         'SERVER_NAME'      => 'localhost',
         'SERVER_PORT'      => 443,
         'SERVER_PROTOCOL'  => 'HTTP/1.1',
         'SCRIPT_NAME'      => '',
         'PATH_INFO'        => '/',
         'psgi.version'     => [ 1, 1 ],
         'psgi.url_scheme'  => 'https',
         'psgi.errors'      => \*STDERR,
         'psgi.input'       => undef,
         %over,
         };
}

sub make_cfg
{
  my %over = @_;

  return {
         APP_NAME     => 'wrtest',
         APP_ROOT     => $APP_ROOT,
         SESS_VAR_DIR => "$APP_ROOT/var",
         DEBUG        => 0,
         %over,
         };
}

sub make_reo
{
  my $env = shift || make_env();
  my $cfg = shift || make_cfg();

  return Web::Reactor::TestReactor->new( $env, $cfg );
}

# runs a full request, returns ( reactor, response )
sub request
{
  my %opt = @_;

  my %env;
  $env{ 'HTTP_COOKIE'  } = "wrtest_cookie=$opt{ COOKIE }" if $opt{ 'COOKIE' };
  $env{ 'QUERY_STRING' } = $opt{ 'QS' } if defined $opt{ 'QS' };
  %env = ( %env, %{ $opt{ 'ENV' } } ) if $opt{ 'ENV' };

  my $r = make_reo( make_env( %env ), make_cfg( %{ $opt{ 'CFG' } || {} } ) );
  $r->{ 'HOOK' } = $opt{ 'HOOK' } if $opt{ 'HOOK' };
  my $res = $r->run();

  # the assertions of a hook are skipped silently if the request fails before
  # the dispatch, so a hook which did not run is a failure on its own
  fail( 'request hook did not run: ' . body( $res ) ) if $opt{ 'HOOK' } and ! $r->{ 'HOOK_DONE' };

  return ( $r, $res );
}

sub body { return join '', @{ $_[0]->[2] } }

# returns the value of the given cookie from the set-cookie headers or undef
sub cookie_of
{
  my $res  = shift;
  my $name = shift || 'wrtest_cookie';

  my @h = @{ $res->[1] };
  for( my $i = 0; $i < @h; $i += 2 )
    {
    next unless lc $h[ $i ] eq 'set-cookie';
    return $1 if $h[ $i + 1 ] =~ /^\Q$name\E=([^;]*)/;
    }

  return undef;
}

sub set_cookie_header
{
  my $res  = shift;
  my $name = shift || 'wrtest_cookie';

  my @h = @{ $res->[1] };
  for( my $i = 0; $i < @h; $i += 2 )
    {
    next unless lc $h[ $i ] eq 'set-cookie';
    return $h[ $i + 1 ] if $h[ $i + 1 ] =~ /^\Q$name\E=/;
    }

  return undef;
}

# returns 1 if any log message collected since the given mark matches
sub log_since
{
  my $mark = shift;
  my $re   = shift;

  return scalar grep { $_ =~ $re } @LOG[ $mark .. $#LOG ];
}

# session file name of the given key components
sub ses_file
{
  my $r = shift;
  return $r->__ses->_key_to_fn( { READONLY => 1 }, @{ $r->__ses->compose_key_from_sid( @_ ) } );
}

##############################################################################
##
##  section 4 -- construction and module attachment
##

my $reo = make_reo();

isa_ok( $reo, 'Web::Reactor', 'reactor object' );

isa_ok( $reo->__ses, 'Web::Reactor::Sessions::Filesystem', 'default session backend' );
isa_ok( $reo->pre,   'Web::Reactor::Preprocessor::Tree',   'default pre() backend'   );
isa_ok( $reo->act,   'Web::Reactor::Actions::Files',       'default act() backend'   );
is( $reo->__ses, $reo->__ses, 'session backend is attached once' );

# http scheme must be rejected unless cookies security is explicitly disabled
{
  eval { make_reo( make_env( 'REQUEST_SCHEME' => 'http', 'psgi.url_scheme' => 'http' ) ) };
  ok( $@, 'plain http request refused while secure cookies are required' );

  my $ok = eval { make_reo( make_env( 'REQUEST_SCHEME' => 'http', 'psgi.url_scheme' => 'http' ),
                            make_cfg( DISABLE_SECURE_COOKIES => 1 ) ) };
  isa_ok( $ok, 'Web::Reactor', 'plain http accepted with DISABLE_SECURE_COOKIES' );
}

# rsa() needs RSA_PUB
{
  eval { $reo->rsa() };
  like( $@, qr/RSA_PUB/, 'rsa() booms without RSA_PUB' );
}

##############################################################################
##
##  section 5 -- session storage api (Filesystem backend)
##

my $ses = $reo->__ses;

{
  my $id1 = $ses->create_id( 16 );
  my $id2 = $ses->create_id( 16 );

  is( length( $id1 ), 16, 'create_id() honours requested length' );
  isnt( $id1, $id2, 'create_id() returns different ids' );
  like( $id1, qr/^[A-Za-z0-9]+$/, 'create_id() is alphanumeric' );
  is( length( $ses->create_id() ), 73, 'create_id() default length is 73' );
}

{
  is_deeply( $ses->compose_key_from_sid( 'USER', 'abcdefgh' ), [ 'USER', 'abcdefgh' ], 'compose_key_from_sid() USER has no parent' );
  is_deeply( $ses->compose_key_from_sid( 'COOK', 'abcdefgh' ), [ 'COOK', 'abcdefgh' ], 'compose_key_from_sid() COOK has no parent' );
  is_deeply( $ses->compose_key_from_sid( 'HOLD', 'abcdefgh' ), [ 'HOLD', 'abcdefgh' ], 'compose_key_from_sid() HOLD has no parent' );
  is_deeply( $ses->compose_key_from_sid( 'PAGE', 'abcdefgh', 'useruser' ), [ 'PAGE', 'useruser', 'abcdefgh' ], 'compose_key_from_sid() PAGE goes under USER' );
  is_deeply( $ses->compose_key_from_sid( 'LINK', 'abcdefgh', 'cookcook' ), [ 'LINK', 'cookcook', 'abcdefgh' ], 'compose_key_from_sid() LINK goes under COOK' );

  eval { $ses->compose_key_from_sid( 'NOSUCH', 'abcdefgh' ) };
  ok( $@, 'compose_key_from_sid() booms on an unknown type' );
  eval { $ses->compose_key_from_sid( 'PAGE', 'abcdefgh' ) };
  ok( $@, 'compose_key_from_sid() booms for PAGE without a parent sid' );
  eval { $ses->compose_key_from_sid( 'USER', 'abcdefgh', 'useruser' ) };
  ok( $@, 'compose_key_from_sid() booms for USER with a parent sid' );
  eval { $ses->compose_key_from_sid( 'USER', 'bad/id' ) };
  ok( $@, 'compose_key_from_sid() booms on a malformed sid' );
}

is( $ses->_split_dir_components( '1234567890', 3, 3 ), '123/456/789/1234567890', '_split_dir_components()' );
eval { $ses->_split_dir_components( '123', 3, 3 ) };
ok( $@, '_split_dir_components() booms on a too short id' );

like( $ses->_key_to_fn( { READONLY => 1 }, 'USER', '1234567890' ),
      qr{^\Q$APP_ROOT\E/var/USER/12/34/1234567890\.wrs2$},
      '_key_to_fn() builds the split path' );

eval { $ses->_key_to_fn( {}, 'lower', 'abcdefgh' ) };
ok( $@, '_key_to_fn() booms on invalid type component' );
eval { $ses->_key_to_fn( {}, 'USER', 'bad/id' ) };
ok( $@, '_key_to_fn() booms on invalid id component' );

{
  my $shr = $ses->create( 'USER', undef, 24 );

  is( ref( $shr ), 'HASH', 'create() returns a session hash' );
  is( $shr->{ ':TYPE' }, 'USER', 'create() stamps :TYPE' );
  is( length( $shr->{ ':SID' } ), 24, 'create() honours the length' );
  is( $shr->{ ':PSID' }, undef, 'create() :PSID is undef for USER' );
  ok( $ses->exists( $shr ), 'exists() true after create()' );
  ok( -s ses_file( $reo, 'USER', $shr->{ ':SID' } ), 'create() writes the initial data, not an empty file' );
  is( ( stat ses_file( $reo, 'USER', $shr->{ ':SID' } ) )[ 2 ] & 0777, 0600, 'session file mode is 0600' );

  is_deeply( $ses->load( 'USER', $shr->{ ':SID' } ), $shr, 'load() of a just created session returns its stamp' );

  $shr->{ 'A' } = 1;
  $shr->{ 'B' } = [ 2, 3 ];
  ok( $ses->save( $shr ), 'save()' );
  is_deeply( $ses->load( 'USER', $shr->{ ':SID' } ), $shr, 'load() returns the saved structure' );
  is( ( stat ses_file( $reo, 'USER', $shr->{ ':SID' } ) )[ 2 ] & 0777, 0600, 'saved session file mode is 0600' );

  is( $ses->load( 'USER', 'NoSuchSessionIdAtAll' ), undef, 'load() of an unknown id returns undef' );
  ok( ! $ses->exists( { ':TYPE' => 'USER', ':SID' => 'NoSuchSessionIdAtAll' } ), 'exists() false for an unknown id' );

  ok( $ses->delete( $shr ), 'delete()' );
  ok( ! $ses->exists( $shr ), 'delete() removes the session' );
  ok( $ses->delete( $shr ), 'delete() of a missing session is fine' );

  my $page = $ses->create( 'PAGE', 'useruseruser', 8 );
  is( $page->{ ':PSID' }, 'useruseruser', 'create() stamps :PSID for PAGE' );
  ok( -e ses_file( $reo, 'PAGE', $page->{ ':SID' }, 'useruseruser' ), 'PAGE session stored under its parent' );

  eval { $ses->create( 'bad type' ) };
  like( $@, qr/invalid session type \[BAD TYPE\], expected one of COOK HOLD LINK PAGE USER/, 'create() booms on an invalid type and names the valid ones' );
  eval { $ses->create( 'XYZ' ) };
  like( $@, qr/invalid session type \[XYZ\]/, 'create() booms on an unknown upper case type' );
  eval { $ses->create( 'USER', undef, 3 ) };
  ok( $@, 'create() booms on a too short length' );
  eval { $ses->create( 'PAGE' ) };
  ok( $@, 'create() booms for PAGE without a parent sid' );
}

# a failed save leaves no temp file behind
{
  my $ses = $reo->__ses;
  my $shr = $ses->create( 'USER', undef, 24 );
  my $key = $ses->compose_key_from_sid( 'USER', $shr->{ ':SID' } );
  my $fn  = $ses->_key_to_fn( {}, @$key );
  ( my $dir = $fn ) =~ s{/[^/]+$}{};
  unlink( $fn );
  mkdir( $fn ) or die "cannot mkdir [$fn]: $!"; # rename() onto a non-empty directory fails
  file_save( "$fn/x", 'x' );
  ok( ! $ses->_storage_save( $key, $shr ), 'a save which cannot rename its temp file fails' );
  is_deeply( [ glob( "$dir/*.part" ) ], [], 'a failed save leaves no temp file behind' );
  unlink( "$fn/x" );
  rmdir( $fn );
}

# the cookie name from the config is used lowercased
{
  my ( undef, $res ) = request( CFG => { COOKIE_NAME => 'MyApp' } );
  ok(   defined cookie_of( $res, 'myapp' ), 'COOKIE_NAME is used lowercased' );
  ok( ! defined cookie_of( $res, 'MyApp' ), 'COOKIE_NAME is not used as given' );
}

# abstract base classes (Sessions, Preprocessor, Actions) must refuse to work
# on their own
{
  for my $m ( qw( _storage_create _storage_load _storage_save _storage_exists _storage_delete _storage_debug_info ) )
    {
    my $sub = \&{ "Web::Reactor::Sessions::$m" };
    eval { $sub->() };
    like( $@, qr/is not implemented/, "Sessions::$m() is an abstract stub" );
    }
  for my $m ( qw( load_page process check_page_name ) )
    {
    my $sub = \&{ "Web::Reactor::Preprocessor::$m" };
    eval { $sub->() };
    like( $@, qr/Preprocessor::\*::$m\(\) is not implemented/, "Preprocessor::$m() is an abstract stub" );
    }
  eval { Web::Reactor::Actions::__find_code_by_name() };
  like( $@, qr/Actions::\*::__find_code_by_name\(\) is not implemented/, 'Actions::__find_code_by_name() is an abstract stub' );
}

like( $ses->_storage_debug_info(), qr/\Q$APP_ROOT\E/, '_storage_debug_info() mentions the session directory' );
{
  my $dr = make_reo( make_env(), make_cfg( SESS_VAR_DIR => undef ) );
  like( $dr->__ses->_storage_debug_info(), qr{\[\Q$APP_ROOT\E/var\]}, '_storage_debug_info() shows the default APP_ROOT/var directory' );
}

##############################################################################
##
##  section 6 -- a complete request cycle through run()
##

my ( $COOKIE, $USID, $PSID );

{
  my ( $r, $res ) = request();

  is( ref( $res ), 'ARRAY', 'run() returns a PSGI triplet' );
  is( $res->[0], 200, 'run() status is 200' );
  is( body( $res ), 'MAIN[][HELLO][PART]', 'main page rendered: hold var, action tag and include' );

  my $sc = set_cookie_header( $res );
  ok( $sc, 'a session cookie is issued' );
  like( $sc, qr/HttpOnly/i,    'cookie is HttpOnly' );
  like( $sc, qr/secure/i,      'cookie is secure' );
  like( $sc, qr/SameSite=Lax/i, 'cookie is SameSite=Lax' );
  like( $sc, qr{path=/app/}i,  'cookie path is the request directory' );

  $COOKIE = cookie_of( $res );
  $USID   = $r->get_user_session_id();
  $PSID   = $r->get_page_session_id();

  ok( $COOKIE, "cookie value [$COOKIE]" );
  is( length( $COOKIE ), 73, 'cookie value is a 73 chars cookie session id' );
  isnt( $COOKIE, $USID, 'the cookie does not carry the user session id' );
  is( $r->get_cookie_session()->{ ':SID' }, $COOKIE, 'cookie value is the cookie session id' );
  is( $r->get_cookie_session()->{ ':USER_SID' }, $USID, 'cookie session points to the user session' );
  is( $r->get_user_session()->{ ':COOKIE_SID' }, $COOKIE, 'user session points back to the cookie session' );
  is( length( $USID ), 73, 'user session id has the default length' );
  is( length( $PSID ),  8, 'page session id is 8 chars' );

  ok( -s ses_file( $r, 'COOK', $COOKIE ), 'cookie session persisted' );
  ok( -s ses_file( $r, 'USER', $USID ),   'user session persisted' );
  ok( -s ses_file( $r, 'PAGE', $PSID, $USID ), 'page session persisted under the user session' );

  my $cook = $r->__ses->load( 'COOK', $COOKIE );
  is( $cook->{ ':USER_SID' }, $USID, 'stored cookie session points to the user session' );

  my $user = $r->__ses->load( 'USER', $USID );
  is( $user->{ ':COOKIE_SID' }, $COOKIE, 'stored user session points to the cookie session' );
  is( scalar @{ $user->{ ':COOKIE_SID_HISTORY' } }, 1, 'cookie history has one entry' );
  is( $user->{ ':COOKIE_SID_HISTORY' }[ 0 ]{ 'SID' }, $COOKIE, 'cookie history records the cookie session' );
  is( $user->{ ':COOKIE_SID_HISTORY' }[ 0 ]{ 'REASON' }, 'new', 'cookie history reason is "new"' );
  is( $user->{ ':HTTP_CHECK_HR' }{ 'HTTP_USER_AGENT' }, 'Web-Reactor-Test/1.0', 'user session keeps the checked http vars' );
}

# second request: the cookie brings back the same user session
{
  my ( $r, $res ) = request( COOKIE => $COOKIE );

  is( $r->get_user_session_id(), $USID, 'user session restored from the cookie' );
  is( cookie_of( $res ), undef, 'no new cookie for a valid cookie session' );
  isnt( $r->get_page_session_id(), $PSID, 'a request without _P gets a new page session' );
}

# links carry safe input through the link session
{
  my $link;
  my ( $r1 ) = request( COOKIE => $COOKIE, HOOK => sub { $link = $_[0]->args_here( COLOUR => 'red', _PN => 'other' ) } );
  my $pid1 = $r1->get_page_session_id();
  my $lsid = $r1->get_link_session()->{ ':SID' };

  like( $link, qr/^[A-Za-z0-9]+\.[A-Za-z0-9]+$/, 'args() returns "link-sid.link-key"' );
  ok( -s ses_file( $r1, 'LINK', $lsid, $COOKIE ), 'link session persisted under the cookie session' );

  my ( $r2, $res ) = request( COOKIE => $COOKIE, QS => "_=$link" );

  is( $r2->get_page_session_id(), $pid1, 'page session restored from the link (_P)' );
  is( $r2->get_safe_input()->{ 'COLOUR' }, 'red', 'safe input arrives through the link session' );
  is( body( $res ), 'OTHER', 'requested page rendered' );

  # the same link without the cookie does not resolve
  my ( $r3, $res3 ) = request( QS => "_=$link" );
  is_deeply( $r3->get_safe_input(), {}, 'a link does not resolve under another cookie session' );
  like( body( $res3 ), qr/^MAIN/, 'unresolved link falls back to the main page' );

  # an unknown link key is ignored
  my ( $r4 ) = request( COOKIE => $COOKIE, QS => "_=$lsid.NoSuchKey" );
  is_deeply( $r4->get_safe_input(), {}, 'unknown link key yields empty safe input' );

  # a malformed token is ignored and logged
  my $mark = scalar @LOG;
  my ( $r5 ) = request( COOKIE => $COOKIE, QS => '_=not-a-link' );
  is_deeply( $r5->get_safe_input(), {}, 'malformed token yields empty safe input' );
  ok( log_since( $mark, qr/invalid safe \[_\] input/ ), 'malformed token is logged' );
}

# an unknown cookie starts a fresh session
{
  my $mark = scalar @LOG;
  my ( $r, $res ) = request( COOKIE => 'NoSuchCookieSessionIdAtAll' );

  isnt( cookie_of( $res ), undef, 'unknown cookie gets a new cookie' );
  isnt( cookie_of( $res ), 'NoSuchCookieSessionIdAtAll', 'the new cookie is a different one' );
  ok( log_since( $mark, qr/invalid cookie session/ ), 'unknown cookie session is logged' );
}

# a user session id used as a cookie does not work
{
  my ( $r, $res ) = request( COOKIE => $USID );
  isnt( $r->get_user_session_id(), $USID, 'a user session id is not accepted as a cookie' );
}

# a cookie session whose user session moved on to another cookie is stale
{
  my ( $r1, $res1 ) = request();
  my $c1 = cookie_of( $res1 );
  my $u1 = $r1->get_user_session_id();

  my $user = $r1->__ses->load( 'USER', $u1 );
  $user->{ ':COOKIE_SID' } = 'SomeOtherCookieSession';
  $r1->__ses->save( $user );

  my $mark = scalar @LOG;
  my ( $r2, $res2 ) = request( COOKIE => $c1 );

  isnt( $r2->get_user_session_id(), $u1, 'stale cookie session gets a new user session' );
  ok( log_since( $mark, qr/discarding stale or orphan cookie session/ ), 'stale cookie session is logged' );
  ok( ! -e ses_file( $r2, 'COOK', $c1 ), 'stale cookie session is deleted' );
  is( $r2->__ses->load( 'USER', $u1 )->{ ':COOKIE_SID' }, 'SomeOtherCookieSession', 'the user session of a stale cookie is left untouched' );
}

# user agent change closes the session
{
  my ( $r1, $res1 ) = request();
  my $c1 = cookie_of( $res1 );
  my $u1 = $r1->get_user_session_id();

  my $mark = scalar @LOG;
  my ( $r2, $res2 ) = request( COOKIE => $c1, ENV => { 'HTTP_USER_AGENT' => 'Somebody-Else/9' } );

  ok( log_since( $mark, qr/session parameter \[HTTP_USER_AGENT\] check failed/ ), 'session hijack check logged' );
  is( body( $res2 ), 'INVALID', 'einvalid page rendered' );
  is( $r2->__ses->load( 'USER', $u1 )->{ ':CLOSED' }, 1, 'changed user agent closes the old user session' );
  ok( ! -e ses_file( $r2, 'COOK', $c1 ), 'the old cookie session is deleted' );
  isnt( cookie_of( $res2 ), undef, 'a new cookie is issued' );
  isnt( $r2->get_user_session_id(), $u1, 'a new user session is active' );

  my ( $r3 ) = request( COOKIE => $c1 );
  isnt( $r3->get_user_session_id(), $u1, 'the old cookie cannot reach the closed session' );
}

# expired logged-in session
{
  my ( $r1, $res1 ) = request( HOOK => sub { $_[0]->login( 'ann' ) } );
  my $c1 = cookie_of( $res1 );
  my $u1 = $r1->get_user_session_id();

  my $user = $r1->__ses->load( 'USER', $u1 );
  $user->{ ':XTIME' } = time() - 10;
  $r1->__ses->save( $user );

  my $mark = scalar @LOG;
  my ( $r2, $res2 ) = request( COOKIE => $c1 );

  ok( log_since( $mark, qr/user session expired or closed/ ), 'session expiry logged' );
  is( body( $res2 ), 'EXPIRED', 'eexpired page rendered' );
  is( $r2->__ses->load( 'USER', $u1 )->{ ':CLOSED' }, 1, 'expired session is closed in storage' );
  is( $r2->is_logged_in(), 0, 'the new session is not logged in' );
  isnt( cookie_of( $res2 ), undef, 'an expired session gets a new cookie' );
}

# anonymous sessions do not expire
{
  my ( $r1, $res1 ) = request();
  my $c1 = cookie_of( $res1 );
  my $u1 = $r1->get_user_session_id();

  my $user = $r1->__ses->load( 'USER', $u1 );
  $user->{ ':XTIME' } = time() - 10;
  $r1->__ses->save( $user );

  my ( $r2, $res2 ) = request( COOKIE => $c1 );
  is( $r2->get_user_session_id(), $u1, 'an anonymous session survives its expire time' );
}

##############################################################################
##
##  section 7 -- login, logout, user hold
##

{
  my ( $before_c, $before_u, $page_before, $hold_ident );

  my ( $r1, $res1 ) = request();
  $before_c = cookie_of( $res1 );
  $before_u = $r1->get_user_session_id();

  my $mark = scalar @LOG;
  my ( $r, $res ) = request( COOKIE => $before_c, HOOK => sub
    {
    my $reo = shift;
    $page_before = $reo->get_page_session_id();
    is( $reo->is_logged_in(), 0, 'is_logged_in() false before login' );
    $reo->login( 'joe@example.com' );
    } );

  is( $r->is_logged_in(), 1, 'is_logged_in() true after login' );
  is( $r->get_user_session_id(), $before_u, 'login() keeps the user session id' );
  is( $r->get_page_session_id(), $page_before, 'login() keeps the page session' );

  my $after_c = cookie_of( $res );
  ok( $after_c, 'login() issues a new cookie' );
  isnt( $after_c, $before_c, 'login() rotates the cookie session id' );
  ok( log_since( $mark, qr/rotated cookie session id on login/ ), 'rotation logged' );
  ok( ! -e ses_file( $r, 'COOK', $before_c ), 'login() deletes the old cookie session' );

  my $user = $r->get_user_session();
  is( $user->{ ':COOKIE_SID' }, $after_c, 'user session points to the new cookie session' );
  is( $user->{ ':USER_IDENT_S' }, 'joe_example_com', 'login() stores a readable user ident' );
  like( $user->{ ':USER_IDENT' }, qr/^[0-9a-f]+$/i, 'login() stores a hex encoded user ident' );
  ok( $user->{ ':LITIME' } > 0, 'login() stores a login time' );
  is( scalar @{ $user->{ ':COOKIE_SID_HISTORY' } }, 2, 'cookie history has two entries after login' );
  is( $user->{ ':COOKIE_SID_HISTORY' }[ 1 ]{ 'SID' },    $after_c, 'cookie history records the new cookie session' );
  is( $user->{ ':COOKIE_SID_HISTORY' }[ 1 ]{ 'REASON' }, 'login',  'cookie history reason is "login"' );

  # a login without an ident has no user hold, so ident-less logins share nothing
  for my $ident ( '', undef )
    {
    my ( $ri ) = request( HOOK => sub
      {
      my $reo = shift;
      $reo->login( $ident );
      is( $reo->is_logged_in(), 1, 'login() without an ident logs in' );
      is( $reo->get_user_session()->{ ':USER_IDENT' }, '', 'login() without an ident stores an empty ident' );
      is( $reo->get_user_hold(), undef, 'login() without an ident gives no user hold' );
      } );
    ok( ! -e ses_file( $ri, 'HOLD', '_' x 8 ), 'login() without an ident creates no padded hold' );
    }

  # passwords stay out of the debug log
  {
    my $mark = scalar @LOG;
    request( COOKIE => $COOKIE, QS => 'password=secret-pw&new_password=secret-new&user=u', CFG => { DEBUG => 2, DISABLE_PASSWORD_ENCRYPT => 1 } );
    ok( ! log_since( $mark, qr/secret-pw/ ), 'the debug dump does not log a password value' );
    ok( ! log_since( $mark, qr/secret-new/ ), 'the debug dump does not log a value of a name containing PASSWORD' );
    ok(   log_since( $mark, qr/PASSWORD.*\*\*\*/s ), 'the debug dump masks the password' );
  }

  my ( $r2 ) = request( COOKIE => $after_c );
  is( $r2->get_user_session_id(), $before_u, 'the new cookie reaches the logged-in user session' );
  is( $r2->is_logged_in(), 1, 'the new cookie is logged in' );

  my ( $r3 ) = request( COOKIE => $before_c );
  isnt( $r3->get_user_session_id(), $before_u, 'the pre-login cookie does not reach the logged-in session' );
  is( $r3->is_logged_in(), 0, 'the pre-login cookie is not logged in' );

  # user hold
  request( COOKIE => $after_c, HOOK => sub
    {
    my $reo = shift;
    my $h1  = $reo->get_user_hold();
    isa_ok( $h1, 'HASH', 'get_user_hold()' );
    is( $h1->{ ':TYPE' }, 'HOLD', 'user hold is a HOLD session' );
    is( $reo->get_user_hold(), $h1, 'get_user_hold() returns the same hash within a request' );
    $h1->{ 'PREF' } = 'dark';
    $hold_ident = $h1->{ ':SID' };
    } );

  my ( $r5 ) = request( COOKIE => $after_c, HOOK => sub { is( $_[0]->get_user_hold()->{ 'PREF' }, 'dark', 'user hold data survives the request' ) } );
  ok( -s ses_file( $r5, 'HOLD', $hold_ident ), 'user hold persisted' );

  # a second login of the same ident gets the same hold
  request( HOOK => sub { $_[0]->login( 'joe@example.com' ); is( $_[0]->get_user_hold()->{ 'PREF' }, 'dark', 'user hold is shared between logins of the same ident' ) } );

  # an anonymous session has no hold
  request( HOOK => sub { is( $_[0]->get_user_hold(), undef, 'get_user_hold() is undef when not logged in' ) } );

  # logout
  my $logout_page;
  my ( $r8, $res8 ) = request( COOKIE => $after_c, HOOK => sub
    {
    my $reo = shift;
    $logout_page = $reo->get_page_session_id();
    $reo->logout();
    } );

  is( $r8->is_logged_in(), 0, 'is_logged_in() false after logout' );
  isnt( $r8->get_user_session_id(), $before_u, 'logout() starts a new user session' );
  isnt( $r8->get_page_session_id(), $logout_page, 'logout() starts a new page session' );
  my $logout_c = cookie_of( $res8 );
  ok( $logout_c, 'logout() issues a new cookie' );
  isnt( $logout_c, $after_c, 'the logout cookie is a new one' );
  ok( ! -e ses_file( $r8, 'COOK', $after_c ), 'logout() deletes the logged-in cookie session' );

  my $closed = $r8->__ses->load( 'USER', $before_u );
  is( $closed->{ ':CLOSED' },    1, 'logout() closes the logged-in user session' );
  is( $closed->{ ':LOGGED_IN' }, 0, 'logout() clears :LOGGED_IN' );
  ok( $closed->{ ':LOTIME' } > 0, 'logout() stores a logout time' );

  my ( $r9 ) = request( COOKIE => $after_c );
  isnt( $r9->get_user_session_id(), $before_u, 'the logged-in cookie is dead after logout' );
  is( $r9->is_logged_in(), 0, 'the logged-in cookie is not logged in after logout' );

  # expire time api
  request( HOOK => sub
    {
    my $reo = shift;
    ok( $reo->get_user_session_expire_time() > time(), 'get_user_session_expire_time()' );
    $reo->set_user_session_expire_time_in( 1234 );
    my $in = $reo->get_user_session_expire_time_in();
    ok( $in > 1200 && $in <= 1234, "get_user_session_expire_time_in() [$in]" );
    $reo->set_user_session_expire_time( time() - 1 );
    is( $reo->get_user_session_expire_time_in(), undef, 'expired session reports undef time-left' );
    is( $reo->get_user_session_agent(), 'Web-Reactor-Test/1.0', 'get_user_session_agent()' );
    } );
}

##############################################################################
##
##  section 8 -- page / link sessions and args
##

{
  request( COOKIE => $COOKIE, HOOK => sub
    {
    my $app = shift;

    isa_ok( $app->get_page_session(), 'HASH', 'get_page_session()' );
    is( $app->get_page_session()->{ ':SID' }, $app->get_page_session_id(), 'page session carries its own :SID' );
    is( $app->get_page_session()->{ ':PAGE_NAME' }, 'main', 'page session remembers the page name' );
    is( $app->get_page_session( 5 ), undef, 'get_page_session() beyond the stack returns undef' );
    is( $app->get_ref_page_session_id(), undef, 'no referring page session on a first request' );

    my ( $usid, $ushr ) = $app->get_user_session();
    is( $usid, $app->get_user_session_id(), 'get_user_session() in list context returns the sid first' );
    is( $ushr, scalar $app->get_user_session(), 'get_user_session() in list context returns the hash second' );

    my ( $lsid, $lshr ) = $app->get_link_session();
    isa_ok( $lshr, 'HASH', 'get_link_session() hash' );
    is( $lshr->{ ':SID' }, $lsid, 'link session carries its own :SID' );
    is( $lshr->{ ':PSID' }, $app->get_cookie_session()->{ ':SID' }, 'link session is under the cookie session' );
    is( length( $lsid ), 8, 'link session id is 8 chars' );
    is( scalar $app->get_link_session(), $lshr, 'get_link_session() in scalar context returns the hash' );

    my ( $lsid2 ) = $app->get_link_session();
    is( $lsid2, $lsid, 'get_link_session() is stable within a request' );

    my $k1 = $app->new_link_session_key();
    my $k2 = $app->new_link_session_key();
    isnt( $k1, $k2, 'new_link_session_key() returns fresh keys' );
    is( length( $k1 ), 8, 'link session key default length is 8' );
    is( length( $app->new_link_session_key( 16 ) ), 16, 'new_link_session_key() honours length' );

    # args() stores the arguments upper-cased into the link session
    my $a = $app->args( colour => 'red', SIZE => 3 );
    my ( $sid, $key ) = split /\./, $a;
    is( $sid, $lsid, 'args() uses the current link session' );
    is_deeply( $lshr->{ 'ARGS' }{ $key }, { COLOUR => 'red', SIZE => 3 }, 'args() upper-cases argument names' );

    my %typed = (
                'args_here'     => '_P',
                'args_new'      => '_R',
                'args_back'     => '_P',
                'args_new_fr'   => '_T',
                );

    for my $m ( sort keys %typed )
      {
      my ( undef, $kk ) = split /\./, $app->$m( X => 1 );
      ok( exists $lshr->{ 'ARGS' }{ $kk }{ $typed{ $m } }, "$m() sets $typed{ $m }" );
      }

    my ( undef, $hk ) = split /\./, $app->args_here();
    is( $lshr->{ 'ARGS' }{ $hk }{ '_P' }, $app->get_page_session_id(), 'args_here() points at the current page session' );

    my ( undef, $nk ) = split /\./, $app->args_new();
    is( $lshr->{ 'ARGS' }{ $nk }{ '_R' }, $app->get_page_session_id(), 'args_new() refers back to the current page' );
    is( $lshr->{ 'ARGS' }{ $nk }{ '_PN' }, 'main', 'args_new() carries the current page name' );

    my ( undef, $ak ) = split /\./, $app->args_new( _AN => 'hello' );
    ok( ! exists $lshr->{ 'ARGS' }{ $ak }{ '_PN' }, 'args_new() with _AN does not add _PN' );

    for my $t ( qw( new new_fr here back none ) )
      {
      like( $app->args_type( $t, X => 1 ), qr/^[A-Za-z0-9]+\.[A-Za-z0-9]+$/, "args_type( '$t' )" );
      }
    eval { $app->args_type( 'nonesuch' ) };
    ok( $@, 'args_type() booms on an unknown type' );

    my $u = $app->create_uniq_id();
    like( $u, qr/^\Q@{[ $app->get_page_session_id() ]}\E\.\d+$/, 'create_uniq_id() is page sid and a number' );
    isnt( $app->create_uniq_id(), $u, 'create_uniq_id() is unique' );
    is( $app->get_uniq_id_scope(), $app->get_page_session_id(), 'get_uniq_id_scope() is the page session id' );
    ok( $app->start_time() > 0, 'start_time()' );
    } );
}

# later requests of the same page continue the html id numbers
{
  my ( $here, $u1, $u2 );
  request( COOKIE => $COOKIE, HOOK => sub { $u1 = $_[0]->create_uniq_id(); $here = $_[0]->args_here() } );
  request( COOKIE => $COOKIE, QS => "_=$here", HOOK => sub { $u2 = $_[0]->create_uniq_id() } );
  my ( $s1, $n1 ) = split /\./, $u1;
  my ( $s2, $n2 ) = split /\./, $u2;
  is( $s2, $s1, 'two requests of the same page share the id scope' );
  ok( $n2 > $n1, "the second request continues the id numbers [$n1] -> [$n2]" );
}

# referrer chain: a new page knows its caller, back links return to it
{
  my ( $new_link, $back_link, $caller, $callee );

  request( COOKIE => $COOKIE, HOOK => sub { $caller = $_[0]->get_page_session_id(); $new_link = $_[0]->args_new( _PN => 'other' ) } );
  request( COOKIE => $COOKIE, QS => "_=$new_link", HOOK => sub
    {
    my $reo = shift;
    $callee = $reo->get_page_session_id();
    is( $reo->get_ref_page_session_id(), $caller, 'args_new() target knows its caller' );
    is( $reo->get_page_session_id( 1 ), $caller, 'get_page_session_id( 1 ) is the caller' );
    is( $reo->get_page_session( 1 )->{ ':PAGE_NAME' }, 'main', 'get_page_session( 1 ) loads the caller page session' );
    $back_link = $reo->args_back();
    } );

  isnt( $callee, $caller, 'args_new() opens a new page session' );

  # two levels back: a page opened from the callee returns to the caller with args_back_back()
  my ( $new_link2, $bb_link );
  request( COOKIE => $COOKIE, QS => "_=$new_link", HOOK => sub { $new_link2 = $_[0]->args_new( _PN => 'other' ) } );
  request( COOKIE => $COOKIE, QS => "_=$new_link2", HOOK => sub { $bb_link = $_[0]->args_back_back() } );
  my ( $rbb ) = request( COOKIE => $COOKIE, QS => "_=$bb_link" );
  is( $rbb->get_page_session_id(), $caller, 'args_back_back() returns to the caller of the caller' );
  my ( undef, $fbb ) = request( COOKIE => $COOKIE, QS => "_=$new_link2", HOOK => sub { $_[0]->forward_back_back() } );
  is( $fbb->[0], 302, 'forward_back_back() sets a 302 status' );
  my %fbh = @{ $fbb->[1] };
  my ( $fbb_link ) = $fbh{ 'location' } =~ /^\?_=(.+)$/;
  my ( $rfbb ) = request( COOKIE => $COOKIE, QS => "_=$fbb_link" );
  is( $rfbb->get_page_session_id(), $caller, 'forward_back_back() goes to the caller of the caller' );

  # args_new_fr() marks the caller as the top page of the new one
  my ( $fr_link, $fr_caller );
  request( COOKIE => $COOKIE, HOOK => sub { $fr_caller = $_[0]->get_page_session_id(); $fr_link = $_[0]->args_new_fr( _PN => 'other' ) } );
  request( COOKIE => $COOKIE, QS => "_=$fr_link", HOOK => sub
    {
    is( $_[0]->get_top_page_session_id(), $fr_caller, 'args_new_fr() target records the caller as its top page' );
    isnt( $_[0]->get_page_session_id(), $fr_caller, 'args_new_fr() opens a new page session' );
    } );

  my ( $r3 ) = request( COOKIE => $COOKIE, QS => "_=$back_link" );
  is( $r3->get_page_session_id(), $caller, 'args_back() returns to the caller page session' );

  # a referrer which cannot be loaded is cut from the chain
  request( COOKIE => $COOKIE, QS => "_=$new_link", HOOK => sub
    {
    my $reo = shift;
    $reo->get_page_session()->{ ':REF_PAGE_SID' } = 'NoSuchPageSession';
    is( $reo->get_page_session( 1 ), undef, 'unloadable referrer returns undef' );
    ok( ! exists $reo->get_page_session()->{ ':REF_PAGE_SID' }, 'unloadable referrer is cut from the page session' );
    } );
}

##############################################################################
##
##  section 9 -- input parameters
##

{
  request( COOKIE => $COOKIE, QS => 'AA=1&BB=2&BB=3', HOOK => sub
    {
    my $reo = shift;
    my $ui  = $reo->get_user_input();
    is( $ui->{ 'AA' }, '1', 'single value parameter, name upper-cased' );

    # param accessors
    %{ $reo->get_user_input() } = ( FOO => 'user-foo', BAR => 'user-bar' );
    %{ $reo->get_safe_input() } = ( FOO => 'safe-foo' );

    is( $reo->param( 'FOO' ),             'safe-foo', 'param() reads safe input'          );
    is( $reo->param_safe( 'FOO' ),        'safe-foo', 'param_safe() is an alias of param' );
    is( $reo->param_unsafe( 'BAR' ),      'user-bar', 'param_unsafe() reads user input'   );
    is( $reo->param_peek( 'FOO' ),        'safe-foo', 'param_peek() reads safe input'     );
    is( $reo->param_peek_safe( 'FOO' ),   'safe-foo', 'param_peek_safe()'                 );
    is( $reo->param_peek_unsafe( 'BAR' ), 'user-bar', 'param_peek_unsafe()'               );
    is( $reo->param( 'foo' ),             'safe-foo', 'param() upper-cases the name'      );

    is_deeply( [ $reo->param( 'FOO', 'NOPE' ) ], [ 'safe-foo', undef ], 'param() in list context' );

    my $ps = $reo->get_page_session();
    is( $ps->{ 'SAVE_SAFE_INPUT' }{ 'FOO' }, 'safe-foo', 'param() caches into the page session' );
    ok( ! exists $ps->{ 'FOO' }, 'param() does not promote to the page session itself' );

    delete $reo->get_safe_input()->{ 'FOO' };
    is( $reo->param( 'FOO' ), 'safe-foo', 'param() returns the cached value when input is gone' );
    is( $reo->param_peek( 'FOO' ), undef, 'param_peek() does not use the cache' );

    $reo->get_safe_input()->{ 'FOO' } = 'safe-foo';
    $reo->param_save( 'FOO' );
    is( $ps->{ 'FOO' }, 'safe-foo', 'param_save() promotes into the page session' );

    $reo->param_clear_cache( 'FOO' );
    ok( ! exists $ps->{ 'SAVE_SAFE_INPUT' }{ 'FOO' }, 'param_clear_cache() drops the safe cache' );
    ok( ! exists $ps->{ 'SAVE_USER_INPUT' }{ 'FOO' }, 'param_clear_cache() drops the user cache' );

    is( $reo->get_input_form_name(), undef, 'get_input_form_name() undef without a form' );
    } );

  # the page session cache survives into the next request of the same page
  my $here;
  request( COOKIE => $COOKIE, QS => 'KEEP=me', HOOK => sub { $_[0]->param_unsafe( 'KEEP' ); $here = $_[0]->args_here() } );
  request( COOKIE => $COOKIE, QS => "_=$here", HOOK => sub { is( $_[0]->param_unsafe( 'KEEP' ), 'me', 'param cache survives into the next request of the page' ) } );
}

# buttons
{
  request( COOKIE => $COOKIE, QS => 'BUTTON%3ASAVE=x', HOOK => sub
    {
    my $reo = shift;
    is( scalar $reo->get_user_input_button(), 'SAVE', 'get_user_input_button() from BUTTON:NAME' );
    is( $reo->get_input_button(), 'SAVE', 'get_input_button() from BUTTON:NAME' );
    is( $reo->get_input_button_id(), undef, 'get_input_button_id() undef without an id' );
    is( $reo->get_input_button_and_remove(), 'SAVE', 'get_input_button_and_remove() returns the button' );
    is( $reo->get_input_button(), undef, 'get_input_button_and_remove() removed the button' );
    } );

  request( COOKIE => $COOKIE, QS => 'BUTTON%3AEDIT%3A42=x', HOOK => sub
    {
    my $reo = shift;
    is( $reo->get_input_button(),    'EDIT', 'get_input_button() from BUTTON:NAME:ID' );
    is( $reo->get_input_button_id(), '42',   'get_input_button_id() from BUTTON:NAME:ID' );
    } );

  request( COOKIE => $COOKIE, QS => 'BUTTON%3ASAVE=x&BUTTON%3ASAVE=y', HOOK => sub
    {
    my $reo = shift;
    is( $reo->get_input_button(), 'SAVE', 'get_input_button() from a repeated button parameter' );
    is( $reo->get_input_button_and_remove(), 'SAVE', 'get_input_button_and_remove() returns the repeated button' );
    is( $reo->get_input_button(), undef, 'get_input_button_and_remove() removed the repeated button' );
    } );

  request( COOKIE => $COOKIE, QS => 'XBUTTON%3ASAVE=x', HOOK => sub
    {
    is( $_[0]->get_input_button(), undef, 'a parameter which only contains BUTTON: is not a button' );
    } );

  request( COOKIE => $COOKIE, QS => 'BUTTON%3AGO.X=3&BUTTON%3AGO.Y=4', HOOK => sub
    {
    is( $_[0]->get_input_button(), 'GO', 'get_input_button() from an image button' );
    } );

  # a button in the safe input (args() links) wins over a form button
  my $link;
  request( COOKIE => $COOKIE, HOOK => sub { $link = $_[0]->args_here( BUTTON => 'LINKED', BUTTON_ID => 7 ) } );
  request( COOKIE => $COOKIE, QS => "_=$link&BUTTON%3ASAVE=x", HOOK => sub
    {
    my $reo = shift;
    is( $reo->get_input_button(),    'LINKED', 'get_input_button() prefers the safe input BUTTON' );
    is( $reo->get_input_button_id(), 7,        'get_input_button_id() takes the safe input BUTTON_ID with it' );
    is( $reo->get_input_button_and_remove(), 'LINKED', 'get_input_button_and_remove() returns the safe button' );
    is( $reo->get_input_button(), undef, 'get_input_button_and_remove() removed both the safe and the form button' );
    } );
}

# password input parameters: names starting with PASS or containing PASSWORD
# are RSA encrypted as hex, see $Web::Reactor::Core::RE_PASSWORD_PARAM_NAMES
{
  require Crypt::PK::RSA;
  require Data::Tools::Crypto::RSA;
  my $pk = Crypt::PK::RSA->new();
  $pk->generate_key( 128 ); # 1024 bits, the smallest usual key, enough for a test
  my $pub_pem  = $pk->export_key_pem( 'public'  );
  my $priv_pem = $pk->export_key_pem( 'private' );
  my $priv     = Data::Tools::Crypto::RSA->new( $priv_pem );

  my %rsa_cfg = ( RSA_PUB => $pub_pem );

  my $mark = scalar @LOG;
  request( COOKIE => $COOKIE, CFG => \%rsa_cfg, QS => 'password=pw1&new_password=pw2&pass2=&passwd=pw3&user_passwd=pw4&name=n', HOOK => sub
    {
    my $ui = $_[0]->get_user_input();
    like( $ui->{ 'PASSWORD' }, qr/^[0-9a-f]+$/i, 'PASSWORD arrives encrypted as hex' );
    is( $priv->decrypt_hex( $ui->{ 'PASSWORD' } ), 'pw1', 'PASSWORD decrypts with the private key' );
    is( $priv->decrypt_hex( $ui->{ 'NEW_PASSWORD' } ), 'pw2', 'a name containing PASSWORD is encrypted too' );
    is( $priv->decrypt_hex( $ui->{ 'PASSWD' } ), 'pw3', 'a name starting with PASS is encrypted' );
    is( $ui->{ 'PASS2' }, '', 'an empty password value stays empty' );
    is( $ui->{ 'USER_PASSWD' }, 'pw4', 'a name with PASS inside but not PASSWORD is not a password' );
    is( $ui->{ 'NAME' }, 'n', 'other parameters are not touched' );
    } );
  ok( ! log_since( $mark, qr/pw1|pw2|pw3/ ), 'plain password values are not logged' );

  $mark = scalar @LOG;
  request( COOKIE => $COOKIE, CFG => \%rsa_cfg, QS => 'password=a&password=b&new_password=c&new_password=d', HOOK => sub
    {
    my $ui = $_[0]->get_user_input();
    ok( ! exists $ui->{ '@PASSWORD' } && ! exists $ui->{ 'PASSWORD' }, 'a repeated PASS* parameter is dropped' );
    ok( ! exists $ui->{ '@NEW_PASSWORD' } && ! exists $ui->{ 'NEW_PASSWORD' }, 'a repeated *PASSWORD* parameter is dropped' );
    } );
  ok( log_since( $mark, qr/password input parameter sent more than once.*\[\@PASSWORD\]/ ),     'the dropped @PASSWORD is logged' );
  ok( log_since( $mark, qr/password input parameter sent more than once.*\[\@NEW_PASSWORD\]/ ), 'the dropped @NEW_PASSWORD is logged' );

  # forced run() arguments are encrypted like request input
  my $r = make_reo( make_env( HTTP_COOKIE => "wrtest_cookie=$COOKIE" ), make_cfg( %rsa_cfg ) );
  $r->{ 'HOOK' } = sub { is( $priv->decrypt_hex( $_[0]->get_user_input()->{ 'PASSWORD' } ), 'forced-pw', 'a forced PASSWORD argument is encrypted' ) };
  $r->run( password => 'forced-pw' );
  ok( $r->{ 'HOOK_DONE' }, 'the forced arguments request ran' );

  request( COOKIE => $COOKIE, CFG => { DISABLE_PASSWORD_ENCRYPT => 1 }, QS => 'password=plain-pw&new_password=plain-new', HOOK => sub
    {
    my $ui = $_[0]->get_user_input();
    is( $ui->{ 'PASSWORD' },     'plain-pw',  'DISABLE_PASSWORD_ENCRYPT leaves PASSWORD as it arrives' );
    is( $ui->{ 'NEW_PASSWORD' }, 'plain-new', 'DISABLE_PASSWORD_ENCRYPT leaves NEW_PASSWORD as it arrives' );
    } );

  # without RSA_PUB a non-empty password fails the request, an empty one does not
  $mark = scalar @LOG;
  my ( $rn, $resn ) = request( COOKIE => $COOKIE, QS => 'password=no-key-pw' );
  ok( ! $rn->{ 'HOOK_DONE' } && log_since( $mark, qr/RSA_PUB/ ), 'a password without RSA_PUB booms' );
  ok( ! log_since( $mark, qr/no-key-pw/ ), 'the failed request does not log the password' );
  request( COOKIE => $COOKIE, QS => 'password=', HOOK => sub { is( $_[0]->get_user_input()->{ 'PASSWORD' }, '', 'an empty password needs no RSA_PUB' ) } );
}

##############################################################################
##
##  section 10 -- forwards
##

{
  my %fw = (
           'forward'         => [ X => 1 ],
           'forward_here'    => [ X => 1 ],
           'forward_back'    => [ X => 1 ],
           'forward_new'     => [ X => 1 ],
           );

  for my $m ( sort keys %fw )
    {
    my ( $r, $res ) = request( COOKIE => $COOKIE, HOOK => sub { $_[0]->$m( @{ $fw{ $m } } ) } );
    is( $res->[0], 302, "$m() sets a 302 status" );
    my %h = @{ $res->[1] };
    like( $h{ 'location' }, qr/^\?_=[A-Za-z0-9]+\.[A-Za-z0-9]+$/, "$m() sets a location" );

    my $err;
    request( COOKIE => $COOKIE, HOOK => sub { eval { $_[0]->$m( 'odd' ) }; $err = $@ } );
    ok( $err, "$m() booms on an odd argument list" );
    }

  my ( $r, $res ) = request( COOKIE => $COOKIE, HOOK => sub { $_[0]->forward_new_page( 'other', X => 1 ) } );
  my %h = @{ $res->[1] };
  my ( $key ) = $h{ 'location' } =~ /\.([A-Za-z0-9]+)$/;
  is( $r->get_link_session()->{ 'ARGS' }{ $key }{ '_PN' }, 'other', 'forward_new_page() sets _PN' );

  ( $r, $res ) = request( COOKIE => $COOKIE, HOOK => sub { $_[0]->forward_new_action( 'hello', X => 1 ) } );
  %h = @{ $res->[1] };
  ( $key ) = $h{ 'location' } =~ /\.([A-Za-z0-9]+)$/;
  is( $r->get_link_session()->{ 'ARGS' }{ $key }{ '_AN' }, 'hello', 'forward_new_action() sets _AN' );

  ( $r, $res ) = request( COOKIE => $COOKIE, HOOK => sub { $_[0]->forward_type( 'here', X => 1 ) } );
  %h = @{ $res->[1] };
  like( $h{ 'location' }, qr/^\?_=/, 'forward_type()' );

  # need_login() forwards anonymous visitors to the login page
  ( $r, $res ) = request( HOOK => sub { $_[0]->need_login() } );
  %h = @{ $res->[1] };
  ( $key ) = $h{ 'location' } =~ /\.([A-Za-z0-9]+)$/;
  is( $r->get_link_session()->{ 'ARGS' }{ $key }{ '_PN' }, 'login', 'need_login() forwards to the login page' );

  my $nl = 'not called';
  request( HOOK => sub { $_[0]->login( 'someone' ); $nl = $_[0]->need_login() } );
  is( $nl, undef, 'need_login() is a no-op once logged in' );
}

##############################################################################
##
##  section 11 -- session state cache and save()
##

{
  my ( $r ) = request( COOKIE => $COOKIE );

  my $page = $r->get_page_session();
  my $psid = $page->{ ':SID' };
  my $usid = $r->get_user_session_id();

  is( $r->sc_get( 'PAGE', $psid, $usid ), $page, 'sc_get() finds the active page session' );
  is( $r->sc_get( 'PAGE', 'NoSuchPage', $usid ), undef, 'sc_get() returns undef for an untracked session' );
  is( $r->sc_add( $page ), $page, 'sc_add() of a tracked hash returns it' );

  eval { $r->sc_add( { %$page } ) };
  like( $@, qr/already tracked with another hash/, 'sc_add() booms on a second hash with the same key' );

  $page->{ 'MARKER' } = 'kept';
  $r->save();
  is( $r->__ses->load( 'PAGE', $psid, $usid )->{ 'MARKER' }, 'kept', 'save() writes modified page session data' );

  # unchanged data must not be rewritten
  my $fn = ses_file( $r, 'PAGE', $psid, $usid );
  utime( 1, 1, $fn );
  $r->save();
  is( ( stat $fn )[ 9 ], 1, 'save() skips sessions whose content did not change' );

  $page->{ 'MARKER' } = 'changed';
  $r->save();
  isnt( ( stat $fn )[ 9 ], 1, 'save() rewrites a session after it changed' );

  # sc_remove() stops tracking, the storage is untouched
  $r->sc_remove( $page );
  is( $r->sc_get( 'PAGE', $psid, $usid ), undef, 'sc_remove() stops tracking' );
  $page->{ 'MARKER' } = 'not saved';
  $r->save();
  is( $r->__ses->load( 'PAGE', $psid, $usid )->{ 'MARKER' }, 'changed', 'an untracked session is not saved' );
  ok( -e $fn, 'sc_remove() does not delete the storage' );

  # an unencodable value is logged as a failed save, save() never raises
  my $mark = scalar @LOG;
  my $u = $r->get_user_session();
  $u->{ 'CODE' } = sub { 1 };
  my $ok = eval { $r->save(); 1 };
  ok( $ok, 'save() does not raise on a failed write' );
  ok( log_since( $mark, qr/error saving session state/ ), 'a failed save is logged' );
  delete $u->{ 'CODE' };
}

# a new session which is never changed after create() is not written again
{
  my ( $r ) = request();
  my $fn = ses_file( $r, 'PAGE', $r->get_page_session_id(), $r->get_user_session_id() );
  ok( -s $fn, 'new page session is on disk' );

  my $link = $r->sc_add( $r->__ses->create( 'LINK', $r->get_cookie_session()->{ ':SID' }, 8 ) );
  my $lfn  = ses_file( $r, 'LINK', $link->{ ':SID' }, $link->{ ':PSID' } );
  utime( 1, 1, $lfn );
  $r->save();
  is( ( stat $lfn )[ 9 ], 1, 'a session not changed after create() is not written again' );
}

##############################################################################
##
##  section 12 -- HTML::Utils
##

my ( $APP ) = request( COOKIE => $COOKIE );

{
  is( html_escape( '<a href="x">&' ), '&#60;a href&#61;&#34;x&#34;&#62;&#38;', 'html_escape()' );

  is( html_element( 'br', undef ), '<br />', 'html_element() self closing without text' );
  is( html_element( 'b', 'txt' ), '<b >txt</b>', 'html_element() with text' );
  is( html_element( 'div', '', class => 'c' ), "<div class='c' ></div>", 'html_element() with an attribute' );
  like( html_element( 'div', 'x', CLASS => 'c' ), qr/class='c'/, 'html_element() lower-cases attribute names' );
  like( html_element( 'div', 'x', title => "it's" ), qr/&#39;|&#x27;|&apos;/, 'html_element() escapes attribute values' );

  is( html_element_e( 'b', '<i>' ), '<b >&#60;i&#62;</b>', 'html_element_e() escapes the text' );

  eval { html_element( 'bad tag', 'x' ) };
  ok( $@, 'html_element() booms on an invalid tag name' );
  eval { html_element( 'div', 'x', 'bad attr' => 1 ) };
  ok( $@, 'html_element() booms on an invalid attribute name' );

  ok(   html_check_tag_name( 'div'  ), 'html_check_tag_name() accepts a plain name' );
  ok(   html_check_tag_name( 'h1'   ), 'html_check_tag_name() accepts digits' );
  ok( ! html_check_tag_name( 'a b'  ), 'html_check_tag_name() rejects whitespace' );
  ok( ! html_check_tag_name( 'a-b'  ), 'html_check_tag_name() rejects dashes' );

  ok(   html_check_attr_name( 'data-x' ), 'html_check_attr_name() accepts dashes' );
  ok(   html_check_attr_name( 'xml:id' ), 'html_check_attr_name() accepts colons' );
  ok( ! html_check_attr_name( 'a b'    ), 'html_check_attr_name() rejects whitespace' );

  eval { html_check_tag_name_boom( 'a b' ) };
  ok( $@, 'html_check_tag_name_boom() booms' );
  eval { html_check_attr_name_boom( 'a b' ) };
  ok( $@, 'html_check_attr_name_boom() booms' );
  eval { html_check_tag_name_boom( 'div' ) };
  ok( ! $@, 'html_check_tag_name_boom() is quiet on a valid name' );

  my $tree = html_ftree( [ 'one', { LABEL => 'group', DATA => [ 'two' ] }, 'three' ] );
  like( $tree, qr/<table id='FTREE_TABLE_\Q$$\E_\d+_\d+'/, 'html_ftree() builds a table, its id has the pid, a time and a counter' );
  like( $tree, qr/<tr id='FTREE_TABLE_[\d_]+\.\d+\.'/, 'html_ftree() quotes the row ids' );
  like( $tree, qr/one/,    'html_ftree() renders leaves'   );
  like( $tree, qr/group/,  'html_ftree() renders labels'   );
  like( $tree, qr/ftree_click/, 'html_ftree() wires the branch toggle' );
  like( $tree, qr/display: none/, 'html_ftree() hides collapsed branches' );
  like( html_ftree( [ 'a' ], CLASS => 'tr' ), qr/class='tr'/, 'html_ftree() quotes the table class' );
  like( html_ftree( [ { LABEL => 'row', CLASS => 'rc' } ] ), qr/class='rc'/, 'html_ftree() quotes the row class' );
  like( html_ftree( [ 'a' ], ARGS_TR => "data-r='1'", ARGS_TD => "data-c='1'" ), qr/<tr [^>]*data-r='1'[^>]*><td [^>]*data-c='1'/, 'html_ftree() ARGS_TR and ARGS_TD go to the rows and cells' );
  my $fo = html_ftree( [ { LABEL => 'a', ARGS => "data-own='1'" } ], ARGS_TR => "data-r='1'" );
  like(   $fo, qr/<tr [^>]*data-own='1'/, 'html_ftree() row ARGS win over ARGS_TR' );
  unlike( $fo, qr/data-r=/,              'html_ftree() ARGS_TR is not added to a row with its own ARGS' );
  my $ft = html_ftree( [ { LABEL => 'b', DATA => [ 'l', { LABEL => 'sb', DATA => [ 'x' ] } ] } ], ARGS_TR => "style='color: red'" );
  unlike( $ft, qr/<tr [^>]*style=[^>]*style=/, 'html_ftree() nested rows with a style in ARGS_TR get one style attribute' );
  is( scalar( () = $ft =~ /style='display: none; color: red'/g ), 3, 'html_ftree() merges display none into the style of every nested row' );

  ok( defined &html_ctable, 'html_ctable() is exported' );
  eval { html_ctable( [] ) };
  like( $@, qr/html_ctable\(\) is not implemented yet/, 'html_ctable() booms instead of returning nothing' );

  like( html_debug( { A => 1 } ), qr/<xmp>.*'A' => 1.*<\/xmp>/s, 'html_debug() dumps its arguments' );

  my $al = html_alink( $APP, 'here', 'CLICK', { CLASS => 'btn' }, X => 1 );
  like( $al, qr/^<a href=\?_=[A-Za-z0-9]+\.[A-Za-z0-9]+/, 'html_alink() builds a reactor link' );
  like( $al, qr/>CLICK<\/a>$/, 'html_alink() wraps the value' );
  like( $al, qr/class='btn'/,  'html_alink() honours CLASS' );
  unlike( $al, qr/id=/i, 'html_alink() emits no id without one' );
  like( html_alink( $APP, 'here', 'C', { ID => 'lnk' } ), qr/ id='lnk'/, 'html_alink() writes the id lowercase' );
  unlike( html_alink( $APP, 'here', 'C', {} ), qr/class=|id=/i, 'html_alink() emits no empty class or ID' );

  like( html_alink( $APP, 'here', 'C', { CONFIRM => 'sure?' } ), qr/confirm\('sure\?'\)/, 'html_alink() CONFIRM' );
  like( html_alink( $APP, 'here', 'C', { DISABLED => 1 } ), qr/disabled-button/, 'html_alink() DISABLED' );
  is( scalar( () = html_alink( $APP, 'here', 'C', { DISABLED => 1, CONFIRM => 'sure' } ) =~ /onclick=/g ), 1, 'html_alink() DISABLED with CONFIRM has one onclick' );
  like( html_alink( $APP, 'here', 'C', { DISABLED => 1, CONFIRM => 'sure' } ), qr/onclick="return false;"/, 'html_alink() DISABLED wins over CONFIRM' );
  is( scalar( () = html_alink( $APP, 'here', 'C', { DISABLED => 1, DISABLE_ON_CLICK => 3 } ) =~ /onclick=/g ), 1, 'html_alink() DISABLED with DISABLE_ON_CLICK has one onclick' );
  my $dc = html_alink( $APP, 'here', 'C', { CLASS => 'b', DISABLE_ON_CLICK => 3, DISABLE_ON_CLICK_CLASS => 'off' } );
  is( scalar( () = $dc =~ /onclick=/g ), 1, 'html_alink() DISABLE_ON_CLICK has one onclick' );
  like( $dc, qr/onclick="return reactor_element_disable_on_click\( this, 3 \);"/, 'html_alink() DISABLE_ON_CLICK calls the disable handler' );
  like( $dc, qr/data-class-on='b' data-class-off='off'/, 'html_alink() DISABLE_ON_CLICK sets the on and off classes' );
  my $cd = html_alink( $APP, 'here', 'C', { CONFIRM => 'sure', DISABLE_ON_CLICK => 3 } );
  is( scalar( () = $cd =~ /onclick=/g ), 1, 'html_alink() CONFIRM with DISABLE_ON_CLICK has one onclick' );
  like( $cd, qr/onclick="return confirm\('sure'\);"/, 'html_alink() CONFIRM wins over DISABLE_ON_CLICK' );
  like( html_alink( $APP, 'here', 'C', { CONFIRM => q{it's "x" & y} } ), qr/onclick="return confirm\('it\\'s &quot;x&quot; &amp; y'\);"/, 'html_alink() CONFIRM with quotes is escaped, not dropped' );
  like( html_alink( $APP, 'here', 'C', { CONFIRM => "a\\b\nc" } ), qr/confirm\('a\\\\b\\nc'\)/, 'html_alink() CONFIRM escapes backslashes and newlines' );
  like( html_alink( $APP, 'here', 'C', { CONFIRM => "a\rb\r\nc" } ), qr/confirm\('a\\nb\\nc'\)/, 'html_alink() CONFIRM escapes lone CR and CRLF line endings' );
  like( html_alink( $APP, 'here', 'C', { DISABLED => 1 } ), qr/class='disabled-button'/, 'html_alink() DISABLED without CLASS has no leading space' );
  like( html_alink( $APP, 'here', 'C', { DISABLED => 1, CLASS => 'b' } ), qr/class='b disabled-button'/, 'html_alink() DISABLED adds to CLASS' );
  {
    package Web::Reactor::TestCoreHtml;
    our @ISA = ( 'Web::Reactor::Core' );
    package main;
    my $core = Web::Reactor::TestCoreHtml->new( make_env(), make_cfg() );
    eval { my $x = html_hover_layer( $core, VALUE => 'v' ) };
    like( $@, qr/needs a Web::Reactor::Reflex or Web::Reactor object/, 'html_hover_layer() booms on a Core reactor' );
    eval { my $x = html_popup_layer( $core, VALUE => 'v' ) };
    like( $@, qr/needs a Web::Reactor::Reflex or Web::Reactor object/, 'html_popup_layer() booms on a Core reactor' );
    eval { html_alink( $core, 'here', 'C', {} ) };
    like( $@, qr/needs a Web::Reactor object \(args_type\)/, 'html_alink() booms on a Core reactor' );
  }
  {
    # reactor classes live under Web::Reactor::, the same rule for all the helpers
    package TestOutsideReactor;
    our @ISA = ( 'Web::Reactor::Reflex' );
    package main;
    my $out = bless { %$APP }, 'TestOutsideReactor';
    eval { html_alink( $out, 'here', 'C', {} ) };
    like( $@, qr/missing REO reactor object/, 'html_alink() booms on a reactor class outside Web::Reactor::' );
    eval { my $x = html_hover_layer( $out, VALUE => 'v' ) };
    like( $@, qr/missing REO reactor object/, 'html_hover_layer() booms on a reactor class outside Web::Reactor::' );
    eval { my $x = html_popup_layer( $out, VALUE => 'v' ) };
    like( $@, qr/missing REO reactor object/, 'html_popup_layer() booms on a reactor class outside Web::Reactor::' );
    eval { html_alink( undef, 'here', 'C', {} ) };
    like( $@, qr/missing REO reactor object/, 'html_alink() booms without a reactor' );
  }

  # in scalar context the layers go into the KIT_HTML hold, see
  # Web::Reactor::Reflex::html_hold_kit_add()
  {
    my $hl = html_alink( $APP, 'here', 'C', { HINT => 'go' } );
    like( $hl, qr/ onmouseover='\s*reactor_hover_show_delay\( this, "R_HOVER_LAYER_[^"]+", 1000, event \)\s*'/, 'html_alink() HINT wires the hover layer to onmouseover' );
    unlike( html_alink( $APP, 'here', 'C', { HINT => 'go', DISABLED => 1 } ), qr/onmouseover/, 'html_alink() a DISABLED link has no hint' );
    my $ps = html_popup_layer( $APP, VALUE => 'accumulated popup' );
    like( $ps, qr/data-popup-layer-id=/, 'html_popup_layer() scalar context returns the handle' );
    my $hs = html_hover_layer( $APP, VALUE => 'accumulated hover' );
    like( $hs, qr/reactor_hover_show_delay/, 'html_hover_layer() scalar context returns the handle' );

    my $kit = $APP->html_hold_get( 'kit_html' );
    like( $kit, qr/>go</,                'html_alink() HINT layer goes into the kit_html hold' );
    like( $kit, qr/accumulated popup/,   'html_popup_layer() scalar context layer goes into the kit_html hold' );
    like( $kit, qr/accumulated hover/,   'html_hover_layer() scalar context layer goes into the kit_html hold' );
  }

  my ( undef, $et ) = html_hover_layer( $APP );
  like( $et, qr{<div [^>]*></div>$}, 'html_hover_layer() without VALUE still closes the div' );
  like( html_hover_layer( $APP, VALUE => 'v', DELAY => 0 ), qr/, 0, event/, 'html_hover_layer() DELAY 0 shows at once' );
  my ( $ph, $pt ) = html_popup_layer( $APP, VALUE => 'popup text' );
  like( $ph, qr/data-popup-layer-id="R_POPUP_LAYER_/, 'html_popup_layer() handle carries the layer id' );
  like( $ph, qr/onClick=/, 'html_popup_layer() CLICK trigger by default' );
  like( $ph, qr/reactor_popup_mouse_over\( this, \{ click_open: 1, timeout: 200, single: 0 \} \)/, 'html_popup_layer() CLICK default options' );
  my ( $cs ) = html_popup_layer( $APP, VALUE => 'v', TIMEOUT => 500, SINGLE => 1 );
  like( $cs, qr/\{ click_open: 1, timeout: 500, single: 1 \}/, 'html_popup_layer() CLICK passes TIMEOUT and SINGLE' );
  like( html_popup_layer( $APP, VALUE => 'v', TYPE => 'context' ), qr/onContextMenu/, 'html_popup_layer() TYPE is case insensitive' );
  eval { html_popup_layer( $APP, VALUE => 'v', TYPE => 'hover' ) };
  like( $@, qr/invalid popup TYPE \[HOVER\]/, 'html_popup_layer() booms on an unknown TYPE' );
  like( $pt, qr/popup text/, 'html_popup_layer() layer carries the value' );
  like( $pt, qr/class='popup-layer'/, 'html_popup_layer() default class' );
  my ( undef, $pe ) = html_popup_layer( $APP, VALUE => 'v', CLASS => q{a'b} );
  like( $pe, qr/class='a&#39;b'/, 'html_popup_layer() escapes the class' );
  my ( undef, $pu ) = html_popup_layer( $APP );
  like( $pu, qr{<div [^>]*></div>$}, 'html_popup_layer() without VALUE still closes the div' );
  my ( $ch ) = html_popup_layer( $APP, VALUE => 'v', TYPE => 'CONTEXT', TIMEOUT => 500, SINGLE => 1 );
  like( $ch, qr/onContextMenu="return reactor_popup_mouse_over\( this, \{ timeout: 500, single: 1 \} \)"/, 'html_popup_layer() CONTEXT passes TIMEOUT and SINGLE' );

  my ( $hh, $ht ) = html_hover_layer( $APP, VALUE => 'hover text', DELAY => 500 );
  like( $hh, qr/reactor_hover_show_delay/, 'html_hover_layer() wires the hover handler' );
  like( $hh, qr/, 500, event/, 'html_hover_layer() honours DELAY' );
  like( $ht, qr/hover text/, 'html_hover_layer() layer carries the value' );
  like( $ht, qr/class='hover-layer'/, 'html_hover_layer() default class' );

  eval { html_popup_layer( 'not a reactor', VALUE => 'x' ) };
  ok( $@, 'html_popup_layer() booms without a reactor object' );
  eval { html_hover_layer( 'not a reactor', VALUE => 'x' ) };
  ok( $@, 'html_hover_layer() booms without a reactor object' );

  my $tabs = html_tabs_table( $APP, [ { LABEL => 'L1', TEXT => 'T1', ON => 1 },
                                      { LABEL => 'L2', TEXT => 'T2' } ] );
  like( $tabs, qr/L1/, 'html_tabs_table() renders the first label'  );
  my $otabs = html_tabs_table( $APP, [ { LABEL => 'L1', TEXT => 'T1', ON => 1, TEXT_TD_ARGS => "data-tt='1'" }, { LABEL => 'L2', TEXT => 'T2' } ],
                                     LABEL_CLASS_ON => 'lon', LABEL_CLASS_OFF => 'loff', LABELS_TABLE_ARGS => "data-lt='1'" );
  like( $otabs, qr/<TD [^>]*class='lon'[^>]*>L1</,  'html_tabs_table() LABEL_CLASS_ON on the active label' );
  like( $otabs, qr/<TD [^>]*class='loff'[^>]*>L2</, 'html_tabs_table() LABEL_CLASS_OFF on the other label' );
  like( $otabs, qr/<table [^>]*data-lt='1'/i,      'html_tabs_table() LABELS_TABLE_ARGS on the labels table' );
  like( $otabs, qr/<TD data-tt='1'>T1<\/TD>/,      'html_tabs_table() TEXT_TD_ARGS on the text cell' );
  unlike( $tabs, qr{</td>}, 'html_tabs_table() closes the cells in the case it opens them' );
  unlike( $tabs, qr/class=''/, 'html_tabs_table() without label classes emits no empty class' );
  like( $tabs, qr/L2/, 'html_tabs_table() renders the second label' );
  like( $tabs, qr/T1/, 'html_tabs_table() renders the first tab'    );
  like( $tabs, qr/reactor_tab_activate_id/, 'html_tabs_table() wires the tab handler' );

  my $vtabs = html_tabs_table( $APP, [ { LABEL => 'L', TEXT => 'T' } ], VERTICAL => 1 );
  like( $vtabs, qr/WIDTH=50%/, 'html_tabs_table() vertical layout' );

  my $ctabs = html_tabs_table( $APP, [ { LABEL => 'L1', TEXT => 'T1', ON => 1, LABEL_TD_ARGS => "class='lbl'" } ] );
  unlike( $ctabs, qr/<TD [^>]*class=[^>]*class=/i, 'html_tabs_table() gives a label TD only one class attribute' );
  like( $ctabs, qr/class='lbl'/, 'html_tabs_table() keeps the LABEL_TD_ARGS class on the handle' );
  my $dtabs = html_tabs_table( $APP, [ { LABEL => 'L1', TEXT => 'T1', ON => 1, LABEL_TD_ARGS => "data-class='z'" } ] );
  like( $dtabs, qr/data-class='z'/, 'html_tabs_table() leaves a data-class attribute in LABEL_TD_ARGS alone' );
  my $wtabs = html_tabs_table( $APP, [ { LABEL => 'L1', TEXT => 'T1', ON => 1, LABEL_TD_ARGS => "class='md:w-1/2'" } ] );
  like( $wtabs, qr{class='md:w-1/2'}, 'html_tabs_table() takes class names with : and /' );
  like( $wtabs, qr{data-class-keep='md:w-1/2'}, 'html_tabs_table() keeps the label class through tab switches' );
  my $utabs = html_tabs_table( $APP, [ { LABEL => 'L1', TEXT => 'T1', ON => 1, LABEL_TD_ARGS => 'class=lbl' } ] );
  like( $utabs, qr/class='lbl/, 'html_tabs_table() takes an unquoted label class' );
  like( $utabs, qr/data-class-keep='lbl'/, 'html_tabs_table() keeps an unquoted label class through tab switches' );
  unlike( $utabs, qr/class=lbl/, 'html_tabs_table() moves the unquoted label class to the handle' );
}

##############################################################################
##
##  section 13 -- HTML::Layout
##

{
  my $t = html_table( [ [ 'a', 'b' ],
                        { DATA => [ 'c', { ARGS => 'align=right', DATA => 'd' } ] },
                        { CCL  => [ 'k', 'v' ], DATA => [ 'name', 'value' ] },
                      ] );
  like( $t, qr/<table/i, 'html_table() builds a table' );
  like( $t, qr/<td[^>]*>a<\/td>/, 'html_table() renders plain cells' );
  like( $t, qr/align=right/, 'html_table() honours cell ARGS' );
  like( $t, qr/class='k'/,  'html_table() honours the column class list' );

  my $g = html_layout_grid( [ [ '1', '2' ], [ '3', '4' ] ] );
  like( $g, qr/<table border=0/, 'html_layout_grid()' );
  like( $g, qr/<td[^>]*>1<\/td>/, 'html_layout_grid() renders cells' );
  like( html_layout_grid( [ [ { ARGS => 'class=x', DATA => 'cell' } ] ] ), qr/<td class=x>cell<\/td>/, 'html_layout_grid() takes { ARGS, DATA } cells' );
  {
    my $gd = [ { ARGS => 'class=r', DATA => [ { ARGS => 'class=x', DATA => 'cell' } ] } ];
    html_layout_grid( $gd );
    like( html_layout_grid( $gd ), qr/<tr class=r><td class=x>cell<\/td>/, 'html_layout_grid() leaves the caller data unchanged' );

    my $td = [ 's', [ \'cl', 'a' ], { data => [ 'x' ] } ];
    html_table( $td );
    ok( ( ! ref $td->[ 0 ] and ref $td->[ 1 ] eq 'ARRAY' and exists $td->[ 2 ]{ 'data' } ), 'html_table() leaves the caller data unchanged' );

    like( html_table( [ { '-NODISPLAY' => 1, DATA => [ 'a' ] } ] ), qr/display: none/, 'html_table() -NODISPLAY works without a CID' );
    my @st = html_table( [ [ 'r1' ], { SKIP => 1, DATA => [ 's' ] }, [ 'r2' ] ] ) =~ /<tr class='(tr-\d)'/g;
    is( "@st", 'tr-1 tr-2', 'html_table() row stripes skip SKIP rows' );
    is( join( ' ', html_table( [ [ 1 ], [ 2 ], [ 3 ] ] ) =~ /<tr class='(tr-\d)'/g ), 'tr-1 tr-2 tr-1', 'html_table() stripes start with TR1' );
    is( join( ' ', html_table( [ [ 1 ], [ 2 ], [ 3 ] ], TRH => 'hd' ) =~ /<tr class='([\w-]+)'/g ), 'hd tr-1 tr-2', 'html_table() with TRH the body stripes start with TR1 too' );
    my $nd = html_table( [ { -NODISPLAY => 1, ARGS => "style='color: red'", DATA => [ 'a' ] } ] );
    like( $nd, qr/<tr style='display: none; color: red' class='tr-1'>/, 'html_table() -NODISPLAY merges into a style in ARGS' );
    is( scalar( () = $nd =~ /style=/g ), 1, 'html_table() -NODISPLAY with a style in ARGS gives one style attribute' );
    my $nu = html_table( [ { -NODISPLAY => 1, ARGS => 'style=color:red', DATA => [ 'a' ] } ] );
    like( $nu, qr/<tr style='display: none; color:red' class='tr-1'>/, 'html_table() -NODISPLAY merges into an unquoted style in ARGS' );
    is( scalar( () = $nu =~ /style=/g ), 1, 'html_table() -NODISPLAY with an unquoted style in ARGS gives one style attribute' );
    my $cc = html_table( [ { CCL => [ 'colc' ], DATA => [ { ARGS => 'align=right', DATA => 'v' } ] }, [ 'plain' ] ] );
    like( $cc, qr/align=right class='colc'/, 'html_table() keeps the column class with cell ARGS' );
    unlike( $cc, qr/class=''/, 'html_table() emits no empty class' );
    like( html_table( [ { ARGS => 'data-class=x', DATA => [ 'a' ] } ] ), qr/<tr data-class=x class='tr-1'>/, 'html_table() row data-class ARGS do not hide the stripe class' );
    like( html_table( [ { CCL => [ 'cc' ], DATA => [ { ARGS => 'data-class=y', DATA => 'v' } ] } ] ), qr/data-class=y class='cc'/, 'html_table() cell data-class ARGS do not hide the column class' );
    unlike( html_hbox( 'content:<', 'a' ), qr/nowrap/, 'box format: letters of the class name are not flags' );
    unlike( html_table( [ { CCL => [ 'skipc' ], SKIP => 1 }, [ 'a' ] ] ), qr/skipc/, 'html_table() CCL of a skipped row is not used for the next row' );
    like( html_table( [ { PCCL => [ 'permc' ], SKIP => 1 }, [ 'a' ] ] ), qr/class='permc'/, 'html_table() PCCL of a skipped row stays' );
    like( html_table( [ { PCCL => [ 'p' ], SKIP => 1 }, [ 'a', 'b' ] ], CCL => [ 'opt1', 'opt2' ] ), qr/class='opt1'/, 'html_table() a skipped row keeps the table CCL option' );
    like( html_table( [ { ARGS => 'id=x', DATA => [ 'a' ] } ] ), qr/<tr id=x class='tr-1'>/, 'html_table() keeps the stripe class with row ARGS' );
    like( html_table( [ [ 'a' ] ], CLASS => 'tbl' ), qr/<table class='tbl'>/, 'html_table() quotes the table class' );
    my $th = html_table( [ [ 'a', 'b' ], [ 'c' ] ], TDH => 'hc', COMMENT => 'cm' );
    is( scalar( () = $th =~ /<td\s+class='hc'>/g ), 2, 'html_table() TDH classes the cells of the first row only' );
    like( $th, qr/<!--- BEGIN TABLE: cm --->.*<!--- END TABLE: cm --->/s, 'html_table() COMMENT wraps the table' );
    my $oc = html_table( [ { ARGS => "class='own'", DATA => [ 'a' ] } ] );
    is( scalar( () = $oc =~ /<tr [^>]*class=/g ), 1, 'html_table() row ARGS class: one class attribute' );
    like( $oc, qr/<tr class='own'>/, 'html_table() row ARGS class wins over the stripe' );
    my $occ = html_table( [ { CCL => [ 'colc' ], DATA => [ { ARGS => 'class=own', DATA => 'v' } ] } ] );
    is( scalar( () = $occ =~ /<td [^>]*class=/g ), 1, 'html_table() cell ARGS class: one class attribute' );
    like( $occ, qr/<td class=own>/, 'html_table() cell ARGS class wins over the column class' );
    like( html_table( [ { CCL => [ 'x' ], SKIP => 1 }, [ 1, 2 ] ], CCL => [ 'a', 'b' ] ), qr/<td\s+class='a'>1<\/td>\s*<td\s+class='b'>2/, 'html_table() a skipped row with its own CCL keeps the table CCL option' );
    like( html_layout_2lr_flex( 'L', 'R', '' ), qr/flex: 99;/, 'html_layout_2lr_flex() with an empty format uses the fixed layout' );
  }

  like( html_layout_hbox( [ 'a', 'b' ] ), qr/valign=top/, 'html_layout_hbox()' );
  like( html_layout_vbox( [ 'a', 'b' ] ), qr/(<tr.*){2}/s, 'html_layout_vbox() stacks rows' );

  my $hf = html_layout_hbox_flex( \'1,2', 'left', 'right' );
  like( $hf, qr/display: flex/, 'html_layout_hbox_flex() uses flex' );
  like( $hf, qr/flex:1;/, 'html_layout_hbox_flex() applies the first weight'  );
  like( $hf, qr/flex:2;/, 'html_layout_hbox_flex() applies the second weight' );

  like( html_layout_2lr( 'L', 'R' ), qr/L/, 'html_layout_2lr() renders the left side'  );
  like( html_layout_2lr( 'L', 'R' ), qr/R/, 'html_layout_2lr() renders the right side' );
  like( html_layout_2lr_flex( 'L', 'R' ), qr/display:\s*flex/, 'html_layout_2lr_flex() uses flex' );
  like( html_layout_2lr_flex( 'L', 'R' ), qr/flex: 99;.*flex: 1;/s, 'html_layout_2lr_flex() without a format: left takes the room' );
  like( html_layout_2lr_flex( 'L', 'R', '>20=>' ), qr/flex: 20;.*flex: 80;/s, 'html_layout_2lr_flex() honours the format' );
  unlike( html_layout_2lr_flex( 'L', 'R', '>20=>' ), qr/;\s*;/, 'html_layout_2lr_flex() style has no empty segments' );
  like( html_layout_2lr_flex( 'L', 'R', '<==>' ), qr/white-space: nowrap/, 'html_layout_2lr_flex() == means no wrap' );
  unlike( html_layout_2lr_flex( 'L', 'R', '<=>' ), qr/nowrap/, 'html_layout_2lr_flex() = wraps' );
  like( html_layout_2lr( 'L', 'R', '<==>' ), qr/nowrap/i, 'html_layout_2lr() == means no wrap' );

  my $hb = html_hbox( 'ctl:<,,>', 'a', 'b', 'c' );
  like( $hb, qr/flex-direction: row/, 'html_hbox() is a row' );
  like( $hb, qr/class='ctl'/, 'html_hbox() applies the class from the format' );
  like( $hb, qr/text-align: left/, 'html_hbox() applies the "<" alignment' );
  like( $hb, qr/text-align: right; [^>]*>c<\/div>/, 'html_hbox() applies the ">" alignment to the third cell' );
  is( scalar( () = $hb =~ /<div [^>]*style='flex/g ), 3, 'html_hbox() emits one cell per value' );

  like( html_vbox( 'a,b', '1', '2' ), qr/flex-direction: column/, 'html_vbox() is a column' );
  like( html_hbox( 'n,w,p', '1', '2', '3' ), qr/white-space: nowrap/, 'box format: n means nowrap' );
  like( html_hbox( 'n,w,p', '1', '2', '3' ), qr/white-space: normal/, 'box format: w means normal wrapping' );
  like( html_hbox( '=', '1' ), qr/flex: 1000/, 'box format: = means take all the room' );
  like( html_hbox( 'a', '1', '2' ), qr/<div style='flex: 1; align-content: center; '>2<\/div>/, 'box format: cells beyond the specs get the default spec' );
}

##############################################################################
##
##  section 14 -- HTML::Form
##
##  HTML::Form will be rewritten, only the reactor side is checked here: the
##  return map stored in the link session and remapped on the way back in
##

{
  {
    local $TODO = 'Web::Reactor::new_form() passes hash arguments to Base::new( $reo, $cfg )';
    my $f = eval { $APP->new_form() };
    isa_ok( $f, 'Web::Reactor::HTML::Form', 'new_form()' );
  }

  my $form = Web::Reactor::HTML::Form->new( $APP, $APP->cfg() );
  isa_ok( $form, 'Web::Reactor::HTML::Form', 'HTML::Form->new( $reo, $cfg )' );
}

# a form round trip: the return map really unmaps the posted values
{
  my ( $sel, $end, $fid );

  my ( $r1 ) = request( COOKIE => $COOKIE, HOOK => sub
    {
    my $reo = shift;
    my $f = Web::Reactor::HTML::Form->new( $reo, $reo->cfg() );
    $f->begin( NAME => 'roundtrip' );
    $fid = $f->get_id();
    $sel = $f->select( NAME => 'colour', DATA => [ { KEY => 'r', VALUE => 'RED', LABEL => 'Red' } ] );
    $end = $f->end();
    } );

  ok( exists $r1->get_link_session()->{ 'FORM_RET_MAP' }{ $fid }, 'form->end() stores the return map in the link session' );

  my ( $hidden_name ) = $sel =~ /name='([^']+)'/;
  my ( $opt_value )   = $sel =~ /<option[^>]*value='([^']+)'/i;
  my ( $state )       = $end =~ /value='([^']+)'/;

  ok( $hidden_name, 'select() produced a mapped input name' );
  like( $state, qr/^[A-Za-z0-9]+\.[A-Za-z0-9]+$/, 'form->end() state keeper holds a link session key' );

  my ( $r2 ) = request( COOKIE => $COOKIE, QS => "_=$state&$hidden_name=$opt_value" );

  is( $r2->get_safe_input()->{ 'colour' }, 'RED', 'form return map turns the posted key back into real data' );
  ok( ! exists $r2->get_user_input()->{ uc $hidden_name }, 'the mapped input name is removed from user input' );
  is( $r2->get_input_form_name(), 'roundtrip', 'get_input_form_name() after a round trip' );
}

##############################################################################
##
##  section 15 -- HTML::Tab
##

{
  my $tab = Web::Reactor::HTML::Tab->new( REO_REACTOR => $APP, NAME => 'tabset',
                                          CLASS_ON => 'on', CLASS_OFF => 'off' );
  isa_ok( $tab, 'Web::Reactor::HTML::Tab', 'HTML::Tab->new()' );
  {
    my ( $fresh ) = request( COOKIE => $COOKIE );
    unlike( $fresh->html_hold_get( 'kit_head' ) // '', qr{reactor\.js}, 'a fresh reactor has no reactor.js in kit_head' );
    Web::Reactor::HTML::Tab->new( REO_REACTOR => $fresh );
    like( $fresh->html_hold_get( 'kit_head' ), qr{src='js/reactor\.js'}, 'HTML::Tab->new() adds reactor.js to the kit_head hold' );
  }

  my ( $handle, $text ) = $tab->add( 'CONTENT-1', TYPE => 'DIV', ON => 1 );
  like( $handle, qr/class='on'/, 'tab->add() uses CLASS_ON for a visible tab' );
  like( $handle, qr/reactor_tab_activate_id/, 'tab->add() wires the activation handler' );
  like( $text, qr/<DIV/i, 'tab->add() wraps the content in the requested element' );
  like( $text, qr/CONTENT-1/, 'tab->add() keeps the content' );

  my ( $h2, $t2 ) = $tab->add( 'CONTENT-2', TYPE => 'DIV' );
  like( $h2, qr/class='off'/, 'tab->add() uses CLASS_OFF for a hidden tab' );
  like( $t2, qr/display: none/, 'tab->add() hides an inactive tab' );

  eval { $tab->add( 'X', TYPE => 'SPAN' ) };
  ok( $@, 'tab->add() booms on an unsupported element type' );

  eval { $tab->add( 'X', TYPE => 'DIV', TAB_ID => q{bad'id} ) };
  like( $@, qr/invalid tab TAB_ID/, 'tab->add() booms on an unsafe TAB_ID' );
  eval { $tab->add( 'X', TYPE => 'DIV', CLASS => q{a"b} ) };
  like( $@, qr/invalid tab CLASS/, 'tab->add() booms on an unsafe CLASS' );
  eval { Web::Reactor::HTML::Tab->new( REO_REACTOR => $APP, NAME => q{x'); alert(1); ('} ) };
  like( $@, qr/invalid tab NAME/, 'HTML::Tab->new() booms on an unsafe NAME' );
  eval { $tab->add( 'X', TYPE => 'DIV', HANDLE_ID => q{a b} ) };
  like( $@, qr/invalid tab HANDLE_ID/, 'tab->add() booms on an unsafe HANDLE_ID' );
  eval { Web::Reactor::HTML::Tab->new( REO_REACTOR => $APP, CLASS_ON => q{a'b} ) };
  like( $@, qr/invalid tab CLASS_ON/, 'HTML::Tab->new() booms on an unsafe CLASS_ON' );
  eval { Web::Reactor::HTML::Tab->new( REO_REACTOR => $APP, CLASS_OFF => q{a<b} ) };
  like( $@, qr/invalid tab CLASS_OFF/, 'HTML::Tab->new() booms on an unsafe CLASS_OFF' );
  eval { $tab->add( 'X', TYPE => 'DIV', HANDLE_CLASS => 'a\\b' ) };
  like( $@, qr/invalid tab HANDLE_CLASS/, 'tab->add() booms on a backslash in HANDLE_CLASS' );

  is( scalar @{ $tab->{ 'TABS_LIST' } }, 2, 'tab keeps a list of its tabs' );

  $tab->finish();
  like( $APP->html_hold_get( 'kit_html' ), qr/reactor_tab_controller[^>]*id='\Q$tab->{ 'TAB_CONTROLLER_ID' }\E'/, 'tab->finish() puts the controller into the kit_html hold' );

  eval { $tab->add( 'X', TYPE => 'DIV' ) };
  like( $@, qr/already finished/, 'tab->add() booms after finish()' );
  my $kit = $APP->html_hold_get( 'kit_html' );
  $tab->finish();
  is( $APP->html_hold_get( 'kit_html' ), $kit, 'a second tab->finish() does nothing' );
  is( $tab->cfg(), $APP->cfg(), 'tab->cfg() is the reactor config' );
  ok( ! exists $tab->{ 'OPT' }{ 'REO_REACTOR' }, 'tab options keep no strong link to the reactor' );
  like( $tab->{ 'TAB_CONTROLLER_ID' }, qr/^RE_TAB_\Q@{[ $APP->get_uniq_id_scope() ]}\E_tabset$/, 'a named tab set id is scope and name' );

  my $un = Web::Reactor::HTML::Tab->new( REO_REACTOR => $APP );
  like( $un->{ 'TAB_CONTROLLER_ID' }, qr/^RE_TAB_\Q@{[ $APP->get_uniq_id_scope() ]}\E\.\d+$/, 'an unnamed tab set id is RE_TAB_ and a uniq id, the scope once' );

  eval { $un->add( 'X', TYPE => 'SPAN' ) };
  like( $@, qr/invalid tab TYPE \[SPAN\]/, 'tab->add() names the invalid TYPE' );

  my ( $uh ) = $un->add( 'A', TYPE => 'DIV', HANDLE_CLASS => 'keep' );
  $un->add( 'B', TYPE => 'DIV' );
  like( $uh, qr/class='keep'/, 'tab->add() puts HANDLE_CLASS on the handle' );
  like( $uh, qr/data-class-keep='keep'/, 'tab->add() marks HANDLE_CLASS to be kept by the switch' );
  like( $uh, qr/ id='/, 'tab->add() writes the handle id lowercase' );
  {
    my $tab3 = Web::Reactor::HTML::Tab->new( REO_REACTOR => $APP, CLASS_ON => 'md:on', CLASS_OFF => 'x/off' );
    my ( $h3 ) = $tab3->add( 'A', TYPE => 'DIV', ON => 1 );
    like( $h3, qr{class='md:on'}, 'tab classes may have : and /' );
    eval { $tab3->add( 'B', TYPE => 'DIV', ON => 1 ) };
    like( $@, qr/already has a tab ON/, 'the second ON add() booms' );
    my ( $h4 ) = $tab3->add( 'C', TYPE => 'DIV' );
    like( $h4, qr/_HANDLE_2'/, 'a failed second ON add() leaves no gap in the tab ids' );
    my ( undef, $t5 ) = $tab3->add( 'D', TYPE => 'DIV', ARGS => "style='color: red'" );
    like( $t5, qr/style='display: none; color: red'/, 'tab->add() merges display none into a style in ARGS' );
    is( scalar( () = $t5 =~ /style=/g ), 1, 'tab->add() hidden tab with a style in ARGS has one style attribute' );
    my ( undef, $t8 ) = $tab3->add( 'F', TYPE => 'DIV', ARGS => 'style=color:red' );
    like( $t8, qr/style='display: none; color:red'/, 'tab->add() merges display none into an unquoted style in ARGS' );
    is( scalar( () = $t8 =~ /style=/g ), 1, 'tab->add() hidden tab with an unquoted style in ARGS has one style attribute' );
    my ( undef, $t6 ) = $tab3->add( 'E', TYPE => 'DIV', ARGS => "data-style='x'" );
    like( $t6, qr/style='display: none;'/, 'tab->add() hidden tab without a style in ARGS gets its own' );
    my $tab4 = Web::Reactor::HTML::Tab->new( REO_REACTOR => $APP );
    my ( $h7 ) = $tab4->add( 'A', TYPE => 'DIV' );
    unlike( $h7, qr/class=/, 'tab->add() without any class emits no empty class attribute' );
  }
  $un->finish();
  like( $APP->html_hold_get( 'kit_html' ), qr/reactor_tab_restore\( "\Q$un->{ 'TAB_CONTROLLER_ID' }\E", "\Q$un->{ 'TABS_LIST' }[ 0 ]\E" \)/, 'without an ON tab the first tab is the default' );
  {
    my $kit0 = $APP->html_hold_get( 'kit_html' );
    Web::Reactor::HTML::Tab->new( REO_REACTOR => $APP )->finish();
    is( $APP->html_hold_get( 'kit_html' ), $kit0, 'tab->finish() with no tabs adds no controller' );
  }
  like( $APP->html_hold_get( 'kit_html' ), qr/reactor_tab_restore\( "\Q$tab->{ 'TAB_CONTROLLER_ID' }\E", "" \)/, 'with an ON tab there is no default tab' );

  {
    package Web::Reactor::TestCoreOnly;
    our @ISA = ( 'Web::Reactor::Core' );
    package main;
    my $core = Web::Reactor::TestCoreOnly->new( make_env(), make_cfg() );
    eval { Web::Reactor::HTML::Tab->new( REO_REACTOR => $core ) };
    like( $@, qr/needs a Web::Reactor::Reflex or Web::Reactor object/, 'HTML::Tab->new() booms on a Core reactor' );
  }
}

##############################################################################
##
##  section 16 -- Web::Reactor::Base
##

{
  my $b = Web::Reactor::Base->new( $APP, { KEY => 'val' } );
  isa_ok( $b, 'Web::Reactor::Base', 'Base->new()' );
  is( $b->reo(), $APP, 'Base->reo()' );
  is( $b->cfg()->{ 'KEY' }, 'val', 'Base->cfg()' );

  eval { Web::Reactor::Base->new( 'not a reactor', {} ) };
  ok( $@, 'Base->new() booms without a reactor object' );

  $b->__lock_self_keys( qw( ONE TWO ) );
  ok( exists $b->{ 'ONE' }, '__lock_self_keys() pre-creates the given keys' );
  eval { $b->{ 'NOPE' } = 1 };
  ok( $@, '__lock_self_keys() locks the object down' );
}

##############################################################################
##
##  section 17 -- distribution files
##

{
  my $dist = dirname( __FILE__ ) . '/..';
  # one file per line, the first field, a description may follow, # lines are comments
  my @manifest = map { ( split /\s+/ )[ 0 ] } grep { /\S/ and ! /^\s*#/ } split /\n/, file_load( "$dist/MANIFEST" );
  my @missing  = grep { ! -e "$dist/$_" } @manifest;
  is_deeply( \@missing, [], 'every MANIFEST file exists' );

  my %listed   = map { $_ => 1 } @manifest;
  my @modules;
  my @dirs = ( "$dist/lib", "$dist/demo" ); # the POD says the demo is in the tarball
  while( my $d = shift @dirs )
    {
    opendir( my $dh, $d ) or die "cannot open [$d]";
    for my $e ( grep { ! /^\./ } readdir $dh )
      {
      my $p = "$d/$e";
      push @dirs, $p if -d $p;
      ( my $rel = $p ) =~ s{^\Q$dist\E/}{};
      push @modules, $rel if $p =~ /\.pm$/ or ( -f $p and $rel =~ m{^demo/} );
      }
    closedir( $dh );
    }
  for my $sub ( [ 'htdocs', qr/^[^.]/ ], [ 't', qr/\.pl$/ ] ) # every htdocs file
    {
    opendir( my $dh, "$dist/$sub->[ 0 ]" ) or die "cannot open [$dist/$sub->[ 0 ]]";
    push @modules, map { "$sub->[ 0 ]/$_" } grep { $_ =~ $sub->[ 1 ] } readdir $dh;
    closedir( $dh );
    }
  my @unlisted = sort grep { ! $listed{ $_ } } @modules;
  is_deeply( \@unlisted, [], 'every module, demo file, htdocs script and test is in MANIFEST' );

  my $mk  = file_load( "$dist/Makefile.PL" );
  my $pod = file_load( "$dist/lib/Web/Reactor.pm" );
  like( $mk, qr/'CryptX'/, 'Makefile.PL requires CryptX (Crypt::PRNG)' );

  # the minimum versions in Makefile.PL are the ones the Web::Reactor POD lists
  for my $m ( qw( Plack Cookie::Baker Data::Tools Exception::Sink ) )
    {
    my ( $mv ) = $mk  =~ /'\Q$m\E'\s*=>\s*'?([\d.]+)/;
    my ( $pv ) = $pod =~ /^\s*\*\s+\Q$m\E\s+([\d.]+)\+/m;
    ok( defined $pv && defined $mv && $mv eq $pv, "Makefile.PL requires $m $pv as the POD says" );
    }
  like( $mk, qr/^\s*test\s*=>\s*\{\s*TESTS\s*=>\s*'t\/\*\.pl'/m, 'Makefile.PL makes "make test" run t/*.pl' );
  like( $mk, qr/^\s*LICENSE\s*=>\s*'gpl_2'/m, 'Makefile.PL sets the license' );
  like( $mk, qr/^\s*AUTHOR\s*=>\s*'\S/m, 'Makefile.PL sets the author' );
  like( $mk, qr/^\s*ABSTRACT_FROM\s*=>\s*'lib\/Web\/Reactor\.pm'/m, 'Makefile.PL takes the abstract from the POD' );
  like( $pod, qr/^=head1 NAME\n\nWeb::Reactor - \S/m, 'the POD NAME line has the "module - abstract" form ABSTRACT_FROM needs' );
  my ( $mp ) = $mk  =~ /MIN_PERL_VERSION\s*=>\s*'([\d.]+)'/;
  my ( $pp ) = $pod =~ /Minimum: Perl ([\d.]+)/;
  require version;
  is( version->parse( $mp )->normal, version->parse( $pp )->normal, 'Makefile.PL minimum perl is the one the POD says' );
}

##############################################################################

done_testing();

##############################################################################
###EOF########################################################################
