##############################################################################
##
##  Web::Reactor application machinery
##  2013 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
package Web::Reactor::Preprocessor;
use strict;
use Exception::Sink;
use Carp;
use Data::Tools;

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

  die "invalid page name, expected ALPHANUMERIC, got [$pn]" unless $pn =~ /^[a-z_0-9]+$/;

  my $reo = $self->{ 'REO_REACTOR' };

  if( exists $self->{ 'FILE_CACHE' }{ $pn } )
    {
    # FIXME: log: debug: file cache hit
    return $self->{ 'FILE_CACHE' }{ $pn };
    }

  my $pn = "$pn.html";
  my $dirs = $self->{ 'ENV' }{ 'HTML_DIRS' } || [];
  if( @$dirs == 0 )
    {
    my $app_root = $self->{ 'ENV' }{ 'APP_ROOT' };
    boom "missing APP_ROOT" unless -d $app_root; # FIXME: function? get_app_root()
    $dirs = [ "$app_root/html" ];
    }

  my $fn;
  for my $dir ( @$dirs )
    {
    # FIXME: move this check on create/new of reactor
    confess "not accessible HTML include dir [$dir]" unless -d $dir;
    next unless -e "$dir/$pn";
    $fn = "$dir/$pn";
    last;
    }

  if( ! $fn )
    {
    # FIXME: not a error really, more like warning, should be able to disable :))
    $reo->log( "error: cannot find file [$fn] dirs list [@$dirs]" );
    return undef;
    }

  my $fdata = file_load( $fn );
  $self->{ 'FILE_CACHE' }{ $pn } = $fdata;

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
  $text =~ s/<([\$\&\#])([a-zA-Z_0-9]+)(\s*[^>]*)*>/$self->__process_tag( $1, $2, $3, $opt )/ge;
  $text =~ s/reactor_((new|back|here)_)?href=([a-z_0-9]+\.([a-z]+)|\.\/?)?\?([^\n\r\s>"']*)/$self->__process_href( $2, $3, $5 )/gie;

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
  die "empty or invalid tag" unless $tag =~ /^[a-zA-Z_0-9]+$/;

  my $reo = $self->{ 'REO_REACTOR' };

  $tag = lc $tag;

  my $text;

  if( $type eq '$' )
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
    while( $args =~ /\s*([^a-zA-Z_0-9]+)(=('([^']*)'|"([^"]*)"|(\S*)))?/g ) # "' # fix string colorization
      {
      my $k = uc $1;
      my $v = $4 || $5 || $6 || 1;
      $args{ $k } = $v;
      }
    $text = $reo->act_call( $tag, HTML_ARGS => \%args );
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
  my $script = shift;
  my $data   = shift;
  
  my $data_hr = url2hash( $data );
  
  my $reo = $self->{ 'REO_REACTOR' };

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
  
  return "href=?_=$href";  
}

##############################################################################
1;
###EOF########################################################################
