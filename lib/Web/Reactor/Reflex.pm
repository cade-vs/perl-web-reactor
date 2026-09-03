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

use Storable qw( dclone freeze thaw ); # FIXME: move to Data::Tools (data_freeze/data_thaw)
use Data::Tools 1.24;
use Exception::Sink;
use Data::Dumper;
use Encode;

our $VERSION = '3.14';

##############################################################################

sub new
{
  my $class = shift;
  my $env   = shift;
  my $cfg   = shift;

  $class = ref( $class ) || $class;

  data_tools_set_text_io_encoding( 'UTF-8' );

  # FIXME: common directories setup code?
  $cfg->{ 'LIB_DIRS' } = [ $cfg->{ 'LIB_DIRS' } ] if ! ref( $cfg->{ 'LIB_DIRS' } ) and $cfg->{ 'LIB_DIRS' };
  $cfg->{ 'LIB_DIRS' } = [ $cfg->{ 'APP_ROOT' } . '/lib/' ] if ! $cfg->{ 'LIB_DIRS' } or @{ $cfg->{ 'LIB_DIRS' } } < 1;

  for my $lib_dir ( @{ $cfg->{ 'LIB_DIRS' } || [] } )
    {
    next unless -d $lib_dir;
    push @INC, $lib_dir;
    }

  @INC = grep { $_ ne '.' } @INC;

  my $self = SUPER::new( $env, $cfg );

  return $self;
}

sub __load_module
{
  my $self = shift;
  my $key  = shift;
  my $mod  = shift;

  my $cfg = $self->get_cfg();

  my $reo_class = $cfg->{ "REO_${key}_CLASS" } ||= $mod;
  my $reo_class_file = perl_package_to_file( $reo_class );
  require $reo_class_file;
  return $reo_class->new( $self, $cfg );
}

##############################################################################

sub act
{
  my $self = shift;

  return $self->{ "REO_ACT" } ||= $self->__attach_module( 'ACT', 'Web::Reactor::Actions::Native' );
}

sub pre
{
  my $self = shift;

  return $self->{ "REO_PRE" } ||= $self->__attach_module( 'PRE', 'Web::Reactor::Preprocessor::Native' );
}

##############################################################################

sub process_request
{
  my $self = shift;
  my $args = @_ / 2; # count of arg pairs
  my %args = @_;

  my $cfg = $self->get_cfg();

  # 0. load/setup env/config defaults
  my $app_name = $cfg->{ 'APP_NAME' } or boom( "missing APP_NAME" );

  my $client_input = $self->get_client_input();




  # 3. get input data, CGI::params, postdata
  my $input_user_hr = $self->{ 'INPUT_USER_HR' } = {};
  my $input_safe_hr = $self->{ 'INPUT_SAFE_HR' } = {};

  # FIXME: TODO: handle and URL params here. only for EX?
  my $iconv;
  my $app_charset = uc $cfg->{ 'APP_CHARSET' } || 'UTF-8';
  my $incoming_charset = $app_charset;

  my $no_pass_encrypt = $cfg->{ 'NO_PASS_ENCRYPT' };

  if( uc( $self->get_http_env->{ 'HTTP_X_REQUESTED_WITH' } ) eq 'XMLHTTPREQUEST' )
    {
    # TODO: it can be different, but nobody seems to use it, should be fixed eventually
    $incoming_charset = 'UTF-8';
    }

  my $plack = $self->{ 'PLACK' };

  my $params = $plack->parameters(); # input parameters, GET + POST
  my %params; # preprocessed parameters

  # check valid params names and preprocess multiple values
  # import plain parameters from GET/POST request
  for my $n ( keys %$params )
    {
    if( $n !~ /^[A-Za-z0-9\-\_\.\:]+$/o )
      {
      $self->log( "error: invalid CGI/input parameter name: [$n]" );
      next;
      }
    my @v = $params->get_all( $n );
    $n = uc $n;
    if( @v > 1 )
      {
      for( my $vi = 0; $vi < @v; $vi++ )
        {
        # ignore the whole array if any value is invalid
        next     if $self->__input_cgi_skip_invalid_value( $n, $v[$vi] );
        $v[$vi] = $self->__input_cgi_make_safe_value( $n, decode( $incoming_charset, $v[$vi] ) );
        }
      $input_user_hr->{ '@' . $n } = \@v;
      }
    elsif ( $n =~ /BUTTON:([a-z0-9_\-]+)(:(.+?))?(\.[XY])?$/oi )
      {
      # regular button BUTTON:CANCEL
      # button with id BUTTON:REDIRECT:USERID
      $input_user_hr->{ 'BUTTON'    } = uc $1;
      $input_user_hr->{ 'BUTTON_ID' } =    $3;
      }
    elsif( $n eq '_BTN' )
      {
      # simulated button, i.e. hidden input with 'BUTTON_NAME:BUTTON_ID'
      my ( $b, $i ) = split /:/, $v[0], 2;
      $input_user_hr->{ 'BUTTON'    } = uc $b;
      $input_user_hr->{ 'BUTTON_ID' } =    $i;
      }
    else
      {
      next                  if $self->__input_cgi_skip_invalid_value( $n, $v[0] );
      my $out;
      if( ! $no_pass_encrypt and $n =~ /^(F:)?PASSWORD/ )
        {
        # TODO: move it to overload function
        $out = $self->rsa_pub_encrypt( $v[0] ) if $v[0] ne '';
        }
      else
        {
        $out = $self->__input_cgi_make_safe_value( $n, decode( $incoming_charset, $v[0] ) );
        }
      $input_user_hr->{ $n } = $out;
      }
    $self->log_debug( "debug: CGI/input param [$n] value [$v[0]] array [@v]" );
    }

  # import uploads
  my $uploads = $plack->uploads();
  for my $n ( keys %$uploads )
    {
    my @u = $uploads->get_all( $n );
    $input_user_hr->{ "#$n" } =  @u; # count of the uploaded files
    $input_user_hr->{ "^$n" } = \@u; # holds all uploads, could be empty
    }

  # merge forced parameters
  %$input_user_hr = ( %$input_user_hr, %args ) if $args;

  my $safe_input_link_sess = $input_user_hr->{ '_' };

  my $link_session_hr; # FIXME!!!!!!!!!!!!!!!!!!!!!

  # parse link session: link-sid.link-key
  if( $safe_input_link_sess =~ /^([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)$/ )
    {
    my ( $link_sid, $link_key ) = ( $1, $2 );

####### my >!!!!!!!!!!!!!!!!!!!!!
    $link_session_hr = $self->ses->load( 'LINK', $link_sid );

    my $link_data = $link_session_hr->{ 'ARGS' }{ $link_key };

    # merge safe input if valid
    %$input_safe_hr = ( %$input_safe_hr, %$link_data ) if $link_data;
    # merge forced parameters
    %$input_safe_hr = ( %$input_safe_hr, %args       ) if $args;
    }
  elsif( $safe_input_link_sess ne '' )
    {
    $self->log( "warning: invalid safe input link session.key [$safe_input_link_sess] ignored" );
    }

  # 4. loading page session
  my $page_sid = __input_sid_check( $input_safe_hr->{ '_P' } );
  my $page_shr = $self->ses->load( 'PAGE', $page_sid ); # user session hash ref
  if( ! $page_shr )
    {
    $self->log_debug( "warning: invalid page session [$page_sid]" ) if $page_sid;
    $page_sid = $self->ses->create( 'PAGE', 8 );
    $page_sid = $HNS[rand(@HNS)] . '_' . $page_sid if $self->is_debug();
    $self->log( "status: new page session created [$page_sid]" );
    $page_shr = { ':ID' => $page_sid };
    }
  $self->__set_session( 'PAGE', $page_sid, $page_shr );

  $page_shr->{ ':REF_PAGE_SID' } = __input_sid_check( $input_safe_hr->{ '_R' } || $page_shr->{ ':REF_PAGE_SID' } );
  $page_shr->{ ':TOP_PAGE_SID' } = __input_sid_check( $input_safe_hr->{ '_T' } || $page_shr->{ ':TOP_PAGE_SID' } );

  # 5. remap form input names and data, post to safe input
  my $form_id = $input_safe_hr->{ 'FORM_ID' }; # FIXME: replace with _FRI
  if( $form_id and exists $link_session_hr->{ 'FORM_RET_MAP' }{ $form_id } )
    {
    my $rmn = $link_session_hr->{ 'FORM_RET_MAP' }{ $form_id }{ 'NAME' }; # return map names
    my $rmd = $link_session_hr->{ 'FORM_RET_MAP' }{ $form_id }{ 'DATA' }; # return map data

    for my $n ( keys %$input_user_hr )
      {
      my $nn = $n;
      if( exists $rmn->{ $n } )
        {
        $nn = $rmn->{ $n };
        $input_user_hr->{ $nn } = $input_user_hr->{ $n };
        delete $input_user_hr->{ $n };
        }
      if( exists $rmd->{ $nn } )
        {
        $input_safe_hr->{ $nn } = $rmd->{ $nn }{ $input_user_hr->{ $nn } };
        delete $input_user_hr->{ $nn };
        }
      }

=pod
    # remap names
    for my $n ( keys %$rmn )
      {
      next unless exists $input_user_hr->{ $n };
      $input_user_hr->{ $rmn->{ $n } } = $input_user_hr->{ $n };
      delete $input_user_hr->{ $n };
      }

    # remap data
    for my $k ( keys %$rmd )
      {
      next unless exists $input_user_hr->{ $k };
      $input_safe_hr->{ $k } = $rmd->{ $k }{ $input_user_hr->{ $k } };
      delete $input_user_hr->{ $k };
      }
=cut

    }

  # 6. get action from input (USER/CGI) or page session
  my $action_name = lc( $input_safe_hr->{ '_AN' } || $input_user_hr->{ '_AN' } || $page_shr->{ ':ACTION_NAME' } );
  if( $action_name =~ /^[a-z0-9_]+$/ )
    {
    $page_shr->{ ':ACTION_NAME' } = $action_name;
    }
  else
    {
    # $self->log( "error: invalid action name [$action_name]" );
    }

  # 7. get page from input (USER/CGI) or page session
  my $page_name = lc( $input_safe_hr->{ '_PN' } || $input_user_hr->{ '_PN' } || $page_shr->{ ':PAGE_NAME' } || { $self->get_page_session( 1 ) || {} }->{ ':PAGE_NAME' } || 'main' );
  if( $page_name ne '' )
    {
    if( $page_name =~ /^[a-z0-9_\-\/]+$/ )
      {
      $page_shr->{ ':PAGE_NAME' } = $page_name;
      }
    else
      {
      $self->log( "error: invalid page name [$page_name]" );
      }
    }

  # 8. render output action/page
  if( $action_name )
    {
    $self->render( ACTION => $action_name );
    }
  else
    {
    $self->render( PAGE => $page_name );
    }
}

### REQUEST/INPUT DATA & UPLOADS #############################################

sub get_client_input_button
{
  my $self  = shift;

  my $input_user_hr = $self->get_client_input();

  for( keys %$input_user_hr )
    {
    # regular button BUTTON:CANCEL
    # button with id BUTTON:REDIRECT:USERID
    next unless /BUTTON:([a-z0-9_\-]+)(:(.+?))?(\.[XY])?$/oi;

    # return ( button, button_id )
    return wantarray ? ( $1, $2 ) : $1
    }

  return ();
}

sub get_lang
{
  my $self  = shift;

  return $self->get_cfg->{ 'LANG' };
}

sub get_app_name
{
  my $self  = shift;

  return $self->get_cfg->{ 'APP_NAME' };
}

sub get_app_root
{
  my $self  = shift;

  return $self->get_cfg->{ 'APP_ROOT' };
}

##############################################################################

sub args
{
  my $self = shift;
  my %args = @_;

  die "not implemented yet";
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
  my $name = shift;

  return $self->{ 'HTML_HOLD' }{ $name };
}

sub html_hold_del
{
  my $self = shift;
  my $name = shift;

  delete $self->{ 'HTML_HOLD' }{ $name };

  return 1;
}

sub html_hold_clear
{
  my $self = shift;

  $self->{ 'HTML_HOLD' } ||= {};
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
  my $name = shift;
  my $text = shift;

  $self->{ 'HTML_HOLD' } ||= {};
  $self->{ 'HTML_HOLD' }{ $name }{ $text }++;

  $self->html_hold_set( $name, join '', keys %{ $self->{ 'HTML_CONTENT' }{ $name } } );
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

sub render_action
{
  my $self   = shift;
  my $action = shift;

  $portray_data = $self->act->call( $action );

  if( $portray_data->{ 'TYPE' } eq 'text/html' )
    {
    $portray_data->{ 'TYPE' } = $self->pre->preprocess( $portray_data->{ 'TYPE' } );
    }

  return $self->render( $portray_data );
}

sub render_page
{
  my $self = shift;
  my $page = shift;

  $portray_data = $self->pre->load_page( $page );

  if( $portray_data->{ 'TYPE' } eq 'text/html' )
    {
    $portray_data->{ 'TYPE' } = $self->pre->preprocess( $portray_data->{ 'TYPE' } );
    }

  return $self->render( $portray_data );
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

  my $cfg = $self->get_cfg();

  my $lang = lc $cfg->{ 'LANG' };

  return 0 if $lang !~ /^[a-z][a-z]$/; # FIXME: move to init check! verofy hash etc. data::tools

  $self->{ 'TRANS' }{ 'LANG' } = $lang;

  return 1 if $self->{ 'TRANS' }{ $lang };

  my $tr = $self->{ 'TRANS' }{ $lang } = {};

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
