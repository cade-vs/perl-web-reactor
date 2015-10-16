##############################################################################
##
##  Web::Reactor application machinery
##  2013 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
package Web::Reactor::Preprocessor::Native;
use strict;
use Exception::Sink;
use Carp;
use Data::Tools;
use Web::Reactor::Preprocessor;

our @ISA = qw( Web::Reactor::Preprocessor );

sub new
{
  my $class = shift;
  my %env = @_;

  $class = ref( $class ) || $class;
  my $self = {
             'ENV'        => \%env,
             'FILE_CACHE' => {},
             };
  bless $self, $class;
  # rcd_log( "debug: rcd_rec:$self created" );

  # FIXME: common directories setup code?
  if( ! $env{ 'HTML_DIRS' } or @{ $env{ 'HTML_DIRS' } } < 1 )
    {
    my $root = $self->{ 'ENV' }{ 'APP_ROOT' };
    my $lang = $self->{ 'ENV' }{ 'LANG' };
    if( $lang )
      {
      $env{ 'HTML_DIRS' } = [ "$root/html/$lang", "$root/html/default" ];
      }
    else
      {
      $env{ 'HTML_DIRS' } = [ "$root/html/default" ];
      }
    }

  my $html_dirs = $env{ 'HTML_DIRS' } || [];
  my $html_dirs_ok = 0;
  for my $html_dir ( @$html_dirs )
    {
    next unless -d $html_dir;
    $html_dirs_ok++;
    }
  boom "invalid or not accessible HTML_DIR's [@$html_dirs]" unless $html_dirs_ok;

  return $self;
}

##############################################################################
##
##
##

sub load_file
{
  my $self = shift;

  my $pn = lc shift; # page name

  die "invalid page name, expected ALPHANUMERIC, got [$pn]" unless $pn =~ /^[a-z_\-0-9]+$/;

  my $reo = $self->{ 'REO_REACTOR' };

  my $lang = $self->{ 'ENV' }{ 'LANG' };

  if( exists $self->{ 'FILE_CACHE' }{ $lang }{ $pn } )
    {
    # FIXME: log: debug: file cache hit
    return $self->{ 'FILE_CACHE' }{ $lang }{ $pn };
    }

  my $pn = "$pn.html";
  my $dirs = $self->{ 'ENV' }{ 'HTML_DIRS' };

  my $fn;
  for my $dir ( @$dirs )
    {
    next unless -e "$dir/$pn";
    $fn = "$dir/$pn";
    last;
    }

  if( ! $fn )
    {
    if( $pn =~ /^page_/ )
      {
      $reo->log( "error: cannot load file for page [$pn] from [@$dirs]" );
      }
    else
      {
      $reo->log( "warning: cannot load file for page [$pn] from [@$dirs]" ) if $reo->is_debug();
      }
    return undef;
    }

  my $fdata = file_load( $fn );
  $self->{ 'FILE_CACHE' }{ $lang }{ $pn } = $fdata;

  return $fdata;
}

sub process
{
  my $self = shift;

  my $text = shift;
  my $opt  = shift || {};

  $opt = { %$opt };
  $opt->{ 'LEVEL' }++;

  # FIXME: cache here? moje bi ne, zaradi modulite
  $text =~ s/<([\$\&\#]|\$\$)([a-zA-Z_\-0-9]+)(\s*[^>]*)?>/$self->__process_tag( $1, $2, $3, $opt )/ge;
  $text =~ s/reactor_((new|back|here)_)?(href|src)=(["'])?([a-z_0-9]+\.([a-z]+)|\.\/?)?\?([^\n\r\s>"']*)(\3)?/$self->__process_href( $2, $3, $5, $7 )/gie;

  return $text;
}

sub __process_tag
{
  my $self = shift;

  my $type = shift; # types are: $ variable, & callback, # template file include
  my $tag  = shift;
  my $args = shift; # the rest of the tag
  my $opt  = shift;

  $opt = { %$opt };
  $opt->{ 'PATH' } .= ", $type$tag";
  my $path = $opt->{ 'PATH' };

  die "preprocess loop detected, tag [$type$tag] path [$path]" if $opt->{ 'SEEN:' . $type . $tag }++;
  die "empty or invalid tag" unless $tag =~ /^[a-zA-Z_\-0-9]+$/;

  my $reo = $self->{ 'REO_REACTOR' };

  $tag = lc $tag;

  my $text;

  if( $type eq '$$' )
    {
    return "<\$$tag>"; # shortcut to deferred eval
    }
  elsif( $type eq '$' )
    {
    # FIXME: get content from reactor?
    $text = undef unless exists $reo->{ 'HTML_CONTENT' }{ $tag };
    $text = $reo->{ 'HTML_CONTENT' }{ $tag };
    }
  elsif( $type eq '#' )
    {
    $text = $self->load_file( $tag );
    }
  elsif( $type eq '&' )
    {
    # FIXME: make args to a function?
    my %args;
    while( $args =~ /\s*([a-zA-Z_0-9]+)(=('([^']*)'|"([^"]*)"|(\S*)))?/g ) # "' # fix string colorization
      {
      my $k = uc $1;
      my $v = $4 || $5 || $6 || 1;
      $args{ $k } = $v;
      }
    $text = $reo->action_call( $tag, HTML_ARGS => \%args );
    }
  else
    {
    re_log( "debug: invalid tag: [$type$tag]" );
    }

  $text = $self->process( $text, $opt );

  return $text;
}

sub __process_href
{
  my $self   = shift;

  my $type   = lc shift || 'here';
  my $attr   = shift; # href or src
  my $script = shift;
  my $data   = shift;

  my $data_hr = url2hash( $data );

  my $reo = $self->{ 'REO_REACTOR' };

  $type = 'new' if $attr eq 'src';

  my $href;
  if( $type eq 'new' )
    {
    $href = $reo->args_new( %$data_hr );
    }
  elsif( $type eq 'back' )
    {
    $href = $reo->args_back( %$data_hr );
    }
  elsif( $type eq 'here' )
    {
    $href = $reo->args_here( %$data_hr );
    }
  else
    {
    boom "invalid first argument, expected one of (new|back|here)";
    }

  return "$attr=?_=$href";
}

##############################################################################
1;
###EOF########################################################################
