#!/usr/bin/perl
##############################################################################
##
##  Web::Reactor::Reflex stateless application machinery
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
##
##  single-file test utility for Web::Reactor::Reflex
##
##  usage:
##
##    cd t && perl test_reactor_reflex.pl        -- run, TAP output on stdout
##    perl t/test_reactor_reflex.pl              -- same, from the distribution root
##    perl t/test_reactor_reflex.pl -v           -- also pass reactor log() to stderr
##    perl -I/path/to/crypto/lib t/test_reactor_reflex.pl
##                                               -- include the safe input tests
##
##  builds a throw-away application (pages, includes, action files, action
##  packages, translations) in a temporary directory and drives it through
##  hand-built PSGI environments; the last section runs it over a real HTTP
##  connection. sections that need Data::Tools::Crypto::Symmetric are skipped
##  when it is not installed.
##
##############################################################################
use strict;

use lib '../lib'; # when run from inside t/
use lib 'lib';    # when run from the distribution root

use Test::More;
use File::Temp qw( tempdir tempfile );
use File::Path qw( make_path );
use Encode;
use Data::Tools;

my $VERBOSE = grep { $_ eq '-v' } @ARGV;

##############################################################################
##
##  test application class
##
##  must live under Web::Reactor:: (see Web::Reactor::Base::__set_reo).
##  LOG collects everything the object logs, HOOK lets a test run code inside
##  process_request() before the normal dispatch, e.g. to forward or to set
##  hold values from safe input.
##

our @LOG;

package Web::Reactor::TestReflex;
our @ISA = ( 'Web::Reactor::Reflex' );

sub log
{
  my $self = shift;
  push @LOG, join '', @_;
  print STDERR @_, "\n" if $VERBOSE;
}

sub process_request
{
  my $self = shift;

  $self->html_hold_set( foo => 'FOO', x => $self->get_safe_input->{ 'X' } // '' );
  $self->{ 'HOOK' }->( $self ) if $self->{ 'HOOK' };

  return $self->SUPER::process_request( @_ );
}

package main;

##############################################################################
##
##  section 1 -- loading
##

require_ok( 'Web::Reactor::Reflex' );
ok( $Web::Reactor::Reflex::VERSION, "Web::Reactor::Reflex::VERSION is set [$Web::Reactor::Reflex::VERSION]" );
isa_ok( 'Web::Reactor::Reflex', 'Web::Reactor::Core', 'Web::Reactor::Reflex' );

for my $m ( qw( new act pre cry process_request render_action render_page
                get_user_input_button get_lang get_app_name get_app_root
                args args_type argsx argsx_type
                html_hold_set html_hold_get html_hold_del html_hold_clear html_hold_reset
                html_hold_kit_add html_hold_kit_js html_hold_kit_css
                forward require_post_method load_trans load_trans_file
                set_browser_window_title
                run cfg env get_user_input get_safe_input render portray forward_url ) )
  {
  can_ok( 'Web::Reactor::Reflex', $m );
  }

my $HAS_CRYPTO = eval { require Data::Tools::Crypto::Symmetric; 1 } ? 1 : 0;
diag( "Data::Tools::Crypto::Symmetric not installed, safe input / forward tests will be skipped" ) unless $HAS_CRYPTO;

##############################################################################
##
##  section 2 -- throw-away application
##
##  html/default/main/index.html          root page, hold + include + title
##  html/default/inc.html                 root include
##  html/default/admin/users/index.html   nested page showing hold x
##  html/default/withact/index.html       page calling an action tag
##  html/default/epostrequired/index.html page rendered by require_post_method()
##  html/default/empty/index.html         empty page file
##  html/bg/main/index.html               language override of the root page
##  actions/*.pm                          Files dispatcher actions (default)
##  lib/Web/Reactor/Actions/testreflex/   Packages dispatcher action
##  trans/bg/ui.tr                        translation file
##

my $ROOT = tempdir( CLEANUP => 1 );

sub put
{
  my ( $rel, $text ) = @_;
  my $fn = "$ROOT/$rel";
  ( my $dir = $fn ) =~ s{/[^/]+$}{};
  make_path( $dir ) unless -d $dir;
  file_save( $fn, $text ) or die "cannot write [$fn]";
}

put( 'html/default/main/index.html',          'MAIN foo=[<$foo>] inc=[<#inc>] title=[<$browser_window_title>]' );
put( 'html/default/inc.html',                 'INC' );
put( 'html/default/admin/users/index.html',   'USERS x=[<$x>]' );
put( 'html/default/withact/index.html',       'act=[<&hello a=1>]' );
put( 'html/default/epostrequired/index.html', 'POST REQUIRED' );
put( 'html/default/empty/index.html',         '' );
put( 'html/bg/main/index.html',               'BG MAIN' );

put( 'actions/hello.pm', <<'EOF' );
package reactor::actions::hello;
use strict;
sub main
{
  my $reo  = shift;
  my %args = @_;
  my $ha   = $args{ 'HTML_ARGS' } || {};
  return 'hello ' . join( ',', map { "$_=$ha->{ $_ }" } sort keys %$ha ) . ' foo=<$foo>';
}
1;
EOF

put( 'actions/portray.pm', <<'EOF' );
package reactor::actions::portray;
use strict;
sub main { my $reo = shift; return $reo->portray( 'raw <$foo>', 'text' ) }
1;
EOF

put( 'actions/empty.pm',  "package reactor::actions::empty;\nuse strict;\nsub main { return '' }\n1;\n" );
put( 'actions/undef.pm',  "package reactor::actions::undef;\nuse strict;\nsub main { return undef }\n1;\n" );
put( 'actions/dies.pm',   "package reactor::actions::dies;\nuse strict;\nsub main { die \"action died on purpose\\n\" }\n1;\n" );
put( 'actions/fwd.pm',    "package reactor::actions::fwd;\nuse strict;\nsub main { \$_[0]->forward( _pn => 'admin/users', x => 'via-fwd' ) }\n1;\n" );
put( 'actions/post.pm',   "package reactor::actions::post;\nuse strict;\nsub main { \$_[0]->require_post_method(); return 'posted' }\n1;\n" );
put( 'actions/title.pm',  "package reactor::actions::title;\nuse strict;\nsub main { \$_[0]->set_browser_window_title( '<b>My</b> Title' ); return 't=[<\$browser_window_title>]' }\n1;\n" );

put( 'actions/btn.pm', <<'EOF' );
package reactor::actions::btn;
use strict;
sub main
{
  my $reo = shift;
  my ( $b, $i ) = $reo->get_user_input_button();
  my $s = $reo->get_user_input_button();
  return 'btn=[' . ( $b // '' ) . '] id=[' . ( $i // '' ) . '] scalar=[' . ( $s // '' ) . ']';
}
1;
EOF

put( 'actions/input.pm', <<'EOF' );
package reactor::actions::input;
use strict;
sub main
{
  my $reo = shift;
  my $in  = $reo->get_user_input();
  my $si  = $reo->get_safe_input();
  return 'user=[' . ( $in->{ 'X' } // '' ) . '] safe=[' . ( $si->{ 'X' } // '' ) . ']';
}
1;
EOF

put( 'lib/Web/Reactor/Actions/testreflex/pkg.pm',
     "package Web::Reactor::Actions::testreflex::pkg;\nuse strict;\nsub main { return 'from package' }\n1;\n" );

# Packages dispatcher: broken app actions must not fall back to Base
put( 'lib/Web/Reactor/Actions/testreflex/brokendep.pm', "package Web::Reactor::Actions::testreflex::brokendep;\nuse strict;\nuse No::Such::Module::Here;\nsub main { 'APP' }\n1;\n" );
put( 'lib/Web/Reactor/Actions/Base/brokendep.pm',       "package Web::Reactor::Actions::Base::brokendep;\nuse strict;\nsub main { 'BASE' }\n1;\n" );
put( 'lib/Web/Reactor/Actions/testreflex/brokensyn.pm', "package Web::Reactor::Actions::testreflex::brokensyn;\nuse strict;\nsub main { 'APP' \n1;\n" );
put( 'lib/Web/Reactor/Actions/Base/brokensyn.pm',       "package Web::Reactor::Actions::Base::brokensyn;\nuse strict;\nsub main { 'BASE' }\n1;\n" );
put( 'lib/Web/Reactor/Actions/Base/inbase.pm',          "package Web::Reactor::Actions::Base::inbase;\nuse strict;\nsub main { 'IN BASE' }\n1;\n" );

# Files dispatcher: an action file which does not compile
put( 'actions/brokenfile.pm', "package reactor::actions::brokenfile;\nuse strict;\nsub main { 'X' \n1;\n" );

put( 'trans/bg/ui.tr', "hello=  Hi there  \nbye=Bye\n" );
put( 'trans/single.tr', "only=one\n" );

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
         'SERVER_NAME'     => 'localhost',
         'SERVER_PORT'     => '443',
         'SERVER_PROTOCOL' => 'HTTP/1.1',
         'REMOTE_ADDR'     => '127.0.0.1',
         'psgi.version'    => [ 1, 1 ],
         'psgi.url_scheme' => 'https',
         'psgi.errors'     => \*STDERR,
         'psgi.input'      => undef,
         %over,
         };
}

# GET request with a query string
sub get { my $qs = shift; return env( 'QUERY_STRING' => $qs, 'REQUEST_URI' => "/app?$qs" ) }

# POST request with a query string and an empty body
sub post { return env( 'REQUEST_METHOD' => 'POST', 'CONTENT_LENGTH' => 0, 'QUERY_STRING' => shift ) }

# base config, extra keys override
sub cfg
{
  return {
         'APP_NAME' => 'testreflex',
         'APP_ROOT' => $ROOT,
         'LANG'     => 'en',
         'CRY_KEY'  => 'k' x 32,
         'DEBUG'    => 0,
         @_,
         };
}

sub app
{
  my $env  = shift || env();
  my $over = shift || {};

  @LOG = ();
  return Web::Reactor::TestReflex->new( $env, cfg( %$over ) );
}

# run a full request, returns the PSGI triplet
sub req
{
  my $env  = shift;
  my $over = shift || {};
  my $hook = shift;

  my $o = app( $env, $over );
  $o->{ 'HOOK' } = $hook if $hook;
  return $o->run();
}

sub body { return join '', @{ $_[0]->[2] } }
sub logs { return join "\n", @LOG }

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

# what a failed request looks like from the outside
sub is_unavailable
{
  my ( $res, $name ) = @_;
  is( $res->[0], 200, "$name: status" );
  like( body( $res ), qr/currently unavailable/, "$name: generic error body" );
}

##############################################################################
##
##  section 3 -- constructor, config validation, plugs
##

{
my $o = app();
isa_ok( $o, 'Web::Reactor::Reflex', 'constructed object' );
isa_ok( $o, 'Web::Reactor::Core',   'constructed object' );

is( $o->cfg->{ 'APP_NAME' }, 'testreflex', 'cfg() carries the config' );
is( $o->cfg->{ 'CHARSET'  }, 'UTF-8',      'CHARSET is forced by Core' );

for my $case ( [ { APP_NAME => 'bad name' }, qr/invalid APP_NAME/, 'APP_NAME with a space'   ],
               [ { APP_NAME => 'Upper'    }, qr/invalid APP_NAME/, 'APP_NAME with uppercase' ],
               [ { APP_NAME => ''         }, qr/invalid APP_NAME/, 'empty APP_NAME'          ],
               [ { APP_NAME => undef      }, qr/invalid APP_NAME/, 'missing APP_NAME'        ],
               [ { LANG => 'BG'           }, qr/invalid LANG/,     'uppercase LANG'          ],
               [ { LANG => 'eng'          }, qr/invalid LANG/,     'three letter LANG'       ],
               [ { LANG => 'e'            }, qr/invalid LANG/,     'one letter LANG'         ],
               [ { APP_ROOT => "$ROOT/no" }, qr/invalid APP_ROOT/, 'missing APP_ROOT'        ] )
  {
  my ( $over, $re, $name ) = @$case;
  eval { app( env(), $over ) };
  like( $@, $re, "new() rejects $name" );
  }

# LANG is optional: empty or missing means no language tree, default only
ok( eval { app( env(), { LANG => '' } ) },    'empty LANG is accepted' );
ok( eval { app( env(), { LANG => undef } ) }, 'missing LANG is accepted' );
is( app( env(), { LANG => '' } )->get_lang(), '', 'get_lang() is empty when LANG is empty' );

# plugs are created on first use, not in the constructor
my $p = app();
ok( ! exists $p->{ 'REO_ACT' }, 'action dispatcher is not created by new()' );
ok( ! exists $p->{ 'REO_PRE' }, 'preprocessor is not created by new()' );
isa_ok( $p->act(), 'Web::Reactor::Actions::Files',     'default act()' );
isa_ok( $p->pre(), 'Web::Reactor::Preprocessor::Tree', 'default pre()' );
is( $p->act(), $p->act(), 'act() returns the same object every time' );
is( $p->pre(), $p->pre(), 'pre() returns the same object every time' );
is( $p->act->reo(), $p, 'dispatcher points back at the reactor' );
is( $p->pre->cfg(), $p->cfg(), 'preprocessor shares the reactor config' );

isa_ok( app( env(), { REO_ACT_CLASS => 'Web::Reactor::Actions::Packages' } )->act(),
        'Web::Reactor::Actions::Packages', 'REO_ACT_CLASS override' );

eval { app( env(), { REO_PRE_CLASS => 'Web::Reactor::No::Such::Class' } )->pre() };
like( $@, qr/Can't locate/, 'an unknown plug class fails loudly' );
}

##############################################################################
##
##  section 4 -- config accessors
##

{
my $o = app();
is( $o->get_lang(),     'en',        'get_lang()'     );
is( $o->get_app_name(), 'testreflex','get_app_name()' );
is( $o->get_app_root(), $ROOT,       'get_app_root()' );
}

##############################################################################
##
##  section 5 -- page dispatch
##

{
my $res = req( env() );
is( $res->[0], 200, 'GET / status' );
is( body( $res ), 'MAIN foo=[FOO] inc=[INC] title=[]', 'GET / renders page main with hold and include' );
is( hdrs( $res->[1] )->{ 'content-type' }, 'text/html; charset=UTF-8', 'page response is UTF-8 html' );

is( body( req( get( '_pn=main' ) ) ),        body( $res ),         '_pn=main is the same as no page name' );
is( body( req( get( '_PN=MAIN' ) ) ),        body( $res ),         'parameter name and page name are case insensitive' );
is( body( req( get( '_pn=admin/users' ) ) ), 'USERS x=[]',         'nested page name selects a page directory' );
is( body( req( get( '_pn=withact' ) ) ),     'act=[hello A=1 foo=FOO]', 'action tag inside a page is called and its output processed' );

my $r = req( get( '_pn=nosuch' ) );
is_unavailable( $r, 'missing page' );
like( logs(), qr/cannot load file \[index\] for page \[nosuch\]/, 'missing page is logged' );

$r = req( get( '_pn=empty' ) );
is_unavailable( $r, 'empty page' );
like( logs(), qr/rendering page \[empty\] returns empty text/, 'empty page is logged' );

for my $bad ( 'Bad%20Name', '../main', 'main/', '/main', 'a//b' )
  {
  $r = req( get( "_pn=$bad" ) );
  is_unavailable( $r, "page name [$bad]" );
  like( logs(), qr/invalid page name/, "page name [$bad] is rejected before any lookup" );
  }

# language: the LANG tree wins, missing pages fall back to default
is( body( req( env(), { LANG => 'bg' } ) ),                 'BG MAIN',    'LANG selects the language page tree' );
is( body( req( get( '_pn=admin/users' ), { LANG => 'bg' } ) ), 'USERS x=[]', 'page missing in the language tree falls back to default' );
is( body( req( env(), { LANG => '' } ) ), 'MAIN foo=[FOO] inc=[INC] title=[]', 'empty LANG serves the default tree only' );
is( body( req( get( '_pn=admin/users' ), { LANG => '' } ) ), 'USERS x=[]', 'empty LANG, nested page' );
}

##############################################################################
##
##  section 6 -- action dispatch
##

{
is( body( req( get( '_an=hello' ) ) ), 'hello  foo=FOO', 'action output is processed as html' );
is( body( req( get( '_AN=HELLO' ) ) ), 'hello  foo=FOO', 'action name is case insensitive' );
is( body( req( get( '_an=hello&_pn=admin/users' ) ) ), 'hello  foo=FOO', 'action wins over page when both are given' );

my $r = req( get( '_an=portray' ) );
is( body( $r ), 'raw <$foo>', 'a non-html portray result is not preprocessed' );
is( hdrs( $r->[1] )->{ 'content-type' }, 'text/plain; charset=UTF-8', 'portray type is honoured' );

is( body( req( get( '_an=title' ) ) ), 't=[My Title]', 'set_browser_window_title() strips html and is visible to templates' );

$r = req( get( '_an=nosuch' ) );
is_unavailable( $r, 'missing action' );
like( logs(), qr/code for action name \[nosuch\] not found/, 'missing action is logged' );

for my $bad ( 'x-y', 'Bad%20Name', 'a/b', 'a.b' )
  {
  $r = req( get( "_an=$bad" ) );
  is_unavailable( $r, "action name [$bad]" );
  like( logs(), qr/invalid action name/, "action name [$bad] is rejected before any lookup" );
  }

$r = req( get( '_an=empty' ) );
is_unavailable( $r, 'action returning empty string' );
like( logs(), qr/rendering action \[empty\] returns empty data/, 'empty action result is logged' );

$r = req( get( '_an=undef' ) );
is_unavailable( $r, 'action returning undef' );
like( logs(), qr/rendering action \[undef\] returns empty data/, 'undef action result is logged' );

$r = req( get( '_an=dies' ) );
is_unavailable( $r, 'dying action' );
like( logs(), qr/action code call failed: dies.*action died on purpose/s, 'the action error is logged with its reason' );
unlike( body( $r ), qr/died on purpose/, 'the action error is not leaked to the client' );
}

##############################################################################
##
##  section 7 -- render_page() and render_action() called directly
##

{
my $o = app();
eval { $o->render_page( 'main' ) };
like( $@, qr/RENDER/, 'render_page() sinks RENDER' );
is( decode( 'UTF-8', $o->res_get_body() ), 'MAIN foo=[] inc=[INC] title=[]', 'render_page() body (no hold set outside dispatch)' );

$o = app();
eval { $o->render_page( 'empty' ) };
like( $@, qr/returns empty text/, 'render_page() booms on an empty page' );

$o = app();
$o->html_hold_set( foo => 'direct' );
eval { $o->render_action( 'hello' ) };
like( $@, qr/RENDER/, 'render_action() sinks RENDER' );
is( decode( 'UTF-8', $o->res_get_body() ), 'hello  foo=direct', 'render_action() body' );

$o = app();
eval { $o->render_action( 'empty' ) };
like( $@, qr/returns empty data/, 'render_action() booms on an empty result' );
}

##############################################################################
##
##  section 8 -- html hold
##

{
my $o = app();

is( ref $o->html_hold_set( Alpha => 'a', beta => 'b' ), 'HASH', 'html_hold_set() returns the hold' );
is( $o->html_hold_get( 'alpha' ), 'a', 'names are stored lower cased' );
is( $o->html_hold_get( 'ALPHA' ), 'a', 'html_hold_get() is case insensitive' );
is( $o->html_hold_get( 'beta'  ), 'b', 'second value' );
is( $o->html_hold_get( 'nope'  ), undef, 'unknown name is undef' );

$o->html_hold_set( alpha => 'a2' );
is( $o->html_hold_get( 'alpha' ), 'a2', 'html_hold_set() overwrites' );
is( $o->html_hold_get( 'beta'  ), 'b',  'html_hold_set() keeps other names' );

ok( $o->html_hold_del( 'ALPHA' ), 'html_hold_del()' );
is( $o->html_hold_get( 'alpha' ), undef, 'deleted name is gone' );

$o->html_hold_clear();
is( $o->html_hold_get( 'beta' ), undef, 'html_hold_clear() empties the hold' );

$o->html_hold_set( one => 1 );
$o->html_hold_reset( two => 2 );
is( $o->html_hold_get( 'one' ), undef, 'html_hold_reset() drops old names' );
is( $o->html_hold_get( 'two' ), 2,     'html_hold_reset() sets new names' );

# kits collect unique snippets, sorted, under one hold name
$o->html_hold_kit_add( 'KIT', '<b>' );
$o->html_hold_kit_add( 'kit', '<a>' );
$o->html_hold_kit_add( 'kit', '<b>' );
is( $o->html_hold_get( 'kit' ), '<a><b>', 'html_hold_kit_add() deduplicates and sorts snippets' );

$o->html_hold_kit_js( 'a.js' );
$o->html_hold_kit_js( 'a.js' );
$o->html_hold_kit_css( 's.css' );
my $head = $o->html_hold_get( 'kit_head' );
is( scalar( () = $head =~ /a\.js/g ), 1, 'html_hold_kit_js() adds a script once' );
like( $head, qr/<script[^>]*src='a\.js'/, 'script tag' );
like( $head, qr/<link[^>]*href="s\.css"/, 'stylesheet tag' );

$o->set_browser_window_title( '<i>Hi</i> <b>there</b>' );
is( $o->html_hold_get( 'browser_window_title' ), 'Hi there', 'set_browser_window_title() strips tags' );
}

##############################################################################
##
##  section 9 -- form buttons
##

{
is( body( req( get( '_an=btn&BUTTON:SAVE:42=1' ) ) ),   'btn=[SAVE] id=[42] scalar=[SAVE]', 'button with id' );
is( body( req( get( '_an=btn&BUTTON:CANCEL=1' ) ) ),    'btn=[CANCEL] id=[] scalar=[CANCEL]', 'button without id' );
is( body( req( get( '_an=btn&BUTTON:GO.X=3&BUTTON:GO.Y=4' ) ) ), 'btn=[GO] id=[] scalar=[GO]', 'image button coordinates are stripped' );
is( body( req( get( '_an=btn&button:save:7=1' ) ) ),    'btn=[SAVE] id=[7] scalar=[SAVE]', 'button parameter name is case insensitive' );
is( body( req( get( '_an=btn&other=1' ) ) ),            'btn=[] id=[] scalar=[]', 'no button pressed' );
}

##############################################################################
##
##  section 10 -- require_post_method
##

{
is( body( req( post( '_an=post' ) ) ), 'posted', 'require_post_method() lets a POST through' );
is( body( req( get(  '_an=post' ) ) ), 'POST REQUIRED', 'require_post_method() renders epostrequired on GET' );
}

##############################################################################
##
##  section 11 -- safe input: args(), forward(), the _ token
##

SKIP:
{
skip( 'Data::Tools::Crypto::Symmetric not installed', 29 ) unless $HAS_CRYPTO;

my $o = app();

# argsx() is the encrypted form, args() is the class default: in Reflex the two
# are the same thing (aliases), Reactor overrides args() with hidden link args
my $tok = $o->argsx( a => 1, Bee => 'x y' );
like( $tok, qr/^~[A-Za-z0-9_\-]+$/, 'argsx() returns a ~ prefixed base64url token' );
is_deeply( $o->cry->thaw_base64url( substr( $tok, 1 ) ), { A => 1, BEE => 'x y' }, 'argsx() token decrypts to the arguments with upper cased keys' );
isnt( $o->argsx( a => 1 ), $o->argsx( a => 1 ), 'every argsx() token is different (random iv)' );
is_deeply( $o->cry->thaw_base64url( substr( $o->argsx_type( 'back', z => 9 ), 1 ) ), { Z => 9 }, 'argsx_type() ignores the type and encodes the arguments' );

like( $o->args( a => 1 ), qr/^~[A-Za-z0-9_\-]+$/, 'args() in Reflex is the encrypted form' );
is_deeply( $o->cry->thaw_base64url( substr( $o->args( q => 'v' ), 1 ) ), { Q => 'v' }, 'args() token decrypts like argsx()' );
is_deeply( $o->cry->thaw_base64url( substr( $o->args_type( 'new', z => 9 ), 1 ) ), { Z => 9 }, 'args_type() in Reflex is argsx_type()' );
is( \&Web::Reactor::Reflex::args,      \&Web::Reactor::Reflex::argsx,      'args is an alias of argsx' );
is( \&Web::Reactor::Reflex::args_type, \&Web::Reactor::Reflex::argsx_type, 'args_type is an alias of argsx_type' );

# an encrypted token is decoded by the safe input importer, hidden link
# tokens (sid.key) are a Reactor feature and are ignored here
is_deeply( app( get( '_=' . $o->argsx( k => 'v' ) ) )->get_safe_input(), { K => 'v' }, 'get_safe_input() decodes an argsx() token' );
is_deeply( app( get( '_=abcd.efgh' ) )->get_safe_input(), {}, 'a hidden sid.key token gives no safe input in Reflex' );
ok( ( grep { /input data \[abcd\.efgh\], ignored/ } @LOG ), 'unsupported hidden token is logged' );
is_deeply( app( env( 'QUERY_STRING' => '_=' . $o->argsx( a => 1 ), 'REQUEST_METHOD' => 'POST', 'CONTENT_LENGTH' => 0 ) )->get_safe_input(), { A => 1 }, 'token in the query of a POST' );

# safe input drives the dispatch and overrides user input
my $t = $o->args( _AN => 'input', X => 'safe' );
is( body( req( get( "_=$t&x=user&_an=hello" ) ) ), 'user=[user] safe=[safe]', 'safe input selects the action and carries its own values' );

my $t2 = $o->args( _PN => 'admin/users', X => 'from-token' );
is( body( req( get( "_=$t2" ) ) ), 'USERS x=[from-token]', 'safe input selects the page' );

my $r = req( get( '_=~garbage' ) );
is( body( $r ), 'MAIN foo=[FOO] inc=[INC] title=[]', 'a tampered token is ignored and the request proceeds' );
like( logs(), qr/invalid or tampered encrypted \[_\] safe input token/, 'a tampered token is logged' );

$r = req( get( '_=notatoken' ) );
is( body( $r ), 'MAIN foo=[FOO] inc=[INC] title=[]', 'a _ value without ~ is ignored' );
unlike( logs(), qr/tampered/, 'a _ value without ~ is not logged as tampered' );

# forward
$r = req( get( '_an=fwd' ) );
is( $r->[0], 302, 'forward() from an action responds 302' );
my $loc = hdrs( $r->[1] )->{ 'location' };
like( $loc, qr/^\?_=~[A-Za-z0-9_\-]+$/, 'forward() location carries a safe input token' );
is_deeply( $r->[2], [ '' ], 'forward() has an empty body' );

( my $qs = $loc ) =~ s/^\?//;
is( body( req( get( $qs ) ) ), 'USERS x=[via-fwd]', 'following the forward renders the target page with the forwarded arguments' );

$r = req( env(), {}, sub { $_[0]->forward( _pn => 'main' ) } );
is( $r->[0], 302, 'forward() outside an action responds 302' );

$r = req( env(), {}, sub { $_[0]->forward( 'odd' ) } );
is_unavailable( $r, 'forward() with an odd argument list' );
like( logs(), qr/expected even number of arguments/, 'forward() argument error is logged' );

# forward_url is inherited and needs no crypto, checked here for completeness
$r = req( env(), {}, sub { $_[0]->forward_url( '/elsewhere' ) } );
is( $r->[0], 302, 'forward_url() responds 302' );
is( hdrs( $r->[1] )->{ 'location' }, '/elsewhere', 'forward_url() location' );
}

# Web::Reactor inherits argsx() unchanged and routes a ~ token through the same
# importer; its own args() is the hidden link form and needs sessions, which
# are exercised by t/test_reactor.pl
SKIP:
{
skip( 'Data::Tools::Crypto::Symmetric not installed', 5 ) unless $HAS_CRYPTO;
require_ok( 'Web::Reactor' );

package Web::Reactor::TestStateful;
our @ISA = ( 'Web::Reactor' );
sub log { my $self = shift; push @main::LOG, join '', @_; print STDERR @_, "\n" if $VERBOSE; }
package main;

my $r = Web::Reactor::TestStateful->new( env(), cfg() );
my $tx = $r->argsx( a => 1, b => 'two' );
like( $tx, qr/^~[A-Za-z0-9_\-]+$/, 'Reactor argsx() returns a ~ prefixed token' );
is_deeply( $r->cry->thaw_base64url( substr( $tx, 1 ) ), { A => 1, B => 'two' }, 'Reactor argsx() token decrypts' );
isnt( \&Web::Reactor::args, \&Web::Reactor::Reflex::argsx, 'Reactor args() is its own (hidden link) implementation, not the alias' );

my $r2 = Web::Reactor::TestStateful->new( get( "_=$tx" ), cfg() );
is_deeply( $r2->get_safe_input(), { A => 1, B => 'two' }, 'Reactor safe input decodes an argsx() token through the shared importer' );
}

##############################################################################
##
##  section 12 -- translations
##

{
my $o = app( env(), { LANG => 'bg', TRANS_DIRS => [ "$ROOT/trans" ] } );
is( $o->load_trans(), 1, 'load_trans() finds the language files' );
is( $o->{ 'TRANS' }{ 'LANG' }, 'bg', 'load_trans() records the language' );
is( $o->{ 'TRANS' }{ 'bg' }{ 'hello' }, 'Hi there', 'translation values are trimmed' );
is( $o->{ 'TRANS' }{ 'bg' }{ 'bye'   }, 'Bye',      'second translation' );
is( $o->load_trans(), 1, 'load_trans() is cached on the second call' );

my $o2 = app( env(), { LANG => 'bg', TRANS_FILE => "$ROOT/trans/single.tr" } );
is( $o2->load_trans(), 1, 'load_trans() with a single TRANS_FILE' );
is( $o2->{ 'TRANS' }{ 'bg' }{ 'only' }, 'one', 'TRANS_FILE is loaded' );
ok( ! exists $o2->{ 'TRANS' }{ 'bg' }{ 'hello' }, 'TRANS_FILE replaces the directory scan' );

my $o3 = app( env(), { LANG => 'en', TRANS_DIRS => [ "$ROOT/trans" ] } );
is( $o3->load_trans(), 1, 'load_trans() with no files for the language' );
is_deeply( $o3->{ 'TRANS' }{ 'en' }, {}, 'no files gives an empty translation table' );

is_deeply( $o->load_trans_file( "$ROOT/trans/single.tr" ), { only => 'one' }, 'load_trans_file() returns the raw hash' );

my $o4 = app( env(), { LANG => '', TRANS_DIRS => [ "$ROOT/trans" ] } );
is( $o4->load_trans(), 0, 'load_trans() returns 0 with an empty LANG' );
ok( ! exists $o4->{ 'TRANS' }, 'load_trans() loads nothing with an empty LANG' );
}

##############################################################################
##
##  section 13 -- the Packages action dispatcher
##

{
my $over = { REO_ACT_CLASS => 'Web::Reactor::Actions::Packages', LIB_DIRS => [ "$ROOT/lib" ] };

is( body( req( get( '_an=pkg' ), $over ) ), 'from package', 'Packages dispatcher loads Web::Reactor::Actions::<app>::<name>' );
ok( ( grep { $_ eq "$ROOT/lib" } @INC ), 'LIB_DIRS are added to @INC' );

my $r = req( get( '_an=hello' ), $over );
is_unavailable( $r, 'Files action under the Packages dispatcher' );
like( logs(), qr/code for action name \[hello\] not found/, 'the two dispatchers do not see each other\'s actions' );

# the normal fallback to the next set is only a debug message
is( body( req( get( '_an=inbase' ), $over ) ), 'IN BASE', 'an action only in Base is found through the sets' );
unlike( logs(), qr/^error:/m, 'the normal fallback to the next set logs no error' );

# a broken app action stops the lookup, Base does not run in its place
$r = req( get( '_an=brokendep' ), $over );
is_unavailable( $r, 'app action with a missing dependency' );
unlike( body( $r ), qr/BASE/, 'a missing dependency does not fall back to Base' );
like( logs(), qr/a module it uses cannot be found/, 'the missing dependency is logged' );

$r = req( get( '_an=brokensyn' ), $over );
is_unavailable( $r, 'app action with a syntax error' );
unlike( body( $r ), qr/BASE/, 'a syntax error does not fall back to Base' );
like( logs(), qr/load action failed/, 'the syntax error is logged' );

$r = req( get( '_an=nosuchaction' ), $over );
like( logs(), qr/action \[nosuchaction\] not found in any of the action sets/, 'a missing action is logged once with the sets' );
}

# Files dispatcher: a failing action file is cached for the request
{
my $o = app();
eval { $o->act->call( 'brokenfile' ) };
eval { $o->act->call( 'brokenfile' ) };
is( scalar( () = logs() =~ /load action failed/g ), 1, 'a failing action file is loaded and logged once per request' );
}

##############################################################################
##
##  section 13b -- name/value pairs given to run() are merged into the input
##

{
my $o = app( get( '' ) );
like( body( $o->run( _pn => 'admin/users', x => 'forced' ) ), qr/^USERS/, 'run() arguments choose the page' );
is( $o->get_user_input()->{ 'X' }, 'forced', 'run() arguments reach the user input, names uppercased' );
is( $o->get_safe_input()->{ 'X' }, 'forced', 'run() arguments reach the safe input' );
}

##############################################################################
##
##  section 13a -- html ids, inherited from Web::Reactor::Core
##

{
my $o = app();
my $scope = $o->get_uniq_id_scope();
like( $scope, qr/^\Q$$\E_\d+_[A-Za-z0-9]{8}$/, 'Reflex uses the Core id scope' );
is( $o->create_uniq_id(), "$scope.1", 'Reflex create_uniq_id() is scope.1 first' );
is( $o->create_uniq_id(), "$scope.2", 'Reflex create_uniq_id() counts up' );
ok( $o->start_time() > 0, 'Reflex start_time()' );
}

##############################################################################
##
##  section 14 -- over a real HTTP connection
##

SKIP:
{
eval { require Plack::Test; require HTTP::Request::Common; require Plack::Middleware::Lint; 1 }
  or skip( 'Plack::Test / Plack::Middleware::Lint not available', 7 );

$Plack::Test::Impl = 'Server';

my $app = sub { @LOG = (); Web::Reactor::TestReflex->new( shift, cfg() )->run() };

Plack::Test::test_psgi( Plack::Middleware::Lint->wrap( $app ), sub
    {
    my $cb = shift;

    my $res = $cb->( HTTP::Request::Common::GET( '/app' ) );
    is( $res->code, 200, 'live page request succeeds and passes PSGI Lint' );
    is( $res->content, 'MAIN foo=[FOO] inc=[INC] title=[]', 'live page body' );
    like( $res->header( 'Content-Type' ), qr{^text/html; charset=UTF-8}, 'live page content type' );

    $res = $cb->( HTTP::Request::Common::GET( '/app?_an=hello' ) );
    is( $res->content, 'hello  foo=FOO', 'live action body' );

    $res = $cb->( HTTP::Request::Common::GET( '/app?_an=nosuch' ) );
    like( $res->content, qr/currently unavailable/, 'live missing action gets the generic error body' );

    } );

# a redirect over the wire; forward() emits a relative location ("?_=~...")
# which browsers resolve against the current URL but LWP refuses to follow,
# so the client must not chase redirects here
SKIP:
  {
  skip( 'Data::Tools::Crypto::Symmetric not installed', 2 ) unless $HAS_CRYPTO;
  require Plack::LWPish; # HTTP::Tiny based client Plack::Test uses itself
  my $ua = Plack::LWPish->new( max_redirect => 0, no_proxy => [ '127.0.0.1' ] );
  my $test = Plack::Test->create( Plack::Middleware::Lint->wrap( $app ), ua => $ua );
  my $res = $test->request( HTTP::Request::Common::GET( '/app?_an=fwd' ) );
  is( $res->code, 302, 'live forward responds 302' );
  like( $res->header( 'Location' ), qr/^\?_=~[A-Za-z0-9_\-]+$/, 'live forward location carries a safe input token' );
  }
}

##############################################################################

done_testing();

###EOF########################################################################
