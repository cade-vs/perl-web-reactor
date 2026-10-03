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
package Web::Reactor;
use strict;

use parent 'Web::Reactor::Reflex';
use Data::Tools 1.24;
use Exception::Sink;
use Data::Dumper;
use Crypt::PRNG;

#use Web::Reactor::Utils;
use Web::Reactor::HTML::Form;

our $VERSION = '3.33';

##############################################################################

#minimum config:
#my %cfg = (
#          '' => ,
#          );

our @HTTP_VARS_CHECK = qw(
                           _CLIENT_IP
                           HTTP_USER_AGENT
                         );

our @HTTP_VARS_SAVE  = qw(
                           _CLIENT_IP
                           REMOTE_ADDR
                           REMOTE_PORT
                           REQUEST_METHOD
                           REQUEST_URI
                           HTTP_REFERER
                           QUERY_STRING
                           HTTP_COOKIE
                           HTTP_USER_AGENT
                           HTTP_CF_CONNECTING_IP
                           HTTP_CF_IPCOUNTRY
                           HTTP_CF_RAY
                           HTTP_X_FORWARDED_FOR
                           HTTP_X_FORWARDED_PROTO
                           HTTP_X_REAL_IP
                         );

our %ENV_ALLOWED_KEYS = (

                        );

##############################################################################

sub new
{
  my $class = shift;
  my $env   = shift;
  my $cfg   = shift;

  $class = ref( $class ) || $class;
  my $self = $class->SUPER::new( $env, $cfg );

  # FIXME: verify %env content! Data::Validate::Struct
  boom "fatal: configuration: request scheme [HTTP] does not match cookies security policy! either enable HTTPS scheme or set DISABLE_SECURE_COOKIES=1"
      if $self->get_request_scheme() eq 'http' and ! $cfg->{ 'DISABLE_SECURE_COOKIES' };

  return $self;
}

### FUNC PLUGS ###############################################################

sub ses
{
  my $self = shift;

  return $self->{ "REO_SES" } ||= $self->__load_and_attach_module( 'SES', 'Web::Reactor::Sessions::Filesystem', $self, $self->cfg() );
}

# actually reactor uses only public part rsa, any private decoders are backend-related
sub rsa
{
  my $self = shift;

  return $self->{ "REO_RSA" } if exists $self->{ "REO_RSA" };

  my $pub = $self->cfg->{ 'RSA_PUB' };
  boom "RSA encryption requested but configuration does not have RSA_PUB key in it" unless $pub;

  return $self->{ "REO_RSA" } = $self->__load_and_attach_module( 'RSA', 'Data::Tools::Crypto::RSA', $pub );
}

##############################################################################

sub process_request
{
  my $self = shift;
  my $args = @_ / 2; # count of arg pairs
  my %args = @_;

  hash_uc_ipl( \%args );

  my $cfg = $self->cfg();

  # 0. load/setup env/config defaults
  my $app_name = $self->get_app_name();

  # 1. loading cookie for keeping user sessions
  my $cookie_name = lc( $cfg->{ 'COOKIE_NAME' } || "$app_name\_cookie" );
  my $user_sid = __input_sid_check( $self->get_cookie( $cookie_name ) );
  $self->log_debug( "debug: incoming USER_SID cookie name [$cookie_name] value [$user_sid]" );

  # 2. loading user session, setup new session and cookie if needed
  my $user_shr = {}; # user session hash ref
  if( $user_sid and $user_shr = $self->ses->load( 'USER', $user_sid ) )
    {
    $self->log_debug( "debug: status: user session ok [$user_sid]" );
    $self->__set_session( 'USER', $user_sid, $user_shr );
    $self->__update_session_fingerprint( 'USER', $user_sid, $user_shr );
    }
  else
    {
    $self->log( "warning: invalid user session [$user_sid]" ) if $user_sid;
    ( $user_sid, $user_shr ) = $self->__create_new_user_session();
    }

  if( ( $user_shr->{ ':LOGGED_IN' } and $user_shr->{ ':XTIME' } > 0 and time() > $user_shr->{ ':XTIME' } )
      or
      ( $user_shr->{ ':CLOSED' } ) )
    {
    $self->log( "status: user session expired or closed, sid [$user_sid]" );
    # not logged-in sessions dont expire
    $user_shr->{ ':CLOSED'       } = 1;
    $user_shr->{ ':ETIME'        } = time();
    $user_shr->{ ':ETIME_STR'    } = scalar localtime();

    ( $user_sid, $user_shr ) = $self->__create_new_user_session();

    $self->render_page( 'eexpired' );
    }

  for my $k ( keys %{ $user_shr->{ ":HTTP_CHECK_HR" } } )
    {
    # check if session parameters are changed, stealing session?
    my $chk_exp = $user_shr->{ ":HTTP_CHECK_HR" }{ $k };
    my $chk_got = $self->{ 'IN' }{ 'ENV' }{ $k };
    next if $chk_exp eq $chk_got;

    $self->log( "error: user session parameter [$k] check failed, expected [$chk_exp] got [$chk_got] for sid [$user_sid]" );
    # FIXME: move to function: close_session();
    $user_shr->{ ':CLOSED'       } = 1;
    $user_shr->{ ':ETIME'        } = time();
    $user_shr->{ ':ETIME_STR'    } = scalar localtime();

    ( $user_sid, $user_shr ) = $self->__create_new_user_session();

    $self->render_page( 'einvalid' );
    last;
    }

  # FIXME: move to single place
  my $user_session_expire = $cfg->{ 'USER_SESSION_EXPIRE' } || 600; # 10 minutes
  $self->set_user_session_expire_time_in( $user_session_expire );

  my $user_input_hr = $self->get_user_input();
  my $safe_input_hr = $self->get_safe_input();

  # merge forced parameters
  # FIXME: TODO: should it go only to the safe params, or?
  %$user_input_hr = ( %$user_input_hr, %args ) if $args;
  %$safe_input_hr = ( %$safe_input_hr, %args ) if $args;


  # 4. loading page session
  my $page_sid = __input_sid_check( $safe_input_hr->{ '_P' } );
  my $page_shr = $self->ses->load( 'PAGE', $page_sid ); # user session hash ref
  if( $page_shr )
    {
    $self->__update_session_fingerprint( 'PAGE', $page_sid, $page_shr );
    }
  else
    {
    $self->log_debug( "warning: invalid page session [$page_sid]" ) if $page_sid;
    $page_sid = $self->ses->create( 'PAGE', 8 );
    $self->log( "status: new page session created [$page_sid]" );
    $page_shr = { ':ID' => $page_sid };
    }
  $self->__set_session( 'PAGE', $page_sid, $page_shr );

  $page_shr->{ ':REF_PAGE_SID' } = __input_sid_check( $safe_input_hr->{ '_R' } || $page_shr->{ ':REF_PAGE_SID' } );
  $page_shr->{ ':TOP_PAGE_SID' } = __input_sid_check( $safe_input_hr->{ '_T' } || $page_shr->{ ':TOP_PAGE_SID' } );

  # 6. get action from input (USER/CGI) or page session
  my $action_name = lc( $safe_input_hr->{ '_AN' } || $user_input_hr->{ '_AN' } );
  my $page_name   = lc( $safe_input_hr->{ '_PN' } || $user_input_hr->{ '_PN' } );
  if( $action_name )
    {
    $self->act->check_action_name( $action_name );
    $page_shr->{ ':ACTION_NAME' } = $action_name;
    delete $page_shr->{ ':PAGE_NAME' };
    }
  elsif( $page_name )
    {
    $self->pre->check_page_name( $page_name );
    $page_shr->{ ':PAGE_NAME' } = $page_name;
    delete $page_shr->{ ':ACTION_NAME' };
    }
  elsif( $page_shr->{ ':ACTION_NAME' } )
    {
    $action_name = $page_shr->{ ':ACTION_NAME' };
    }
  elsif( $page_shr->{ ':PAGE_NAME' } )
    {
    $page_name = $page_shr->{ ':PAGE_NAME' };
    }
  else
    {
    my $rs = $self->get_page_session( 1 ) || {};
    $page_name = $rs->{ ':PAGE_NAME' } if $rs;
    $page_name ||= 'main';
    $page_shr->{ ':PAGE_NAME' } = $page_name if $page_name;
    }

  $self->save();

  if( $action_name )
    {
    $self->render_action( $action_name );
    }
  else
    {
    $self->render_page( $page_name );
    }

}

### USER SESSION API #########################################################

sub __input_sid_check
{
  return $_[0] =~ /^[a-zA-Z0-9_]+$/ ? $_[0] : undef;
}

sub __create_new_user_session
{
  my $self = shift;

  my $user_sid;
  my $user_shr;

  my $cfg = $self->cfg();

  $user_sid = $self->ses->create( 'USER' );
  $user_shr = { ':ID' => $user_sid };

  $self->__set_user_session_cookie( $user_sid ); # FIXME: CHECK ROTATION
  $self->log( "debug: creating new user session [$user_sid]" );

  my $user_session_expire = $cfg->{ 'USER_SESSION_EXPIRE' } || 600; # 10 minutes

  $user_shr->{ ':CTIME'      } = time();
  $user_shr->{ ':CTIME_STR'  } = scalar localtime();

  # read and save http environment data into user session, used for checks and info
  $user_shr->{ ":HTTP_CHECK_HR" } = { map { $_ => $self->{ 'IN' }{ 'ENV' }{ $_ } } @HTTP_VARS_CHECK };
  $user_shr->{ ":HTTP_ENV_HR"   } = { map { $_ => $self->{ 'IN' }{ 'ENV' }{ $_ } } @HTTP_VARS_SAVE  };

  $self->__set_session( 'USER', $user_sid, $user_shr );

  $self->set_user_session_expire_time_in( $user_session_expire );

  return ( $user_sid, $user_shr );
}

# (re)issue the user session cookie bound to the given session id
sub __set_user_session_cookie
{
  my $self     = shift;
  my $user_sid = shift;

  my $cfg = $self->cfg();

  my $app_name    = $cfg->{ 'APP_NAME' } or boom( "missing APP_NAME" );
  my $cookie_name = lc( $cfg->{ 'COOKIE_NAME' } || "$app_name\_cookie" );

  my $path = $cfg->{ 'COOKIE_PATH' };
  if( ! $path )
    {
    # directory part of the request path, safe characters only (no ';', spaces,
    # controls etc.), so REQUEST_URI cannot inject cookie attributes
    ( $path ) = $self->get_request_uri() =~ m{^(/[A-Za-z0-9/._~%-]*/)};
    }
  $path ||= '/';

  my $secure_cookie = $cfg->{ 'DISABLE_SECURE_COOKIES' } ? 0 : 1;
  $self->res_set_cookie( $cookie_name, value => $user_sid, path => $path, httponly => 1, secure => $secure_cookie, samesite => 'lax' );
}

sub __rotate_user_session_id
{
  my $self = shift;

  my $old_sid  = $self->get_user_session_id();
  my $user_shr = $self->get_user_session();

  # allocate a fresh, unpredictable session id for the elevated session
  my $new_sid = $self->ses->create( 'USER' );

  # re-key the current in-memory user session data under the new id (data kept)
  delete $self->{ 'SESSIONS' }{ 'DATA'              }{ 'USER' }{ $old_sid };
  delete $self->{ 'CACHE'    }{ 'SESSION_DATA_SHA1' }{ 'USER' }{ $old_sid };
  $user_shr->{ ':ID' } = $new_sid;
  $self->{ 'SESSIONS' }{ 'SID'  }{ 'USER' }             = $new_sid;
  $self->{ 'SESSIONS' }{ 'DATA' }{ 'USER' }{ $new_sid } = $user_shr;
###########  $self->__update_session_fingerprint( 'USER', $new_sid, $user_shr );

  # re-save all related link and page sessions, drop modification fingerprints
  delete $self->{ 'CACHE' }{ 'SESSION_DATA_SHA1' }{ $_ } for qw( PAGE LINK );

  # reissue the cookie bound to the new id
  $self->__set_user_session_cookie( $new_sid );

  # invalidate the old session in storage so a fixed pre-login cookie is useless
  $self->ses->save( 'USER', $old_sid, { ':ID' => $old_sid, ':CLOSED' => 1, ':ETIME' => time(), ':ETIME_STR' => scalar localtime() } );

  $self->log( "status: rotated user session id on login [$old_sid] -> [$new_sid]" );

  return $new_sid;
}

##############################################################################

sub __import_single_safe_entry
{
  my $self = shift;
  my $z    = shift;

  return $self->__import_hidden_safe_input( $1, $2  ) if $z =~ /^([a-zA-Z0-9_]+)\.([a-zA-Z0-9_]+)$/;
  return $self->SUPER::__import_single_safe_entry( $z );
}

sub __import_hidden_safe_input
{
  my $self = shift;
  my $link_sid = shift;
  my $link_key = shift;

  my %safe_input_hr;

  my $link_session_hr = $self->ses->load( 'LINK', $link_sid ) or return {};
  my $ldhr = $link_session_hr->{ 'ARGS' }{ $link_key } or return {}; # link data hashref
  %safe_input_hr = %$ldhr;

  # remap incoming parameter names and values, hidden by the FORMs engine
  my $form_id = $safe_input_hr{ 'FORM_ID' }; # FIXME: replace with _FRI
  if( $form_id and exists $link_session_hr->{ 'FORM_RET_MAP' }{ $form_id } )
    {
    my $rmn = $link_session_hr->{ 'FORM_RET_MAP' }{ $form_id }{ 'NAME' }; # return map names
    my $rmd = $link_session_hr->{ 'FORM_RET_MAP' }{ $form_id }{ 'DATA' }; # return map data

    my $user_input_hr = $self->get_user_input();
    # remap input data
    for my $n ( keys %$user_input_hr )
      {
      my $nn = $n;
      if( exists $rmn->{ $n } )
        {
        # remap names
        $nn = $rmn->{ $n };
        $user_input_hr->{ $nn } = $user_input_hr->{ $n };
        delete $user_input_hr->{ $n };
        }
      if( exists $rmd->{ $nn } )
        {
        # remap values
        $safe_input_hr{ $nn } = $rmd->{ $nn }{ $user_input_hr->{ $nn } };
        delete $user_input_hr->{ $nn };
        }
      }
    }

  return \%safe_input_hr;
}

##############################################################################

sub run_print_final_debug
{
  my $self = shift;

  my $psid = $self->get_page_session_id( 0 ) || 'empty';
  my $rsid = $self->get_page_session_id( 1 ) || 'empty';
  my $usid = $self->get_user_session_id(   ) || 'empty';
  $self->log_dumper( "USER INPUT-------------------------------------", $self->get_user_input()   );
  $self->log_dumper( "SAFE INPUT-------------------------------------", $self->get_safe_input()   );
  $self->log_dumper( "PAGE SESSION [$psid]-----------------------------------", $self->get_page_session() );
  $self->log_dumper( "REF  SESSION [$rsid]-----------------------------------", $self->get_page_session( 1 ) );

  if( $self->is_debug() > 2 )
    {
    $self->log_dumper( "USER SESSION [$usid]---------------------------", $self->get_user_session() );
    my ( $ls, $lsid ) = $self->get_link_session();
    $self->log_dumper( "FINAL LINK SESSION  [$lsid]-----------------------------------", $ls );
    }
}

##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################
##############################################################################

##############################################################################
#
# usual user visible api
#

# user hold is data, which is preserved between login sessions, can carry anything
# user hold is available only after login and only if login has username or other user identification

sub get_user_hold
{
  my $self = shift;

  my $uid = $self->get_user_session()->{ ':USER_IDENT' } or return undef; # logged-out session has no user hold

  return $self->{ 'SESSIONS' }{ 'DATA' }{ 'HOLD' }{ $uid } if $self->{ 'SESSIONS' }{ 'DATA' }{ 'HOLD' }{ $uid };

  my $hold = $self->ses->load( 'HOLD', $uid ) || {};

  $self->{ 'SESSIONS' }{ 'DATA' }{ 'HOLD' }{ $uid } = $hold;

  return $hold;
}

sub get_user_session
{
  my $self = shift;

  my $user_sid = $self->{ 'SESSIONS' }{ 'SID'  }{ 'USER' };
  my $user_shr = $self->{ 'SESSIONS' }{ 'DATA' }{ 'USER' }{ $user_sid };

  return $user_shr;
}

sub get_user_session_id
{
  my $self = shift;

  my $user_sid = $self->{ 'SESSIONS' }{ 'SID'  }{ 'USER' };

  return $user_sid;
}

sub get_page_session
{
  my $self  = shift;
  my $level = shift;

  my $page_sid = $self->{ 'SESSIONS' }{ 'SID'  }{ 'PAGE' };
  my $page_shr = $self->{ 'SESSIONS' }{ 'DATA' }{ 'PAGE' }{ $page_sid };

  while( $level-- )
    {
    my $pre_page_shr = $page_shr; # save for cutting ref link if needed
    $page_sid = $page_shr->{ ':REF_PAGE_SID' };
    return undef unless $page_sid;
    next if $page_shr = $self->{ 'SESSIONS' }{ 'DATA' }{ 'PAGE' }{ $page_sid };
    $page_shr = $self->ses->load( 'PAGE', $page_sid );
    if( ! $page_shr )
      {
      delete $pre_page_shr->{ ':REF_PAGE_SID' };
      return undef;
      }
    $self->{ 'SESSIONS' }{ 'DATA' }{ 'PAGE' }{ $page_sid } = $page_shr;
    $self->__update_session_fingerprint( 'PAGE', $page_sid, $page_shr );
    }

  return $page_shr;
}

sub get_link_session
{
  my $self  = shift;

  my $link_sid;
  my $link_shr;

  if( ! $self->{ 'SESSIONS' }{ 'SID'  }{ 'LINK' } )
    {
    $link_sid = $self->ses->create( 'LINK', 8 );
    $link_shr = { ':ID' => $link_sid };
    $self->__set_session( 'LINK', $link_sid, $link_shr );
    }
  else
    {
    $link_sid = $self->{ 'SESSIONS' }{ 'SID'  }{ 'LINK' };
    $link_shr = $self->{ 'SESSIONS' }{ 'DATA' }{ 'LINK' }{ $link_sid };
    }

  return wantarray ? ( $link_shr, $link_sid ) : $link_shr;
}

sub new_link_session_key
{
  my $self = shift;
  my $len  = shift || 8;

  my $link_shr = $self->get_link_session();

  my $link_key;
  my $limit = 137;
  while( $limit-- )
    {
    $link_key = $self->ses->create_id( $len );
    return $link_key if ! exists $link_shr->{ 'ARGS' }{ $link_key };
    }
  boom( "cannot create LINK key" );
}

sub get_page_session_id
{
  my $self  = shift;
  my $level = shift;

  my $shr = $self->get_page_session( $level ) || {};

  return $shr->{ ':ID' };
}

sub get_ref_page_session_id
{
  my $self  = shift;
  my $level = shift;

  my $shr = $self->get_page_session( $level ) || {};

  return $shr->{ ':REF_PAGE_SID' };
}

sub get_top_page_session_id
{
  my $self  = shift;
  my $level = shift;

  my $shr = $self->get_page_session( $level ) || {};

  return $shr->{ ':TOP_PAGE_SID' };
}

sub get_input_button
{
  my $self  = shift;

  my $input_user_hr = $self->get_user_input();
  my $input_safe_hr = $self->get_safe_input();
  return $input_safe_hr->{ 'BUTTON' } || $input_user_hr->{ 'BUTTON' };
}

sub get_input_button_id
{
  my $self  = shift;

  my $input_user_hr = $self->get_user_input();
  my $input_safe_hr = $self->get_safe_input();
  return $input_safe_hr->{ 'BUTTON_ID' } || $input_user_hr->{ 'BUTTON_ID' };
}

sub get_input_button_and_remove
{
  my $self  = shift;

  my $input_user_hr = $self->get_user_input();
  my $input_safe_hr = $self->get_safe_input();
  my $button = $input_safe_hr->{ 'BUTTON' } || $input_user_hr->{ 'BUTTON' };
  delete $input_user_hr->{ 'BUTTON' };
  delete $input_safe_hr->{ 'BUTTON' };
  return $button;
}

sub get_input_form_name
{
  my $self  = shift;

  my $input_safe_hr = $self->get_safe_input();
  my $form_name = $input_safe_hr->{ 'FORM_NAME' }; # FIXME: replace with _FN

  return $form_name;
}

### ARGS #####################################################################

sub args
{
  my $self = shift;
  my %args = @_;

  hash_uc_ipl( \%args );

  my ( $link_shr, $link_sid ) = $self->get_link_session();
  my $link_key = $self->new_link_session_key();

  $link_shr->{ 'ARGS' }{ $link_key } = \%args;

  return $link_sid . '.' . $link_key;
}

sub args_back
{
  my $self = shift;
  my %args = @_;

  hash_uc_ipl( \%args );

  $args{ '_P'  } = $self->get_ref_page_session_id();
#  $args{ '_PN' } = 'main' unless $args{ '_P' }; # return to 'main' if no referer given

  return $self->args( %args );
}

sub args_back_back
{
  my $self = shift;
  my %args = @_;

  hash_uc_ipl( \%args );

  $args{ '_P' } = $self->get_ref_page_session_id( 1 );
#  $args{ '_PN' } = 'main' unless $args{ '_P' }; # return to 'main' if no referer given

  return $self->args( %args );
}

sub args_new
{
  my $self = shift;
  my %args = @_;

  hash_uc_ipl( \%args );

  $args{ '_R' } = $self->get_page_session_id();

  my $page_shr = $self->get_page_session();
  $args{ '_PN' } ||= $page_shr->{ ':PAGE_NAME' } || 'main' unless $args{ '_AN' };

  return $self->args( %args );
}

# new page session inside a vsFrame
sub args_new_fr
{
  my $self = shift;
  my %args = @_;

  hash_uc_ipl( \%args );

  $args{ '_T' } = $self->get_page_session_id(); # top session (browser window one)

  return $self->args( %args );
}

sub args_here
{
  my $self = shift;
  my %args = @_;

  hash_uc_ipl( \%args );

  $args{ '_P' } = $self->get_page_session_id();

  return $self->args( %args );
}

sub args_type
{
  my $self = shift;

  my $type = lc shift;

  return $self->args_new( @_ )     if $type eq 'new';
  return $self->args_new_fr( @_ )  if $type eq 'new_fr';
  return $self->args_here( @_ )    if $type eq 'here';
  return $self->args_back( @_ )    if $type eq 'back';
  return $self->args( @_ )         if $type eq 'none';
  boom( "unknown or not supported TYPE [$type]" );
}


##############################################################################

sub __set_session
{
  my $self = shift;

  my $type = shift;
  my $sid  = shift;
  my $hr   = shift;

  boom( "session [$type:$sid] already set" ) if exists $self->{ 'SESSIONS' }{ 'DATA' }{ $type }{ $sid };

  $self->{ 'SESSIONS' }{ 'SID'  }{ $type }         = $sid; # keeps only main, USER, PAGE, etc. session IDs
  $self->{ 'SESSIONS' }{ 'DATA' }{ $type }{ $sid } = $hr;
}

sub __update_session_fingerprint
{
  my $self = shift;

  my $type = shift;
  my $sid  = shift;
  my $hr   = shift;

  $self->{ 'CACHE' }{ 'SESSION_DATA_SHA1' }{ $type }{ $sid } = hash_fingerprint( $hr );
}

sub save
{
  my $self = shift;

  my $mod_cache = $self->{ 'CACHE' }{ 'SESSION_DATA_SHA1' } ||= {}; # modify cache
  for my $type ( qw( USER PAGE LINK HOLD ) )
    {
    my $type_hr = $self->{ 'SESSIONS' }{ 'DATA' }{ $type } or next;;
    for my $sid ( keys %$type_hr )
      {
      my $shr = $type_hr->{ $sid };

      my $sha1   = hash_fingerprint( $shr );
      my $cache1 = $mod_cache->{ $type }{ $sid };

      next if $sha1 eq $cache1;

      $self->log_debug( "saving session data [$type:$sid] --> $sha1 <> $cache1" );


      if( $self->ses->save( $type, $sid, $shr ) )
        {
        $mod_cache->{ $type }{ $sid } = $sha1;
        }
      else
        {
        $self->log( "error saving session state for [$type:$sid] --> new $sha1 <> old $cache1" );
        }
      }
    }
}

#sub discard_session_data
#{
#  my $self = shift;
#
#
#  $self->{ 'CACHE' }{ 'SESSION_DATA_SHA1' } = {};
#  $self->{ 'SESSIONS' } = {};
#}

##############################################################################

sub forward
{
  my $self = shift;

  boom "expected even number of arguments" unless @_ % 2 == 0;

  my $fw = $self->args( @_ );
  return $self->forward_url( "?_=$fw" );
}

sub forward_type
{
  my $self = shift;

  boom "expected odd number of arguments" if @_ % 2 == 0;

  my $fw = $self->args_type( @_ );
  return $self->forward_url( "?_=$fw" );
}

sub forward_here
{
  my $self = shift;

  boom "expected even number of arguments" unless @_ % 2 == 0;

  my $fw = $self->args_here( @_ );
  return $self->forward_url( "?_=$fw" );
}

sub forward_back
{
  my $self = shift;

  boom "expected even number of arguments" unless @_ % 2 == 0;

  my $fw = $self->args_back( @_ );
  return $self->forward_url( "?_=$fw" );
}

sub forward_back_back
{
  my $self = shift;

  boom "expected even number of arguments" unless @_ % 2 == 0;

  my $fw = $self->args_back_back( @_ );
  return $self->forward_url( "?_=$fw" );
}

sub forward_new
{
  my $self = shift;

  boom "expected even number of arguments" unless @_ % 2 == 0;

  my $fw = $self->args_new( @_ );
  return $self->forward_url( "?_=$fw" );
}

sub forward_new_page
{
  my $self = shift;
  my $page = shift;

  boom "expected page name + even number of arguments" unless @_ % 2 == 0;

  return $self->forward_new( _PN => $page, @_ );
}

sub forward_new_action
{
  my $self = shift;
  my $actn = shift;

  boom "expected action name + even number of arguments" unless @_ % 2 == 0;

  return $self->forward_new( _AN => $actn, @_ );
}

##############################################################################
##
## helpers
##

sub __param
{
  my $self = shift;
  my $save = shift; # 0 not save, 1 save in cache, 2 save in cache and page session (ps)
  my $safe = shift; # 0 user (unsafe) input, 1 safe input

  my $input_hr;
  my $save_key;
  if( $safe )
    {
    $input_hr = $self->get_safe_input();
    $save_key = 'SAVE_SAFE_INPUT';
    }
  else
    {
    $input_hr = $self->get_user_input();
    $save_key = 'SAVE_USER_INPUT';
    }

  my $ps = $self->get_page_session();

  $ps->{ $save_key } ||= {} if $save > 0;

  my @res;
  while( @_ )
    {
    my $p = uc shift;
    if( $save > 0 )
      {
      if( exists $input_hr->{ $p } )
        {
        $ps->{ $save_key }{ $p } = $input_hr->{ $p };
        $ps->{ $p } = $input_hr->{ $p } if $save > 1;
        }
      push @res, $ps->{ $save_key }{ $p };
      }
    else
      {
      push @res, $input_hr->{ $p };
      }
    }

  return wantarray ? @res : shift( @res );
}

sub param_unsafe
{
  my $self = shift;
  return $self->__param( 1, 0, @_ );
}

sub param
{
  my $self = shift;
  return $self->__param( 1, 1, @_ );
}

sub param_save
{
  my $self = shift;
  return $self->__param( 2, 1, @_ );
}

sub param_safe
{
  my $self = shift;
  return $self->param( @_ );
}

sub param_peek_unsafe
{
  my $self = shift;
  return $self->__param( 0, 0, @_ );
}

sub param_peek
{
  my $self = shift;
  return $self->__param( 0, 1, @_ );
}

sub param_peek_safe
{
  my $self = shift;
  return $self->param_peek( @_ );
}

sub param_clear_cache
{
  my $self = shift;

  my $ps = $self->get_page_session();

  while( @_ )
    {
    my $p = uc shift;
    delete $ps->{ 'SAVE_SAFE_INPUT' }{ $p };
    delete $ps->{ 'SAVE_USER_INPUT' }{ $p };
    }

  return 1;
}


sub is_logged_in
{
  my $self = shift;

  my $user_shr = $self->get_user_session();
  return $user_shr->{ ':LOGGED_IN' } ? 1 : 0;
}

sub login
{
  my $self = shift;
  my $user_ident = shift; # user identifier, login name, used for mapping of cross-login-session permanent data

  $self->__rotate_user_session_id();

  my $user_ident_s = $user_ident;

  $user_ident_s =~ s/[^a-z0-9_\-:]/_/gi; # human readable
  $user_ident   = str_hex_utf8( $user_ident );

  # NOTE: user names (login idents) are limited to 64 chars. the HOLD id is the
  #       hex of the UTF-8 bytes and its file name, with ".wrs2" and the
  #       ".tmp.PID.part" save suffix, must stay under 255 bytes, i.e. up to
  #       ~116 UTF-8 bytes: 64 ASCII chars fit, 64 two-byte chars (Cyrillic etc.)
  #       do not. SHA1 ids, see the TODO below, would have no such limit.

  # TODO: UNDECIDED: migrate to SHA1 pros and cons
  #       i.e. $user_ident = sha1_hex( str_hex_utf8( $user_ident ) ) instead of padded hex
  #       pros: fixed 40 chars id, no padding needed
  #             any login length: hex doubles the name and a file name over 255
  #             bytes (with ".wrs2" and ".tmp.PID.part") cannot be saved, so
  #             logins over ~116 bytes fail now (e-mails may be up to 254 chars)
  #             even spread over HOLD/xx/yy/ dirs, hex uses the first 2 login bytes
  #             login names are not visible in HOLD file names (backups, dumps)
  #       cons: one-time rename of existing HOLD files, new name is
  #             sha1_hex( old id ) and goes under the new id's own HOLD/xx/yy/ dir
  #             file names cannot be reversed to login names for audits,
  #             hex ids reverse with str_unhex_utf8()

  my $ml = $self->ses->get_min_ses_id_len();
  $user_ident  .= '_' x ( $ml - length $user_ident ) if length $user_ident < $ml;

  my $user_shr = $self->get_user_session();
  $user_shr->{ ':LOGGED_IN'    } = 1;
  $user_shr->{ ':LITIME'       } = time();
  $user_shr->{ ':LITIME_STR'   } = scalar localtime();
  $user_shr->{ ':USER_IDENT'   } = $user_ident;
  $user_shr->{ ':USER_IDENT_S' } = $user_ident_s;
  # FIXME: add more login info
}

sub logout
{
  my $self = shift;

  my $user_shr = $self->get_user_session();
  $user_shr->{ ':LOGGED_IN'    } = 0;
  $user_shr->{ ':CLOSED'       } = 1;
  $user_shr->{ ':LOTIME'       } = time();
  $user_shr->{ ':LOTIME_STR'   } = scalar localtime();
  $user_shr->{ ':ETIME'        } = time();
  $user_shr->{ ':ETIME_STR'    } = scalar localtime();
  # FIXME: add more logout info
  # FIXME: PAGE and LINK sessions are stored under the user sid that is current
  #        at save() time, not the one they were loaded or created with. the
  #        current page session (and any LINK made in this request) is saved
  #        under the new anonymous user sid below, so its logged-in data, and
  #        pre-logout links pointing to it, stay reachable after logout. a LINK
  #        made before logout also leaves an empty file under the old user sid.
  #        possible fix: $self->save() first, so everything goes to the old user
  #        sid, then drop PAGE and LINK from $self->{ 'SESSIONS' } and their
  #        fingerprints, so nothing reaches the anonymous user namespace.
  my ( $user_sid, $user_shr ) = $self->__create_new_user_session();
}

# FIXME: s?
sub need_login
{
  my $self = shift;

  return if $self->is_logged_in();

  my $fw = $self->args_new( _PN => 'login' );
  return $self->forward_url( "?_=$fw" );

  # return $self->forward( _PN => 'login' );
}

sub set_user_session_expire_time
{
  my $self  = shift;
  my $xtime = shift;

  my $user_shr = $self->get_user_session();
  $user_shr->{ ':XTIME'     } = $xtime; # FIXME: sanity?
  $user_shr->{ ':XTIME_STR' } = scalar localtime $user_shr->{ ':XTIME' };
  return exists $user_shr->{ ':XTIME' } ? $user_shr->{ ':XTIME' } : undef;
}

sub set_user_session_expire_time_in
{
  my $self    = shift;
  my $seconds = shift;

  # FIXME: support for more user friendly time periods 10m 60s
  return $self->set_user_session_expire_time( time() + $seconds );
}

# returns unix time at which user session will expire, undef if no expire time specified
sub get_user_session_expire_time
{
  my $self = shift;

  my $user_shr = $self->get_user_session();

  return exists $user_shr->{ ':XTIME' } ? $user_shr->{ ':XTIME' } : undef;
}

# returns time period in seconds, in which user session will expire, undef if no expire time specified
sub get_user_session_expire_time_in
{
  my $self = shift;

  my $xi = $self->get_user_session_expire_time() - time();
  return $xi > 0 ? $xi : undef;
}

sub get_user_session_agent
{
  my $self = shift;

  my $user_session = $self->get_user_session();
  my $user_agent   = $user_session->{ ':HTTP_ENV_HR' }{ 'HTTP_USER_AGENT' };

  return $user_agent || 'n/a';
}

##############################################################################

# NOTE: translation handling lives in Web::Reactor::Reflex (load_trans(),
#       load_trans_file()), these old copies are disabled
#
#sub load_trans
#{
#  my $self = shift;
#
#  my $cfg = $self->cfg();
#
#  my $lang = lc $cfg->{ 'LANG' };
#
#  return 0 if $lang !~ /^[a-z][a-z]$/; # FIXME: move to init check! verofy hash etc. data::tools
#
#  $self->{ 'TRANS' }{ 'LANG' } = $lang;
#
#  return 1 if $self->{ 'TRANS' }{ $lang };
#
#  my $tr = $self->{ 'TRANS' }{ $lang } = {};
#
#  my $trans_dirs = $cfg->{ 'TRANS_DIRS' };
#  my $trans_file = $cfg->{ 'TRANS_FILE' };
#
#  my @tf;
#  if( -e $trans_file )
#    {
#    # quick select single translation file, if specified
#    @tf = ( $trans_file );
#    }
#  else
#    {
#    for my $dir ( @$trans_dirs )
#      {
#      push @tf, glob( "$dir/$lang/*.tr" );
#      push @tf, glob( "$dir/$lang/text/*.tr" );
#      }
#    }
#
#  for my $tf ( @tf )
#    {
#    my $hr = $self->load_trans_file( $tf );
#    # trim whitespace
#    my @temp = %$hr;
#    for( @temp )
#      {
#      s/^\s*//;
#      s/\s*$//;
#      }
#    %$hr = @temp;
#    @temp = ();
#    @{ $tr }{ keys %$hr } = values %$hr;
#    }
#
#  return 1;
#}
#
#sub load_trans_file
#{
#  my $self = shift;
#
#  return hash_load( shift );
#}

##############################################################################
##
## REO proxies
##

sub new_form
{
  my $self = shift;

  my $form = new Web::Reactor::HTML::Form( @_, REO_REACTOR => $self );

  return $form;
}

##############################################################################

sub create_uniq_id
{
  my $self = shift;
  my $case = shift;

  my $cfg = $self->cfg();
  my $let = $cfg->{ 'SESS_LETTERS' } || 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  my $limit = 137;
  while( $limit-- )
    {
    my $nid = Crypt::PRNG::random_string_from( $let, 16 );
    $nid = uc $nid if $case == 1;
    $nid = lc $nid if $case == 2;
    next if $self->{ 'CREATE_UNIQ_ID' }{ $nid }++;
    my $psid = $self->get_page_session_id();
    # my $tsid = $self->get_top_page_session_id();
    $self->{ 'CREATE_UNIQ_ID' }{ ':COUNT' }++;
    return $psid . '.' . $nid;
    }
  boom "cannot create new uniq html id";
  return undef;
}

##############################################################################


=pod

=head1 NAME

Web::Reactor perl-based web application machinery.

=head1 SYNOPSIS

Startup CGI script example (LEGACY):

  #!/usr/bin/perl
  use strict;
  use lib '/opt/perl/reactor/lib';
  use Web::Reactor;

  my %cfg = (
            'APP_NAME'     => 'demo',
            'APP_ROOT'     =>   '/opt/reactor/demo/',
            'LIB_DIRS'     => [ '/opt/reactor/demo/lib/'  ],
            'HTML_DIRS'    => [ '/opt/reactor/demo/html/' ],
            'SESS_VAR_DIR' =>   '/opt/reactor/demo/var/sess/',
            'ACTIONS_SETS' => [ 'demo', 'Base', 'Core' ],
            'DEBUG'        => 4,
            );

  eval { new Web::Reactor( %cfg )->run(); };
  if( $@ )
    {
    print STDERR "REACTOR CGI EXCEPTION: $@";
    print "content-type: text/html\n\nsystem is temporary unavailable";
    }

Startup PLACK/PSGI script example (RECOMMENDED):

  #!/usr/bin/perl
  # app.psgi
  use strict;
  use Web::Reactor;

  my %cfg = (
            'APP_NAME'     => 'demo',
            'APP_ROOT'     => '/opt/reactor/demo/',
            'LIB_DIRS'     => [ '/opt/reactor/demo/lib/'  ],
            'ACTIONS_SETS' => [ 'demo', 'Base', 'Core' ],
            'HTML_DIRS'    => [ '/opt/reactor/demo/html/' ],
            'SESS_VAR_DIR' => '/opt/reactor/demo/var/sess/',
            'DEBUG'        => 0,
            );

  my $app = sub {
    my $env = shift;
    my $reactor = new Web::Reactor( $env, \%cfg );
    return $reactor->run();
  };

  return $app;

Run with: plackup -p 5000 app.psgi
Or with reverse proxy (nginx): plackup --server Starman -p 5000 app.psgi

=head1 INTRODUCTION

Web::Reactor is a perl module which automates as much as possible of the all
routine tasks when implementing web applications, interactive sites, etc.
Main task is to handle all the repetative work and adding more comfortable
functionality like:

  * setting and recognising web browser cookies (for sessions or other data)
  * handling user and page sessions (storage, cookie management, etc.)
  * hiding html link data and forms data to rise page-to-page transfer safety.
  * preprocessing of text/html, including hiding data, calling actions etc.
  * on-demand loading of 'actions', perl code modules to handle dynamic pages.

Web::Reactor can be extended, though it was not supposed to. There are 4 main
parts of it which can be extended. See section EXTENDING below for details.

=head1 SECURITY FEATURES

Web::Reactor includes several built-in security features:

=head2 HTTPS Enforcement

By default, Web::Reactor requires HTTPS for secure cookie handling. This prevents
downgrade attacks. To disable (NOT RECOMMENDED for production):

  'DISABLE_SECURE_COOKIES' => 1

=head2 Secure Cookie Flags

All session cookies are set with:

  - httponly: Prevents JavaScript access (XSS protection)
  - secure: Only sent over HTTPS (unless DISABLE_SECURE_COOKIES=1)
  - samesite=lax: CSRF protection (cookies not sent on cross-site requests)

=head2 Session Hijacking Prevention

Session validity is checked on each request:

  - Client IP address is tracked and validated
  - User-Agent is tracked and validated

If either changes, the session is invalidated and a new one created. This
protects against session fixation and hijacking attacks.

=head2 Session Expiration

User sessions can expire after a configurable timeout (default: 600 seconds):

  'USER_SESSION_EXPIRE' => 600,  # 10 minutes

=head2 Input Validation

All input parameters are validated:

  - Parameter names: alphanumeric, dash, underscore, dot, colon
  - Page names: lowercase alphanumeric, dash, underscore, slash
  - Action names: lowercase alphanumeric, underscore
  - Session IDs: alphanumeric, underscore

Invalid input is logged and silently ignored.

=head2 Data Encryption (Optional)

Web::Reactor can encrypt sensitive data with ChaCha20-Poly1305, see cry()
and argsx().
See CRYPTOGRAPHY section below.

=head2 Password Encryption (Optional)

Data such as passwords can be encrypted with an RSA public key through rsa().
Configure RSA_PUB with the PEM text of the public key.

=head2 Content Security Policy (Optional)

Set HTTP_CSP config to add Content-Security-Policy header:

  'HTTP_CSP' => "default-src 'self'; script-src 'self' 'unsafe-inline'",

=head1 EXAMPLES

HTML page file example:

  <#html_header>

  <$app_name>

  <#menu>

  testing page html file

  action test: <&test>

  <#html_footer>

Action module example:

  package Reactor::Actions::demo::test;
  use strict;
  use Data::Dumper;
  use Web::Reactor::HTML::Form;

  sub main
  {
    my $reo = shift; # Web::Reactor object. Provides all API and context.

    my $text; # result html text

    if( $reo->get_input_button() eq 'FORM_CANCEL' )
      {
      # if clicked form button is cancel,
      # return back to the calling/previous page/view with optional data
      return $reo->forward_back( ACTION_RETURN => 'IS_CANCEL' );
      }

    # add some html content
    $text .= "<p>Reactor::Actions::demo::test here!<p>";

    # create link and hide its data. only accessible from inside web app.
    my $grid_href = $reo->args_new( _PN => 'grid', TABLE => 'testtable', );
    $text .= "<a href=?_=$grid_href>go to grid</a><p>";

    # access page session. it will be auto-loaded on demand
    my $page_session_hr = $reo->get_page_session();
    my $fortune = $page_session_hr->{ 'FORTUNE' } ||= `/usr/games/fortune`;

    # access input (form) data. $i and $e are hashrefs
    my $i = $reo->get_user_input(); # get plain user input (hashref)
    my $e = $reo->get_safe_input(); # get safe data (never reach user browser)

    $text .= "<p><hr><p>$fortune<hr>";

    my $bc = $reo->args_here(); # session keeper, this is manual use

    $text .= "<form method=post>";
    $text .= "<input type=hidden name=_ value=$bc>";
    $text .= "input <input name=inp>";
    $text .= "<input type=submit name=button:form_ok>";
    $text .= "<input type=submit name=button:form_cancel>";
    $text .= "</form>";

    my $form = $reo->new_form();

    $text .= "<p><hr><p>";

    return $text;
  }

  1;

=head1 PAGE NAMES, HTML FILE TEMPLATES, PAGE INSTANCES

Web::Reactor has a notion of a "page" which represents visible output to the
end user browser. It has (i.e. uses) the following attributes:

  * html file template (page name)
  * page session data
  * actions code (i.e. callbacks) used inside html text

All of those represent "page instance" and produce end user html visible page.

"Page names" are strictly limited to be alphanumeric and are mapped to file
(or other storage) html content:

                   page name: example
  html file template will be: page_example.html

HTML content may include other files (also limited to be alphanumeric):

          include text: <#other_file>
         file included: other_file.html
  directories searched: 'HTML_DIRS' from Web::Reactor parameters.

Page names may be requested from the end user side, but include html files may
be used only from the pages already requested.

=head1 ACTIONS/MODULES/CALLBACKS

Actions are loaded and executed by package names. In the HTML source files they
can be called this way:

  <&test_action arg1=val1 arg2=val2 flag1 flag2...>
  <&test_action>

This will instruct Reactor action handler to look for this package name inside
standard or user-added library directories:

  Web/Reactor/Actions/*/test_action.pm

Asterisk will be replaced with the name of the used "action sets" give in config
hash:

  'ACTIONS_SETS' => [ 'demo', 'Base', 'Core' ],

So the result list in this example will be:

  Web/Reactor/Actions/demo/test_action.pm
  Web/Reactor/Actions/Base/test_action.pm
  Web/Reactor/Actions/Core/test_action.pm

This is used to allow overriding of standard modules or modules you dont have
write access to.

Another way to call a module is directly from another module code with:

  $reo->act->call( 'test_action', @args );

The package file will look like this:

  package Web/Reactor/Actions/demo/test_action;
  use strict;

  sub main
  {
    my $reo  = shift; # Web::Reactor object/instance
    my %args = @_; # all args passed to the action

    my $html_args = $args{ 'HTML_ARGS' }; # all
    ...
    return $result_data; # usually html text
  }

$html_args is hashref with all args give inside the html code if this action
is called from a html text. If you look the example above:

  <&test_action arg1=val1 arg2=val2 flag1 flag2...>

The $html_args will look like this:

  $html_args = {
               'arg1'  => 'val1',
               'arg2'  => 'val2',
               'flag1' => 1,
               'flag2' => 1,
               };

=head1 HTTP PARAMETERS NAMES

Web::Reactor uses underscore and one or two letters for its system http/html
parameters. Some of the system params are:

  _PN  -- html page name (points to file template, restricted to alphanumeric)
  _AN  -- action name (points to action package name, restricted to alphanumeric)
  _P   -- page session
  _R   -- referer (caller) page session
  _T   -- top-level page session (browser window)

Usually those names should not be directly used or visible inside actions code.
More details about how those params are used can be found below.

=head1 USER SESSIONS

WR creates unique session for each connected user. The session is kept by a cookie.
Usually WR needs just this cookie to handle all user/server interaction. Inside
WR action code, user session is represented as a hash reference. It may hold
arbitrary data. "System" or WR-specific data inside user session has colon as
prefix:

  # $reo is Web::Reactor object (i.e. context) passed to the action/module code
  my $user_session = $reo->get_user_session();
  print STDERR $user_session->{ ':CTIME_STR' };
  # prints in http log the create time in human friendly form

All data saved inside user session is automatically saved. When needed it can
be explicitly saved with:

  $reo->save();
  # saves all modified context to disk or other storage

=head1 PAGE SESSIONS

Each page presented to the user has own session. It is very similar to the user
session (it is hash reference, may hold any data, can be saved with $reo->save()).
It is expected that page sessions hold all context data needed for any page to
display properly. To preserve page session it is needed that it is included
in any link to this page instance or in any html form used.

When called for the first time, each page request needs page name (_PN). Afterwards
a unique page session is created and page name is saved inside. At this moment
this page instance can be accessed (i.e. given control to) only with a page
session id (_P):

  $page_sid = ...; # taken from somewhere
  # to pass control to the page instance:
  $reo->forward( _P => $page_sid );
  # the page instance will pull data from its page session and display in
  # its last known state

Not always page session are needed. For example, when forward to the caller is
needed, you just need to:

  $reo->forward_back();
  # this is equivalent to
  my $ref_page_sid = $reo->get_ref_page_session_id();
  $reo->forward( _P => $ref_page_sid );

Each page instance knows the caller page session and can give control back to.
However it may pass more data when returning back to the caller:

  $reo->forward_back( MORE_DATA => 'is here', OPTIONS_LIST => \@list );

When new page instance has to be called (created):

  $reo->forward_new( _PN => 'some_page_name' );

=head1 CONFIG ENTRIES

Upon creation, Web::Reactor instance gets hash with config entries/keys.

=head2 Required Config Entries

  APP_NAME      -- alphanumeric application name (plus underscore)

=head2 Optional Config Entries (with defaults)

  APP_ROOT                  -- Application root directory (default: current dir)
  APP_CHARSET               -- Character encoding (default: UTF-8)
  LIB_DIRS                  -- Lib directories (default: ["$APP_ROOT/lib"])
  ACTIONS_SETS              -- Action sets (default: [$APP_NAME, 'Base', 'Core'])
  HTML_DIRS                 -- HTML template dirs (default: ["$APP_ROOT/html"])
  SESS_VAR_DIR              -- Session storage dir (default: "$APP_ROOT/var")
  DEBUG                     -- Debug level 0-4 (default: 0)
  COOKIE_NAME               -- Session cookie name (default: "${APP_NAME}_cookie")
  COOKIE_PATH               -- Cookie path (default: derived from REQUEST_URI)
  USER_SESSION_EXPIRE       -- Session timeout in seconds (default: 600)
  LANG                      -- Language code for translations (default: none)

=head2 Security Config Entries

  DISABLE_SECURE_COOKIES    -- Disable HTTPS enforcement (default: 0, NOT RECOMMENDED)
  CRY_KEY                   -- 32 raw bytes key for cry() and argsx() (required if used)
  RSA_PUB                   -- RSA public key PEM text for rsa() (required if used)
  HTTP_CSP                  -- Content-Security-Policy header (optional)

=head2 Extension Config Entries

  REO_SES_CLASS             -- Session storage class (default: Web::Reactor::Sessions::Filesystem)
  REO_PRE_CLASS             -- Preprocessor class (default: Web::Reactor::Preprocessor::Native)
  REO_ACT_CLASS             -- Actions class (default: Web::Reactor::Actions::Native)

=head2 Translation Config Entries

  TRANS_DIRS                -- Directories with .tr translation files (array ref)
  TRANS_FILE                -- Specific translation file to load (string)

=head1 API FUNCTIONS

This section covers the most commonly used API functions. For comprehensive
documentation, see the method source code and examples in the demo/ directory.

=head2 Input Data Functions

  get_user_input()        -- Get all user (unsafe) input from request
  get_safe_input()        -- Get safe input from hidden form fields
  param( @names )         -- Get and cache safe input parameters
  param_unsafe( @names )  -- Get unsafe user input
  param_peek( @names )    -- Get safe input without caching
  param_save( @names )    -- Get, cache, and save to page session
  get_input_button()      -- Get which form button was clicked
  get_input_button_id()   -- Get form button ID if applicable

=head2 Session Functions

  get_user_session()                  -- Get current user session hashref
  get_user_session_id()               -- Get current user session ID
  get_user_session_expire_time()      -- Get expiration timestamp
  get_user_session_expire_time_in()   -- Get remaining time in seconds
  set_user_session_expire_time( $ts ) -- Set expiration timestamp
  set_user_session_expire_time_in( $s ) -- Set expiration in seconds

  get_page_session( $level )          -- Get current page session hashref
  get_page_session_id( $level )       -- Get current page session ID
  get_ref_page_session_id( $level )   -- Get caller page session ID
  get_top_page_session_id( $level )   -- Get top-level page session ID

  get_user_hold()                     -- Get persistent user data (requires login)

=head2 Argument/Link Construction Functions

  args( %data )           -- Create link with safe data (current page)
  args_new( %data )       -- Create link for new page with referer
  args_here( %data )      -- Create link staying on same page
  args_back( %data )      -- Create link returning to caller
  args_back_back( %data ) -- Create link returning to caller's caller

=head2 Forwarding Functions

  forward( %data )        -- Forward with safe data (full args)
  forward_new( %data )    -- Forward to new page
  forward_here( %data )   -- Forward staying on same page
  forward_back( %data )   -- Forward returning to caller
  forward_url( $url )     -- Forward to absolute URL (302 redirect)

=head2 HTML and Form Functions

  html_hold_set( %vars )  -- Set HTML template variables
  new_form( %opt )        -- Create new form object
  render_page( $name )    -- Load, preprocess and render page template
  render_action( $name )  -- Call action and render its result
  render_data( $data, $type ) -- Render data with mime type, see portray()
  render( $portray_hr )   -- Render portray data, i.e. render( portray( ... ) )

=head2 Login/Logout Functions

  is_logged_in()          -- Check if user is logged in
  login( $user_ident )    -- Mark user as logged in
  logout()                -- Log out current user
  need_login()            -- Require login, forward to login page

=head2 Encryption Functions

  cry()                   -- Symmetric crypto object (CRY_KEY), see CRYPTOGRAPHY API
  rsa()                   -- RSA public key object (RSA_PUB), see CRYPTOGRAPHY API
  argsx( %args )          -- Encrypted safe input token, carries data in the link

=head1 CRYPTOGRAPHY API

Links and forms do not need encryption: args() keeps their data on the server,
in LINK sessions, and the link carries only an opaque "sid.key" reference.
Encryption is available through two plugs, loaded on first use, for
application data and for the argsx() tokens inherited from Web::Reactor::Reflex.

=head2 Configuration

  my %cfg = (
            'CRY_KEY' => $key,  # exactly 32 raw bytes, for cry() and argsx()
            'RSA_PUB' => $pem,  # RSA public key PEM text, for rsa()
            );

The plug classes can be replaced with REO_CRY_CLASS and REO_RSA_CLASS.

=head2 Symmetric Encryption: cry()

  my $cry = $reo->cry(); # Data::Tools::Crypto::Symmetric, ChaCha20-Poly1305

  my $ctext  = $cry->encrypt( $ptext );          # binary
  my $ptext  = $cry->decrypt( $ctext );          # undef if modified or wrong key

  my $hex    = $cry->encrypt_hex( $ptext );      # also _base64() and _base64url()
  my $sealed = $cry->freeze_base64url( \%data ); # serialize and encrypt
  my $hr     = $cry->thaw_base64url( $sealed );  # undef if modified or wrong key

cry() booms if CRY_KEY is not configured. Encryption is authenticated:
cryptotext modified in any way does not decrypt at all. See
Data::Tools::Crypto::Symmetric and Data::Tools::Crypto for all methods.

=head2 Encrypted Safe Input: argsx()

  my $token = $reo->argsx( _AN => 'transfer', ACCOUNT => $account_id );
  $html .= "<a href='?_=$token'>Process Transfer</a>";

  # on the next request the token is decrypted into the safe input
  my $account_id = $reo->get_safe_input()->{ 'ACCOUNT' };

argsx() tokens start with "~" and carry the data itself, encrypted with
CRY_KEY, so they need no server-side storage. args() tokens keep the data in
a LINK session instead. Both arrive the same way in get_safe_input().

=head2 Public Key Encryption: rsa()

  my $rsa = $reo->rsa(); # Data::Tools::Crypto::RSA with the RSA_PUB key

  my $ctext = $rsa->encrypt_base64url( $secret ); # only the private key decrypts
  my $ok    = $rsa->verify_base64url( $message, $signature );

rsa() booms if RSA_PUB is not configured. The reactor holds only the public
key, decrypting with the private key belongs to the backend.

=head2 Security Considerations

  - Keep CRY_KEY secret, generate it with Crypt::PRNG::random_bytes( 32 )
  - Use different keys for different environments (dev, staging, production)
  - Do NOT hardcode keys in source code, use environment variables or config files

=head1 DEPLOYMENT, DIRECTORIES, FILESYSTEM STRUCTURE

=head2 Session Storage Directory

Create and protect the session directory:

  mkdir -p /var/reactor/sessions
  chmod 0700 /var/reactor/sessions
  chown www-data:www-data /var/reactor/sessions

Session files are stored in Storable binary format with .wrs extension.

=head2 Installation

Install via CPAN:

  cpanm Web::Reactor

Or from GitHub:

  git clone git://github.com/cade-vs/perl-web-reactor.git
  cd perl-web-reactor
  perl Makefile.PL
  make test
  make install

=head2 Custom Installation

For development or custom locations:

  perl Makefile.PL PREFIX=/opt/perl/reactor
  make test
  make install

Then use in code:

  use lib '/opt/perl/reactor/lib';
  use Web::Reactor;

=head1 EXTENDING

Web::Reactor is designed to allow extending or replacing the 4 main parts:

=head2 Session Storage

  Base module:    Web::Reactor::Sessions
  Current in use: Web::Reactor::Sessions::Filesystem

Extend by subclassing Web::Reactor::Sessions to use different storage backends
(database, remote servers, memory, etc.)

=head2 HTML Preprocessing

  Base module:    Web::Reactor::Preprocessor
  Current in use: Web::Reactor::Preprocessor::Native

Extend by subclassing Web::Reactor::Preprocessor to customize HTML processing,
template syntax, or add new markup handlers.

=head2 Actions Execution

  Base module:    Web::Reactor::Actions
  Current in use: Web::Reactor::Actions::Native

Extend by subclassing Web::Reactor::Actions to customize action loading,
execution, or error handling.

=head2 Main Module

  Base module:    Web::Reactor
  Current in use: Web::Reactor

The main module handles all logic and is not recommended for modification.
However, the reactor instance is passed to all actions and modules, so you
can add application-specific methods by extending in your application code.

Except main module (Web::Reactor) is expected that base modules are
subclassed for extension. Inside each of them there are notes on what must
be extended and usage hints.

Current implementations of the modules, shipped with Web::Reactor, can also
be extended and/or modified. However it is suggested checking base modules
first.

=head1 SECURITY BEST PRACTICES

When deploying Web::Reactor applications:

=head2 Configuration Security

1. Set CRY_KEY to exactly 32 random raw bytes, for example

   Crypt::PRNG::random_bytes( 32 ), or decode_base64() of: openssl rand -base64 32

2. Store sensitive config (keys, passwords) in environment variables,
   not in source code or version control

3. Ensure SESS_VAR_DIR has restrictive permissions:

   mkdir -p /var/reactor/sessions
   chmod 0700 /var/reactor/sessions
   chown www-data:www-data /var/reactor/sessions

4. Disable HTTPS only in development/testing:

   PRODUCTION: DISABLE_SECURE_COOKIES not set or = 0
   DEVELOPMENT: Set DISABLE_SECURE_COOKIES=1 if testing without HTTPS

=head2 Session Security

1. Set USER_SESSION_EXPIRE to reasonable timeout (default 600 = 10 min)

   Shorter for high-security apps (e.g., banking), longer for low-security

2. Session hijacking detection is automatic (IP + User-Agent checking)

   Sessions are invalidated if either changes

3. Session data is stored on filesystem in Storable format

   Ensure proper file permissions (0700) on session directory

=head2 Deployment

1. Use HTTPS in production (enforced by default)

2. Use Plack with a production server:

   NOT RECOMMENDED: plackup (single process, no reload protection)

   RECOMMENDED:
     - Starman (multi-worker, production-ready)
       plackup --server Starman --workers 4 app.psgi

     - Use reverse proxy (nginx/Apache) with:
       * X-Real-IP header passing
       * X-Forwarded-Proto HTTPS enforcement
       * gzip compression

3. Set Content-Security-Policy to restrict resource loading:

   'HTTP_CSP' => "default-src 'self'",

4. Enable form CSRF protection via page sessions (automatic)

   All forms must include session ID (_P parameter)

5. Log security events:

   Set DEBUG => 1+ to see:
   * Invalid input attempts
   * Session hijacking attempts
   * Expired sessions
   * Invalid page/action names

=head2 Input Validation

1. User input is never automatically trusted

2. Always use get_safe_input() for form data, not get_user_input()

3. Implement application-level validation in action modules:

   if ( $reo->param('amount') < 0 ) {
     $reo->log("error: negative amount not allowed");
     return $reo->render_page( 'error_invalid' );
   }

4. HTML escape all output in templates to prevent XSS

=head2 Password Security

1. Encrypt passwords with an RSA public key if needed (optional):

   'RSA_PUB' => $public_key_pem_text

   rsa() gives the key object, the framework does not encrypt password
   fields in the browser by itself

2. Never log passwords (application responsibility)

3. Use bcrypt/argon2 for password hashing (application responsibility)

=head2 Monitoring and Logging

1. Monitor application logs for:

   * Invalid input attempts
   * Session errors
   * Encryption/decryption failures
   * Unusual IP changes
   * High frequency of requests

2. Set DEBUG level appropriately:

   0 = no debug (production)
   1 = basic info
   2 = detailed info
   3 = very detailed
   4 = maximum debug (development only)

3. Implement rate limiting at application level (not provided by framework)

=head1 PROJECT STATUS

Web::Reactor is stable and it is used in many production sites including
banks, insurance, travel and other smaller companies.

API is frozen but it could be extended.

If you are interested in the project or have some notes etc, contact me at:

  Vladi Belperchinov-Shabanski "Cade"
  <cade@noxrun.com>

further contact info, mailing list and github repository is listed below.

=head1 TODO:

The following items are planned for future releases:

  * Migrate from Storable to JSON for session storage
  * Add more config validation at startup
  * Implement built-in rate limiting
  * Add more comprehensive error pages
  * Support HTTP/2 Server Push
  * Enhanced debugging with request/response profiling
  * More comprehensive test suite
  * Performance optimizations

See GitHub issues for details: https://github.com/cade-vs/perl-web-reactor/issues

=head1 REQUIRED ADDITIONAL MODULES

Web::Reactor requires the following Perl modules:

=head2 Core Modules (included with Perl)

  * Scalar::Util
  * Hash::Util
  * Data::Dumper (for debugging)
  * Encode
  * MIME::Base64
  * Digest::SHA

=head2 CPAN Modules (required)

  * Plack 1.0000+          -- PSGI web framework
  * Cookie::Baker 0.001+   -- Cookie handling
  * Data::Tools 1.24+      -- Data manipulation utilities
  * Exception::Sink 0.01+  -- Exception handling
  * Crypt::PRNG            -- session and link ids (CryptX)
  * Data::Tools::Crypto    -- cry() and rsa() plugs, ChaCha20-Poly1305 and RSA (CryptX)

=head2 GitHub Repositories

  * Exception::Sink
    https://github.com/cade-vs/perl-exception-sink

  * Data::Tools
    https://github.com/cade-vs/perl-data-tools

=head2 Perl Version

  Minimum: Perl 5.10.0
  Tested:  Perl 5.20, 5.24, 5.28, 5.32, 5.36

=head1 DEMO APPLICATION

Documentation will be improved. Meanwhile you can check 'demo' directory inside
distribution tarball or inside the github repository. This is fully functional
(however simple) application. It shows how data is processed, calling pages/views,
inspecting page (calling views) stack, html forms automation, forwarding.

Additionally you may check DECOR information systems infrastructure, which uses
Web::Reactor for its main web interface:

  https://github.com/cade-vs/perl-decor

=head1 MAILING LIST

  web-reactor@googlegroups.com

=head1 GITHUB REPOSITORY

  https://github.com/cade-vs/perl-web-reactor

  git clone git://github.com/cade-vs/perl-web-reactor.git

=head1 AUTHOR

  Vladi Belperchinov-Shabanski "Cade"

  <cade@bis.bg> <cade@cpan.org> <shabanski@gmail.com>

  http://cade.noxrun.com

  https://github.com/cade-vs

=cut


##############################################################################
1;
###EOF########################################################################
