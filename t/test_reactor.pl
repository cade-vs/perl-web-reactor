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
##  state cache, args and forwards, params, and the HTML helpers which need
##  a live reactor.
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
use Data::Tools;
use Data::Dumper;

my $VERBOSE = grep { $_ eq '-v' or $_ eq '--verbose' } @ARGV;

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
                Web::Reactor::Sessions::Dummy
                Web::Reactor::HTML::Utils
                Web::Reactor::HTML::Layout
                Web::Reactor::HTML::Form
                Web::Reactor::HTML::FormEngine
                Web::Reactor::HTML::Tab
                );

require_ok( $_ ) for @MODULES;

Web::Reactor::HTML::Utils->import();
Web::Reactor::HTML::Layout->import();
Web::Reactor::HTML::FormEngine->import();

ok( $Web::Reactor::VERSION, "Web::Reactor::VERSION is set [$Web::Reactor::VERSION]" );

isa_ok( 'Web::Reactor',                       'Web::Reactor::Reflex',       'Web::Reactor'         );
isa_ok( 'Web::Reactor::Reflex',               'Web::Reactor::Core',         'Reflex'               );
isa_ok( 'Web::Reactor::Sessions::Filesystem', 'Web::Reactor::Sessions',     'Sessions::Filesystem' );
isa_ok( 'Web::Reactor::Sessions::Dummy',      'Web::Reactor::Sessions',     'Sessions::Dummy'      );
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

# a plain Web::Reactor (not the test subclass) after a full request, for code
# which checks the exact class
sub plain_reo
{
  my %opt = @_;

  my %env;
  $env{ 'QUERY_STRING' } = $opt{ 'QS' } if defined $opt{ 'QS' };

  my $r = Web::Reactor->new( make_env( %env ), make_cfg() );
  $r->run();

  return $r;
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
ok( $@, '_split_dir_components() dies on a too short id' );

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
  ok( $@, 'create() dies on an invalid type' );
  eval { $ses->create( 'USER', undef, 3 ) };
  ok( $@, 'create() dies on a too short length' );
  eval { $ses->create( 'PAGE' ) };
  ok( $@, 'create() dies for PAGE without a parent sid' );
}

# abstract base class must refuse to work on its own
{
  for my $m ( qw( _storage_create _storage_load _storage_save _storage_exists _storage_delete _storage_debug_info ) )
    {
    my $sub = \&{ "Web::Reactor::Sessions::$m" };
    eval { $sub->() };
    like( $@, qr/is not implemented/, "Sessions::$m() is an abstract stub" );
    }
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
  my $mark = scalar @LOG;

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

  my ( $r2 ) = request( COOKIE => $after_c );
  is( $r2->get_user_session_id(), $before_u, 'the new cookie reaches the logged-in user session' );
  is( $r2->is_logged_in(), 1, 'the new cookie is logged in' );

  my ( $r3 ) = request( COOKIE => $before_c );
  isnt( $r3->get_user_session_id(), $before_u, 'the pre-login cookie does not reach the logged-in session' );
  is( $r3->is_logged_in(), 0, 'the pre-login cookie is not logged in' );

  # user hold
  my ( $r4 ) = request( COOKIE => $after_c, HOOK => sub
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
  my ( $r6 ) = request( HOOK => sub { $_[0]->login( 'joe@example.com' ); is( $_[0]->get_user_hold()->{ 'PREF' }, 'dark', 'user hold is shared between logins of the same ident' ) } );

  # an anonymous session has no hold
  my ( $r7 ) = request( HOOK => sub { is( $_[0]->get_user_hold(), undef, 'get_user_hold() is undef when not logged in' ) } );

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
  my ( $r10 ) = request( HOOK => sub
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
  my ( $r ) = request( COOKIE => $COOKIE, HOOK => sub
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

  my ( $r1 ) = request( COOKIE => $COOKIE, HOOK => sub { $caller = $_[0]->get_page_session_id(); $new_link = $_[0]->args_new( _PN => 'other' ) } );
  my ( $r2 ) = request( COOKIE => $COOKIE, QS => "_=$new_link", HOOK => sub
    {
    my $reo = shift;
    $callee = $reo->get_page_session_id();
    is( $reo->get_ref_page_session_id(), $caller, 'args_new() target knows its caller' );
    is( $reo->get_page_session_id( 1 ), $caller, 'get_page_session_id( 1 ) is the caller' );
    is( $reo->get_page_session( 1 )->{ ':PAGE_NAME' }, 'main', 'get_page_session( 1 ) loads the caller page session' );
    $back_link = $reo->args_back();
    } );

  isnt( $callee, $caller, 'args_new() opens a new page session' );

  my ( $r3 ) = request( COOKIE => $COOKIE, QS => "_=$back_link" );
  is( $r3->get_page_session_id(), $caller, 'args_back() returns to the caller page session' );

  # a referrer which cannot be loaded is cut from the chain
  my ( $r4 ) = request( COOKIE => $COOKIE, QS => "_=$new_link", HOOK => sub
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
  my ( $r ) = request( COOKIE => $COOKIE, QS => 'AA=1&BB=2&BB=3', HOOK => sub
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
  my ( $r1 ) = request( COOKIE => $COOKIE, QS => 'KEEP=me', HOOK => sub { $_[0]->param_unsafe( 'KEEP' ); $here = $_[0]->args_here() } );
  my ( $r2 ) = request( COOKIE => $COOKIE, QS => "_=$here", HOOK => sub { is( $_[0]->param_unsafe( 'KEEP' ), 'me', 'param cache survives into the next request of the page' ) } );
}

# buttons
{
  my ( $r ) = request( COOKIE => $COOKIE, QS => 'BUTTON%3ASAVE=x', HOOK => sub
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
  like( $tree, qr/<table id=FTREE_TABLE_\d+/, 'html_ftree() builds a table' );
  like( $tree, qr/one/,    'html_ftree() renders leaves'   );
  like( $tree, qr/group/,  'html_ftree() renders labels'   );
  like( $tree, qr/ftree_click/, 'html_ftree() wires the branch toggle' );
  like( $tree, qr/display: none/, 'html_ftree() hides collapsed branches' );

  ok( defined &html_ctable, 'html_ctable() is exported' );

  like( html_debug( { A => 1 } ), qr/<xmp>.*'A' => 1.*<\/xmp>/s, 'html_debug() dumps its arguments' );

  my $al = html_alink( $APP, 'here', 'CLICK', { CLASS => 'btn' }, X => 1 );
  like( $al, qr/^<a href=\?_=[A-Za-z0-9]+\.[A-Za-z0-9]+/, 'html_alink() builds a reactor link' );
  like( $al, qr/>CLICK<\/a>$/, 'html_alink() wraps the value' );
  like( $al, qr/class='btn'/,  'html_alink() honours CLASS' );
  unlike( $al, qr/ID=/, 'html_alink() emits no ID without one' );
  unlike( html_alink( $APP, 'here', 'C', {} ), qr/class=|ID=/, 'html_alink() emits no empty class or ID' );

  like( html_alink( $APP, 'here', 'C', { CONFIRM => 'sure?' } ), qr/confirm\('sure\?'\)/, 'html_alink() CONFIRM' );
  like( html_alink( $APP, 'here', 'C', { DISABLED => 1 } ), qr/disabled-button/, 'html_alink() DISABLED' );

  # in scalar context the layers go into the KIT_HTML hold, see
  # Web::Reactor::Reflex::html_hold_kit_add()
  {
    my $hl = html_alink( $APP, 'here', 'C', { HINT => 'go' } );
    like( $hl, qr/reactor_hover_show_delay/, 'html_alink() HINT adds a hover layer' );
    my $ps = html_popup_layer( $APP, VALUE => 'accumulated popup' );
    like( $ps, qr/data-popup-layer-id=/, 'html_popup_layer() scalar context returns the handle' );
    my $hs = html_hover_layer( $APP, VALUE => 'accumulated hover' );
    like( $hs, qr/reactor_hover_show_delay/, 'html_hover_layer() scalar context returns the handle' );

    my $kit = $APP->html_hold_get( 'kit_html' );
    like( $kit, qr/>go</,                'html_alink() HINT layer goes into the kit_html hold' );
    like( $kit, qr/accumulated popup/,   'html_popup_layer() scalar context layer goes into the kit_html hold' );
    like( $kit, qr/accumulated hover/,   'html_hover_layer() scalar context layer goes into the kit_html hold' );
  }

  my ( $ph, $pt ) = html_popup_layer( $APP, VALUE => 'popup text' );
  like( $ph, qr/data-popup-layer-id="R_POPUP_LAYER_/, 'html_popup_layer() handle carries the layer id' );
  like( $ph, qr/onClick=/, 'html_popup_layer() CLICK trigger by default' );
  like( $pt, qr/popup text/, 'html_popup_layer() layer carries the value' );
  like( $pt, qr/class='popup-layer'/, 'html_popup_layer() default class' );

  my ( $ch ) = html_popup_layer( $APP, VALUE => 'x', TYPE => 'CONTEXT' );
  like( $ch, qr/onContextMenu/i, 'html_popup_layer() CONTEXT trigger' );

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
  like( $tabs, qr/L2/, 'html_tabs_table() renders the second label' );
  like( $tabs, qr/T1/, 'html_tabs_table() renders the first tab'    );
  like( $tabs, qr/reactor_tab_activate_id/, 'html_tabs_table() wires the tab handler' );

  my $vtabs = html_tabs_table( $APP, [ { LABEL => 'L', TEXT => 'T' } ], VERTICAL => 1 );
  like( $vtabs, qr/WIDTH=50%/, 'html_tabs_table() vertical layout' );
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

  like( html_layout_hbox( [ 'a', 'b' ] ), qr/valign=top/, 'html_layout_hbox()' );
  like( html_layout_vbox( [ 'a', 'b' ] ), qr/(<tr.*){2}/s, 'html_layout_vbox() stacks rows' );

  my $hf = html_layout_hbox_flex( \'1,2', 'left', 'right' );
  like( $hf, qr/display: flex/, 'html_layout_hbox_flex() uses flex' );
  like( $hf, qr/flex:1;/, 'html_layout_hbox_flex() applies the first weight'  );
  like( $hf, qr/flex:2;/, 'html_layout_hbox_flex() applies the second weight' );

  like( html_layout_2lr( 'L', 'R' ), qr/L/, 'html_layout_2lr() renders the left side'  );
  like( html_layout_2lr( 'L', 'R' ), qr/R/, 'html_layout_2lr() renders the right side' );
  like( html_layout_2lr_flex( 'L', 'R' ), qr/display:\s*flex/, 'html_layout_2lr_flex() uses flex' );

  my $hb = html_hbox( 'ctl:<10,70 x3,20', 'a', 'b', 'c' );
  like( $hb, qr/flex-direction: row/, 'html_hbox() is a row' );
  like( $hb, qr/class='ctl'/, 'html_hbox() applies the class from the format' );
  like( $hb, qr/text-align: left/, 'html_hbox() applies the "<" alignment' );
  is( scalar( () = $hb =~ /<div [^>]*style='flex/g ), 3, 'html_hbox() emits one cell per value' );

  like( html_vbox( 'a,b', '1', '2' ), qr/flex-direction: column/, 'html_vbox() is a column' );
  like( html_hbox( 'n,w,p', '1', '2', '3' ), qr/white-space: nowrap/, 'box format: n means nowrap' );
  like( html_hbox( '=', '1' ), qr/flex: 1000/, 'box format: = means take all the room' );
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
  like( $APP->html_hold_get( 'kit_head' ), qr{src='js/reactor\.js'}, 'HTML::Tab->new() adds reactor.js to the kit_head hold' );

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

  is( scalar @{ $tab->{ 'TABS_LIST' } }, 2, 'tab keeps a list of its tabs' );

  $tab->finish();
  like( $APP->html_hold_get( 'kit_html' ), qr/reactor_tab_controller[^>]*id='\Q$tab->{ 'TAB_CONTROLLER_ID' }\E'/, 'tab->finish() puts the controller into the kit_html hold' );
}

##############################################################################
##
##  section 16 -- HTML::FormEngine
##

{
  my $form_def = [
                 { NAME => 'name',  TYPE => 'STRING', LABEL => 'Name'  },
                 { NAME => 'age',   TYPE => 'STRING', LABEL => 'Age', RE => '^\d+$', RE_HELP => 'digits only' },
                 { NAME => 'note',  TYPE => 'TEXT',   LABEL => 'Note'  },
                 { NAME => 'ok',    TYPE => 'CB',     LABEL => 'Ok'    },
                 { NAME => 'go',    TYPE => 'BUTTON', LABEL => '', VALUE => 'Go' },
                 ];

  # the form engine accepts Web::Reactor and its subclasses
  {
    my ( $sub ) = request( COOKIE => $COOKIE, QS => 'NAME=cade' );
    my ( $sd ) = html_form_engine_import_input( $sub, $form_def, NAME => 'F' );
    is( $sd->{ 'NAME' }, 'cade', 'form engine accepts a Web::Reactor subclass' );
  }

  my $r = plain_reo( QS => 'NAME=cade&AGE=42&NOTE=hi' );

  my ( $data, $errors ) = html_form_engine_import_input( $r, $form_def, NAME => 'F' );
  is( $data->{ 'NAME' }, 'cade', 'form engine imported a plain field' );
  is( $data->{ 'AGE' },  '42',   'form engine imported a field matching its RE' );
  is( $errors, undef, 'form engine reported no errors' );

  my $r2 = plain_reo( QS => 'NAME=cade&AGE=old' );
  my ( $d2, $e2 ) = html_form_engine_import_input( $r2, $form_def, NAME => 'F' );
  is( $e2->{ 'AGE' }, 1, 'form engine flags a field failing its RE' );
  ok( ! exists $d2->{ 'AGE' }, 'form engine drops the invalid value' );
  is( $r2->get_page_session()->{ 'FORM_INPUT_DATA' }{ 'F' }{ 'NAME' }, 'cade',
      'form engine caches imported data in the page session' );

  eval { html_form_engine_import_input( 'not a reactor', $form_def ) };
  ok( $@, 'html_form_engine_import_input() booms without a reactor object' );
  eval { html_form_engine_display( $APP, 'not an arrayref' ) };
  ok( $@, 'html_form_engine_display() booms on a bad form definition' );

  # new_form() is broken (see the TODO in the HTML::Form section), so the
  # display is checked with a form object made directly
  {
    no warnings 'redefine';
    local *Web::Reactor::TestReactor::new_form = sub { my $reo = shift; return Web::Reactor::HTML::Form->new( $reo, $reo->cfg() ) };
    my ( $rd ) = request( COOKIE => $COOKIE );
    my $html = html_form_engine_display( $rd, [ { NAME => 'a', TYPE => 'STRING', LABEL => 'A' } ], NAME => 'F' );
    like( $html, qr{<table border=0><tr><td align=right>A</td>}, 'html_form_engine_display() opens each row with <tr>' );
    unlike( $html, qr{<table border=0></tr>}, 'html_form_engine_display() does not start a row with </tr>' );
  }
}

##############################################################################
##
##  section 17 -- alternate session backend
##

{
  my $d = make_reo( make_env(), make_cfg( REO_SES_CLASS => 'Web::Reactor::Sessions::Dummy' ) );
  isa_ok( $d->__ses, 'Web::Reactor::Sessions::Dummy', 'REO_SES_CLASS override' );

  is( $d->__ses->_storage_load(), undef, 'Dummy _storage_load() finds nothing' );
  is( $d->__ses->_storage_create(), 1, 'Dummy _storage_create()' );
  is( $d->__ses->_storage_save(),   1, 'Dummy _storage_save()'   );
  is( $d->__ses->_storage_exists(), 0, 'Dummy _storage_exists() is always false' );
  like( $d->__ses->_storage_debug_info(), qr/Dummy/, 'Dummy _storage_debug_info()' );
  is( $d->__ses->_storage_delete(), 1, 'Dummy _storage_delete()' );

  my $res = $d->run();
  is( $res->[0], 200, 'a full request cycle runs on the Dummy backend' );

  my ( $d2, $res2 ) = request( COOKIE => cookie_of( $res ), CFG => { REO_SES_CLASS => 'Web::Reactor::Sessions::Dummy' } );
  unlike( body( $res2 ), qr/currently unavailable/, 'a returning cookie works on the Dummy backend' );
  isnt( cookie_of( $res2 ), undef, 'a returning cookie gets a new session on the Dummy backend' );
}

##############################################################################
##
##  section 18 -- Web::Reactor::Base
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

done_testing();

##############################################################################
###EOF########################################################################
