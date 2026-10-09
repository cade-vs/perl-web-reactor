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
package Web::Reactor::Preprocessor::Tree;
use strict;
use List::Util qw( first );
use Exception::Sink;
use Data::Dumper;
use Data::Tools 1.53; # file_text_load()
use Web::Reactor::Preprocessor;

use parent 'Web::Reactor::Preprocessor';

sub new
{
  my $class = shift;
  $class = ref( $class ) || $class;

  my $self = $class->SUPER::new( @_ );

  $self->{ 'FILE_CACHE' } = {};
  $self->{ 'DIRS_CACHE' } = {};

  my $cfg = $self->cfg();

  # FIXME: the same directories setup code is in Web::Reactor::Actions::new(),
  #        move it to a common function
  my $dirs = $cfg->{ 'HTML_DIRS' };
  my $root = $self->reo->get_app_root();

  # single directory (scalar) specified, convert to list
  $dirs = [ $dirs ] if ! ref( $dirs ) and $dirs;
  # nothing specified, set default
  $dirs = [ $root . '/html' ] if ! $dirs or @{ $dirs } < 1;

  $self->{ 'HTML_DIRS' } = $dirs;

  return $self;
}

##############################################################################
##
##
##

sub load_page
{
  my $self = shift;

  return $self->load_file( shift, 'index' );
}

# constructs real filesystem/storage file name and loads the file text, used
# by load_page() and for <#include> tags, not part of the preprocessor api
# args:
#       $page_name  -- page name (path), it should be sanitized, the file is
#                      looked up for this page in the file, storage, or sth.
#       $file_name  -- file name inside the page (no path, no extension),
#                      'index' is the page itself, other names are includes
#
# returns:
#       file text or undef if not found
sub load_file
{
  my $self = shift;

  my $pn = lc shift || 'main';  # page name (i.e. file path only)
  my $fn = lc shift || 'index'; # file name (file name only, no path, no ext)

  # sanitize page name
  $pn =~ s|^\s*/*||o; # strip leading  /s (but checked again later in check_page_name())
  $pn =~ s|/*\s*$||o; # strip trailing /s (but checked again later in check_page_name())
  $pn =~ s|\.+||go;   # remove all dots
  $pn =~ s|/+|/|go;   # compact repeating /s

  $self->check_page_name( $pn );
  $self->check_page_file_name( $fn );

  my $lang = $self->reo->get_lang();

  if( exists $self->{ 'FILE_CACHE' }{ $lang }{ $pn }{ $fn } )
    {
    # FIXME: log: debug: file cache hit
    return $self->{ 'FILE_CACHE' }{ $lang }{ $pn }{ $fn };
    }

  my $dirs;

  if( exists $self->{ 'DIRS_CACHE' }{ $lang }{ $pn } )
    {
    # FIXME: log: debug: dirs cache hit
    $dirs = $self->{ 'DIRS_CACHE' }{ $lang }{ $pn };
    }
  else
    {
    $dirs = $self->{ 'HTML_DIRS' };

    my @lang = ( 'default' );
    unshift @lang, $lang if $lang;

    my @pn = grep { $_ } split /\/+/, $pn;

    my @dirx; # expanded with pn/pn/pn etc...

    for my $ln ( @lang )
      {
      my @dx;
      my $pp;
      for my $p ( undef, @pn )
        {
        $pp .= $p . '/' if $p;
        for my $dir ( reverse @$dirs )
          {
          push @dx, "$dir/$ln/$pp";
          }
        }
      push @dirx, reverse @dx;
      }

    $dirs = [ grep { -d } @dirx ];

    boom "empty HTML_DIRS list or dirs do not exist after expansion [@dirx]" unless @$dirs;

    $self->{ 'DIRS_CACHE' }{ $lang }{ $pn } = $dirs;
    }

  my $reo = $self->reo();

  my $fname = first { -e } map { "$_/$fn.html" } @$dirs;

  if( ! $fname )
    {
    if( $fn eq 'index' )
      {
      $reo->log( "error: cannot load file [$fn] for page [$pn] from [@$dirs]" );
      }
    else
      {
      $reo->log( "warning: cannot load file [$fn] for page [$pn] from [@$dirs]" ) if $reo->is_debug();
      }
    return undef;
    }

  my $fdata = file_text_load( $fname );

  $reo->log_debug2( "debug: preprocessor load page [$pn] file [$fn] OK [$fname]" );

  $self->{ 'FILE_CACHE' }{ $lang }{ $pn }{ $fn } = $fdata;

  return $fdata;
}

sub process
{
  my $self = shift;

  my $pn   = lc shift; # page name
  my $text = shift;
  my $opt  = shift || {};
  my $ctx  = shift || {};

  my $c = 16; # 16+ passes is definitely a bug
  while( $c-- )
    {
    delete $opt->{ ':REPEAT_PROCESSING_REQUESTED' };
    $text = $self->process_single_pass( $pn, $text, $opt, $ctx );
    return $self->__translate( $text ) unless $opt->{ ':REPEAT_PROCESSING_REQUESTED' };
    }

  boom "too many processing passes at page [$pn], deferred tags never settle, probable bug in actions or page files";
}

# remaps the [~text] and <~text> literals to the loaded language, a literal
# without a translation keeps its own text. runs once, after all passes settle
sub __translate
{
  my $self = shift;
  my $text = shift;

  return $text unless $text =~ /\[~|<~/; # no literals, no need to load the translation files

  my $tr = $self->reo->get_trans();

  # one pass for both forms, the branch reset (?|) puts the literal in $1 for
  # either of them. a replacement is never scanned again, so literals inside a
  # translation stay as they are, whichever form they use
  # literals stay on one line, so a stray <~ or [~ cannot swallow markup
  $text =~ s/(?|<~([^<>\r\n]*)>|\[~([^\[\]\r\n]*)\])/__translate_literal( $tr, $1 )/ge;

  return $text;
}

# looks a literal up trimmed, as load_trans() trims the translation keys, and
# keeps the literal as written when there is no translation
sub __translate_literal
{
  my $tr  = shift;
  my $lit = shift;

  ( my $key = $lit ) =~ s/^\s+|\s+$//g;

  return $tr->{ $key } || $lit;
}

sub process_single_pass
{
  my $self = shift;

  my $pn   = lc shift; # page name
  my $text = shift;
  my $opt  = shift || {};
  my $ctx  = shift || {};

#print STDERR "DEBUG: PROCESS PAGE----------------------- [$pn]\n";

  boom "too many nesting levels at page [$pn], probable bug in actions or page files" if defined( (caller(128))[0] ); # FIXME: config option for max level

  $ctx = { %$ctx };
  $ctx->{ 'LEVEL' }++;

#print STDERR Dumper( 'PROCESS PRE --- ' x 7, $pn, $text );

  # FIXME: cache here? probably not, because of the modules: action tags
  #        produce different output on each call
  $text =~ s/<([\$\&\#]|\$\$+|\&\&)([a-zA-Z_\-0-9]+)(:([a-zA-Z_\-0-9]+))?(\s*[^>]*)?>/$self->__process_tag( $pn, $1, $2, $4, $5, $opt, $ctx )/ge;
  $text =~ s/reactor_((new|back|here|none)_)?(href|src)=(["'])?([a-z_0-9]+\.([a-z]+)|\.\/?)?\?([^\n\r\s>"'#]*)(#[a-z_0-9\.]+)?(\4)?/$self->__process_href( $2, $3, $5, $7, $8 )/gie;

#print STDERR Dumper( 'PROCESS POST --- ' x 7, $pn, $text );

  return $text;
}

sub __process_tag
{
  my $self = shift;

  my $pn    = lc shift; # page name
  my $type  =    shift; # types are: $ variable, & callback, # template file include
  my $tag   =    shift;
  my $tagid =    shift;
  my $args  =    shift; # the rest of the tag
  my $opt   =    shift;
  my $ctx   =    shift;

#print STDERR "DEBUG: PROCESS PAGE TAG ----------------------- [$pn] [$type] [$tag]:[$tagid]\n";

#print STDERR Dumper( 'PROCESS ARGS --- ' x 7, ( $pn, $type, $tag, $args, $opt, $ctx ) );
  $ctx = { %$ctx }; # FIXME: CHECK, was opt
  $ctx->{ 'PATH' } .= ", $type$tag";
  my $path = $ctx->{ 'PATH' };

  boom "preprocess loop detected, tag [$type$tag] path [$path]" if $ctx->{ 'SEEN:' . $type . $tag }++;
  boom "empty or invalid tag" unless $tag =~ /^[a-zA-Z_\-0-9]+$/;

  # the tag id is popped when this sub is left in any way, also by a boom
  # from a nested tag, so no stale tag id stays on the stack
  $self->tagid_push( $tagid );
  my $tagid_guard = bless [ $self ], 'Web::Reactor::Preprocessor::Tree::__TagIdGuard';

  my $reo = $self->reo();

  $tag = lc $tag;

  my $text;

  if( $type =~ /^\$\$+/ )
    {
    $opt->{ ':REPEAT_PROCESSING_REQUESTED' }++;
    my $nt = substr( $type, 1 );
    return "<${nt}$tag>"; # shortcut to deferred eval
    }
  elsif( $type eq '$' )
    {
    $text = $reo->html_hold_get( $tag );
    }
  elsif( $type eq '#' )
    {
    $text = $self->load_file( $pn, $tag );
    }
  elsif( $type eq '&' or $type eq '&&' )
    {
    # FIXME: make args to a function?
    my %args;
    while( $args =~ /\s*([a-zA-Z_0-9]+)(=('([^']*)'|"([^"]*)"|(\S*)))?/g ) # "' # fix string colorization
      {
      my $k = uc $1;
      # name=value keeps the value as given, also "0" and "", a bare name is a flag
      my $v = defined $2 ? $4 // $5 // $6 : 1;
      $args{ $k } = $v;
      }
    # FIXME: action calls may return non-text data, however the preprocessor expects text data for now...

    # session stack, parents etc?

#print STDERR ">>> $reo->act->call( $tag, HTML_ARGS => \%args )\n";
    my $calltext = $reo->act->call( $tag, HTML_ARGS => \%args );
    if( $type eq '&&' )
      {
      $calltext = "<div class='vframe'>" . $calltext . "</div>";
      }
    $text .= $calltext;
    }

# print STDERR Dumper( 'PROCESS TEXT --- ' x 7, ( $pn, $text, $opt, $ctx ) );
#print STDERR ">>> $self->process( $pn, $text, $opt, $ctx )\n";
  $text = $self->process_single_pass( $pn, $text, $opt, $ctx );

  return $text;
}

sub __process_href
{
  my $self   = shift;

  my $type   = lc shift || 'here';
  my $attr   = shift; # href or src
  my $script = shift;
  my $data   = shift;
  my $anchor = shift;

  my $data_hr = url2hash( $data );

  my $reo = $self->reo();

  $type = 'new' if $attr eq 'src'; # images

  my $href = $reo->args_type( $type, %$data_hr );

  return "$attr=$script?_=$href$anchor";
}

#-----------------------------------------------------------------------------


# tag id stack management

sub tagid_push
{
  my $self  = shift;
  my $tagid = shift;

  push @{ $self->{ 'TAG_ID_STACK' } }, $tagid;
}

sub tagid_pop
{
  my $self  = shift;

  return pop @{ $self->{ 'TAG_ID_STACK' } };
}

sub tagid_peek
{
  my $self  = shift;

  return undef unless exists $self->{ 'TAG_ID_STACK' };
  return $self->{ 'TAG_ID_STACK' }->[-1];
}

# pops the tag id pushed by __process_tag() when it goes out of scope
package Web::Reactor::Preprocessor::Tree::__TagIdGuard;
sub DESTROY { $_[0][0]->tagid_pop() }
package Web::Reactor::Preprocessor::Tree;

##############################################################################

sub check_page_name
{
  my $self = shift;
  boom "invalid page name [$_[0]]" unless $_[0] =~ /^[a-z0-9_\-]+(\/[a-z0-9_\-]+)*$/o;
}

sub check_page_file_name
{
  my $self = shift;
  boom "invalid page file name [$_[0]]" unless $_[0] =~ /^[a-z0-9_\-]+$/o;
}

##############################################################################
1;
###EOF########################################################################
