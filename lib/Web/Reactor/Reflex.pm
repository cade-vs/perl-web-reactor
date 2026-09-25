##############################################################################
##
##  Web::Reactor::Reflex stateless application machinery
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com> <cade@bis.bg> <cade@cpan.org>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
package Web::Reactor::Reflex;
use strict;

use parent 'Web::Reactor::Core';

use Data::Tools 1.24;
use Exception::Sink;
use Data::Dumper;

our $VERSION = '3.33';

##############################################################################

sub new
{
  my $class = shift;
  my $env   = shift;
  my $cfg   = shift;

  $class = ref( $class ) || $class;
  my $self = $class->SUPER::new( $env, $cfg );

  $cfg = $self->cfg();
  $env = $self->env();

  data_tools_set_text_io_encoding( 'UTF-8' );

  # FIXME: common directories setup code?
  $cfg->{ 'LIB_DIRS' } = [ $cfg->{ 'LIB_DIRS' } ] if ! ref( $cfg->{ 'LIB_DIRS' } ) and $cfg->{ 'LIB_DIRS' };
  $cfg->{ 'LIB_DIRS' } = [ $cfg->{ 'APP_ROOT' } . '/lib/' ] if ! $cfg->{ 'LIB_DIRS' } or @{ $cfg->{ 'LIB_DIRS' } } < 1;

  for my $lib_dir ( @{ $cfg->{ 'LIB_DIRS' } || [] } )
    {
    next unless -d $lib_dir;
    next if grep { $_ eq $lib_dir } @INC; # persistent servers call new() per request
    push @INC, $lib_dir;
    }

  @INC = grep { $_ ne '.' } @INC;


  return $self;
}

sub __load_and_attach_module
{
  my $self = shift;
  my $key  = shift;
  my $mod  = shift;
  my @args = @_;

  my $cfg = $self->cfg();

  my $reo_class = $cfg->{ "REO_${key}_CLASS" } ||= $mod;
  my $reo_class_file = perl_package_to_file( $reo_class );
  require $reo_class_file;
  return $reo_class->new( @args );
}

### FUNC PLUGS ###############################################################

sub act
{
  my $self = shift;

  return $self->{ "REO_ACT" } ||= $self->__load_and_attach_module( 'ACT', 'Web::Reactor::Actions::Native', $self, $self->cfg() );
}

sub pre
{
  my $self = shift;

  return $self->{ "REO_PRE" } ||= $self->__load_and_attach_module( 'PRE', 'Web::Reactor::Preprocessor::Native', $self, $self->cfg() );
}

sub cry
{
  my $self = shift;

  return $self->{ "REO_CRY" } ||= $self->__load_and_attach_module( 'CRY', 'Data::Tools::Crypto::Symmetric', $self->cfg->{ 'CRY_KEY' } );
}

##############################################################################

sub process_request
{
  my $self = shift;
  my $args = @_ / 2; # count of arg pairs
  my %args = @_;

  my $cfg = $self->cfg();

  my $app_name = $cfg->{ 'APP_NAME' } or boom( "missing APP_NAME" );

  my $user_input_hr = $self->get_user_input();
  my $safe_input_hr = $self->get_safe_input();

  my $action_name = lc( $safe_input_hr->{ '_AN' } || $user_input_hr->{ '_AN' } );
  boom "invalid action name [$action_name]" unless $action_name =~ /^[a-z0-9_]*$/;

  my $page_name = lc( $safe_input_hr->{ '_PN' } || $user_input_hr->{ '_PN' } );
  # TODO: "/" is allowed here but Preprocessor::Native rejects it, only Extended accepts paths; align them
  boom "invalid page name [$page_name]" unless $page_name =~ /^[a-z0-9_\-\/]*$/;

  if( $action_name )
    {
    $self->render_action( $action_name );
    }
  else
    {
    $self->render_page( $page_name || 'main' );
    }
}

#-----------------------------------------------------------------------------

sub render_action
{
  my $self   = shift;
  my $action = shift;

  my $portray_data = $self->act->call( $action );

  boom "rendering action [$action] returns empty data" if ! ref $portray_data and $portray_data eq '';

  $portray_data = $self->portray( $portray_data, 'text/html' ) unless ref $portray_data;

  if( $portray_data->{ 'TYPE' } eq 'text/html' )
    {
    $portray_data->{ 'DATA' } = $self->pre->process( '*', $portray_data->{ 'DATA' } );
    }

  return $self->render( $portray_data );
}

sub render_page
{
  my $self = shift;
  my $page = shift;

  # page data is always text/html and must be preprocessed
  my $text = $self->pre->load_page( $page );

  boom "rendering page [$page] returns empty text, file does not exists or is empty" if $text eq '';

  $text = $self->pre->process( $page, $text );

  return $self->render( $self->portray( $text, 'text/html' ) );
}

### REQUEST/INPUT DATA & UPLOADS #############################################

sub get_user_input_button
{
  my $self  = shift;

  my $user_input_hr = $self->get_user_input();

  for( keys %$user_input_hr )
    {
    # regular button BUTTON:CANCEL
    # button with id BUTTON:REDIRECT:USERID
    next unless /BUTTON:([a-z0-9_\-]+)(:(.+?))?(\.[XY])?$/oi;

    # return ( button, button_id )
    return wantarray ? ( $1, $3 ) : $1
    }

  return ();
}

sub get_lang
{
  my $self  = shift;

  return lc $self->cfg->{ 'LANG' };
}

sub get_app_name
{
  my $self  = shift;

  return $self->cfg->{ 'APP_NAME' };
}

sub get_app_root
{
  my $self  = shift;

  return $self->cfg->{ 'APP_ROOT' };
}

#-----------------------------------------------------------------------------

sub __import_safe_input
{
  my $self = shift;

  my $user_input_hr = $self->get_user_input();
  my $x = $user_input_hr->{ '_' } or return {};
  return {} unless $x =~ s/^~//;

  my $hr = $self->cry->thaw_base64url( $x );
  $self->log( "error: invalid or tampered safe input token, ignored" ) unless $hr;
  return $hr || {};
}

##############################################################################

sub args
{
  my $self = shift;
  my %args = @_;

  hash_uc_ipl( \%args );

  return '~' . $self->cry()->freeze_base64url( \%args );
}

sub args_type
{
  my $self = shift;
  my $type = shift;

  # type (here/back/new/none) is ignored: stateless reactor has no link/page
  # sessions, so "back" has nothing to return to and all types behave as "here"

  return $self->args( @_ );
}

### HTML HOLD ### CONTAINS PREPROCESSING CHUNKS OF HTML ######################

sub html_hold_set
{
  my $self = shift;
  my %hc   = @_;

  hash_lc_ipl( \%hc );
  $self->{ 'HTML_HOLD' } ||= {};
  %{ $self->{ 'HTML_HOLD' } } = ( %{ $self->{ 'HTML_HOLD' } }, %hc );

  return $self->{ 'HTML_HOLD' };
}

sub html_hold_get
{
  my $self = shift;
  my $name = lc shift;

  return undef unless exists $self->{ 'HTML_HOLD' }{ $name };
  return $self->{ 'HTML_HOLD' }{ $name };
}

sub html_hold_del
{
  my $self = shift;
  my $name = lc shift;

  delete $self->{ 'HTML_HOLD' }{ $name };

  return 1;
}

sub html_hold_clear
{
  my $self = shift;

  $self->{ 'HTML_HOLD' } = {};
}

sub html_hold_reset
{
  my $self = shift;

  $self->html_hold_clear();
  return $self->html_hold_set( @_ );
}

sub html_hold_kit_add
{
  my $self = shift;
  my $name = lc shift;
  my $text = shift;

  # kit snippets are collected in a separate hash, so each unique snippet is
  # emitted once; the joined text goes into the hold under the same (lc) name
  $self->{ 'HTML_HOLD_KIT' }{ $name }{ $text }++;

  $self->html_hold_set( $name, join '', sort keys %{ $self->{ 'HTML_HOLD_KIT' }{ $name } } );
}

# <$kit_head> is assumed to be in the <head> section
sub html_hold_kit_js
{
  my $self = shift;
  my $text = shift;

  $text = "<script type='text/javascript' src='$text'></script>";
  $self->html_hold_kit_add( "KIT_HEAD", $text );
}

sub html_hold_kit_css
{
  my $self = shift;
  my $css = shift;

  my $text = qq{ <link href="$css" rel="stylesheet" type="text/css"> };
  $self->html_hold_kit_add( "KIT_HEAD", $text );
}

##############################################################################

sub forward
{
  my $self = shift;

  boom "expected even number of arguments" unless @_ % 2 == 0;

  my $fw = $self->args( @_ );
  return $self->forward_url( "?_=$fw" );
}

##############################################################################
##
## helpers
##

sub require_post_method
{
  my $self = shift;

  return if $self->get_request_method() eq 'POST';

  $self->render_page( 'epostrequired' );
}

##############################################################################

sub load_trans
{
  my $self = shift;

  my $cfg = $self->cfg();

  my $lang = lc $cfg->{ 'LANG' };

  return 0 if $lang !~ /^[a-z][a-z]$/; # FIXME: move to init check! verofy hash etc. data::tools

  $self->{ 'TRANS' }{ 'LANG' } = $lang;

  return 1 if $self->{ 'TRANS' }{ $lang };

  my $tr = $self->{ 'TRANS' }{ $lang } = {};

  # FIXME: TRANS_DIRS may be undef (dies on deref below) and TRANS_FILE may be undef (-e warns)
  my $trans_dirs = $cfg->{ 'TRANS_DIRS' };
  my $trans_file = $cfg->{ 'TRANS_FILE' };

  my @tf;
  if( -e $trans_file )
    {
    # quick select single translation file, if specified
    @tf = ( $trans_file );
    }
  else
    {
    for my $dir ( @$trans_dirs )
      {
      push @tf, glob( "$dir/$lang/*.tr" );
      push @tf, glob( "$dir/$lang/text/*.tr" );
      }
    }

  for my $tf ( @tf )
    {
    my $hr = $self->load_trans_file( $tf );
    # trim whitespace
    my @temp = %$hr;
    for( @temp )
      {
      s/^\s*//;
      s/\s*$//;
      }
    %$hr = @temp;
    @temp = ();
    @{ $tr }{ keys %$hr } = values %$hr;
    }

  return 1;
}

sub load_trans_file
{
  my $self = shift;

  return hash_load( shift );
}

##############################################################################

sub set_browser_window_title
{
  my $self  = shift;
  my $title = shift;

  $title =~ s/<[^>]*>//g; # remove HTML if any
  $self->html_hold_set( 'BROWSER_WINDOW_TITLE', $title );
}

##############################################################################

=pod

   pod here

=cut

##############################################################################
1;
###EOF########################################################################
