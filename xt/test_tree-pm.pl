#!/usr/bin/perl
##############################################################################
##
##  Web::Reactor::Preprocessor::Tree process() tests
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
##
##  single-file test for Web::Reactor::Preprocessor::Tree::process()
##
##  usage:
##
##    perl xt/test_tree-pm.pl               -- from the distribution root
##    perl xt/test_tree-pm.pl -v            -- also pass reactor log() to stderr
##
##  builds a throw-away application tree (html pages, includes, action files)
##  in a temporary directory and drives process() directly, without HTTP.
##  href rewriting needs Data::Tools::Crypto::Symmetric and is skipped when it
##  is not installed (add its lib dir with -I to include those tests).
##
##############################################################################
use strict;

use lib '../lib'; # when run from inside xt/
use lib 'lib';    # when run from the distribution root

use Test::More;
use File::Temp qw( tempdir );
use File::Path qw( make_path );
use Data::Tools;

my $VERBOSE = grep { $_ eq '-v' } @ARGV;

##############################################################################
##
##  test reactor class, must live under Web::Reactor:: (see Base::__set_reo)
##

our @LOG;

package Web::Reactor::TestTree;
our @ISA = ( 'Web::Reactor::Reflex' );
sub log
{
  my $self = shift;
  push @LOG, join '', @_;
  print STDERR @_, "\n" if $VERBOSE;
}

package main;

##############################################################################
##
##  section 1 -- loading
##

require_ok( 'Web::Reactor::Reflex' );
require_ok( 'Web::Reactor::Preprocessor::Tree' );

my $HAS_CRYPTO = eval { require Data::Tools::Crypto::Symmetric; 1 } ? 1 : 0;
diag( "Data::Tools::Crypto::Symmetric not available, href rewriting tests will be skipped" ) unless $HAS_CRYPTO;

##############################################################################
##
##  section 2 -- throw-away application tree
##
##  html/
##    default/
##      inc.html                 root include, visible from every page
##      main/index.html
##      admin/users/index.html
##      admin/users/local.html   page-local include
##      admin/users/inc.html     overrides the root include for that page only
##    bg/
##      inc.html                 language override of the root include
##  actions/
##    echo.pm      returns its HTML_ARGS and the current tag id
##    tags.pm      returns text with tags in it, must be processed again
##    dies.pm      dies
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

put( 'html/default/inc.html',               'ROOT-INC[<$foo>]' );
put( 'html/default/main/index.html',        'MAIN' );
put( 'html/default/admin/users/index.html', 'USERS' );
put( 'html/default/admin/users/local.html', 'LOCAL-USERS' );
put( 'html/default/admin/users/inc.html',   'USERS-INC' );
put( 'html/bg/inc.html',                    'BG-INC' );

put( 'actions/echo.pm', <<'EOF' );
package reactor::actions::echo;
use strict;
sub main
{
  my $reo  = shift;
  my %args = @_;
  my $ha   = $args{ 'HTML_ARGS' } || {};
  my $id   = $reo->pre->tagid_peek();
  return 'echo(' . join( ',', map { "$_=$ha->{ $_ }" } sort keys %$ha ) . ')id[' . ( defined $id ? $id : 'undef' ) . ']';
}
1;
EOF

put( 'actions/tags.pm', <<'EOF' );
package reactor::actions::tags;
use strict;
sub main { return 'tags[<$foo>|<#inc>]' }
1;
EOF

put( 'actions/dies.pm', <<'EOF' );
package reactor::actions::dies;
use strict;
sub main { die "action died on purpose" }
1;
EOF

##############################################################################
##
##  helpers
##

sub env
{
  return {
         'REQUEST_METHOD'  => 'GET',
         'QUERY_STRING'    => '',
         'psgi.url_scheme' => 'https',
         'psgi.input'      => \*STDIN,
         'psgi.errors'     => \*STDERR,
         };
}

# new reactor with fresh hold, LANG defaults to 'bg' so both language dirs are exercised
sub reo
{
  my %opt = @_;
  my $cfg = {
            'APP_NAME' => 'testapp',
            'APP_ROOT' => $ROOT,
            'CRY_KEY'  => 'k' x 32,
            'LANG'     => $opt{ 'LANG' } || 'bg',
            'DEBUG'    => 0,
            };
  @LOG = ();
  my $reo = Web::Reactor::TestTree->new( env(), $cfg );
  $reo->html_hold_set( foo => 'FOO', bar => 'BAR', late => 'LATE', loop => '<$loop>', empty => '' );
  return $reo;
}

# process $text as page $pn, returns output; dies propagate
sub proc
{
  my ( $reo, $pn, $text, $opt ) = @_;
  return $reo->pre->process( $pn, $text, $opt );
}

##############################################################################
##
##  section 3 -- plain text and hold variables
##

{
my $reo = reo();

is( proc( $reo, 'main', '' ),              '',              'empty text stays empty' );
is( proc( $reo, 'main', 'no tags here' ),  'no tags here',  'text without tags is returned unchanged' );
is( proc( $reo, 'main', '<$foo>' ),        'FOO',           '<$tag> is replaced with hold value' );
is( proc( $reo, 'main', '<$FOO>' ),        'FOO',           '<$TAG> lookup is case insensitive' );
is( proc( $reo, 'main', 'a<$foo>b<$bar>c' ), 'aFOObBARc',   'several tags in one text' );
is( proc( $reo, 'main', '[<$nothing>]' ),  '[]',            'unknown hold name expands to empty string' );
is( proc( $reo, 'main', '[<$empty>]' ),    '[]',            'empty hold value expands to empty string' );
is( proc( $reo, 'main', '<$foo:someid>' ), 'FOO',           '<$tag:id> works like <$tag>' );
is( proc( $reo, 'main', '<%zzz> <!x>' ),   '<%zzz> <!x>',   'unknown tag types are left untouched' );
is( proc( $reo, 'main', '<$foo' ),         '<$foo',         'unterminated tag is left untouched' );
}

##############################################################################
##
##  section 4 -- deferred <$$tag>, second pass
##

{
my $reo = reo();

is( proc( $reo, 'main', '<$$late>' ),            'LATE',            '<$$tag> alone resolves on the second pass' );
is( proc( $reo, 'main', 'a:[<$foo>] b:[<$$late>]' ), 'a:[FOO] b:[LATE]', '<$$tag> after another tag resolves' );
is( proc( $reo, 'main', 'a:[<$$late>] b:[<$foo>]' ), 'a:[LATE] b:[FOO]', '<$$tag> before another tag resolves' );

my $opt = {};
proc( $reo, 'main', '<$$late>', $opt );
ok( ! $opt->{ ':REPEAT_PROCESSING_REQUESTED' }, 'repeat flag is not left set in caller options after process()' );

is_deeply( $reo->pre->{ 'TAG_ID_STACK' } || [], [], 'tag id stack is empty after deferred tags' );
}

##############################################################################
##
##  section 5 -- includes: root, page-local, precedence, language
##

{
my $reo = reo();

is( proc( $reo, 'main', '<#inc>' ),           'BG-INC',            'root include, language dir wins over default' );
is( proc( $reo, 'main', '<#nosuch>' ),        '',                  'missing include expands to empty string' );
is( proc( $reo, 'admin/users', '<#local>' ),  'LOCAL-USERS',       'page-local include from nested page' );
# search order is language-major: all of the LANG tree (deepest first) before
# any of the default tree, so a language root include beats a page-local
# default include; see load_file() in Tree.pm
is( proc( $reo, 'admin/users', '<#inc>' ),    'BG-INC',            'language root include beats page-local default include (language-major order)' );
is( proc( $reo, 'admin', '<#inc>' ),          'BG-INC',            'parent page without own include falls back to root' );
is( proc( $reo, 'main', '<#INC>' ),           'BG-INC',            '<#TAG> lookup is case insensitive' );
is( proc( $reo, undef, '<#inc>' ),            'BG-INC',            'undef page name (action output) resolves root includes' );

my $en = reo( LANG => 'en' );
is( proc( $en, 'main', '<#inc>' ),            'ROOT-INC[FOO]',     'missing language dir falls back to default, include text is processed' );
is( proc( $en, 'admin/users', '<#inc>' ),     'USERS-INC',         'within one language tree the page-local include beats the root include' );
}

##############################################################################
##
##  section 6 -- action calls <&tag> and <&&tag>
##

{
my $reo = reo();

is( proc( $reo, 'main', '<&echo>' ),                     'echo()id[undef]',          '<&action> without args' );
is( proc( $reo, 'main', '<&echo a=1>' ),                 'echo(A=1)id[undef]',       'bare argument, key uppercased' );
is( proc( $reo, 'main', q{<&echo a='x y' b="p q">} ),    'echo(A=x y,B=p q)id[undef]', 'single and double quoted arguments' );
is( proc( $reo, 'main', '<&echo flag>' ),                'echo(FLAG=1)id[undef]',    'argument without value is 1' );
is( proc( $reo, 'main', q{<&echo n=0 s="" q='0' e=>} ),   'echo(E=,N=0,Q=0,S=)id[undef]', 'argument values 0 and empty are kept' );
is( proc( $reo, 'main', '<&echo:tag7 z=3>' ),            'echo(Z=3)id[tag7]',        '<&action:id> exposes the tag id via tagid_peek' );
like( proc( $reo, 'main', '<&&echo>' ),   qr{^<div class=(['"])vframe\1>echo\(\)id\[undef\]</div>$}, '<&&action> is wrapped in a vframe div' );
is( proc( $reo, 'main', '<&ECHO>' ),                     'echo()id[undef]',          '<&ACTION> is case insensitive' );
is( proc( $reo, 'main', '<&tags>' ),                     'tags[FOO|BG-INC]',         'action output is processed again for tags' );

my $out = eval { proc( $reo, 'main', '[<&dies>]' ) };
ok( ! $@, 'dying action does not die the preprocessor' );
is( $out, '[]', 'dying action expands to empty string' );
ok( ( grep { /action died on purpose/ } @LOG ), 'dying action error is logged' );

$out = eval { proc( $reo, 'main', '[<&nosuch>]' ) };
like( $@, qr/code for action name \[nosuch\] not found/, 'missing action booms' );
}

##############################################################################
##
##  section 7 -- loop detection and nesting
##

{
my $reo = reo();

my $out = eval { proc( $reo, 'main', '<$loop>' ) };
like( $@, qr/preprocess loop detected/, 'self-referencing hold value is detected' );
is_deeply( $reo->pre->{ 'TAG_ID_STACK' } || [], [], 'the tag id stack is empty after a loop boom' );

$reo = reo();
$reo->html_hold_set( a => '<$b>', b => '<$c>', c => 'deep' );
is( proc( $reo, 'main', '<$a>' ), 'deep', 'nested hold references are followed' );

$reo->html_hold_set( x => '<$y>', y => '<$x>' );
$out = eval { proc( $reo, 'main', '<$x>' ) };
like( $@, qr/preprocess loop detected/, 'mutual hold reference is detected' );
}

##############################################################################
##
##  section 8 -- href rewriting
##

SKIP:
{
skip( 'Data::Tools::Crypto::Symmetric not installed', 6 ) unless $HAS_CRYPTO;

my $reo = reo();

my $out = proc( $reo, 'main', '<a reactor_href="?_pn=admin/users&x=1">l</a>' );
like( $out, qr/^<a href=\?_=~[A-Za-z0-9_\-]+>l<\/a>$/, 'reactor_href is rewritten to an encrypted args link' );
my ( $tok ) = $out =~ /\?_=~([A-Za-z0-9_\-]+)/;
is_deeply( $reo->cry->thaw_base64url( $tok ), { _PN => 'admin/users', X => 1 }, 'link args round-trip with uppercased keys' );

$out = proc( $reo, 'main', '<img reactor_src="pic.png?id=7">' );
like( $out, qr/^<img src=pic\.png\?_=~[A-Za-z0-9_\-]+>$/, 'reactor_src keeps the script name' );

$out = proc( $reo, 'main', '<a reactor_new_href="?_an=hello#top">n</a>' );
like( $out, qr/^<a href=\?_=~[A-Za-z0-9_\-]+#top>n<\/a>$/, 'typed href keeps the anchor' );

$out = proc( $reo, 'main', q{<a reactor_href='?a=1'>q</a>} );
like( $out, qr/^<a href=\?_=~[A-Za-z0-9_\-]+>q<\/a>$/, 'single quoted href attribute' );

$out = proc( $reo, 'main', '<a href="?_pn=x">plain</a>' );
is( $out, '<a href="?_pn=x">plain</a>', 'plain href without reactor_ prefix is untouched' );
}

##############################################################################

done_testing();

###EOF########################################################################
