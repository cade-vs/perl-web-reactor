##############################################################################
##
##  Web::Reactor application machinery
##  Copyright (c) 2013-2022 Vladi Belperchinov-Shabanski "Cade"
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

use Storable qw( dclone freeze thaw ); # FIXME: move to Data::Tools (data_freeze/data_thaw)
use Plack::Request;
use Cookie::Baker;
use MIME::Base64;
use Data::Tools 1.24;
use Exception::Sink;
use Data::Dumper;
use Encode;
use Crypt::PRNG;

use Web::Reactor::Utils;
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
                           HTTP_REFERRER
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

my @HNS = qw( Abby Ada Alexa Alfie Alia Alice Anna Aria Ava Axel Beau Bran Chanel Cali Calla Carys Cole Cruz Dash Dean Demi Dior Dora Drew Eira Eli
              Elise Ella Elle Ellie Elsa Emma Enzo Eva Eve Evie Faye Fia Fifi Fox Freya Gabe Gaia Gia Greer Gwen Gogo Gyro Hugo Ilia Ilse Iris Isla
              Indie Inez Ivan Jace James Joki Juko Juki Jack June Jimmy John Kaia Kali Kate Kaya Kent Kim Kitty Knox Lane Lani Leda Lexi Levi Liam
              Liv Lola Lucia Lucy Luna Lyra Macy Maya Mimi Mia Milo Mina Mira Nash Neo Neve Noel Nola Nora Onyx Orla Owen Pearl Prue Reid Rhea Rhys
              Rose Rimini Rome Rita Ruby Rumi Runa Ryla Siena Sofia Sage Shea Svea Tate Taya Thera Tori Tinko Tina Tupcho Tova Toto Trudi Trina Uma
              Uber Una Uno Viki Vera Voom Veda Vidin Vida Vita Wells Willa Wren Xena Xylo Yael Zezo Zaza Zane Zuki Zooo Zana Zara Zeev Zeno Zera Zoro );

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

  return $self->{ "REO_SES" } ||= $self->__attach_module( 'SES', 'Web::Reactor::Sessions::Filesystem' );
}

##############################################################################

sub run
{
  my $self = shift;

  srand();

  my $res;
  eval
    {
    $self->prepare_and_execute( @_ );
    };
  if( surface( 'RENDER' ) )
    {
    my $status  = $self->res_get_status() || 200;
    my $headers = $self->res_get_headers_ar();
    my $body    = $self->res_get_body();
    $body = [ $body ] unless ref $body;
    $res = [ $status, $headers, $body ];
    }
  elsif( surface( '*' ) )
    {
    $self->log( "error: prepare or execute code failed: $@" );
    $res = [ 200, [ 'content-type' => 'text/plain' ], [ 'system is currently unavailable (*)' ] ];
    }
  else
    {
    $self->log( "error: unknown or empty result or exception" );
    $res = [ 200, [ 'content-type' => 'text/plain' ], [ 'system is currently unavailable' ] ];
    }

  $self->save();

  $self->run_print_final_debug() if $self->is_debug();

  # $self->log_dumper( 'RUN RESULT, CODE, HEADERS, BODY_LENGTH:', $res->[0], $res->[1], length( $res->[2] ) );
  return $res;
}

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

sub prepare_and_execute
{
  my $self = shift;
  my $args = @_;
  my %args = @_;

  my $cfg = $self->cfg();

  # 0. load/setup env/config defaults
  my $app_name = $cfg->{ 'APP_NAME' } or boom( "missing APP_NAME" );

  # 1. loading cookie
  my $cookie_name = lc( $cfg->{ 'COOKIE_NAME' } || "$app_name\_cookie" );
  my $user_sid = $self->get_cookie( $cookie_name );
  $self->log_debug( "debug: incoming USER_SID cookie name [$cookie_name] value [$user_sid]" );

  # 2. loading user session, setup new session and cookie if needed
  my $user_shr = {}; # user session hash ref
  unless( $user_sid =~ /^[a-zA-Z0-9_]+$/ and $user_shr = $self->ses->load( 'USER', $user_sid ) )
    {
    $self->log( "warning: invalid user session [$user_sid]" );
    ( $user_sid, $user_shr ) = $self->__create_new_user_session();
    }
  $self->__set_session( 'USER', $user_sid, $user_shr );

  if( ( $user_shr->{ ':LOGGED_IN' } and $user_shr->{ ':XTIME' } > 0 and time() > $user_shr->{ ':XTIME' } )
      or
      ( $user_shr->{ ':CLOSED' } ) )
    {
    $self->log( "status: user session expired or closed, sid [$user_sid]" );
    # not logged-in sessions dont expire
    $user_shr->{ ':XTIME_STR'    } = scalar localtime() if time() > $user_shr->{ ':XTIME' };
    $user_shr->{ ':CLOSED'       } = 1;
    $user_shr->{ ':ETIME'        } = time();
    $user_shr->{ ':ETIME_STR'    } = scalar localtime();

    ( $user_sid, $user_shr ) = $self->__create_new_user_session();

    $self->render( PAGE => 'eexpired' );
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

    $self->render( PAGE => 'einvalid' );
    last;
    }

  # FIXME: move to single place
  my $user_session_expire = $cfg->{ 'USER_SESSION_EXPIRE' } || 600; # 10 minutes
  $self->set_user_session_expire_time_in( $user_session_expire );

  $self->save();

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

# ROTATION REMOVED #   # FIXME: move to function
# ROTATION REMOVED #   my $app_name = $cfg->{ 'APP_NAME' } or boom( "missing APP_NAME" );
# ROTATION REMOVED #   my $cookie_name = lc( $cfg->{ 'COOKIE_NAME' } || "$app_name\_cookie" );

  $user_sid = $self->ses->create( 'USER' );
  $user_shr = { ':ID' => $user_sid };

# ROTATION REMOVED #   my $path = $cfg->{ 'COOKIE_PATH' };
# ROTATION REMOVED #   if( ! $path )
# ROTATION REMOVED #     {
# ROTATION REMOVED #     $path = $self->get_request_uri();
# ROTATION REMOVED #     $path =~ s/^([^\?]*\/)([^\?\/]*)(\?.*)?$/$1/; # remove args: ?...
# ROTATION REMOVED #     }
# ROTATION REMOVED #   $path ||= '/';
# ROTATION REMOVED #
# ROTATION REMOVED #   my $secure_cookie = $cfg->{ 'DISABLE_SECURE_COOKIES' } ? 0 : 1;
# ROTATION REMOVED #   $self->res_set_cookie( $cookie_name, value => $user_sid, path => $path, httponly => 1, secure => $secure_cookie, samesite => 'lax' );
  $self->__set_user_session_cookie( $user_sid ); # FIXME: CHECK ROTATION
  $self->log( "debug: creating new user session [$user_sid]" );

  my $user_session_expire = $cfg->{ 'USER_SESSION_EXPIRE' } || 600; # 10 minutes

  $user_shr->{ ':CTIME'      } = time();
  $user_shr->{ ':CTIME_STR'  } = scalar localtime();

  $self->set_user_session_expire_time_in( $user_session_expire );

  # read and save http environment data into user session, used for checks and info
  $user_shr->{ ":HTTP_CHECK_HR" } = { map { $_ => $self->{ 'IN' }{ 'ENV' }{ $_ } } @HTTP_VARS_CHECK };
  $user_shr->{ ":HTTP_ENV_HR"   } = { map { $_ => $self->{ 'IN' }{ 'ENV' }{ $_ } } @HTTP_VARS_SAVE  };

  return ( $user_sid, $user_shr );
}

# FIXME: CHECK ROTATION
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
    $path = $self->get_request_uri();
    $path =~ s/^([^\?]*\/)([^\?\/]*)(\?.*)?$/$1/; # remove args: ?...
    }
  $path ||= '/';

  my $secure_cookie = $cfg->{ 'DISABLE_SECURE_COOKIES' } ? 0 : 1;
  $self->res_set_cookie( $cookie_name, value => $user_sid, path => $path, httponly => 1, secure => $secure_cookie, samesite => 'lax' );
}

# FIXME: CHECK ROTATION
# rotate the user session id, migrating current (anonymous) session data to a
# fresh id. used on privilege change (login) to prevent session fixation.
# note: PAGE/LINK sessions are namespaced under the user id, so the pre-login
# page back-stack is intentionally not carried across the rotation.
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
  $self->__update_session_fingerprint( 'USER', $new_sid, $user_shr );

  # reissue the cookie bound to the new id
  $self->__set_user_session_cookie( $new_sid );

  # invalidate the old session in storage so a fixed pre-login cookie is useless
  $self->ses->save( 'USER', $old_sid, { ':ID' => $old_sid, ':CLOSED' => 1, ':ETIME' => time(), ':ETIME_STR' => scalar localtime() } );

  $self->log( "status: rotated user session id on login [$old_sid] -> [$new_sid]" );

  return $new_sid;
}

sub get_postdata_fh
{
  my $self = shift;

  return $self->{ 'PLACK' }->body();
}

sub get_postdata_body
{
  my $self = shift;

  my $fh = $self->get_postdata_fh();

  local $/ = undef;
  return <$fh>;
}

sub cfg
{
  my $self = shift;

  return $self->{ 'CFG' };
}

##############################################################################
#
# usual user visible api
#

# user hold is data, which is preserved between login sessions, can carry anything
# user hold is available only after login and only if login has username or other user identification

sub get_user_hold
{
  my $self = shift;

  my $uid = $self->get_user_session()->{ ':USER_IDENT' };

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
    $page_sid = $page_shr->{ ':REF_PAGE_SID' };
    return undef unless $page_sid;
    $page_shr = $self->{ 'SESSIONS' }{ 'DATA' }{ 'PAGE' }{ $page_sid };
    if( ! $page_shr )
      {
      $page_shr = $self->ses->load( 'PAGE', $page_sid );
      $self->{ 'SESSIONS' }{ 'DATA' }{ 'PAGE' }{ $page_sid } = $page_shr;
      $self->__update_session_fingerprint( 'PAGE', $page_sid, $page_shr );
      }
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
  my $type = shift;
  my $len  = shift || 8;

  # FRM is FORM RETURN MAP
  boom( "cannot create LINK key: type must be ARGS" ) unless $type eq 'ARGS';

  my $link_shr = $self->get_link_session();

  my $link_key;
  while(4)
    {
    $link_key = $self->ses->create_id( $len );
    last if ! exists $link_shr->{ $type }{ $link_key };
    }
  boom( "cannot create LINK key" ) unless $link_key;

  return wantarray ? ( $link_key, $link_shr->{ $type }{ $link_key } ) : $link_key;
}

sub get_http_env
{
  my $self  = shift;

  return $self->{ 'IN'  }{ 'ENV' };
}

sub get_client_ip
{
  my $self  = shift;

  my $env = $self->get_http_env();

  my $client_ip;

  $client_ip ||= $env->{ $_ } for qw( HTTP_CF_CONNECTING_IP HTTP_X_REAL_IP REMOTE_ADDR );

  return $client_ip;
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

sub get_safe_input
{
  my $self  = shift;

  my $input_safe_hr = $self->{ 'INPUT_SAFE_HR' };
  return $input_safe_hr;
}

sub get_user_input
{
  my $self  = shift;

  my $input_user_hr  = $self->{ 'INPUT_USER_HR'  };
  return $input_user_hr;
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

sub get_lang
{
  my $self  = shift;

  return $self->cfg->{ 'LANG' };
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

sub args
{
  my $self = shift;
  my %args = @_;

  hash_uc_ipl( \%args );

  my ( $link_shr, $link_sid ) = $self->get_link_session();
  my $link_key = $self->new_link_session_key( 'ARGS' );

  $link_shr->{ 'ARGS' }{ $link_key } = \%args;

  return $link_sid . '.' . $link_key;
}

sub args_back
{
  my $self = shift;
  my %args = @_;

  $args{ '_P'  } = $self->get_ref_page_session_id();
#  $args{ '_PN' } = 'main' unless $args{ '_P' }; # return to 'main' if no referer given

  return $self->args( %args );
}

sub args_back_back
{
  my $self = shift;
  my %args = @_;

  $args{ '_P' } = $self->get_ref_page_session_id( 1 );
#  $args{ '_PN' } = 'main' unless $args{ '_P' }; # return to 'main' if no referer given

  return $self->args( %args );
}

sub args_new
{
  my $self = shift;
  my %args = @_;

  $args{ '_R' } = $self->get_page_session_id();

  my $page_shr = $self->get_page_session();
  $args{ '_PN' } ||= $page_shr->{ ':PAGE_NAME' };

  return $self->args( %args );
}

# new page session inside a vsFrame
sub args_new_fr
{
  my $self = shift;
  my %args = @_;

  $args{ '_T' } = $self->get_page_session_id(); # top session (browser window one)

  return $self->args( %args );
}

sub args_here
{
  my $self = shift;
  my %args = @_;

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

sub get_request_scheme
{
  my $self   = shift;

  return $self->{ 'IN' }{ 'ENV' }{ 'REQUEST_SCHEME' };
}

sub get_request_uri
{
  my $self   = shift;

  return $self->{ 'IN' }{ 'ENV' }{ 'REQUEST_URI' };
}

sub get_request_method
{
  my $self   = shift;

  return $self->{ 'IN' }{ 'ENV' }{ 'REQUEST_METHOD' };
}

sub get_headers
{
  my $self  = shift;

  return $self->{ 'IN' }{ 'HEADERS' } ||= { map { lc( $_ ) => $self->{ 'IN' }{ 'ENV' }{ $_ } } grep /^(HTTPS?_|SSL_)/, keys %{ $self->{ 'IN' }{ 'ENV' } } };
}

sub get_header
{
  my $self = shift;
  my $name = shift;

  return $self->get_headers->{ $name };
}

sub get_cookies
{
  my $self = shift;
  return $self->{ 'IN' }{ 'COOKIES' } ||= crush_cookie( $self->get_header( 'http_cookie' ) );;
}

sub get_cookie
{
  my $self = shift;
  my $name = shift;

  my $cookie = $self->get_cookies->{ $name };
  $self->log_debug( "get_cookie: name [$name] value [$cookie]" );
  return $cookie;
}

### RESULT/OUTPUT API ########################################################

sub res_set_status
{
  my $self   = shift;
  my $status = shift;

  return $self->{ 'OUT' }{ 'STATUS' } = $status;
}

sub res_get_status
{
  my $self   = shift;

  return $self->{ 'OUT' }{ 'STATUS' };
}

#-----------------------------------------------------------------------------

sub res_set_headers
{
  my $self = shift;
  my %h    = @_;

  hash_lc_ipl( \%h );

  if( exists $h{ 'status' } )
    {
    $self->res_set_status( $h{ 'status' } );
    delete $h{ 'status' };
    }

  return $self->{ 'OUT' }{ 'HEADERS' } = { %{ $self->{ 'OUT' }{ 'HEADERS' } || {} }, %h };
}

sub res_get_headers_ar
{
  my $self = shift;

  my $headers;

  $self->{ 'OUT' }{ 'HEADERS' }{ 'content-type' } ||= 'text/html';

  # postprocess headers, custom logic, etc.
  my %headers_out = %{ $self->{ 'OUT' }{ 'HEADERS' } };

  if( exists $headers_out{ 'content-charset' } )
    {
    if( $headers_out{ 'content-type' } !~ /;\s*charset=/i )
      {
      $headers_out{ 'content-type' } .= '; charset=' . $headers_out{ 'content-charset' };
      }
    delete $headers_out{ 'content-charset' };
    };

  if( exists $headers_out{ 'location' } )
    {
    delete $headers_out{ 'content-type' };
    }

  my @headers;
  while( my ( $k, $v ) = each %headers_out )
    {
    push @headers, $k, $v;
    }

  while( my ( $k, $v ) = each %{ $self->{ 'OUT' }{ 'COOKIES' } } )
    {
    push @headers, 'set-cookie', $v;
    }

  $self->log_dumper( 'RESULT HEADERS---------------------------------', \@headers );

  return \@headers;
}

#-----------------------------------------------------------------------------

sub res_set_cookie
{
  my $self = shift;
  my $name = shift;
  my %opt  = @_;

  $self->log( "debug: creating new cookie [$name]" );
  # FIXME: validate %opt  Data::Validate::Struct

  $self->{ 'OUT' }{ 'COOKIES' }{ $name } = bake_cookie( $name, \%opt );
}

#-----------------------------------------------------------------------------

sub res_set_body
{
  my $self = shift;
  my $body = shift;

  return $self->{ 'OUT' }{ 'BODY' } = $body;
}

sub res_get_body
{
  my $self = shift;
  my $body = shift;

  return $self->{ 'OUT' }{ 'BODY' };
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

  $self->__update_session_fingerprint( $type, $sid, $hr );
}

sub __update_session_fingerprint
{
  my $self = shift;

  my $type = shift;
  my $sid  = shift;
  my $hr   = shift;

  $self->{ 'CACHE' }{ 'SESSION_DATA_SHA1' }{ $type }{ $sid } = sha1_hex( freeze( $hr ) );
}

sub save
{
  my $self = shift;

  my $mod_cache = $self->{ 'CACHE' }{ 'SESSION_DATA_SHA1' } ||= {};
  for my $type ( qw( USER PAGE LINK HOLD ) )
    {
    next unless exists $self->{ 'SESSIONS' }{ 'DATA' }{ $type };
    while( my ( $sid, $shr ) = each %{ $self->{ 'SESSIONS' }{ 'DATA' }{ $type } } )
      {
      boom( "SESSION:DATA:$type:$sid is not hashref" ) unless ref( $shr ) eq 'HASH';

      my $sha1   = sha1_hex( freeze( $shr ) );
      my $cache1 = $mod_cache->{ $type }{ $sid };

      next if $sha1 eq $cache1;

      $self->log_debug( "saving session data [$type:$sid] --> $sha1 <> $cache1" );

      $mod_cache->{ $type }{ $sid } = $sha1;

      $self->ses->save( $type, $sid, $shr );
      }
    }
}

##############################################################################
##
##  CRYPTO api :)
##

sub __rsa_object
{
  my $self = shift;

  return $self->{ 'RSAO' } if exists $self->{ 'RSAO' };

  eval { require Data::Tool::Crypto::RSA; };
  boom( "error: require Data::Tool::Crypto::RSA [$@]" ) if $@;

  my $pub_key = $self->cfg()->{ 'RSA_PUB_KEY' }; # file name or, if reference, the actual pem data
  my $pub = Data::Tool::Crypto::RSA->new( $pub_key );
  $self->{ 'RSAO' } = $pub;

  return $pub;
}

sub rsa_pub_encrypt
{
  my $self = shift;

  return $self->__rsa_object()->encrypt_base64url( $_[0] );
}

## FIXME: move most to Data::Tools or separate module


##############################################################################

sub set_debug
{
  my $self  = shift;
  my $level = abs(int(shift));

  return $self->cfg->{ 'DEBUG' } = $level;
}

sub is_debug
{
  my $self = shift;

  return $self->cfg->{ 'DEBUG' } || 0;
}

#-----------------------------------------------------------------------------

sub log
{
  my $self = shift;

  print STDERR @_, "\n";
}

sub log_debug
{
  my $self = shift;

  return unless $self->is_debug();
  my @args = @_;
  chomp( @args );
  my $msg = join( "\n", @args );
  $msg = "debug: $msg" unless $msg =~ /^debug:/i;
  $self->log( $msg );
}

sub log_debug2
{
  my $self = shift;

  return unless $self->is_debug() > 1;
  $self->log_debug( @_ );
}

sub log_stack
{
  my $self = shift;

  $self->log_debug( @_, "\n", Exception::Sink::get_stack_trace() );
}

sub log_dumper
{
  my $self = shift;

  return unless $self->is_debug();

  local $Data::Dumper::Sortkeys = 1;

  $self->log_debug( Dumper( @_ ) );
}

##############################################################################
##
## sanity policies
## these are internal subs but are designed to be overriden if required
##

# fix/remove invalid parts of a CGI/input value
sub __input_cgi_make_safe_value
{
  my $self = shift;
  my $n = shift; # arg name
  my $v = shift; # arg value

  $v =~ s/[\000]//go;

  return $v;
}

# must return 1 for values which must be removed from input or 0 for ok
# this is called before __input_cgi_make_safe_value, default is pass all
sub __input_cgi_skip_invalid_value
{
  my $self = shift;
  # this is placeholder really
  # my $n = shift; # arg name
  # my $v = shift; # arg value
  # if( ... )
  #   {
  #   $self->log( "error: invalid CGI/input value for parameter: [$n]" );
  #   return 1; # skip it!
  #   }
  return 0;
}

##############################################################################

sub html_content
{
  my $self = shift;
  my %hc   = @_;

  hash_lc_ipl( \%hc );
  $self->{ 'HTML_CONTENT' } ||= {};
  %{ $self->{ 'HTML_CONTENT' } } = ( %{ $self->{ 'HTML_CONTENT' } }, %hc );

  return $self->{ 'HTML_CONTENT' };
}

sub html_content_clear
{
  my $self = shift;

  $self->{ 'HTML_CONTENT' } ||= {};
}

sub html_content_set
{
  my $self = shift;

  $self->html_content_clear();
  return $self->html_content( @_ );
}

sub html_content_accumulator
{
  my $self = shift;
  my $name = shift;
  my $text = shift;

  $self->{ 'HTML_CONTENT' } ||= {};
  $self->{ 'HTML_CONTENT' }{ $name }{ $text }++;

  $self->html_content_set( $name, join '', keys %{ $self->{ 'HTML_CONTENT' }{ $name } } );
}

sub html_content_accumulator_js
{
  my $self = shift;
  my $text = shift;

  $text = "<script type='text/javascript' src='$text'></script>";
  $self->html_content_accumulator( "ACCUMULATOR_JS", $text );
}

sub html_content_accumulator_css
{
  my $self = shift;
  my $css = shift;

  my $text = qq{ <link href="$css" rel="stylesheet" type="text/css"> };
  $self->html_content_accumulator( "ACCUMULATOR_HEAD", $text );
}

##############################################################################

sub render_data
{
  my $self = shift;

  return $self->render( DATA   => $self->portray( @_ ) );
}

sub render_action
{
  my $self   = shift;
  my $action = shift;

  return $self->render( ACTION => $action, @_ );
}

sub render_page
{
  my $self = shift;
  my $page = shift;

  return $self->render( PAGE   => $page, @_ );
}

sub render
{
  my $self = shift;
  my %opt  = @_;

  boom "too many nesting levels in rendering, probable bug in actions or pages" if (caller(128))[0] ne ''; # FIXME: config option for max level

  my $action = $opt{ 'ACTION' };
  my $page   = $opt{ 'PAGE'   };
  my $data   = $opt{ 'DATA'   };

  # FIXME: content vars handling set_content()/etc.
  my $ah = $self->args_here();
  $self->html_content( 'FORM_INPUT_SESSION_KEEPER' => "<input type=hidden name=_ value=$ah>" );
  $self->html_content( %opt );

  my $portray_data;

  if( ref( $data ) eq 'HASH'  )
    {
    $portray_data = $data;
    $page = $action = undef;
    }
  elsif( $action )
    {
    # FIXME: handle content type also!
    $portray_data = $self->act->call( $action );
    $page = undef;
    }
  elsif( $page )
    {
    $portray_data = $self->pre->load_page( $page );

    $action = undef;
    }
  else
    {
    boom "render() needs PAGE or ACTION";
    }

  if( ref( $portray_data ) eq 'HASH' )
    {
    # as expected but no handling required
    }
  elsif( ref( $portray_data ) )
    {
    boom "expected portray data (i.e. HASHREF) but got different reference";
    }
  else
    {
    # default portray type is html
    $portray_data = $self->portray( $portray_data, 'text/html' );
    }

  my $page_data = $portray_data->{ 'DATA'      };
  my $page_fh   = $portray_data->{ 'FH'        }; # filehandle has priority
  my $page_type = $portray_data->{ 'TYPE'      };
  my $file_name = $portray_data->{ 'FILE_NAME' };
  my $disp_type = $portray_data->{ 'DISPOSITION_TYPE' } || 'inline'; # default, rest must be handled as 'attachment', ref: rfc6266#section-4.2

  # preparing headers --------------------------------------------------------
  # FIXME: charset
  $self->res_set_headers( 'content-type'        => $page_type );
  if( $file_name )
    {
    # sanitize + RFC 6266 encode: strip CR/LF/controls (header injection),
    # escape/quote the ASCII form, add RFC 5987 filename* for non-ASCII names
    ( my $fn_ascii = $file_name ) =~ s/[\x00-\x1f\x7f]//g;   # strip control chars incl CR/LF/NUL
    $fn_ascii =~ s/(["\\])/\\$1/g;                           # escape quote and backslash
    $fn_ascii =~ s/[^\x20-\x7e]/_/g;                         # replace remaining non-ASCII
    my $cd = qq{$disp_type; filename="$fn_ascii"};
    if( $file_name =~ /[^\x20-\x7e]/ )
      {
      ( my $fn_utf8 = encode( 'UTF-8', $file_name ) ) =~ s/([^A-Za-z0-9_.~-])/sprintf '%%%02X', ord $1/ge;
      $cd .= "; filename*=UTF-8''$fn_utf8";
      }
    $self->res_set_headers( 'content-disposition' => $cd );
    }

  # handling Content Security Policy (CSP) -- https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP
  my $http_csp = $self->cfg->{ 'HTTP_CSP' }; # || " default-src 'self' ";
  $self->res_set_headers( 'Content-Security-Policy' => $http_csp ) if $http_csp;

  my $app_charset = uc $self->cfg->{ 'APP_CHARSET' } || 'UTF-8';

  my $page_type_is_text = $page_type =~ /^text\//i;
  if( $page_type_is_text )
    {
    # set charset for TEXT only
    $self->res_set_headers( 'content-charset' => $app_charset );
    }

  # preparing body -----------------------------------------------------------

  if( $page_fh )
    {
    $self->res_set_body( $page_fh );
    }
  elsif( lc $page_type =~ /^text\/html/ )
    {
    my $prep_opt1 = {};
    $page_data = $self->pre->process( $page, $page_data, $prep_opt1 );

    my $prep_opt2 = {};
    $page_data = $self->pre->process( $page, $page_data, $prep_opt2 ) if $prep_opt1->{ 'SECOND_PASS_REQUIRED' };

    # FIXME: translation
    $self->load_trans();
    my $tr = $self->{ 'TRANS' }{ $self->cfg->{ 'LANG' } } || {};
    $page_data =~ s/\<~([^\<\>]*)\>/$tr->{ $1 } || $1/ge;
    $page_data =~ s/\[~([^\[\]]*)\]/$tr->{ $1 } || $1/ge;

    $self->res_set_body( encode( $app_charset, $page_data ) );
    }
  else
    {
    $self->res_set_body( $page_data );
    }

  sink 'RENDER';
}

my %SIMPLE_PORTRAY_TYPE_MAP = (
                              html => 'text/html',
                              text => 'text/plain',
                              txt  => 'text/plain',
                              jpeg => 'image/jpeg',
                              png  => 'image/png',
                              bin  => 'application/octet-stream',
                              );

sub portray
{
  my $self = shift;
  my $data = shift;
  my $type = lc shift; # mime type text/html
  my %opt  = @_; # file name, charset, etc.

  $type = $SIMPLE_PORTRAY_TYPE_MAP{ $type } || $type;

  boom "portray needs mime type xxx/xxx as arg 2, got [$type]" unless $type =~ /^[a-z\-_0-9]+\/[a-z\-_0-9\.]+$/;

  return { DATA => $data, TYPE => $type, @_ };
}

##############################################################################

sub forward_url
{
  my $self = shift;
  my $url  = shift;

  # FIXME: use render+portray
  $self->res_set_headers( status => 302, location => $url );
  $self->res_set_body();

  sink 'RENDER';
}

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

  # FIXME: CHECK ROTATION
  # rotate session id on privilege elevation to defeat session fixation;
  # anonymous user-session data is preserved (re-keyed under the new id)
  $self->__rotate_user_session_id();

  my $user_ident_s = $user_ident;

  $user_ident_s =~ s/[^a-z0-9_\-:]/_/gi; # human readable
  $user_ident   = str_hex( $user_ident );

  my $user_shr = $self->get_user_session();
  $user_shr->{ ':LOGGED_IN'    } = 1;
  $user_shr->{ ':LTIME'        } = time();
  $user_shr->{ ':LTIME_STR'    } = scalar localtime();
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
  $user_shr->{ ':ETIME'        } = time();
  $user_shr->{ ':ETIME_STR'    } = scalar localtime();
  # FIXME: add more logout info
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

#use Exception::Sink;
#my $xin = $xtime - time();
#my $xtt = localtime( $xtime );
#print STDERR "*********************************** set_user_session_expire_time($xtime)[$xtt]\n" . Exception::Sink::get_stack_trace();
#print STDERR "*********************************** set_user_session_expire_time($xtime)[$xtt] in [$xin] seconds\n";

  my $user_shr = $self->get_user_session();
  $user_shr->{ ':XTIME'     } = $xtime; # FIXME: sanity?
  $user_shr->{ ':XTIME_STR' } = scalar localtime $user_shr->{ ':XTIME' };
  return exists $user_shr->{ ':XTIME' } ? $user_shr->{ ':XTIME' } : undef;
}

sub set_user_session_expire_time_in
{
  my $self    = shift;
  my $seconds = shift;

#use Exception::Sink;
#print STDERR "************************************** set_user_session_expire_time_in($seconds)\n" . Exception::Sink::get_stack_trace();
#print STDERR "************************************** set_user_session_expire_time_in($seconds) seconds\n";

  # FIXME: support for more user friendly time periods 10m 60s
  return $self->set_user_session_expire_time( time() + $seconds );
}

# returns unix time at which user session will expire, undef if no expire time specified
sub get_user_session_expire_time
{
  my $self = shift;

  my $user_shr = $self->get_user_session();

#use Exception::Sink;
#my $xtt = localtime( $user_shr->{ ':XTIME' } );
#print STDERR "get_user_session_expire_time($user_shr->{ ':XTIME' })[$xtt]\n" . Exception::Sink::get_stack_trace();

  return exists $user_shr->{ ':XTIME' } ? $user_shr->{ ':XTIME' } : undef;
}

# returns time period in seconds, in which user session will expire, undef if no expire time specified
sub get_user_session_expire_time_in
{
  my $self = shift;

  my $xi = $self->get_user_session_expire_time() - time();
  return $xi > 0 ? $xi : undef;
}

sub require_post_method
{
  my $self = shift;

  return if $self->get_request_method() eq 'POST';

  $self->logout();
  $self->render( PAGE => 'epostrequired' );
}

sub get_user_session_agent
{
  my $self = shift;

  my $user_session = $self->get_user_session();
  my $user_agent   = $user_session->{ ':HTTP_ENV_HR' }{ 'HTTP_USER_AGENT' };

  return $user_agent || 'n/a';
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
##
## REO proxies
##

sub ses { my $self = shift; return $self->{ 'REO_SES' } };
sub pre { my $self = shift; return $self->{ 'REO_PRE' } };
sub act { my $self = shift; return $self->{ 'REO_ACT' } };

sub new_form
{
  my $self = shift;

  my $form = new Web::Reactor::HTML::Form( @_, REO_REACTOR => $self );

  return $form;
}

##############################################################################

sub set_browser_window_title
{
  my $self  = shift;
  my $title = shift;

  $title =~ s/<[^>]*>//g; # remove HTML if any
  $self->html_content( 'BROWSER_WINDOW_TITLE', $title );
}

##############################################################################

sub create_uniq_id
{
  my $self = shift;
  my $case = shift;

  my $cfg = $self->cfg();
  my $let = $cfg->{ 'SESS_LETTERS' } || 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  my $nid;
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

Web::Reactor can encrypt sensitive data using AES-CBC encryption.
See CRYPTOGRAPHY section below.

=head2 Password Encryption (Optional)

Password fields can be encrypted with RSA before sending to server.
Configure with RSA_PUB_KEY file path or PEM data.

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
  ENCRYPT_CIPHER            -- Encryption cipher (default: 'AES')
  ENCRYPT_KEY               -- Encryption key (required if using encryption)
  RSA_PUB_KEY               -- RSA public key for password encryption (optional)
  HTTP_CSP                  -- Content-Security-Policy header (optional)
  NO_PASS_ENCRYPT           -- Disable password encryption (default: 0)

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

  html_content( %vars )   -- Set HTML template variables
  new_form( %opt )        -- Create new form object
  render( PAGE => $name ) -- Render page template
  render( ACTION => $name ) -- Call and render action
  render_page( $name )    -- Render page (shortcut)
  render_action( $name )  -- Render action (shortcut)

=head2 Login/Logout Functions

  is_logged_in()          -- Check if user is logged in
  login( $user_ident )    -- Mark user as logged in
  logout()                -- Log out current user
  need_login()            -- Require login, forward to login page

=head2 Encryption Functions

  encrypt( $data )        -- Encrypt data (binary output)
  decrypt( $encrypted )   -- Decrypt binary data
  encrypt_hex( $data )    -- Encrypt with hex encoding
  decrypt_hex( $hex )     -- Decrypt hex-encoded data
  encrypt_base64u( $data ) -- Encrypt with base64url encoding
  decrypt_base64u( $b64 ) -- Decrypt base64url-encoded data
  crypto_freeze_base64u( $ref ) -- Serialize and encrypt with base64url
  crypto_thaw_base64u( $b64 )   -- Decrypt and deserialize from base64url

=head1 CRYPTOGRAPHY API

Web::Reactor provides AES-CBC encryption for sensitive data. This is used
internally to hide form data and page session IDs in URLs.

=head2 Configuration

To enable encryption, set two config parameters:

  my %cfg = (
            'ENCRYPT_CIPHER' => 'AES',  # cipher (default)
            'ENCRYPT_KEY'    => 'your-secret-key-here',  # required
            );

The key must be between min and max key size for the chosen cipher:

  - AES: 16, 24, or 32 bytes (128, 192, or 256 bits)

=head2 Encryption Methods

=head3 Binary Encryption/Decryption

  my $encrypted = $reo->encrypt( $data );
  my $decrypted = $reo->decrypt( $encrypted );

The encrypted data includes a random IV (initialization vector) prepended
to the ciphertext.

=head3 Hexadecimal Encoding

  my $hex_encrypted = $reo->encrypt_hex( $data );
  my $decrypted     = $reo->decrypt_hex( $hex_encrypted );

Useful for URLs and database storage.

=head3 Base64URL Encoding

  my $b64u_encrypted = $reo->encrypt_base64u( $data );
  my $decrypted      = $reo->decrypt_base64u( $b64u_encrypted );

URL-safe base64 encoding, no padding.

=head3 Serialization with Encryption

  my $b64u_data = $reo->crypto_freeze_base64u( { key => 'value' } );
  my $hashref   = $reo->crypto_thaw_base64u( $b64u_data );

Automatically serializes/deserializes data structures with encryption.

=head3 Hexadecimal Serialization

  my $hex_data = $reo->crypto_freeze_hex( { key => 'value' } );
  my $hashref  = $reo->crypto_thaw_hex( $hex_data );

Same as above but with hexadecimal encoding.

=head2 Implementation Details

  Algorithm:  AES (Advanced Encryption Standard)
  Mode:       CBC (Cipher Block Chaining)
  IV:         Random, generated per encryption, prepended to ciphertext
  Padding:    PKCS#7 (handled by Crypt::Mode::CBC)
  Key:        User-provided, validated against cipher key size requirements

=head2 Example: Hiding Form Data

  my $form_data = {
                  'account_id' => $account_id,
                  'action'     => 'transfer',
                  'amount'     => $amount,
                  };
  my $encrypted_link = $reo->args(
                                  '_SAFE_DATA' =>
                                    $reo->crypto_freeze_base64u( $form_data ),
                                  );
  $html .= "<a href='?_=$encrypted_link'>Process Transfer</a>";

  # On next request:
  my $safe_input = $reo->get_safe_input();
  my $form_data = $reo->crypto_thaw_base64u( $safe_input->{ '_SAFE_DATA' } );

=head2 Security Considerations

  - Keep ENCRYPT_KEY secret and secure
  - Rotate encryption keys periodically
  - Use different keys for different environments (dev, staging, production)
  - Key should be at least 32 bytes (256 bits) for AES
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

1. Set ENCRYPT_KEY to a strong, random value (at least 32 bytes)

   Use: openssl rand -base64 32

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
     return $reo->render( PAGE => 'error_invalid' );
   }

4. HTML escape all output in templates to prevent XSS

=head2 Password Security

1. Use RSA encryption for password fields (optional):

   'RSA_PUB_KEY' => '/path/to/public.key'

   Passwords are encrypted in browser before sending to server

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
  * Crypt::Cipher          -- Base class for encryption ciphers
  * Crypt::Mode::CBC       -- AES encryption in CBC mode
  * Crypt::PK::RSA         -- RSA encryption (for password fields)

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
