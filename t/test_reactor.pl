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
##  single-file test utility for the whole Web::Reactor stack
##
##  usage:
##
##    cd t && perl test_all.pl          -- run, TAP output on stdout
##    perl t/test_all.pl                -- same, from the distribution root
##    perl t/test_all.pl -v             -- also pass reactor log() to stderr
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
use Data::Dumper;

##############################################################################
##
##  section 1 -- loading all modules
##

my @MODULES = qw(
                Web::Reactor
                Web::Reactor::Base
                Web::Reactor::Utils
                Web::Reactor::Actions
                Web::Reactor::Actions::Native
                Web::Reactor::Actions::Alt
                Web::Reactor::Preprocessor
                Web::Reactor::Preprocessor::Native
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

ok( $Web::Reactor::VERSION,                     "Web::Reactor::VERSION is set [$Web::Reactor::VERSION]" );
is( $Web::Reactor::HTML::Form::VERSION, $Web::Reactor::VERSION, 'HTML::Form version matches Web::Reactor version' );

isa_ok( 'Web::Reactor::Sessions::Filesystem', 'Web::Reactor::Sessions',    'Sessions::Filesystem' );
isa_ok( 'Web::Reactor::Sessions::Dummy',      'Web::Reactor::Sessions',    'Sessions::Dummy'      );
isa_ok( 'Web::Reactor::Sessions',             'Web::Reactor::Base',        'Sessions'             );
isa_ok( 'Web::Reactor::Actions::Native',      'Web::Reactor::Actions',     'Actions::Native'      );
isa_ok( 'Web::Reactor::Actions::Alt',         'Web::Reactor::Actions',     'Actions::Alt'         );
isa_ok( 'Web::Reactor::Preprocessor::Native', 'Web::Reactor::Preprocessor','Preprocessor::Native' );
isa_ok( 'Web::Reactor::HTML::Form',           'Web::Reactor::Base',        'HTML::Form'           );

##############################################################################
##
##  section 2 -- quiet down (and capture) the reactor log
##

my $VERBOSE = grep { $_ eq '-v' or $_ eq '--verbose' } @ARGV;
my @LOG;

{
  no strict 'refs';
  no warnings 'redefine';
  *Web::Reactor::log = sub
    {
    my $self = shift;
    my $msg  = join '', @_;
    push @LOG, $msg;
    print STDERR "$msg\n" if $VERBOSE;
    };
}

# returns the set-cookie header value for the given cookie name
sub cookie_of
{
  my $res  = shift;
  my $name = shift;

  my @h = @{ $res->[1] };
  for( my $i = 0; $i < @h; $i += 2 )
    {
    next unless $h[ $i ] eq 'set-cookie';
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

##############################################################################
##
##  section 3 -- throw-away application tree
##

my $APP_ROOT = tempdir( 'web-reactor-test-XXXXXX', TMPDIR => 1, CLEANUP => 1 );

make_path( "$APP_ROOT/$_" ) for qw(
                                  var
                                  html/default
                                  html/bg
                                  lib/Web/Reactor/Actions/wrtest
                                  actions
                                  trans/en
                                  );

sub write_file
{
  my $name = shift;
  my $text = shift;

  open( my $fh, '>', "$APP_ROOT/$name" ) or die "cannot write [$APP_ROOT/$name]: $!";
  print $fh $text;
  close $fh;
}

write_file( 'html/default/page_main.html',   'MAIN[<$greet>][<&hello>][<#part>]' );
write_file( 'html/default/page_other.html',  'OTHER' );
write_file( 'html/default/page_defer.html',  'DEFER[<$$late>]' );
write_file( 'html/default/page_trans.html',  'T:<~apple> B:[~pear]' );
write_file( 'html/default/page_link.html',   '<a reactor_new_href=?_pn=other>go</a>' );
write_file( 'html/default/part.html',        'PART' );
write_file( 'html/default/selfref.html',     '<#selfref>' );
write_file( 'html/bg/page_other.html',       'DRUGO' );

write_file( 'lib/Web/Reactor/Actions/wrtest/hello.pm', <<'ACT' );
package Web::Reactor::Actions::wrtest::hello;
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

write_file( 'lib/Web/Reactor/Actions/wrtest/broken.pm', <<'ACT' );
package Web::Reactor::Actions::wrtest::broken;
use strict;

sub main { die "this action always dies\n"; }

1;
ACT

write_file( 'actions/altact.pm', <<'ACT' );
package reactor::actions::altact;
use strict;

sub main { return 'ALT-OK'; }

1;
ACT

write_file( 'trans/en/main.tr', "apple=jabalka\npear=krusha\n" );

##############################################################################
##
##  section 4 -- environment / config helpers
##

my $ENCRYPT_KEY = 'wr-test-key-0123456789-abcdefghi'; # 32 chars, a valid AES key

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
         'SCRIPT_NAME'      => '',
         'PATH_INFO'        => '/',
         'psgi.url_scheme'  => 'https',
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
         HTML_DIRS    => [ "$APP_ROOT/html/default" ],
         LIB_DIRS     => [ "$APP_ROOT/lib" ],
         ACTIONS_SETS => [ 'wrtest', 'Core' ],
         ENCRYPT_KEY  => $ENCRYPT_KEY,
         DEBUG        => 0,
         %over,
         };
}

sub make_reo
{
  my $env = shift || make_env();
  my $cfg = shift || make_cfg();

  return Web::Reactor->new( $env, $cfg );
}

##############################################################################
##
##  section 5 -- construction and module attachment
##

my $reo = make_reo();

isa_ok( $reo, 'Web::Reactor', 'reactor object' );

isa_ok( $reo->ses, 'Web::Reactor::Sessions::Filesystem',    'default ses() backend' );
isa_ok( $reo->pre, 'Web::Reactor::Preprocessor::Native',    'default pre() backend' );
isa_ok( $reo->act, 'Web::Reactor::Actions::Native',         'default act() backend' );

is( $reo->get_app_name(), 'wrtest',   'get_app_name()' );
is( $reo->get_app_root(), $APP_ROOT,  'get_app_root()' );
is( $reo->get_lang(),     undef,      'get_lang() undef when not configured' );
is( $reo->cfg()->{ 'APP_CHARSET' }, 'UTF-8', 'APP_CHARSET defaults to UTF-8' );

is( $reo->get_request_scheme(), 'https', 'get_request_scheme()' );
is( $reo->get_request_method(), 'GET',   'get_request_method()' );
is( $reo->get_request_uri(),    '/app/', 'get_request_uri()'    );
is( $reo->get_client_ip(),      '10.0.0.1', 'get_client_ip() falls back to REMOTE_ADDR' );

is( $reo->get_http_env()->{ '_CLIENT_IP' }, '10.0.0.1', 'ENV _CLIENT_IP filled in by new()' );

is( $reo->get_header( 'http_user_agent' ), 'Web-Reactor-Test/1.0', 'get_header()' );
ok( ! exists $reo->get_headers()->{ 'remote_addr' }, 'get_headers() only exposes HTTP_/SSL_ keys' );

is( $reo->is_debug(), 0, 'is_debug() off by default' );
is( $reo->set_debug( 2 ), 2, 'set_debug() returns level' );
is( $reo->is_debug(), 2, 'is_debug() reflects set_debug()' );
$reo->set_debug( 0 );

# client ip preference order
{
  my $cf = make_reo( make_env( 'HTTP_CF_CONNECTING_IP' => '9.9.9.9', 'HTTP_X_REAL_IP' => '8.8.8.8' ) );
  is( $cf->get_client_ip(), '9.9.9.9', 'get_client_ip() prefers HTTP_CF_CONNECTING_IP' );
}

# http scheme must be rejected unless cookies security is explicitly disabled
{
  my $err = '';
  eval { make_reo( make_env( 'REQUEST_SCHEME' => 'http', 'psgi.url_scheme' => 'http' ) ) };
  $err = $@;
  ok( $err, 'plain http request refused while secure cookies are required' );

  my $ok = eval { make_reo( make_env( 'REQUEST_SCHEME' => 'http', 'psgi.url_scheme' => 'http' ),
                            make_cfg( DISABLE_SECURE_COOKIES => 1 ) ) };
  isa_ok( $ok, 'Web::Reactor', 'plain http accepted with DISABLE_SECURE_COOKIES' );
}

# missing or empty APP_NAME is fatal at construction (checked in Reflex::new)
{
  for my $bad ( undef, '', 'bad name', 'Upper' )
    {
    eval { make_reo( make_env(), make_cfg( APP_NAME => $bad ) ) };
    like( $@, qr/invalid APP_NAME/, 'new() booms on APP_NAME [' . ( $bad // 'undef' ) . ']' );
    }
}

##############################################################################
##
##  section 6 -- cookies
##

{
  my $ck = make_reo( make_env( 'HTTP_COOKIE' => 'aaa=111; bbb=222' ) );
  is( $ck->get_cookie( 'aaa' ), '111', 'get_cookie() first cookie'  );
  is( $ck->get_cookie( 'bbb' ), '222', 'get_cookie() second cookie' );
  is_deeply( [ sort keys %{ $ck->get_cookies() } ], [ qw( aaa bbb ) ], 'get_cookies()' );
}

##############################################################################
##
##  section 7 -- session storage api (Filesystem backend)
##

my $ses = $reo->ses;

{
  my $id1 = $ses->create_id( 16 );
  my $id2 = $ses->create_id( 16 );

  is( length( $id1 ), 16, 'create_id() honours requested length' );
  isnt( $id1, $id2, 'create_id() returns different ids' );
  like( $id1, qr/^[A-Za-z0-9]+$/, 'create_id() is alphanumeric' );
  is( length( $ses->create_id() ), 73, 'create_id() default length is 73' );
  is( length( $ses->create_id( 8, 'ab' ) ), 8, 'create_id() with custom letter set' );
  like( $ses->create_id( 20, 'ab' ), qr/^[ab]{20}$/, 'create_id() uses only given letters' );
}

{
  # USER type is not namespaced under the current user session
  is_deeply( [ $ses->compose_key_from_id( 'USER', 'abc' ) ], [ 'USER', 'abc' ], 'compose_key_from_id() USER' );
  is_deeply( [ $ses->compose_key_from_id( 'HOLD', 'abc' ) ], [ 'HOLD', 'abc' ], 'compose_key_from_id() HOLD' );

  eval { $ses->compose_key_from_id( 'bad type', 'abc' ) };
  ok( $@, 'compose_key_from_id() booms on non-alphanumeric type' );

  # everything else needs a user session id in place
  eval { $ses->compose_key_from_id( 'PAGE', 'abc' ) };
  ok( $@, 'compose_key_from_id() booms for PAGE without a user session' );
}

is( $ses->_split_dir_components( '1234567890', 3, 3 ), '123/456/789/1234567890', '_split_dir_components()' );
eval { $ses->_split_dir_components( '123', 3, 3 ) };
ok( $@, '_split_dir_components() dies when parts do not fit' );

like( $ses->_key_to_fn( { READONLY => 1 }, 'USER', '1234567890' ),
      qr{^\Q$APP_ROOT\E/var/USER/12/34/1234567890\.wrs$},
      '_key_to_fn() builds the split path' );

eval { $ses->_key_to_fn( {}, 'lower', 'abc' ) };
ok( $@, '_key_to_fn() booms on invalid type component' );
eval { $ses->_key_to_fn( {}, 'USER', 'bad/id' ) };
ok( $@, '_key_to_fn() booms on invalid id component' );

{
  my $id = $ses->create( 'USER', 24 );

  ok( $id, "ses->create() returned an id [$id]" );
  is( length( $id ), 24, 'ses->create() honours length' );
  ok( $ses->exists( 'USER', $id ), 'ses->exists() true after create' );
  # a freshly created session is an empty file, Storable cannot retrieve it
  is( $ses->load( 'USER', $id ), undef, 'ses->load() of a not yet saved session returns undef' );

  ok( $ses->save( 'USER', $id, { A => 1, B => [ 2, 3 ] } ), 'ses->save()' );
  is_deeply( $ses->load( 'USER', $id ), { A => 1, B => [ 2, 3 ] }, 'ses->load() returns saved structure' );

  is( $ses->load( 'USER', undef ), undef, 'ses->load() undef id returns undef' );
  is( $ses->save( 'USER', undef, {} ), 0, 'ses->save() undef id returns 0' );
  is( $ses->exists( 'USER', undef ), 0, 'ses->exists() undef id returns 0' );
  is( $ses->delete( 'USER', undef ), 0, 'ses->delete() undef id returns 0' );

  ok( ! $ses->exists( 'USER', 'NoSuchSessionIdAtAll' ), 'ses->exists() false for unknown id' );

  {
    local $TODO = 'Sessions::Filesystem does not implement _storage_delete()';
    my $rc = eval { $ses->delete( 'USER', $id ) };
    ok( $rc && ! $ses->exists( 'USER', $id ), 'ses->delete() removes the session' );
  }

  eval { $ses->create( 'bad type', 8 ) };
  ok( $@, 'ses->create() dies on invalid type' );
  is( length( $ses->create( 'USER', 0 ) ), 73, 'ses->create() falls back to the default length' );
  eval { $ses->create( 'USER', -1 ) };
  ok( $@, 'ses->create() dies on a negative length' );
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

##############################################################################
##
##  section 8 -- a complete request cycle through run()
##

my ( $usid, $psid, $cookie_name );

{
  my $mark = scalar @LOG;

  my $r   = make_reo();
  my $res = $r->run();

  is( ref( $res ), 'ARRAY', 'run() returns a PSGI triplet' );
  is( $res->[0], 200, 'run() status is 200' );
  is( ref( $res->[1] ), 'ARRAY', 'run() headers is an arrayref' );
  is( ref( $res->[2] ), 'ARRAY', 'run() body is an arrayref' );

  my %h = @{ $res->[1] };
  like( $h{ 'content-type' }, qr{^text/html}, 'content-type is text/html' );
  like( $h{ 'content-type' }, qr{charset=UTF-8}, 'content-type carries the app charset' );
  ok( exists $h{ 'set-cookie' }, 'a session cookie is issued' );
  like( $h{ 'set-cookie' }, qr/^wrtest_cookie=/, 'cookie is named after APP_NAME' );
  like( $h{ 'set-cookie' }, qr/HttpOnly/, 'cookie is HttpOnly' );
  like( $h{ 'set-cookie' }, qr/secure/i,  'cookie is secure' );
  like( $h{ 'set-cookie' }, qr/SameSite=Lax/i, 'cookie is SameSite=Lax' );

  is( $res->[2][0], 'MAIN[][HELLO][PART]', 'page rendered: content var, action tag and include' );

  ok( log_since( $mark, qr/creating new user session/ ), 'new user session logged' );
  ok( log_since( $mark, qr/new page session created/  ), 'new page session logged' );

  $usid = $r->get_user_session_id();
  $psid = $r->get_page_session_id();

  ok( $usid, "user session id created [$usid]" );
  ok( $psid, "page session id created [$psid]" );
  is( length( $usid ), 73, 'user session id has the default length' );
  is( length( $psid ),  8, 'page session id is 8 chars' );

  ok( -e "$APP_ROOT/var/USER/" . substr( $usid, 0, 2 ) . '/' . substr( $usid, 2, 2 ) . "/$usid.wrs",
      'user session persisted on disk' );
}

# second request: cookie carries the user session, link session carries safe input
{
  my $r1   = make_reo();
  $r1->run();
  my $sid1 = $r1->get_user_session_id();
  my $pid1 = $r1->get_page_session_id();
  my $link = $r1->args_here( COLOUR => 'red', _PN => 'other' );
  $r1->save();

  like( $link, qr/^[A-Za-z0-9]+\.[A-Za-z0-9]+$/, 'args() returns "link-sid.link-key"' );

  my $r2  = make_reo( make_env( 'HTTP_COOKIE' => "wrtest_cookie=$sid1", 'QUERY_STRING' => "_=$link" ) );
  my $res = $r2->run();

  is( $r2->get_user_session_id(), $sid1, 'user session restored from cookie' );
  is( $r2->get_page_session_id(), $pid1, 'page session restored from the link session (_P)' );
  is( $r2->get_safe_input()->{ 'COLOUR' }, 'red', 'safe input arrives through the link session' );
  is( $r2->get_safe_input()->{ '_PN' }, 'other', 'page name arrives as safe input' );
  is( $res->[2][0], 'OTHER', 'requested page rendered' );

  # a forged/unknown link session must simply be ignored
  my $mark = scalar @LOG;
  my $r3   = make_reo( make_env( 'HTTP_COOKIE' => "wrtest_cookie=$sid1", 'QUERY_STRING' => '_=not a link' ) );
  $r3->run();
  is_deeply( $r3->get_safe_input(), {}, 'malformed link session yields empty safe input' );
  ok( log_since( $mark, qr/invalid safe input link session/ ), 'malformed link session is logged' );

  # an unknown cookie must start a fresh session, not resurrect anything
  $mark = scalar @LOG;
  my $r4 = make_reo( make_env( 'HTTP_COOKIE' => 'wrtest_cookie=NoSuchUserSessionId' ) );
  $r4->run();
  isnt( $r4->get_user_session_id(), 'NoSuchUserSessionId', 'unknown cookie gets a brand new session' );
  ok( log_since( $mark, qr/invalid user session/ ), 'unknown user session is logged' );
}

# user agent / ip fingerprint change closes the session
{
  my $r1 = make_reo();
  $r1->run();
  my $sid = $r1->get_user_session_id();

  my $mark = scalar @LOG;
  my $r2  = make_reo( make_env( 'HTTP_COOKIE' => "wrtest_cookie=$sid", 'HTTP_USER_AGENT' => 'Somebody-Else/9' ) );
  my $res = $r2->run();

  ok( log_since( $mark, qr/session parameter \[HTTP_USER_AGENT\] check failed/ ), 'session hijack check logged' );
  is( $r2->ses->load( 'USER', $sid )->{ ':CLOSED' }, 1, 'changed user agent closes the old user session' );
  unlike( cookie_of( $res, 'wrtest_cookie' ), qr/\Q$sid\E/, 'a different session id is handed out in the cookie' );
}

# expired session
{
  my $r1 = make_reo();
  $r1->run();
  my $sid = $r1->get_user_session_id();
  my $shr = $r1->ses->load( 'USER', $sid );
  $shr->{ ':LOGGED_IN' } = 1;
  $shr->{ ':XTIME'     } = time() - 10;
  $r1->ses->save( 'USER', $sid, $shr );

  my $mark = scalar @LOG;
  my $r2  = make_reo( make_env( 'HTTP_COOKIE' => "wrtest_cookie=$sid" ) );
  my $res = $r2->run();

  ok( log_since( $mark, qr/user session expired or closed/ ), 'session expiry logged' );
  is( $r2->get_user_session()->{ ':CLOSED' }, 1, 'expired session is marked closed' );
  unlike( cookie_of( $res, 'wrtest_cookie' ), qr/\Q$sid\E/, 'an expired session gets a new cookie' );
}

##############################################################################
##
##  section 9 -- a live reactor to exercise the rest of the api
##

my $app = make_reo();
$app->run();

##############################################################################
##
##  section 10 -- user session, login, logout, expiry
##

{
  isa_ok( $app->get_user_session(), 'HASH', 'get_user_session()' );
  is( $app->get_user_session()->{ ':ID' }, $app->get_user_session_id(), 'user session carries its own :ID' );
  ok( $app->get_user_session()->{ ':CTIME' } > 0, 'user session has a creation time' );
  is( $app->get_user_session_agent(), 'Web-Reactor-Test/1.0', 'get_user_session_agent()' );

  is( $app->is_logged_in(), 0, 'is_logged_in() false before login' );

  my $before = $app->get_user_session_id();
  $app->login( 'joe@example.com' );

  is( $app->is_logged_in(), 1, 'is_logged_in() true after login' );
  isnt( $app->get_user_session_id(), $before, 'login() rotates the user session id' );
  is( $app->get_user_session()->{ ':ID' }, $app->get_user_session_id(), 'rotated session carries the new :ID' );
  is( $app->get_user_session()->{ ':USER_IDENT_S' }, 'joe_example_com', 'login() stores a readable user ident' );
  ok( $app->get_user_session()->{ ':USER_IDENT' } =~ /^[0-9a-f]+$/i, 'login() stores a hex encoded user ident' );
  ok( $app->get_user_session()->{ ':LTIME' } > 0, 'login() stores a login time' );

  my $old = $app->ses->load( 'USER', $before );
  is( $old->{ ':CLOSED' }, 1, 'login() closes the pre-login session in storage' );

  isa_ok( $app->get_user_hold(), 'HASH', 'get_user_hold()' );
  $app->get_user_hold()->{ 'PREF' } = 'dark';
  $app->save();
  is( $app->get_user_hold()->{ 'PREF' }, 'dark', 'user hold data survives save()' );

  ok( $app->get_user_session_expire_time() > time(), 'get_user_session_expire_time()' );
  $app->set_user_session_expire_time_in( 1234 );
  my $in = $app->get_user_session_expire_time_in();
  ok( $in > 1200 && $in <= 1234, "get_user_session_expire_time_in() [$in]" );

  $app->set_user_session_expire_time( time() - 1 );
  is( $app->get_user_session_expire_time_in(), undef, 'expired session reports undef time-left' );
  $app->set_user_session_expire_time_in( 3600 );

  $app->logout();
  is( $app->is_logged_in(), 0, 'is_logged_in() false after logout' );
  is( $app->get_user_session()->{ ':CLOSED' }, 1, 'logout() closes the session' );
  ok( $app->get_user_session()->{ ':ETIME' } > 0, 'logout() stores a logout time' );
}

##############################################################################
##
##  section 11 -- page / link sessions and args
##

{
  isa_ok( $app->get_page_session(), 'HASH', 'get_page_session()' );
  is( $app->get_page_session()->{ ':ID' }, $app->get_page_session_id(), 'page session carries its own :ID' );
  is( $app->get_page_session()->{ ':PAGE_NAME' }, 'main', 'page session remembers the page name' );
  is( $app->get_page_session( 5 ), undef, 'get_page_session() beyond the stack returns undef' );
  is( $app->get_ref_page_session_id(), undef, 'no referring page session on a first request' );

  my ( $lshr, $lsid ) = $app->get_link_session();
  isa_ok( $lshr, 'HASH', 'get_link_session() hash' );
  is( $lshr->{ ':ID' }, $lsid, 'link session carries its own :ID' );
  is( length( $lsid ), 8, 'link session id is 8 chars' );

  my ( $lshr2, $lsid2 ) = $app->get_link_session();
  is( $lsid2, $lsid, 'get_link_session() is stable within a request' );

  my $k1 = $app->new_link_session_key( 'ARGS' );
  my $k2 = $app->new_link_session_key( 'ARGS' );
  isnt( $k1, $k2, 'new_link_session_key() returns fresh keys' );
  is( length( $k1 ), 8, 'link session key default length is 8' );
  is( length( $app->new_link_session_key( 'ARGS', 16 ) ), 16, 'new_link_session_key() honours length' );

  eval { $app->new_link_session_key( 'FRM' ) };
  ok( $@, 'new_link_session_key() booms for unsupported types' );

  # args() stores the arguments upper-cased into the link session
  my $a = $app->args( colour => 'red', SIZE => 3 );
  my ( $sid, $key ) = split /\./, $a;
  is( $sid, $lsid, 'args() uses the current link session' );
  is_deeply( $lshr->{ 'ARGS' }{ $key }, { COLOUR => 'red', SIZE => 3 }, 'args() upper-cases argument names' );

  # the typed variants
  my %typed = (
              'args_here'     => '_P',
              'args_new'      => '_R',
              'args_back'     => '_P',
              'args_new_fr'   => '_T',
              );

  while( my ( $m, $k ) = each %typed )
    {
    my $r = $app->$m( X => 1 );
    my ( undef, $kk ) = split /\./, $r;
    ok( exists $lshr->{ 'ARGS' }{ $kk }{ $k }, "$m() sets $k" );
    }

  is( $app->args_here()      =~ /\./ ? 1 : 0, 1, 'args_here() with no arguments' );
  my ( undef, $hk ) = split /\./, $app->args_here();
  is( $lshr->{ 'ARGS' }{ $hk }{ '_P' }, $app->get_page_session_id(), 'args_here() points at the current page session' );

  my ( undef, $nk ) = split /\./, $app->args_new();
  is( $lshr->{ 'ARGS' }{ $nk }{ '_R' }, $app->get_page_session_id(), 'args_new() refers back to the current page' );
  is( $lshr->{ 'ARGS' }{ $nk }{ '_PN' }, 'main', 'args_new() carries the current page name' );

  for my $t ( qw( new new_fr here back none ) )
    {
    like( $app->args_type( $t, X => 1 ), qr/^[A-Za-z0-9]+\.[A-Za-z0-9]+$/, "args_type( '$t' )" );
    }
  eval { $app->args_type( 'nonesuch' ) };
  ok( $@, 'args_type() booms on an unknown type' );

  my $u = $app->create_uniq_id();
  like( $u, qr/^\Q@{[ $app->get_page_session_id() ]}\E\.[A-Za-z0-9]{16}$/, 'create_uniq_id()' );
  isnt( $app->create_uniq_id(), $u, 'create_uniq_id() is unique' );
  like( $app->create_uniq_id( 1 ), qr/\.[A-Z0-9]{16}$/, 'create_uniq_id( 1 ) is upper case' );
  like( $app->create_uniq_id( 2 ), qr/\.[a-z0-9]{16}$/, 'create_uniq_id( 2 ) is lower case' );
}

##############################################################################
##
##  section 12 -- input parameters
##

{
  my $q = 'AA=1&BB=2&BB=3&BUTTON%3ASAVE=x&CC=%3Cscript%3E';
  my $r = make_reo( make_env( 'QUERY_STRING' => $q ) );
  $r->run();

  my $ui = $r->get_user_input();
  isa_ok( $ui, 'HASH', 'get_user_input()' );
  is( $ui->{ 'AA' }, '1', 'single value parameter, name upper-cased' );
  is_deeply( $ui->{ '@BB' }, [ '2', '3' ], 'multi value parameter stored under @NAME' );

  is( $r->get_input_button(), 'SAVE', 'get_input_button() from BUTTON:NAME' );
  is( $r->get_input_button_id(), undef, 'get_input_button_id() undef without an id' );
  is( $r->get_input_button_and_remove(), 'SAVE', 'get_input_button_and_remove() returns the button' );
  is( $r->get_input_button(), undef, 'get_input_button_and_remove() removed the button' );

  my $r2 = make_reo( make_env( 'QUERY_STRING' => 'BUTTON%3AEDIT%3A42=x' ) );
  $r2->run();
  is( $r2->get_input_button(),    'EDIT', 'button name with an id'  );
  is( $r2->get_input_button_id(), '42',   'get_input_button_id()'   );

  my $r3 = make_reo( make_env( 'QUERY_STRING' => '_BTN=DELETE%3A7' ) );
  $r3->run();
  is( $r3->get_input_button(),    'DELETE', 'simulated button via _BTN' );
  is( $r3->get_input_button_id(), '7',      'simulated button id'       );

  my $mark = scalar @LOG;
  my $r4 = make_reo( make_env( 'QUERY_STRING' => 'bad%20name=1' ) );
  $r4->run();
  ok( log_since( $mark, qr/invalid CGI\/input parameter name/ ), 'invalid parameter name rejected and logged' );
  is( $r4->get_user_input()->{ 'BAD NAME' }, undef, 'invalid parameter name not imported' );

  # param accessors
  $r->{ 'INPUT_USER_HR' } = { FOO => 'user-foo', BAR => 'user-bar' };
  $r->{ 'INPUT_SAFE_HR' } = { FOO => 'safe-foo' };

  is( $r->param( 'FOO' ),             'safe-foo', 'param() reads safe input'          );
  is( $r->param_safe( 'FOO' ),        'safe-foo', 'param_safe() is an alias of param' );
  is( $r->param_unsafe( 'BAR' ),      'user-bar', 'param_unsafe() reads user input'   );
  is( $r->param_peek( 'FOO' ),        'safe-foo', 'param_peek() reads safe input'     );
  is( $r->param_peek_safe( 'FOO' ),   'safe-foo', 'param_peek_safe()'                 );
  is( $r->param_peek_unsafe( 'BAR' ), 'user-bar', 'param_peek_unsafe()'               );

  is_deeply( [ $r->param( 'FOO', 'NOPE' ) ], [ 'safe-foo', undef ], 'param() in list context' );

  my $ps = $r->get_page_session();
  is( $ps->{ 'SAVE_SAFE_INPUT' }{ 'FOO' }, 'safe-foo', 'param() caches into the page session' );
  ok( ! exists $ps->{ 'FOO' }, 'param() does not promote to the page session itself' );

  # the cache survives a request without the parameter
  delete $r->{ 'INPUT_SAFE_HR' }{ 'FOO' };
  is( $r->param( 'FOO' ), 'safe-foo', 'param() returns the cached value when input is gone' );
  is( $r->param_peek( 'FOO' ), undef, 'param_peek() does not use the cache' );

  $r->{ 'INPUT_SAFE_HR' }{ 'FOO' } = 'safe-foo';
  $r->param_save( 'FOO' );
  is( $ps->{ 'FOO' }, 'safe-foo', 'param_save() promotes into the page session' );

  $r->param_clear_cache( 'FOO' );
  ok( ! exists $ps->{ 'SAVE_SAFE_INPUT' }{ 'FOO' }, 'param_clear_cache() drops the safe cache' );
  ok( ! exists $ps->{ 'SAVE_USER_INPUT' }{ 'FOO' }, 'param_clear_cache() drops the user cache' );

  is( $r->get_input_form_name(), undef, 'get_input_form_name() undef without a form' );
}

##############################################################################
##
##  section 13 -- html content variables
##

{
  my $r = make_reo();
  $r->run();

  $r->html_content_set( GREET => 'hi' );
  my $hc = $r->html_content();
  is( $hc->{ 'greet' }, 'hi', 'html_content_set() lower-cases the key' );

  $r->html_content( OTHER => 'x' );
  is( $r->html_content()->{ 'greet' }, 'hi', 'html_content() keeps existing keys' );
  is( $r->html_content()->{ 'other' }, 'x',  'html_content() adds new keys'       );

  $r->html_content_accumulator( 'ACC', 'a' );
  $r->html_content_accumulator( 'ACC', 'b' );
  $r->html_content_accumulator( 'ACC', 'a' ); # duplicates collapse
  my $acc = $r->html_content()->{ 'acc' };
  is( length( $acc ), 2, 'html_content_accumulator() collapses duplicates' );
  like( $acc, qr/a/, 'accumulator holds the first fragment'  );
  like( $acc, qr/b/, 'accumulator holds the second fragment' );

  $r->html_content_accumulator_js( 'js/app.js' );
  like( $r->html_content()->{ 'accumulator_js' }, qr{<script type='text/javascript' src='js/app\.js'></script>},
        'html_content_accumulator_js()' );

  $r->html_content_accumulator_css( 'css/app.css' );
  like( $r->html_content()->{ 'accumulator_head' }, qr{<link href="css/app\.css" rel="stylesheet"},
        'html_content_accumulator_css()' );

  $r->set_browser_window_title( 'a <b>bold</b> title' );
  is( $r->html_content()->{ 'browser_window_title' }, 'a bold title', 'set_browser_window_title() strips html' );

  # a content variable really does reach the rendered page
  my $r2 = make_reo();
  $r2->run();
  $r2->html_content( GREET => 'HOLA' );
  eval { $r2->render( PAGE => 'main' ) }; # render() always leaves through a sink
  like( $r2->res_get_body(), qr/MAIN\[HOLA\]/, 'content variable substituted into the page' );
}

##############################################################################
##
##  section 14 -- preprocessor
##

{
  my $pre = $app->pre;

  is( $pre->load_file( 'part' ), 'PART', 'pre->load_file()' );
  is( $pre->load_page( 'other' ), 'OTHER', 'pre->load_page() prepends page_' );
  is( $pre->load_file( 'nosuchfile' ), undef, 'pre->load_file() returns undef when missing' );

  eval { $pre->load_file( 'Bad Name' ) };
  ok( $@, 'pre->load_file() dies on an invalid name' );

  $app->html_content( GREET => 'G' );
  is( $pre->process( 'main', 'x<$greet>y', {} ), 'xGy', 'preprocessor substitutes $var tags' );
  is( $pre->process( 'main', 'x<$nosuch>y', {} ), 'xy', 'unknown $var expands to nothing' );
  is( $pre->process( 'main', 'x<#part>y', {} ), 'xPARTy', 'preprocessor includes #file tags' );
  is( $pre->process( 'main', 'x<&hello>y', {} ), 'xHELLOy', 'preprocessor calls &action tags' );
  is( $pre->process( 'main', "x<&hello who=bob>y", {} ), 'xHELLO:boby', 'action tag arguments are passed through' );
  is( $pre->process( 'main', "x<&hello who='bo b'>y", {} ), 'xHELLO:bo by', 'quoted action tag arguments' );

  my $opt = {};
  is( $pre->process( 'defer', 'x<$$late>y', $opt ), 'x<$late>y', 'deferred $$var is rewritten to $var' );
  is( $opt->{ 'SECOND_PASS_REQUIRED' }, 1, 'deferred tag requests a second pass' );

  eval { $pre->process( 'selfref', '<#selfref>', {} ) };
  like( $@, qr/loop detected/, 'preprocessor detects include loops' );

  eval { $pre->process( 'main', '<$>', {} ) };
  is( $pre->process( 'main', '<$>', {} ), '<$>', 'a malformed tag is left alone' );

  # reactor_*href rewriting
  for my $t ( qw( new back here none ) )
    {
    my $out = $pre->process( 'main', "<a reactor_${t}_href=?_pn=other>x</a>", {} );
    like( $out, qr/^<a href=\?_=[A-Za-z0-9]+\.[A-Za-z0-9]+>x<\/a>$/, "reactor_${t}_href rewritten" );
    }

  like( $pre->process( 'main', '<a reactor_href=?a=1>x</a>', {} ), qr/href=\?_=/, 'bare reactor_href rewritten' );
  like( $pre->process( 'main', '<img reactor_src=?a=1>', {} ), qr/src=\?_=/, 'reactor_src rewritten' );
  like( $pre->process( 'main', '<a reactor_href=?a=1#top>x</a>', {} ), qr/#top/, 'anchor preserved on rewrite' );

  # the rewritten link really carries the arguments
  my ( $lshr ) = $app->get_link_session();
  my $out = $pre->process( 'main', '<a reactor_none_href=?colour=blue>x</a>', {} );
  my ( $key ) = $out =~ /\.([A-Za-z0-9]+)>/;
  is( $lshr->{ 'ARGS' }{ $key }{ 'COLOUR' }, 'blue', 'rewritten href carries its arguments' );

  # html dir selection by language
  my $bg = make_reo( make_env(), make_cfg( LANG => 'bg', HTML_DIRS => undef ) );
  is_deeply( $bg->cfg()->{ 'HTML_DIRS' },
             [ "$APP_ROOT/html/bg", "$APP_ROOT/html/default" ],
             'HTML_DIRS defaults to html/<lang> then html/default' );
  is( $bg->pre->load_page( 'other' ), 'DRUGO', 'language specific page wins' );
  is( $bg->pre->load_page( 'main' ), 'MAIN[<$greet>][<&hello>][<#part>]', 'falls back to html/default' );
}

##############################################################################
##
##  section 15 -- actions
##

{
  my $act = $app->act;

  is( $act->call( 'hello' ), 'HELLO', 'act->call() finds an application action' );
  is( $act->call( 'HELLO' ), 'HELLO', 'act->call() is case insensitive' );
  is( $act->call( 'hello', HTML_ARGS => { WHO => 'ann' } ), 'HELLO:ann', 'act->call() passes named arguments' );
  is( $act->call( 'test' ), 'Web::Reactor::Actions::Core::test here!', 'act->call() falls back to the Core action set' );

  eval { $act->call( 'no such action' ) };
  ok( $@, 'act->call() dies on an invalid action name' );

  eval { $act->call( 'nosuchaction' ) };
  ok( $@, 'act->call() booms when the action package is not found' );

  my $mark = scalar @LOG;
  is( $act->call( 'broken' ), undef, 'act->call() returns undef when the action dies' );
  ok( log_since( $mark, qr/call native action failed/ ), 'failing action is logged' );

  # abstract base
  eval { Web::Reactor::Actions::call() };
  like( $@, qr/is not implemented/, 'Actions::call() is an abstract stub' );
  eval { Web::Reactor::Preprocessor::load_file() };
  like( $@, qr/is not implemented/, 'Preprocessor::load_file() is an abstract stub' );
  eval { Web::Reactor::Preprocessor::process() };
  like( $@, qr/is not implemented/, 'Preprocessor::process() is an abstract stub' );

  # the Alt action backend loads plain files from ACTIONS_DIRS
  my $alt = make_reo( make_env(), make_cfg( REO_ACT_CLASS => 'Web::Reactor::Actions::Alt',
                                            ACTIONS_DIRS  => [ "$APP_ROOT/actions" ] ) );
  isa_ok( $alt->act, 'Web::Reactor::Actions::Alt', 'REO_ACT_CLASS override' );
  is( $alt->act->call( 'altact' ), 'ALT-OK', 'Alt action loaded and called' );

  $mark = scalar @LOG;
  is( $alt->act->call( 'nosuchaltact' ), undef, 'Alt returns undef for a missing action' );
  ok( log_since( $mark, qr/cannot load action/ ), 'missing Alt action is logged' );

  $mark = scalar @LOG;
  is( $alt->act->call( 'not valid' ), undef, 'Alt rejects an invalid action name' );
  ok( log_since( $mark, qr/invalid action name/ ), 'invalid Alt action name is logged' );
}

##############################################################################
##
##  section 16 -- render, portray, forward
##

{
  is_deeply( $app->portray( 'DATA', 'html' ), { DATA => 'DATA', TYPE => 'text/html' }, 'portray() html shortcut' );
  is( $app->portray( 'D', 'txt'  )->{ 'TYPE' }, 'text/plain',              'portray() txt shortcut'  );
  is( $app->portray( 'D', 'text' )->{ 'TYPE' }, 'text/plain',              'portray() text shortcut' );
  is( $app->portray( 'D', 'png'  )->{ 'TYPE' }, 'image/png',               'portray() png shortcut'  );
  is( $app->portray( 'D', 'jpeg' )->{ 'TYPE' }, 'image/jpeg',              'portray() jpeg shortcut' );
  is( $app->portray( 'D', 'bin'  )->{ 'TYPE' }, 'application/octet-stream','portray() bin shortcut'  );
  is( $app->portray( 'D', 'application/pdf' )->{ 'TYPE' }, 'application/pdf', 'portray() passes real mime types through' );
  is( $app->portray( 'D', 'html', FILE_NAME => 'a.txt' )->{ 'FILE_NAME' }, 'a.txt', 'portray() keeps extra options' );

  eval { $app->portray( 'D', 'nonsense' ) };
  ok( $@, 'portray() booms on a non mime type' );

  # render() always leaves through a RENDER sink
  {
    my $r = make_reo();
    $r->run();
    eval { $r->render( PAGE => 'other' ) };
    ok( Exception::Sink::surface( 'RENDER' ), 'render() raises a RENDER sink' );
    is( $r->res_get_body(), 'OTHER', 'render( PAGE => ... ) sets the body' );
  }

  {
    my $r = make_reo();
    $r->run();
    eval { $r->render( ACTION => 'hello' ) };
    is( $r->res_get_body(), 'HELLO', 'render( ACTION => ... ) sets the body' );
  }

  {
    my $r = make_reo();
    $r->run();
    eval { $r->render_page( 'other' ) };
    is( $r->res_get_body(), 'OTHER', 'render_page()' );
  }

  {
    my $r = make_reo();
    $r->run();
    eval { $r->render_action( 'hello' ) };
    is( $r->res_get_body(), 'HELLO', 'render_action()' );
  }

  {
    my $r = make_reo();
    $r->run();
    eval { $r->render_data( 'PLAIN', 'text' ) };
    is( $r->res_get_body(), 'PLAIN', 'render_data() sets the body' );
    my %h = @{ $r->res_get_headers_ar() };
    like( $h{ 'content-type' }, qr{^text/plain}, 'render_data() sets the content type' );
  }

  {
    my $r = make_reo();
    $r->run();
    eval { $r->render( DATA => $r->portray( 'BYTES', 'bin', FILE_NAME => 'my report.txt' ) ) };
    my %h = @{ $r->res_get_headers_ar() };
    like( $h{ 'content-type' }, qr{^application/octet-stream}, 'binary portray content type' );
    is( $h{ 'content-disposition' }, 'inline; filename="my report.txt"', 'content-disposition built from FILE_NAME' );
  }

  {
    my $r = make_reo();
    $r->run();
    eval { $r->render( DATA => $r->portray( 'B', 'bin', FILE_NAME => "evil\r\nX-Injected: 1.txt",
                                            DISPOSITION_TYPE => 'attachment' ) ) };
    my %h = @{ $r->res_get_headers_ar() };
    unlike( $h{ 'content-disposition' }, qr/[\r\n]/, 'content-disposition strips CR/LF' );
    like( $h{ 'content-disposition' }, qr/^attachment;/, 'DISPOSITION_TYPE honoured' );
  }

  {
    my $r = make_reo();
    $r->run();
    eval { $r->render( DATA => $r->portray( 'B', 'bin', FILE_NAME => "\x{43f}\x{440}.txt" ) ) };
    my %h = @{ $r->res_get_headers_ar() };
    like( $h{ 'content-disposition' }, qr/filename\*=UTF-8''/, 'non-ascii file name gets an RFC 5987 filename*' );
  }

  {
    my $r = make_reo( make_env(), make_cfg( HTTP_CSP => "default-src 'self'" ) );
    $r->run();
    my %h = @{ $r->res_get_headers_ar() };
    is( $h{ 'content-security-policy' }, "default-src 'self'", 'HTTP_CSP emitted as Content-Security-Policy' );
  }

  eval { $app->render() };
  like( $@, qr/needs PAGE or ACTION/, 'render() booms without PAGE or ACTION' );

  eval { $app->render( DATA => \'not a hash' ) };
  ok( $@, 'render() booms on a non hash portray reference' );

  # forwards
  my %fw = (
           'forward'         => [ X => 1 ],
           'forward_here'    => [ X => 1 ],
           'forward_back'    => [ X => 1 ],
           'forward_new'     => [ X => 1 ],
           );

  for my $m ( sort keys %fw )
    {
    my $r = make_reo();
    $r->run();
    eval { $r->$m( @{ $fw{ $m } } ) };
    is( $r->res_get_status(), 302, "$m() sets a 302 status" );
    like( $r->{ 'OUT' }{ 'HEADERS' }{ 'location' }, qr/^\?_=[A-Za-z0-9]+\.[A-Za-z0-9]+$/, "$m() sets a location" );
    eval { $r->$m( 'odd' ) };
    ok( $@, "$m() booms on an odd argument list" );
    }

  {
    my $r = make_reo();
    $r->run();
    eval { $r->forward_url( 'https://example.com/' ) };
    is( $r->{ 'OUT' }{ 'HEADERS' }{ 'location' }, 'https://example.com/', 'forward_url()' );
    my %h = @{ $r->res_get_headers_ar() };
    ok( ! exists $h{ 'content-type' }, 'a redirect drops the content-type header' );
  }

  {
    my $r = make_reo();
    $r->run();
    eval { $r->forward_new_page( 'other', X => 1 ) };
    my ( $key ) = $r->{ 'OUT' }{ 'HEADERS' }{ 'location' } =~ /\.([A-Za-z0-9]+)$/;
    my ( $ls ) = $r->get_link_session();
    is( $ls->{ 'ARGS' }{ $key }{ '_PN' }, 'other', 'forward_new_page() sets _PN' );

    eval { $r->forward_new_action( 'hello', X => 1 ) };
    ( $key ) = $r->{ 'OUT' }{ 'HEADERS' }{ 'location' } =~ /\.([A-Za-z0-9]+)$/;
    is( $ls->{ 'ARGS' }{ $key }{ '_AN' }, 'hello', 'forward_new_action() sets _AN' );

    eval { $r->forward_type( 'here', X => 1 ) };
    like( $r->{ 'OUT' }{ 'HEADERS' }{ 'location' }, qr/^\?_=/, 'forward_type()' );
    eval { $r->forward_type( 'here', 'odd', 'args', 'here' ) };
    ok( $@, 'forward_type() booms on an even argument list' );
  }

  # need_login() forwards anonymous visitors to the login page
  {
    my $r = make_reo();
    $r->run();
    eval { $r->need_login() };
    my ( $key ) = $r->{ 'OUT' }{ 'HEADERS' }{ 'location' } =~ /\.([A-Za-z0-9]+)$/;
    my ( $ls ) = $r->get_link_session();
    is( $ls->{ 'ARGS' }{ $key }{ '_PN' }, 'login', 'need_login() forwards to the login page' );

    $r->login( 'someone' );
    is( $r->need_login(), undef, 'need_login() is a no-op once logged in' );
  }

  # require_post_method()
  {
    my $r = make_reo( make_env( 'REQUEST_METHOD' => 'POST' ) );
    $r->run();
    is( $r->require_post_method(), undef, 'require_post_method() passes on POST' );

    my $g = make_reo();
    $g->run();
    $g->login( 'joe' );
    eval { $g->require_post_method() };
    is( $g->is_logged_in(), 0, 'require_post_method() logs the user out on GET' );
    is( $g->get_user_session()->{ ':CLOSED' }, 1, 'require_post_method() closes the session on GET' );
  }
}

##############################################################################
##
##  section 17 -- response api
##

{
  my $r = make_reo();

  is( $r->res_set_status( 404 ), 404, 'res_set_status() returns the status' );
  is( $r->res_get_status(), 404, 'res_get_status()' );

  $r->res_set_headers( 'X-One' => 'a' );
  $r->res_set_headers( 'x-two' => 'b' );
  is( $r->{ 'OUT' }{ 'HEADERS' }{ 'x-one' }, 'a', 'res_set_headers() lower-cases names' );
  is( $r->{ 'OUT' }{ 'HEADERS' }{ 'x-two' }, 'b', 'res_set_headers() accumulates' );

  $r->res_set_headers( status => 201 );
  is( $r->res_get_status(), 201, 'res_set_headers( status => ... ) sets the status' );
  ok( ! exists $r->{ 'OUT' }{ 'HEADERS' }{ 'status' }, 'status is not emitted as a header' );

  $r->res_set_headers( 'content-type' => 'text/plain', 'content-charset' => 'UTF-8' );
  my %h = @{ $r->res_get_headers_ar() };
  is( $h{ 'content-type' }, 'text/plain; charset=UTF-8', 'content-charset folded into content-type' );
  ok( ! exists $h{ 'content-charset' }, 'content-charset is not emitted on its own' );

  $r->res_set_cookie( 'c1', value => 'v1', path => '/', httponly => 1 );
  my @hdr = @{ $r->res_get_headers_ar() };
  my @ck;
  for ( my $i = 0; $i < @hdr; $i += 2 ) { push @ck, $hdr[ $i + 1 ] if $hdr[ $i ] eq 'set-cookie' }
  ok( scalar( grep { /^c1=v1/ } @ck ), 'res_set_cookie() emits a set-cookie header' );

  is( $r->res_set_body( 'BODY' ), 'BODY', 'res_set_body() returns the body' );
  is( $r->res_get_body(), 'BODY', 'res_get_body()' );
}

##############################################################################
##
##  section 18 -- crypto
##

{
  # Web::Reactor does not load Crypt::Mode::CBC itself, so the symmetric crypto
  # api only works if the application (or this test) pulls it in
  if( ! Crypt::Mode::CBC->can( 'encrypt' ) )
    {
    local $TODO = 'Web/Reactor.pm is missing "use Crypt::Mode::CBC"';
    my $ok = eval { $app->encrypt( 'x' ); 1 };
    ok( $ok, 'encrypt() works without the application loading Crypt::Mode::CBC' );
    }

  require Crypt::Mode::CBC;
  delete $app->{ 'CRYO' }; # drop the cipher object cached by the failed attempt

  my $enc = $app->encrypt( 'top secret' );
  isnt( $enc, 'top secret', 'encrypt() actually encrypts' );
  is( $app->decrypt( $enc ), 'top secret', 'decrypt() round trip' );
  isnt( $app->encrypt( 'top secret' ), $enc, 'encrypt() uses a random iv' );

  my $hex = $app->encrypt_hex( 'hex secret' );
  like( $hex, qr/^[0-9a-f]+$/i, 'encrypt_hex() returns hex' );
  is( $app->decrypt_hex( $hex ), 'hex secret', 'decrypt_hex() round trip' );

  my $b64 = $app->encrypt_base64u( 'b64 secret' );
  like( $b64, qr/^[A-Za-z0-9_-]+$/, 'encrypt_base64u() is url safe' );
  is( $app->decrypt_base64u( $b64 ), 'b64 secret', 'decrypt_base64u() round trip' );

  my $data = { NAME => 'cade', LIST => [ 1, 2, 3 ] };
  is_deeply( $app->crypto_thaw_hex( $app->crypto_freeze_hex( $data ) ), $data, 'crypto_freeze_hex/thaw_hex round trip' );
  is_deeply( $app->crypto_thaw_base64u( $app->crypto_freeze_base64u( $data ) ), $data, 'crypto_freeze/thaw_base64u round trip' );

  # a bad key must be refused
  {
    my $r = make_reo( make_env(), make_cfg( ENCRYPT_KEY => 'short' ) );
    eval { $r->encrypt( 'x' ) };
    like( $@, qr/invalid key size/, 'encrypt() booms on a too short key' );

    my $r2 = make_reo( make_env(), make_cfg( ENCRYPT_KEY => '' ) );
    eval { $r2->encrypt( 'x' ) };
    like( $@, qr/missing key/, 'encrypt() booms without a key' );
  }

  # rsa
  SKIP:
  {
    eval { require Crypt::PK::RSA; 1 } or skip 'Crypt::PK::RSA not available', 3;

    my $rsa = Crypt::PK::RSA->new();
    $rsa->generate_key( 128, 65537 );
    my $pem = $rsa->export_key_pem( 'public' );

    my $r = make_reo( make_env(), make_cfg( RSA_PUB_KEY => \$pem ) );
    my $out = $r->rsa_pub_encrypt( 'password' );

    ok( $out, 'rsa_pub_encrypt() returned something' );
    like( $out, qr{^[A-Za-z0-9+/=\s]+$}, 'rsa_pub_encrypt() returns base64' );
    is( $rsa->decrypt( MIME::Base64::decode_base64( $out ), 'oaep', 'SHA256' ), 'password',
        'rsa_pub_encrypt() output decrypts with the private key' );
  }

  # PASSWORD parameters are rsa encrypted on the way in
  SKIP:
  {
    eval { require Crypt::PK::RSA; 1 } or skip 'Crypt::PK::RSA not available', 2;

    my $rsa = Crypt::PK::RSA->new();
    $rsa->generate_key( 128, 65537 );
    my $pem = $rsa->export_key_pem( 'public' );

    my $r = make_reo( make_env( 'QUERY_STRING' => 'PASSWORD=hunter2' ),
                      make_cfg( RSA_PUB_KEY => \$pem ) );
    $r->run();
    my $got = $r->get_user_input()->{ 'PASSWORD' };
    isnt( $got, 'hunter2', 'PASSWORD input is not kept in clear text' );
    is( $rsa->decrypt( MIME::Base64::decode_base64( $got ), 'oaep', 'SHA256' ), 'hunter2',
        'PASSWORD input is rsa encrypted' );

    my $np = make_reo( make_env( 'QUERY_STRING' => 'PASSWORD=hunter2' ),
                       make_cfg( NO_PASS_ENCRYPT => 1 ) );
    $np->run();
    is( $np->get_user_input()->{ 'PASSWORD' }, 'hunter2', 'NO_PASS_ENCRYPT keeps the password as is' );
  }
}

##############################################################################
##
##  section 19 -- session persistence through save()
##

{
  my $r = make_reo();
  $r->run();

  my $sid = $r->get_page_session_id();
  $r->get_page_session()->{ 'MARKER' } = 'kept';
  $r->save();

  is( $r->ses->load( 'PAGE', $sid )->{ 'MARKER' }, 'kept', 'save() writes modified page session data' );

  # unchanged data must not be rewritten
  my $fn = $r->ses->_key_to_fn( { READONLY => 1 }, $r->ses->compose_key_from_id( 'PAGE', $sid ) );
  my $mtime = ( stat $fn )[ 9 ];
  $r->save();
  is( ( stat $fn )[ 9 ], $mtime, 'save() skips sessions whose content did not change' );

  $r->{ 'SESSIONS' }{ 'DATA' }{ 'PAGE' }{ $sid } = 'not a hashref';
  eval { $r->save() };
  like( $@, qr/is not hashref/, 'save() booms on corrupt session data' );
}

##############################################################################
##
##  section 20 -- translations
##

{
  my $r = make_reo( make_env(), make_cfg( LANG => 'en', TRANS_DIRS => [ "$APP_ROOT/trans" ] ) );
  my $res = $r->run();

  is( $r->get_lang(), 'en', 'get_lang()' );

  my $r2 = make_reo( make_env( 'QUERY_STRING' => '_PN=trans' ),
                     make_cfg( LANG => 'en', TRANS_DIRS => [ "$APP_ROOT/trans" ] ) );
  is( $r2->run()->[2][0], 'T:jabalka B:krusha', 'both <~key> and [~key] forms translated' );

  # untranslated keys fall back to themselves
  my $r3 = make_reo( make_env(), make_cfg( LANG => 'en', TRANS_DIRS => [ "$APP_ROOT/trans" ] ) );
  $r3->run();
  $r3->load_trans();
  is( $r3->{ 'TRANS' }{ 'en' }{ 'apple' }, 'jabalka', 'load_trans() filled the translation table' );

  my $r4 = make_reo();
  is( $r4->load_trans(), 0, 'load_trans() is a no-op without LANG' );

  is_deeply( $app->load_trans_file( "$APP_ROOT/trans/en/main.tr" ),
             { apple => 'jabalka', pear => 'krusha' }, 'load_trans_file()' );

  # a single TRANS_FILE short-cuts the directory scan
  my $r5 = make_reo( make_env(), make_cfg( LANG => 'en', TRANS_FILE => "$APP_ROOT/trans/en/main.tr" ) );
  $r5->load_trans();
  is( $r5->{ 'TRANS' }{ 'en' }{ 'pear' }, 'krusha', 'TRANS_FILE loaded' );
}

##############################################################################
##
##  section 21 -- HTML::Utils
##

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

  my $al = html_alink( $app, 'here', 'CLICK', { CLASS => 'btn', HINT => 'go' }, X => 1 );
  like( $al, qr/^<a href=\?_=[A-Za-z0-9]+\.[A-Za-z0-9]+/, 'html_alink() builds a reactor link' );
  like( $al, qr/>CLICK<\/a>$/, 'html_alink() wraps the value' );
  like( $al, qr/class='btn'/,  'html_alink() honours CLASS' );

  like( html_alink( $app, 'here', 'C', { CONFIRM => 'sure?' } ), qr/confirm\('sure\?'\)/, 'html_alink() CONFIRM' );
  like( html_alink( $app, 'here', 'C', { DISABLED => 1 } ), qr/disabled-button/, 'html_alink() DISABLED' );

  my ( $ph, $pt ) = html_popup_layer( $app, VALUE => 'popup text' );
  like( $ph, qr/data-popup-layer-id="R_POPUP_LAYER_/, 'html_popup_layer() handle carries the layer id' );
  like( $ph, qr/onClick=/, 'html_popup_layer() CLICK trigger by default' );
  like( $pt, qr/popup text/, 'html_popup_layer() layer carries the value' );
  like( $pt, qr/class='popup-layer'/, 'html_popup_layer() default class' );

  my ( $ch ) = html_popup_layer( $app, VALUE => 'x', TYPE => 'CONTEXT' );
  like( $ch, qr/onContextMenu/i, 'html_popup_layer() CONTEXT trigger' );

  # in scalar context the layer goes into the html accumulator instead
  my $ps = html_popup_layer( $app, VALUE => 'accumulated popup' );
  like( $ps, qr/data-popup-layer-id=/, 'html_popup_layer() scalar context returns the handle' );
  like( $app->html_content()->{ 'accumulator_html' }, qr/accumulated popup/,
        'html_popup_layer() scalar context accumulates the layer' );

  my ( $hh, $ht ) = html_hover_layer( $app, VALUE => 'hover text', DELAY => 500 );
  like( $hh, qr/reactor_hover_show_delay/, 'html_hover_layer() wires the hover handler' );
  like( $hh, qr/, 500, event/, 'html_hover_layer() honours DELAY' );
  like( $ht, qr/hover text/, 'html_hover_layer() layer carries the value' );
  like( $ht, qr/class='hover-layer'/, 'html_hover_layer() default class' );

  eval { html_popup_layer( 'not a reactor', VALUE => 'x' ) };
  ok( $@, 'html_popup_layer() booms without a reactor object' );
  eval { html_hover_layer( 'not a reactor', VALUE => 'x' ) };
  ok( $@, 'html_hover_layer() booms without a reactor object' );

  my $tabs = html_tabs_table( $app, [ { LABEL => 'L1', TEXT => 'T1', ON => 1 },
                                      { LABEL => 'L2', TEXT => 'T2' } ] );
  like( $tabs, qr/L1/, 'html_tabs_table() renders the first label'  );
  like( $tabs, qr/L2/, 'html_tabs_table() renders the second label' );
  like( $tabs, qr/T1/, 'html_tabs_table() renders the first tab'    );
  like( $tabs, qr/reactor_tab_activate_id/, 'html_tabs_table() wires the tab handler' );

  my $vtabs = html_tabs_table( $app, [ { LABEL => 'L', TEXT => 'T' } ], VERTICAL => 1 );
  like( $vtabs, qr/WIDTH=50%/, 'html_tabs_table() vertical layout' );
}

##############################################################################
##
##  section 22 -- HTML::Layout
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
##  section 23 -- HTML::Form
##

{
  # new_form() is broken, see the KNOWN ISSUES note at the end
  {
    local $TODO = 'Web::Reactor::new_form() passes hash arguments to Base::new( $reo, $cfg )';
    my $f = eval { $app->new_form() };
    isa_ok( $f, 'Web::Reactor::HTML::Form', 'new_form()' );
  }

  my $form = Web::Reactor::HTML::Form->new( $app, $app->cfg() );
  isa_ok( $form, 'Web::Reactor::HTML::Form', 'HTML::Form->new( $reo, $cfg )' );

  my $begin = $form->begin( NAME => 'testform', METHOD => 'POST' );
  like( $begin, qr/<FORM /i, 'form->begin() opens a form' );
  like( $begin, qr/name='testform'/, 'form->begin() sets the name' );
  like( $begin, qr/method='POST'/, 'form->begin() sets the method' );
  like( $begin, qr/enctype='multipart\/form-data'/, 'form->begin() sets the enctype' );
  ok( $form->get_id(), 'form->get_id() returns the form id' );

  like( $form->begin( NAME => 'f2', DEFAULT_BUTTON => 'SAVE' ), qr/BUTTON:SAVE/, 'form->begin() DEFAULT_BUTTON' );
  like( $form->begin( NAME => 'f3', NO_AUTOCOMPLETE => 1 ), qr/autocomplete='off'/, 'form->begin() NO_AUTOCOMPLETE' );

  eval { $form->begin( NAME => 'f4', METHOD => 'PUT' ) };
  ok( $@, 'form->begin() booms on an unsupported method' );
  eval { $form->begin( NAME => 'bad name' ) };
  ok( $@, 'form->begin() booms on an invalid name' );

  $form->begin( NAME => 'testform' );
  my $fid = $form->get_id();

  my $in = $form->input( NAME => 'login', VALUE => 'cade', SIZE => 20, MAXLEN => 30 );
  like( $in, qr/name='LOGIN'/, 'form->input() upper-cases the name' );
  like( $in, qr/value='cade'/, 'form->input() sets the value' );
  like( $in, qr/size='20'/, 'form->input() sets the size' );
  like( $in, qr/maxlength='30'/, 'form->input() sets the max length' );
  like( $in, qr/form='\Q$fid\E'/, 'form->input() binds to the form id' );

  like( $form->input( NAME => 'p', PASS => 1 ), qr/type='password'/, 'form->input() PASS' );
  like( $form->input( NAME => 'h', HIDDEN => 1 ), qr/type='hidden'/, 'form->input() HIDDEN' );
  like( $form->input( NAME => 'r', RO => 1 ), qr/readonly='readonly'/, 'form->input() RO' );
  like( $form->input( NAME => 'q', REQ => 1 ), qr/required='required'/, 'form->input() REQ' );
  like( $form->input( NAME => 'd', DISABLED => 1 ), qr/disabled='disabled'/, 'form->input() DISABLED' );
  like( $form->input( NAME => 'ph', PH => 'type here' ), qr/placeholder='type here'/, 'form->input() PH' );
  like( $form->input( NAME => 'l', LEN => 12 ), qr/size='12'.*maxlength='12'|maxlength='12'.*size='12'/, 'form->input() LEN sets both' );
  like( $form->input( NAME => 'e', VALUE => "<b>" ), qr/&#60;b&#62;/, 'form->input() escapes the value' );
  eval { $form->input( NAME => 'x', ARGS => 'y' ) };
  ok( $@, 'form->input() rejects the removed ARGS option' );

  my $ta = $form->textarea( NAME => 'note', VALUE => 'hi', ROWS => 4, COLS => 60 );
  like( $ta, qr/<textarea/i, 'form->textarea()' );
  like( $ta, qr/rows='4'/,  'form->textarea() ROWS' );
  like( $ta, qr/cols='60'/, 'form->textarea() COLS' );
  like( $ta, qr/>hi</, 'form->textarea() carries the value' );
  like( $form->textarea( NAME => 'g', GEO => '80*10' ), qr/cols='80'.*rows='10'|rows='10'.*cols='80'/,
        'form->textarea() GEOMETRY' );

  my $cb = $form->checkbox( NAME => 'agree', VALUE => 1 );
  like( $cb, qr/type='hidden' name='agree'/, 'form->checkbox() emits the data holder' );
  like( $cb, qr/type='checkbox'/, 'form->checkbox() emits the visible box' );
  like( $cb, qr/checked/, 'form->checkbox() marks a true value as checked' );
  unlike( $form->checkbox( NAME => 'agree', VALUE => 0 ), qr/checked/, 'form->checkbox() unchecked when false' );

  like( $form->checkbox_multi( NAME => 'stage', VALUE => 1, STAGES => 3 ), qr/stage/i, 'form->checkbox_multi()' );
  like( $form->checkbox_3state( NAME => 't' ), qr/t/i, 'form->checkbox_3state()' );

  my $ra = $form->radio( NAME => 'pick', KEY => 'a', ON => 1 );
  like( $ra, qr/type='radio'/, 'form->radio()' );
  like( $ra, qr/checked/, 'form->radio() ON' );
  like( $ra, qr/value='a'/, 'form->radio() KEY becomes the value' );

  my $rm = $form->radio( NAME => 'pick2', RET => { REAL => 'data' } );
  like( $rm, qr/value='[^']+'/, 'form->radio() RET maps to an opaque value' );
  my ( $rv ) = $rm =~ /value='([^']+)'/;
  is_deeply( $form->{ 'RET_MAP' }{ 'DATA' }{ 'pick2' }{ $rv }, { REAL => 'data' }, 'form->radio() RET recorded in the return map' );

  is( $form->end_radios(), undef, 'form->end_radios() is currently a no-op' );

  my $sel = $form->select( NAME => 'colour',
                           DATA => [ { KEY => 'r', VALUE => 'RED',  LABEL => 'Red'   },
                                     { KEY => 'g', VALUE => 'GREEN',LABEL => 'Green' } ],
                           SELECTED => { RED => 1 } );
  like( $sel, qr/<select/i, 'form->select()' );
  like( $sel, qr/>Red</, 'form->select() renders labels' );
  like( $sel, qr/value='r'/, 'form->select() uses KEY as the html option value' );
  like( $sel, qr/selected='selected'/i, 'form->select() marks the option whose VALUE is SELECTED' );
  unlike( $sel, qr/name='colour'/i, 'form->select() hides the real name behind the return map' );
  is( $form->{ 'RET_MAP' }{ 'DATA' }{ 'colour' }{ 'r' }, 'RED', 'form->select() maps the option key back to its VALUE' );

  my $selh = $form->select( NAME => 'c2', DATA => { r => 'Red', g => 'Green' } );
  like( $selh, qr/Red/, 'form->select() accepts a hashref of options' );

  eval { $form->select( NAME => 'c9', DATA => 'not a reference' ) };
  ok( $@, 'form->select() booms when DATA is not an ARRAY or HASH reference' );

  like( $form->combo( NAME => 'c3', DATA => { a => 'A' } ), qr/<select/i, 'form->combo()' );
  like( $form->select( NAME => 'c4', DATA => { a => 'A' }, MULTIPLE => 1 ), qr/multiple='multiple'/,
        'form->select() MULTIPLE' );
  like( $form->select( NAME => 'c5', DATA => { a => 'A' }, SUBMIT_ON_CHANGE => 1 ), qr/onchange=/i,
        'form->select() SUBMIT_ON_CHANGE' );

  my $up = $form->file_upload( NAME => 'doc' );
  like( $up, qr/type=file/, 'form->file_upload()' );
  like( $up, qr/name='DOC'/, 'form->file_upload() upper-cases the name' );
  like( $form->file_upload_multi( NAME => 'docs' ), qr/multiple/, 'form->file_upload_multi()' );

  my $bt = $form->button( NAME => 'save', VALUE => 'Save' );
  like( $bt, qr/<button/i, 'form->button()' );
  like( $bt, qr/name='button:SAVE'/, 'form->button() emits the button: prefix' );
  like( $bt, qr/>Save</, 'form->button() carries the label' );
  like( $form->button( NAME => 'd', VALUE => 'x', DISABLED => 1 ), qr/disabled='disabled'/, 'form->button() DISABLED' );
  like( $form->button( NAME => 'c', VALUE => 'x', CONFIRM => 'really?' ), qr/confirm\(&#34;really\?&#34;\)/,
        'form->button() CONFIRM' );

  like( $form->image_button( NAME => 'img', SRC => 'a.png' ), qr/a\.png/, 'form->image_button()' );
  like( $form->image_button_default( NAME => 'imgd', SRC => 'a.png' ), qr/height='0'|height=0/, 'form->image_button_default()' );

  # form state
  $form->state( EXTRA => 'value' );
  $form->state_new();
  is( $form->{ 'FORM_STATE' }{ ':ARGS_TYPE' }, 'NEW', 'form->state_new()' );
  $form->state_here();
  is( $form->{ 'FORM_STATE' }{ ':ARGS_TYPE' }, 'HERE', 'form->state_here()' );
  $form->state_back();
  is( $form->{ 'FORM_STATE' }{ ':ARGS_TYPE' }, 'BACK', 'form->state_back()' );
  $form->state_none();
  is( $form->{ 'FORM_STATE' }{ ':ARGS_TYPE' }, 'NONE', 'form->state_none()' );
  is( $form->{ 'FORM_STATE' }{ 'EXTRA' }, 'value', 'form->state() keeps earlier state' );

  $form->state_here();
  my $end = $form->end();
  like( $end, qr/type='hidden'/, 'form->end() emits the state keeper' );
  like( $end, qr/name='_'/, 'form->end() names the state keeper "_"' );
  like( $end, qr/value='[A-Za-z0-9]+\.[A-Za-z0-9]+'/, 'form->end() state keeper holds a link session key' );
  like( $end, qr/form='\Q$fid\E'/, 'form->end() binds the state keeper to the form' );

  my ( $ls ) = $app->get_link_session();
  ok( exists $ls->{ 'FORM_RET_MAP' }{ $fid }, 'form->end() stores the return map in the link session' );

  like( $form->create_uniq_id(), qr/\./, 'form->create_uniq_id() delegates to the reactor' );
}

# a form round trip: the return map really unmaps the posted values
{
  my $r1 = make_reo();
  $r1->run();

  my $f = Web::Reactor::HTML::Form->new( $r1, $r1->cfg() );
  $f->begin( NAME => 'roundtrip' );
  my $sel = $f->select( NAME => 'colour', DATA => [ { KEY => 'r', VALUE => 'RED', LABEL => 'Red' } ] );
  my $end = $f->end();
  $r1->save();

  my ( $hidden_name ) = $sel =~ /name='([^']+)'/;
  my ( $opt_value )   = $sel =~ /<option[^>]*value='([^']+)'/i;
  my ( $state )       = $end =~ /value='([^']+)'/;

  ok( $hidden_name, 'select() produced a mapped input name' );

  my $r2 = make_reo( make_env( 'HTTP_COOKIE'  => 'wrtest_cookie=' . $r1->get_user_session_id(),
                               'QUERY_STRING' => "_=$state&$hidden_name=$opt_value" ) );
  $r2->run();

  is( $r2->get_safe_input()->{ 'colour' }, 'RED', 'form return map turns the posted key back into real data' );
  is( $r2->get_input_form_name(), 'roundtrip', 'get_input_form_name() after a round trip' );
}

##############################################################################
##
##  section 24 -- HTML::Tab
##

{
  my $tab = Web::Reactor::HTML::Tab->new( REO_REACTOR => $app, NAME => 'tabset',
                                          CLASS_ON => 'on', CLASS_OFF => 'off' );
  isa_ok( $tab, 'Web::Reactor::HTML::Tab', 'HTML::Tab->new()' );

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

  $tab->finish();
  like( $app->html_content()->{ 'accumulator_html' }, qr/reactor_tab_controller/,
        'tab->finish() puts the controller into the html accumulator' );
  is( scalar @{ $tab->{ 'TABS_LIST' } }, 2, 'tab keeps a list of its tabs' );
}

##############################################################################
##
##  section 25 -- HTML::FormEngine
##

{
  my $form_def = [
                 { NAME => 'name',  TYPE => 'STRING', LABEL => 'Name'  },
                 { NAME => 'age',   TYPE => 'STRING', LABEL => 'Age', RE => '^\d+$', RE_HELP => 'digits only' },
                 { NAME => 'note',  TYPE => 'TEXT',   LABEL => 'Note'  },
                 { NAME => 'ok',    TYPE => 'CB',     LABEL => 'Ok'    },
                 { NAME => 'go',    TYPE => 'BUTTON', LABEL => '', VALUE => 'Go' },
                 ];

  my $r = make_reo( make_env( 'QUERY_STRING' => 'NAME=cade&AGE=42&NOTE=hi' ) );
  $r->run();

  my ( $data, $errors ) = html_form_engine_import_input( $r, $form_def, NAME => 'F' );
  is( $data->{ 'NAME' }, 'cade', 'form engine imported a plain field' );
  is( $data->{ 'AGE' },  '42',   'form engine imported a field matching its RE' );
  is( $errors, undef, 'form engine reported no errors' );

  my $r2 = make_reo( make_env( 'QUERY_STRING' => 'NAME=cade&AGE=old' ) );
  $r2->run();
  my ( $d2, $e2 ) = html_form_engine_import_input( $r2, $form_def, NAME => 'F' );
  is( $e2->{ 'AGE' }, 1, 'form engine flags a field failing its RE' );
  ok( ! exists $d2->{ 'AGE' }, 'form engine drops the invalid value' );
  is( $r2->get_page_session()->{ 'FORM_INPUT_DATA' }{ 'F' }{ 'NAME' }, 'cade',
      'form engine caches imported data in the page session' );

  eval { html_form_engine_import_input( 'not a reactor', $form_def ) };
  ok( $@, 'html_form_engine_import_input() booms without a reactor object' );
  eval { html_form_engine_display( $app, 'not an arrayref' ) };
  ok( $@, 'html_form_engine_display() booms on a bad form definition' );

  {
    local $TODO = 'html_form_engine_display() calls the broken new_form()';
    my $html = eval { html_form_engine_display( $r, $form_def, NAME => 'F', INPUT_DATA => $data, INPUT_ERRORS => $errors ) };
    like( $html, qr/<input[^>]*name='NAME'/i, 'html_form_engine_display() renders the form' );
  }
}

##############################################################################
##
##  section 26 -- alternate session backend
##

{
  my $d = make_reo( make_env(), make_cfg( REO_SES_CLASS => 'Web::Reactor::Sessions::Dummy' ) );
  isa_ok( $d->ses, 'Web::Reactor::Sessions::Dummy', 'REO_SES_CLASS override' );

  is_deeply( $d->ses->_storage_load(), {}, 'Dummy _storage_load() returns an empty hash' );
  is( $d->ses->_storage_create(), 1, 'Dummy _storage_create()' );
  is( $d->ses->_storage_save(),   1, 'Dummy _storage_save()'   );
  is( $d->ses->_storage_exists(), 1, 'Dummy _storage_exists()' );

  my $res = $d->run();
  is( $res->[0], 200, 'a full request cycle runs on the Dummy backend' );
}

##############################################################################
##
##  section 27 -- Web::Reactor::Base
##

{
  my $b = Web::Reactor::Base->new( $app, { KEY => 'val' } );
  isa_ok( $b, 'Web::Reactor::Base', 'Base->new()' );
  is( $b->get_reo(), $app, 'Base->get_reo()' );
  is( $b->cfg()->{ 'KEY' }, 'val', 'Base->cfg()' );

  eval { Web::Reactor::Base->new( 'not a reactor', {} ) };
  like( $@, qr/Web::Reactor object required/, 'Base->new() booms without a reactor object' );

  $b->__lock_self_keys( qw( ONE TWO ) );
  ok( exists $b->{ 'ONE' }, '__lock_self_keys() pre-creates the given keys' );
  eval { $b->{ 'NOPE' } = 1 };
  ok( $@, '__lock_self_keys() locks the object down' );
}

##############################################################################

done_testing();

##############################################################################

END
{
  print "\n";
  print "# ----------------------------------------------------------------\n";
  print "# KNOWN ISSUES exercised as TODO above:\n";
  print "#\n";
  print "#  1. Web/Reactor.pm does not 'use Crypt::Mode::CBC', so encrypt(),\n";
  print "#     decrypt() and the crypto_freeze/thaw helpers die unless the\n";
  print "#     application happens to load the module itself.\n";
  print "#\n";
  print "#  2. Web::Reactor::new_form() calls\n";
  print "#       new Web::Reactor::HTML::Form( \@_, REO_REACTOR => \$self )\n";
  print "#     but HTML::Form inherits Base::new( \$class, \$reo, \$cfg ), so\n";
  print "#     the string 'REO_REACTOR' arrives where the reactor is expected\n";
  print "#     and __set_reo() booms.  This also breaks\n";
  print "#     html_form_engine_display().\n";
  print "#\n";
  print "#  3. Web::Reactor::Sessions::Filesystem does not implement\n";
  print "#     _storage_delete(), so Sessions::delete() always dies.\n";
  print "# ----------------------------------------------------------------\n";
}

##############################################################################
###EOF########################################################################
