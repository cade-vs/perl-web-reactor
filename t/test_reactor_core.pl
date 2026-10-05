#!/usr/bin/perl
##############################################################################
##
##  Web::Reactor::Core foundation for stateless and stateful application machinery
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
##
##  single-file test utility for Web::Reactor::Core
##
##  usage:
##
##    cd t && perl test_reactor_core.pl         -- run, TAP output on stdout
##    perl t/test_reactor_core.pl               -- same, from the distribution root
##    perl t/test_reactor_core.pl -v            -- also pass Web::Reactor::Core log() to stderr
##
##  sections 1-12 run against hand-built PSGI environments, section 13 runs a
##  throw-away HTTP::Server::PSGI on a local socket. nothing outside of the
##  temporary directory is touched.
##
##############################################################################
use strict;

use lib '../lib'; # when run from inside t/
use lib 'lib';    # when run from the distribution root

use Test::More;
use File::Temp qw( tempfile );
use Encode;
use Data::Dumper;

my $VERBOSE = grep { $_ eq '-v' } @ARGV;

##############################################################################
##
##  test application classes
##
##  LOG collects everything the object logs, so error paths can be asserted on
##  instead of just scrolling past on stderr
##

our @LOG;

package TestApp;
our @ISA = ( 'Web::Reactor::Core' );
sub log
{
  my $self = shift;
  push @LOG, join '', @_;
  print STDERR @_, "\n" if $VERBOSE;
}
sub process_request
{
  my $self = shift;
  # each test installs its own handler, see req()
  return $self->{ 'HANDLER' }->( $self );
}

package main;

##############################################################################
##
##  section 1 -- loading
##

require_ok( 'Web::Reactor::Core' );
ok( $Web::Reactor::Core::VERSION, "Web::Reactor::Core::VERSION is set [$Web::Reactor::Core::VERSION]" );

for my $m ( qw( new run process_request set_debug is_debug inc_debug cfg plack
                env get_client_ip get_request_scheme get_request_uri
                get_request_method get_request_path_info get_headers get_header
                get_cookies get_cookie get_safe_input get_user_input
                get_user_uploads get_user_postdata_fh get_user_postdata_body
                res_set_status res_get_status res_set_headers res_get_headers_ar
                res_set_cookie res_set_body res_get_body render portray forward_url
                log log_debug log_debug2 log_stack log_dumper
                res_clear_headers run_print_final_debug save
                start_time get_uniq_id_scope create_uniq_id ) )
  {
  can_ok( 'Web::Reactor::Core', $m );
  }

##############################################################################
##
##  helpers
##

# minimal but complete PSGI environment, extra keys override
sub env
{
  my %over = @_;

  return {
         'REQUEST_METHOD'  => 'GET',
         'SCRIPT_NAME'     => '/app',
         'PATH_INFO'       => '',
         'QUERY_STRING'    => '',
         'REQUEST_URI'     => '/app',
         'REQUEST_SCHEME'  => 'http',
         'SERVER_NAME'     => 'localhost',
         'SERVER_PORT'     => '80',
         'SERVER_PROTOCOL' => 'HTTP/1.1',
         'REMOTE_ADDR'     => '127.0.0.1',
         'psgi.version'    => [ 1, 1 ],
         'psgi.url_scheme' => 'http',
         'psgi.errors'     => \*STDERR,
         'psgi.input'      => undef,
         %over,
         };
}

sub app
{
  my $env = shift;
  my $cfg = shift || {};

  @LOG = ();
  return TestApp->new( $env, { DEBUG => 0, %$cfg } );
}

# run a handler through the full run() cycle, returns the PSGI triplet
sub req
{
  my $handler = shift;
  my $env     = shift || env();
  my $cfg     = shift || {};

  my $o = app( $env, $cfg );
  $o->{ 'HANDLER' } = $handler;
  return $o->run();
}

# response headers arrayref as a hash, for order independent assertions
sub hdrs
{
  my $ar = shift;

  my %h;
  for( my $i = 0; $i < @$ar; $i += 2 )
    {
    my ( $k, $v ) = ( $ar->[ $i ], $ar->[ $i + 1 ] );
    if( exists $h{ $k } ) { $h{ $k } = [ ( ref $h{ $k } ? @{ $h{ $k } } : $h{ $k } ), $v ] }
    else                  { $h{ $k } = $v }
    }
  return \%h;
}

##############################################################################
##
##  section 2 -- constructor, config, debug level
##

{
my $o = app( env() );
isa_ok( $o, 'Web::Reactor::Core', 'constructed object' );
isa_ok( $o->plack(), 'Plack::Request', 'plack() request object' );

like( ( eval { Web::Reactor::Core->new( 'not a hash', {} ) } , $@ ), qr/ENV hash reference/, 'new() rejects non-hashref ENV' );
like( ( eval { Web::Reactor::Core->new( {}, 'not a hash' ) } , $@ ), qr/CFG hash reference/, 'new() rejects non-hashref CFG' );

# CFG is deep cloned, the object must not share anything with the caller
my $cfg = { DEBUG => 0, NAME => 'orig' };
my $o2  = TestApp->new( env(), $cfg );
$cfg->{ 'NAME' } = 'changed';
is( $o2->cfg->{ 'NAME' }, 'orig', 'CFG is cloned, later caller changes are not visible' );
is( $o2->cfg->{ 'CHARSET' }, 'UTF-8', 'CFG CHARSET is forced to UTF-8' );

# ENV is copied too (shallow, file handles stay shared), the caller's hash is
# never written to, not even the synthetic _CLIENT_IP key
my $env = env();
my $o3  = TestApp->new( $env, { DEBUG => 0 } );
ok( ! exists $env->{ '_CLIENT_IP' }, 'caller ENV is not modified by the constructor' );
is( $o3->env->{ '_CLIENT_IP' }, '127.0.0.1', 'object ENV carries _CLIENT_IP' );
isnt( $o3->env, $env, 'object ENV is a copy, not the caller hash' );

# flat config only, dclone cannot store code refs
like( ( eval { TestApp->new( env(), { CB => sub { 1 } } ) }, $@ ), qr/Can't store CODE/, 'CFG must be flat, code refs are rejected by dclone' );

# debug level handling
is( $o->is_debug(), 0, 'debug is off by default' );
is( $o->set_debug( 3 ),  3, 'set_debug( 3 )' );
is( $o->is_debug(),      3, 'is_debug() reports the level' );
is( $o->set_debug( -3 ), 3, 'set_debug() takes absolute value' );
is( $o->set_debug( 0 ),  0, 'set_debug( 0 ) turns debugging off' );
is( $o->inc_debug(),     1, 'inc_debug() defaults to step 1' );
is( $o->inc_debug( 2 ),  3, 'inc_debug( 2 )' );
}

##############################################################################
##
##  section 3 -- request environment
##

{
my $o = app( env( 'REQUEST_METHOD' => 'POST', 'PATH_INFO' => '/users/42',
                  'REQUEST_URI' => '/app/users/42?a=1', 'REQUEST_SCHEME' => 'https' ) );

is( $o->get_request_method(),    'POST',              'get_request_method()'    );
is( $o->get_request_path_info(), '/users/42',         'get_request_path_info()' );
is( $o->get_request_uri(),       '/app/users/42?a=1', 'get_request_uri()'       );
is( $o->get_request_scheme(),    'https',             'get_request_scheme()'    );
is( ref $o->env(),      'HASH',              'env() is a hashref' );

# client ip: proxy headers are trusted only when the config says so, otherwise
# anyone could spoof their address by sending them directly
my $spoof = env( 'HTTP_X_REAL_IP' => '10.0.0.9', 'HTTP_CF_CONNECTING_IP' => '8.8.8.8' );
is( app( env() )->get_client_ip(), '127.0.0.1', 'get_client_ip() falls back to REMOTE_ADDR' );
is( app( $spoof )->get_client_ip(), '127.0.0.1', 'proxy headers are ignored without CLOUDFLARE/PROXY_REMOTE config' );
is( app( $spoof, { PROXY_REMOTE => 1 } )->get_client_ip(), '10.0.0.9',
    'PROXY_REMOTE trusts HTTP_X_REAL_IP' );
is( app( $spoof, { CLOUDFLARE => 1 } )->get_client_ip(), '8.8.8.8',
    'CLOUDFLARE trusts HTTP_CF_CONNECTING_IP' );
is( app( $spoof, { CLOUDFLARE => 1, PROXY_REMOTE => 1 } )->get_client_ip(), '8.8.8.8',
    'CLOUDFLARE wins over PROXY_REMOTE when both are set' );
is( app( env( 'HTTP_X_REAL_IP' => '10.0.0.9' ), { CLOUDFLARE => 1 } )->get_client_ip(), '127.0.0.1',
    'CLOUDFLARE alone does not trust HTTP_X_REAL_IP' );
is( $o->env()->{ '_CLIENT_IP' }, '127.0.0.1', 'ENV _CLIENT_IP is set at construction' );

# scheme: REQUEST_SCHEME is CGI only, PSGI servers provide psgi.url_scheme
is( app( env( 'REQUEST_SCHEME' => undef, 'psgi.url_scheme' => 'https' ) )->get_request_scheme(), 'https',
    'get_request_scheme() falls back to psgi.url_scheme' );
is( app( env( 'REQUEST_SCHEME' => 'HTTPS' ) )->get_request_scheme(), 'https',
    'get_request_scheme() is lower cased' );
}

##############################################################################
##
##  section 4 -- request headers and cookies
##
##  PSGI/CGI mangles header names, get_headers() must undo that entirely
##

{
my $o = app( env( 'HTTP_USER_AGENT'  => 'test-agent/1.0',
                  'HTTP_X_CUSTOM'    => 'custom-value',
                  'HTTP_HOST'        => 'example.org',
                  'CONTENT_TYPE'     => 'application/json',
                  'CONTENT_LENGTH'   => '7',
                  'HTTP_COOKIE'      => 'sid=abc123; lang=bg',
                  ) );

my $h = $o->get_headers();
is( ref $h, 'HASH', 'get_headers() returns a hashref' );

is( $o->get_header( 'user-agent'     ), 'test-agent/1.0',   'HTTP_USER_AGENT  -> user-agent'     );
is( $o->get_header( 'x-custom'       ), 'custom-value',     'HTTP_X_CUSTOM    -> x-custom'       );
is( $o->get_header( 'host'           ), 'example.org',      'HTTP_HOST        -> host'           );
is( $o->get_header( 'content-type'   ), 'application/json', 'CONTENT_TYPE     -> content-type'   );
is( $o->get_header( 'content-length' ), '7',                'CONTENT_LENGTH   -> content-length' );

is( $o->get_header( 'X-Custom' ), 'custom-value', 'get_header() lookup is case insensitive' );
is( $o->get_header( 'http_x_custom' ), undef, 'mangled CGI name is not a header key' );
is( $o->get_header( 'content_type'  ), undef, 'underscore form is not a header key'  );

# only real headers, no PSGI internals and no synthetic keys
ok( ! exists $h->{ 'psgi.input'      }, 'psgi.input is not a header'      );
ok( ! exists $h->{ 'psgi.url-scheme' }, 'psgi.url_scheme is not a header' );
ok( ! exists $h->{ 'remote-addr'     }, 'REMOTE_ADDR is not a header'     );
ok( ! exists $h->{ 'script-name'     }, 'SCRIPT_NAME is not a header'     );
ok( ! exists $h->{ '-client-ip'      }, '_CLIENT_IP is not a header'      );
is( scalar keys %$h, 6, 'exactly the six request headers are exposed' );

# cookies
is( ref $o->get_cookies(), 'HASH', 'get_cookies() returns a hashref' );
is( $o->get_cookie( 'sid'  ), 'abc123', 'get_cookie( sid )'  );
is( $o->get_cookie( 'lang' ), 'bg',     'get_cookie( lang )' );
is( $o->get_cookie( 'nope' ), undef,    'get_cookie() of a missing cookie is undef' );
is( app( env() )->get_cookie( 'sid' ), undef, 'get_cookie() with no cookie header at all' );
}

##############################################################################
##
##  section 5 -- client input parameters and uploads
##

{
my $o = app( env( 'QUERY_STRING' => 'a=1&a=2&b=x&na.me=ok&bad+name%21=nope&nul=a%00b&uni=%E2%98%83' ) );
my $in = $o->get_user_input();

is( ref $in, 'HASH', 'get_user_input() returns a hashref' );
is( $in->{ 'B' }, 'x', 'parameter names are upper cased' );
is( $in->{ 'NA.ME' }, 'ok', 'dots are valid in parameter names' );

is_deeply( $in->{ '@A' }, [ '1', '2' ], 'repeated parameter collected under @NAME' );
ok( ! exists $in->{ 'A' }, 'repeated parameter is not also stored as a scalar' );

ok( ! exists $in->{ 'BAD NAME!' }, 'invalid parameter name is skipped' );
like( join( '', @LOG ), qr/invalid CGI\/input parameter name/, 'invalid parameter name is logged' );

is( $in->{ 'NUL' }, 'ab', 'NUL bytes are stripped from values' );
is( $in->{ 'UNI' }, "\x{2603}", 'values are decoded from UTF-8' );
ok( utf8::is_utf8( $in->{ 'UNI' } ), 'decoded value is a character string' );

is( $o->get_user_input(), $in, 'get_user_input() result is cached' );

# safe input is a declared extension point, base has no facility for it
is_deeply( $o->get_safe_input(), {}, 'get_safe_input() is empty in the base class' );

# uploads, exercised over a real multipart request in section 13
is_deeply( app( env() )->get_user_uploads(), {}, 'get_user_uploads() is empty without a body' );
}

##############################################################################
##
##  section 6 -- post data
##
##  the body is deliberately not cached, whoever reads it owns it
##

{
my ( $fh, $fn ) = tempfile( UNLINK => 1 );
print $fh 'raw-body-payload';
close $fh;
open my $in, '<', $fn or die $!;

my $o = app( env( 'REQUEST_METHOD' => 'POST', 'CONTENT_LENGTH' => 16,
                  'CONTENT_TYPE'   => 'application/octet-stream', 'psgi.input' => $in ) );

ok( $o->get_user_postdata_fh(), 'get_user_postdata_fh() returns a handle' );
is( $o->get_user_postdata_body(), 'raw-body-payload', 'get_user_postdata_body() reads the body' );
is( $o->get_user_postdata_body(), undef, 'body is read once only, by design' );
close $in;
}

##############################################################################
##
##  section 7 -- response status, headers, cookies, body
##

{
my $o = app( env() );

is( $o->res_get_status(), undef, 'status is unset initially' );
is( $o->res_set_status( 404 ), 404, 'res_set_status()' );
is( $o->res_get_status(), 404,      'res_get_status()' );

is( $o->res_set_body( 'hello' ), 'hello', 'res_set_body()' );
is( $o->res_get_body(), 'hello',          'res_get_body()' );

# header names are lower cased, values are left alone
$o->res_set_headers( 'X-Mixed-Case' => '/Some/MixedCase/Path?A=B' );
is( hdrs( $o->res_get_headers_ar() )->{ 'x-mixed-case' }, '/Some/MixedCase/Path?A=B',
    'header names are lower cased, values are preserved verbatim' );

# status may be passed as a pseudo header
my $o2 = app( env() );
$o2->res_set_headers( status => 301, location => '/moved' );
is( $o2->res_get_status(), 301, 'status passed through res_set_headers()' );
ok( ! exists hdrs( $o2->res_get_headers_ar() )->{ 'status' }, 'status is not emitted as a header' );

# defaults and content type post processing
is( hdrs( app( env() )->res_get_headers_ar() )->{ 'content-type' }, 'application/octet-stream',
    'content-type defaults to application/octet-stream' );

my $o3 = app( env() );
$o3->res_set_headers( 'content-type' => 'text/html', 'content-charset' => 'UTF-8' );
my $h3 = hdrs( $o3->res_get_headers_ar() );
is( $h3->{ 'content-type' }, 'text/html; charset=UTF-8', 'content-charset is folded into content-type' );
ok( ! exists $h3->{ 'content-charset' }, 'content-charset is not emitted as a header' );

my $o4 = app( env() );
$o4->res_set_headers( 'content-type' => 'text/html; charset=iso-8859-1', 'content-charset' => 'UTF-8' );
is( hdrs( $o4->res_get_headers_ar() )->{ 'content-type' }, 'text/html; charset=iso-8859-1',
    'an existing charset in content-type is not overridden' );

# a location response carries no content type
my $o5 = app( env() );
$o5->res_set_headers( location => '/next' );
my $h5 = hdrs( $o5->res_get_headers_ar() );
is( $h5->{ 'location' }, '/next', 'location is emitted' );
ok( ! exists $h5->{ 'content-type' }, 'content-type is dropped when location is set' );

# cookies are emitted as repeated set-cookie headers
my $o6 = app( env() );
$o6->res_set_cookie( 'a', value => 1 );
$o6->res_set_cookie( 'b', value => 2, path => '/', httponly => 1 );
my $c6 = hdrs( $o6->res_get_headers_ar() )->{ 'set-cookie' };
is( ref $c6, 'ARRAY', 'two cookies produce two set-cookie headers' );
is( scalar @$c6, 2, 'both cookies are present' );
like( join( ' ', @$c6 ), qr/\ba=1\b/,        'first cookie value'  );
like( join( ' ', @$c6 ), qr/b=2.*HttpOnly/i, 'second cookie with attributes' );

is( scalar @{ app( env() )->res_get_headers_ar() } % 2, 0, 'header arrayref is always even length' );
}

##############################################################################
##
##  section 8 -- response header injection
##
##  CR/LF anywhere in a response header is a hard error, raised by
##  res_set_headers() so it happens inside the run() eval and the request gets
##  the ordinary error response instead of killing the application
##

{
for my $case ( [ 'value', 'location',      "/ok\r\nX-Injected: evil" ],
               [ 'value', 'x-thing',       "v\nX-Injected: evil"     ],
               [ 'name',  "x-bad\r\nx-in", 'clean-value'             ] )
  {
  my ( $what, $k, $v ) = @$case;
  my $o = app( env() );

  eval { $o->res_set_headers( $k => $v ) };
  like( $@, qr/invalid output header/, "CR/LF in header $what is a hard error on set" );

  # nothing poisoned may reach the stored headers
  my $stored = join '', %{ $o->{ 'OUT' }{ 'HEADERS' } || {} };
  unlike( $stored, qr/[\r\n]/, "CR/LF in header $what is never stored" );

  # and the response assembled afterwards must still be well formed
  my $ar = eval { $o->res_get_headers_ar() };
  is( $@, '', "res_get_headers_ar() is safe after a rejected header ($what)" );
  unlike( join( '', map { defined $_ ? $_ : '' } @$ar ), qr/[\r\n]/,
          "emitted headers never carry CR/LF ($what)" );
  }

my $o = app( env() );
$o->res_set_headers( 'x-clean' => 'perfectly-fine', 'content-type' => 'text/plain' );
my $ar = eval { $o->res_get_headers_ar() };
is( $@, '', 'clean headers do not raise' );
is( hdrs( $ar )->{ 'x-clean' }, 'perfectly-fine', 'clean headers are emitted' );

# res_get_headers_ar() no longer validates, so it must be repeatable: every
# call has to return the same complete set, never a truncated one
my $o2 = app( env() );
$o2->res_set_headers( 'x-a' => 1, 'x-b' => 2, 'x-c' => 3 );

my @tries;
push @tries, join( '|', @{ $o2->res_get_headers_ar() } ) for 1 .. 3;
is( scalar( grep { $_ eq $tries[0] } @tries ), 3, 'res_get_headers_ar() returns the same set on every call' );

# a poisoned header inside a run() must not escape as a crash
my $res = req( sub { $_[0]->forward_url( "/ok\r\nX-Injected: evil" ) } );
is( ref $res, 'ARRAY', 'a poisoned header still produces a PSGI response, not a crash' );
like( $res->[2][0], qr/currently unavailable/, 'a poisoned header gets the generic error body' );
unlike( join( '', map { defined $_ ? $_ : '' } @{ $res->[1] } ), qr/[\r\n]/,
        'the error response carries no injected header' );
}

##############################################################################
##
##  section 9 -- portray
##

{
my $o = app( env() );

my $pd = $o->portray( 'data', 'html' );
is( $pd->{ 'TYPE' }, 'text/html', 'portray() maps the html shortcut' );
is( $pd->{ 'DATA' }, 'data',      'portray() carries the data' );

is( $o->portray( '', 'text' )->{ 'TYPE' }, 'text/plain',               'text shortcut'  );
is( $o->portray( '', 'txt'  )->{ 'TYPE' }, 'text/plain',               'txt shortcut'   );
is( $o->portray( '', 'jpeg' )->{ 'TYPE' }, 'image/jpeg',               'jpeg shortcut'  );
is( $o->portray( '', 'png'  )->{ 'TYPE' }, 'image/png',                'png shortcut'   );
is( $o->portray( '', 'bin'  )->{ 'TYPE' }, 'application/octet-stream', 'bin shortcut'   );
is( $o->portray( '', 'application/pdf' )->{ 'TYPE' }, 'application/pdf', 'full mime type passes through' );
is( $o->portray( '', 'image/svg+xml' )->{ 'TYPE' }, 'image/svg+xml', 'mime type with + suffix is accepted' );
is( $o->portray( '', 'application/vnd.ms-excel' )->{ 'TYPE' }, 'application/vnd.ms-excel', 'vendor tree mime type is accepted' );

is( $o->portray( 'x', 'text', FILE_NAME => 'r.txt' )->{ 'FILE_NAME' }, 'r.txt', 'extra options pass through' );

eval { $o->portray( 'x', 'nonsense' ) };
like( $@, qr/portray needs mime type/, 'portray() rejects a non mime type' );
}

##############################################################################
##
##  section 10 -- render
##

{
# text is encoded to UTF-8 bytes and gets a charset
my $o = app( env() );
eval { $o->render( $o->portray( "snow \x{2603}", 'html' ) ) };
my $body = $o->res_get_body();
ok( ! utf8::is_utf8( $body ), 'rendered text body is bytes, not characters' );
is( $body, encode( 'UTF-8', "snow \x{2603}" ), 'body is encoded as UTF-8' );
is( hdrs( $o->res_get_headers_ar() )->{ 'content-type' }, 'text/html; charset=UTF-8',
    'text response carries the UTF-8 charset' );

# binary is passed through untouched and gets no charset
my $o2 = app( env() );
my $png = "\x89PNG\r\n\x1a\n\x00\xff";
eval { $o2->render( $o2->portray( $png, 'png' ) ) };
is( $o2->res_get_body(), $png, 'binary body is passed through unchanged' );
is( hdrs( $o2->res_get_headers_ar() )->{ 'content-type' }, 'image/png', 'binary response has no charset' );

# a file handle takes priority over data
my ( $tfh, $tfn ) = tempfile( UNLINK => 1 );
print $tfh 'from-file';
close $tfh;
open my $rfh, '<', $tfn or die $!;
my $o3 = app( env() );
eval { $o3->render( { FH => $rfh, DATA => 'ignored', TYPE => 'text/plain' } ) };
is( $o3->res_get_body(), $rfh, 'FH takes priority over DATA' );
close $rfh;

# content-disposition, plain ascii file name
my $o4 = app( env() );
eval { $o4->render( $o4->portray( 'x', 'bin', FILE_NAME => 'report.pdf' ) ) };
is( hdrs( $o4->res_get_headers_ar() )->{ 'content-disposition' }, 'inline; filename="report.pdf"',
    'content-disposition defaults to inline' );

my $o5 = app( env() );
eval { $o5->render( $o5->portray( 'x', 'bin', FILE_NAME => 'r.pdf', DISPOSITION_TYPE => 'attachment' ) ) };
like( hdrs( $o5->res_get_headers_ar() )->{ 'content-disposition' }, qr/^attachment; /,
      'DISPOSITION_TYPE is honoured' );

# a file name must never be able to inject a header
my $o6 = app( env() );
eval { $o6->render( $o6->portray( 'x', 'bin', FILE_NAME => "a\r\nX-Injected: evil.pdf" ) ) };
my $cd6 = hdrs( $o6->res_get_headers_ar() )->{ 'content-disposition' };
unlike( $cd6, qr/[\r\n]/, 'CR/LF is stripped from the file name' );

# non ascii file names get the RFC 5987 form alongside the ascii one
my $o7 = app( env() );
eval { $o7->render( $o7->portray( 'x', 'bin', FILE_NAME => "\x{441}\x{43D}\x{435}\x{433}.pdf" ) ) };
my $cd7 = hdrs( $o7->res_get_headers_ar() )->{ 'content-disposition' };
like( $cd7, qr/filename="_+\.pdf"/,      'non ascii file name has an ascii fallback' );
like( $cd7, qr/filename\*=UTF-8''%D1%81/, 'non ascii file name has a percent encoded UTF-8 form' );

# content security policy comes from config
my $o8 = app( env(), { HTTP_CSP => "default-src 'self'" } );
eval { $o8->render( $o8->portray( 'x', 'html' ) ) };
is( hdrs( $o8->res_get_headers_ar() )->{ 'content-security-policy' }, "default-src 'self'",
    'HTTP_CSP config is emitted as a header' );
ok( ! exists hdrs( app( env() )->res_get_headers_ar() )->{ 'content-security-policy' },
    'no CSP header without the config' );

# render() does not return, it unwinds to run()
my $o9 = app( env() );
eval { $o9->render( $o9->portray( 'x', 'html' ) ); fail( 'render() returned' ) };
ok( $@, 'render() raises to unwind into run()' );
}

##############################################################################
##
##  section 11 -- forward_url
##

{
my $res = req( sub { $_[0]->forward_url( '/somewhere/else' ) } );

is( $res->[0], 302, 'forward_url() responds 302' );
my $h = hdrs( $res->[1] );
is( $h->{ 'location' }, '/somewhere/else', 'forward_url() sets location' );
ok( ! exists $h->{ 'content-type' }, 'a redirect carries no content-type' );
is_deeply( $res->[2], [ '' ], 'a redirect has an empty string body, not undef' );
}

##############################################################################
##
##  section 12 -- run(), the full PSGI cycle
##

{
my $res = req( sub { my $s = shift; $s->render( $s->portray( 'body text', 'text' ) ) } );

is( ref $res,      'ARRAY', 'run() returns an arrayref' );
is( scalar @$res,  3,       'run() returns a triplet' );
is( $res->[0],     200,     'status defaults to 200' );
is( ref $res->[1], 'ARRAY', 'headers are an arrayref' );
is( ref $res->[2], 'ARRAY', 'body is an arrayref' );
is( $res->[2][0],  'body text', 'body content' );
is( hdrs( $res->[1] )->{ 'content-type' }, 'text/plain; charset=UTF-8', 'content type of the response' );

# an explicit status is kept
my $res2 = req( sub { my $s = shift; $s->res_set_status( 404 ); $s->render( $s->portray( 'gone', 'text' ) ) } );
is( $res2->[0], 404, 'an explicit status survives run()' );

# a handler that dies gets the generic error response, never a stack trace
my $res3 = req( sub { die "something broke in the application\n" } );
is( $res3->[0], 200, 'a dying handler still produces a response' );
like( $res3->[2][0], qr/currently unavailable/, 'a dying handler gets the generic error body' );
unlike( $res3->[2][0], qr/something broke/, 'the internal error is not leaked to the client' );
like( join( '', @LOG ), qr/something broke/, 'the internal error is logged' );

# a handler that renders nothing at all
my $res4 = req( sub { 1 } );
is( $res4->[0], 200, 'a handler that never renders still produces a response' );
like( $res4->[2][0], qr/currently unavailable/, 'no render gets the generic error body' );

# base class without an implementation must say so
my $o = Web::Reactor::Core->new( env(), { DEBUG => 0 } );
eval { $o->process_request() };
like( $@, qr/subclass Web::Reactor::Core/, 'process_request() must be implemented by a subclass' );
}

##############################################################################
##
##  section 12b -- res_clear_headers(), run_print_final_debug()
##

{
my $o = app( env() );
$o->res_set_headers( 'X-One' => 'a' );
$o->res_clear_headers();
my %h = @{ $o->res_get_headers_ar() };
ok( ! exists $h{ 'x-one' }, 'res_clear_headers() drops the headers set before' );
ok( eval { $o->run_print_final_debug(); 1 }, 'run_print_final_debug() is a no-op in Core' );
}

##############################################################################
##
##  section 12a -- start time and html ids
##

{
my $o  = app( env() );
my $o2 = app( env() );

ok( $o->start_time() > 0, 'start_time() is set by new()' );
like( $o->start_time(), qr/^\d+(\.\d+)?$/, 'start_time() is unix time, with fractions' );

my $scope = $o->get_uniq_id_scope();
like( $scope, qr/^\Q$$\E_\d+_[A-Za-z0-9]{8}$/, 'get_uniq_id_scope() is pid, start time in microseconds and a random part' );
is( $o->get_uniq_id_scope(), $scope, 'get_uniq_id_scope() is the same within the object' );
isnt( $o2->get_uniq_id_scope(), $scope, 'another object gets another scope' );

is( $o->create_uniq_id(), "$scope.1", 'create_uniq_id() is scope.1 first' );
is( $o->create_uniq_id(), "$scope.2", 'create_uniq_id() counts up' );
is( $o2->create_uniq_id(), $o2->get_uniq_id_scope() . '.1', 'the counter is per object' );
}

##############################################################################
##
##  section 13 -- over a real HTTP connection
##
##  everything above builds its own environment, this section proves the same
##  code path works against a server that produces the environment for us
##

SKIP:
{
eval { require Plack::Test; require HTTP::Request::Common; require Plack::Middleware::Lint; 1 }
  or skip( 'Plack::Test / Plack::Middleware::Lint not available', 13 );

$Plack::Test::Impl = 'Server';

my ( $ufh, $ufn ) = tempfile( UNLINK => 1 );
print $ufh "uploaded-file-content\n";
close $ufh;

# the application under test reports back everything it saw on the request
my $app = sub
    {
    my $o = TestApp->new( shift, { DEBUG => 0 } );
    $o->{ 'HANDLER' } = sub
        {
        my $s  = shift;
        my $in = $s->get_user_input();
        my $up = $s->get_user_uploads();
        my $out = join "\n",
                  'method: '    . $s->get_request_method(),
                  'ctype: '     . ( $s->get_header( 'content-type' ) || '' ),
                  'custom: '    . ( $s->get_header( 'x-custom'     ) || '' ),
                  'cookie: '    . ( $s->get_cookie( 'sid' )          || '' ),
                  'query: '     . ( $in->{ 'Q' }                     || '' ),
                  'multi: '     . join( ',', @{ $in->{ '@M' } || [] } ),
                  'uni: '       . ( $in->{ 'UNI' }                   || '' ),
                  'upload: '    . join( ',', map { $_->filename } @{ $up->{ 'FILE' } || [] } );
        $s->res_set_cookie( 'given', value => 'yes' );
        $s->render( $s->portray( $out, 'text' ) );
        };
    return $o->run();
    };

Plack::Test::test_psgi( Plack::Middleware::Lint->wrap( $app ), sub
    {
    my $cb = shift;

    my $res = $cb->( HTTP::Request::Common::POST(
                     '/app?q=hello&uni=%E2%98%83',
                     'X-Custom'     => 'custom-header',
                     'Cookie'       => 'sid=cookie-value',
                     'Content-Type' => 'form-data',
                     'Content'      => [ m => 'one', m => 'two',
                                         file => [ $ufn, 'upload.txt' ] ] ) );

    is( $res->code, 200, 'live request succeeds and passes PSGI Lint' );

    my %got = map { /^(\w+): (.*)$/ ? ( $1 => $2 ) : () } split /\n/, decode( 'UTF-8', $res->content );

    is(   $got{ 'method' }, 'POST',                     'live request method'     );
    like( $got{ 'ctype'  }, qr{^multipart/form-data},   'live content-type header' );
    is(   $got{ 'custom' }, 'custom-header',            'live custom header'      );
    is(   $got{ 'cookie' }, 'cookie-value',             'live request cookie'     );
    is(   $got{ 'query'  }, 'hello',                    'live query parameter'    );
    is(   $got{ 'multi'  }, 'one,two',                  'live repeated parameter' );
    is(   $got{ 'uni'    }, "\x{2603}",                 'live UTF-8 parameter'    );
    is(   $got{ 'upload' }, 'upload.txt',               'live file upload'        );

    like( $res->header( 'Content-Type' ), qr/text\/plain; charset=UTF-8/, 'live response content type' );
    like( $res->header( 'Set-Cookie'   ), qr/given=yes/,                  'live response cookie'       );
    } );

# a redirect over the wire
my $redir = sub
    {
    my $o = TestApp->new( shift, { DEBUG => 0 } );
    $o->{ 'HANDLER' } = sub { $_[0]->forward_url( '/redirected' ) };
    return $o->run();
    };

Plack::Test::test_psgi( Plack::Middleware::Lint->wrap( $redir ), sub
    {
    my $res = shift->( HTTP::Request::Common::GET( '/app' ) );

    is( $res->code, 302, 'live redirect status' );
    is( $res->header( 'Location' ), '/redirected', 'live redirect location' );
    } );
}

##############################################################################

done_testing();

###EOF########################################################################
