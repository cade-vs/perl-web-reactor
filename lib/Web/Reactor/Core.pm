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
## this is part of Web::Reactor package and serves as base class for:
##
##      Web::Reactor::Reflex  -- stateless machinery
##      Web::Reactor          -- full state integrated actor
##
##############################################################################
package Web::Reactor::Core;
use strict;
use Storable qw( dclone );
use Plack::Request;
use Cookie::Baker;
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

  die "expected first  argument to be ENV hash reference" unless ref $env eq 'HASH';
  die "expected second argument to be CFG hash reference" unless ref $cfg eq 'HASH';

  srand();

  $class = ref( $class ) || $class;
  my $self = {};
  bless $self, $class;

  $self->{ 'CFG' }                    = dclone( $cfg );
  $self->{ 'CFG' }{ 'CHARSET' }       = 'UTF-8'; # force UTF-8 always
  $self->{ 'IN'  }{ 'ENV'         }   = $env; # including headers
  $self->{ 'IN'  }{ 'ENV'         }{ ':CLIENT_IP' } = $self->get_client_ip(); # this is always end-point client browser IP, reglardless of claudflare proxy etc.

  $self->set_debug( $cfg->{ 'DEBUG' } );

  $self->log_debug( "\n\n\n\n\n" . ( '*' x 64 ) ) if $self->is_debug();
  $self->log_dumper( "debug: *** BEGIN *** obj [$self] *** setup (ENV & CFG): ", $env, $cfg ) if $self->is_debug() > 3;

  $self->{ 'PLACK' } = Plack::Request->new( $env );

  return $self;
}

sub DESTROY
{
  my $self = shift;

  $self->log_debug( "info: *** END *** obj [$self] ***" ) if $self->is_debug();
  $self->log_debug( "\n\n\n\n\n" . ( '*' x 64 ) ) if $self->is_debug();
}

##############################################################################

sub run
{
  my $self = shift;

  my $res;
  eval
    {
    $self->process_request( @_ );
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
    $res = [ 200, [ 'content-type' => 'text/plain' ], [ 'system is currently unavailable (!)' ] ];
    }

  return $res;
}

sub process_request
{
  my $self = shift;
  my $args = @_ / 2; # count of arg pairs
  my %args = @_;

  die "you need to subclass Web::Reactor::Core and reimplement Web::Reactor::Core::process_request";
}

### SET/GET INSTANCE STATE ###################################################

sub set_debug
{
  my $self  = shift;
  my $level = abs(int(shift));

  return $self->{ 'DEBUG' } = $level;
}

sub is_debug
{
  my $self = shift;

  return ( $self->{ 'DEBUG' } || 0 );
}

sub inc_debug
{
  my $self = shift;
  my $step = abs(int(shift)) || 1;

  return $self->{ 'DEBUG' } += $step;
}

### GET HELPERS ##############################################################

sub get_cfg
{
  my $self = shift;

  return $self->{ 'CFG' };
}

sub plack
{
  my $self = shift;

  return ( $self->{ 'PLACK' } || die "missing PLACK object" );
}

sub get_http_env
{
  my $self  = shift;

  return $self->{ 'IN'  }{ 'ENV' };
}

### REQUEST/INPUT STATE ######################################################

sub get_client_ip
{
  my $self  = shift;

  my $env = $self->get_http_env();

  my $client_ip;

  $client_ip ||= $env->{ $_ } for qw( HTTP_CF_CONNECTING_IP HTTP_X_REAL_IP REMOTE_ADDR );

  return $client_ip;
}

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

sub get_request_path_info
{
  my $self   = shift;

  return $self->{ 'IN' }{ 'ENV' }{ 'PATH_INFO' };
}

sub get_headers
{
  my $self  = shift;

  # PSGI/CGI mangles header names: dashes to underscores, uppercased, HTTP_ prefixed,
  # except CONTENT_TYPE/CONTENT_LENGTH which lose the prefix entirely. undo all of it
  # here, so headers are looked up by their real names: content-type, x-custom, etc.
  # which is dumb by design
  my $env = $self->{ 'IN' }{ 'ENV' };

  return $self->{ 'IN' }{ 'HEADERS' } ||= {
        map  { my $k = lc; $k =~ s/^http_//o; $k =~ tr/_/-/; ( $k => $env->{ $_ } ) }
        grep { /^HTTP_/o or $_ eq 'CONTENT_TYPE' or $_ eq 'CONTENT_LENGTH' }
        keys %$env
        };
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
  return $self->{ 'IN' }{ 'COOKIES' } ||= crush_cookie( $self->get_header( 'cookie' ) );
}

sub get_cookie
{
  my $self = shift;
  my $name = shift;

  my $cookie = $self->get_cookies->{ $name };
  $self->log_debug( "get_cookie: name [$name] value [$cookie]" );
  return $cookie;
}

### REQUEST/INPUT DATA & UPLOADS #############################################

sub get_safe_input
{
  my $self  = shift;

  return $self->{ 'SAFE_INPUT_HR' } ||= $self->__import_safe_input();
}

sub get_client_input
{
  my $self  = shift;

  return $self->{ 'CLIENT_INPUT_HR'  } ||= $self->__import_client_input();
}

sub get_client_uploads
{
  my $self  = shift;

  return $self->{ 'CLIENT_UPLOADS_HR'  } ||= $self->__import_client_uploads();
}

sub get_client_postdata_fh
{
  my $self = shift;

  return $self->plack()->body();
}

sub get_client_postdata_body
{
  my $self = shift;

  my $fh = $self->get_client_postdata_fh();

  local $/ = undef;
  return <$fh>;
}

### RESULT/OUTPUT API ########################################################


# it is http status, i.e. 200, 404, etc.
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

##
## TODO: response headers API extensions:
##
##       res_get_headers()        -- return OUT/HEADERS as hashref, read access
##                                   (res_get_headers_ar() flattens for PSGI only)
##       res_del_header( $name )  -- remove a single header already set
##       res_add_header( $n, $v ) -- append a value, for headers which may repeat
##                                   (set-cookie, link, vary, www-authenticate...)
##                                   OUT/HEADERS is a plain hash, so one name holds
##                                   one value only; set-cookie escapes this because
##                                   it lives in its own OUT/COOKIES hash
##

sub res_set_headers
{
  my $self = shift;
  my %h    = @_;

  for my $k ( keys %h )
    {
    my $v = $h{ $k };
    my $k = lc $k;
    boom "invalid output headers [$k] value [$v]" if ( $k . $v ) =~ /[\r\n]/;

    if( $k eq 'status' )
      {
      $self->res_set_status( $v );
      }
    else
      {
      $self->{ 'OUT' }{ 'HEADERS' }{ $k } = $v;
      }
    }

  return $self->{ 'OUT' }{ 'HEADERS' };
}

sub res_get_headers_ar
{
  my $self = shift;


  my $ho = $self->{ 'OUT' }{ 'HEADERS' };

  $ho->{ 'content-type' } ||= 'application/octet-stream';

  if( exists $ho->{ 'content-charset' } )
    {
    if( $ho->{ 'content-type' } !~ /;\s*charset=/i )
      {
      $ho->{ 'content-type' } .= '; charset=' . $ho->{ 'content-charset' };
      }
    delete $ho->{ 'content-charset' };
    };

  if( exists $ho->{ 'location' } )
    {
    delete $ho->{ 'content-type' };
    }

  my @ho;
  for my $k ( sort keys %$ho )
    {
    push @ho, $k, $ho->{ $k };
    }

  while( my ( $k, $v ) = each %{ $self->{ 'OUT' }{ 'COOKIES' } || {} } )
    {
    push @ho, 'set-cookie', $v;
    }

  $self->log_dumper( 'RESULT HEADERS---------------------------------', \@ho );

  return \@ho;
}

#-----------------------------------------------------------------------------

sub res_set_cookie
{
  my $self = shift;
  my $name = shift;
  my %opt  = @_;

  $self->log_debug( "debug: creating new cookie [$name]" );
  # FIXME: validate %opt  Data::Validate::Struct

  $self->{ 'OUT' }{ 'COOKIES' }{ $name } = bake_cookie( $name, \%opt );
}

#-----------------------------------------------------------------------------

sub res_set_body
{
  my $self = shift;

  return $self->{ 'OUT' }{ 'BODY' } = $_[0];
}

sub res_get_body
{
  my $self = shift;

  return $self->{ 'OUT' }{ 'BODY' };
}

### INTERNAL API: IMPORT INPUT DATA & UPLOADS ################################

sub __import_client_input
{
  my $self = shift;

  my $input_client_hr = {};

  my $params = $self->plack()->parameters(); # input parameters, GET + POST
  my %params; # preprocessed parameters

  # check valid params names and preprocess multiple values
  # import plain parameters from GET/POST request
  PARAM_LOOP: for my $n ( keys %$params )
    {
    unless( __input_param_name_check( $n ) )
      {
      $self->log( "error: invalid CGI/input parameter name: [$n]" );
      next;
      }

    my @v = $params->get_all( $n );
    $n = uc $n; # FIXME: option? uc/lc/asis

    for( my $vi = 0; $vi < @v; $vi++ )
      {
      # ignore the whole array if any value is invalid
      next PARAM_LOOP if $self->__input_param_invalid_value( $n, $v[$vi] );
      $v[$vi] = $self->__input_param_make_safe_value( $n, decode( 'UTF-8', $v[$vi] ) );
      }

    if( @v > 1 )
      {
      $input_client_hr->{ '@' . $n } = \@v;
      }
    else
      {
      $input_client_hr->{ $n } = $v[0];
      }

    $self->log_debug( "debug: input param [$n] value [$v[0]] array [@v]" );
    }

  return $input_client_hr;
}

sub __import_safe_input
{
  my $self = shift;

  return {}; # not implemented in base
}

sub __import_client_uploads
{
  my $self = shift;

  my %uploads;
  # import uploads
  my $uploads = $self->plack()->uploads();
  for my $n ( keys %$uploads )
    {
    my @u = $uploads->get_all( $n );
    $uploads{ uc $n } = \@u; # FIXME: again, uc/lc/asis
    }

  return \%uploads;
}

### INTERNAL API: SANITY CHECKS ##############################################
##
## these are internal subs but are designed to be overriden if required
##

# fix/remove invalid parts of a input param value
sub __input_param_make_safe_value
{
  my $self = shift;
  my $n = shift; # arg name
  my $v = shift; # arg value

  $v =~ s/[\000]//go; # remove NULLs

  return $v;
}

# must return 1 for values which must be removed from input or 0 for ok
# this is called before __input_param_make_safe_value, default is pass all
sub __input_param_invalid_value
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

sub __input_param_name_check
{
  return $_[0] =~ /^[A-Za-z0-9\-\_\.\:]+$/o ? $_[0] : undef;
}

sub __input_sid_check
{
  return $_[0] =~ /^[a-zA-Z0-9_]+$/o ? $_[0] : undef;
}

##############################################################################

### LOGGING ##################################################################

# log() is possibly reimplemented in the subclass
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

sub render
{
  my $self = shift;

  my $pd  = ref $_[0] eq 'HASH' ? shift : { @_ }; # portray data

  my $page_data = $pd->{ 'DATA'      };
  my $page_fh   = $pd->{ 'FH'        }; # filehandle has priority
  my $page_type = $pd->{ 'TYPE'      } || 'application/octet-stream';
  my $file_name = $pd->{ 'FILE_NAME' };
  my $disp_type = $pd->{ 'DISPOSITION_TYPE' } || 'inline'; # default, rest must be handled as 'attachment', ref: rfc6266#section-4.2

  # preparing headers --------------------------------------------------------
  # FIXME: charset
  # TODO: move to func
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
  my $http_csp = $self->get_cfg->{ 'HTTP_CSP' }; # || " default-src 'self' ";
  $self->res_set_headers( 'Content-Security-Policy' => $http_csp ) if $http_csp;

  my $page_type_is_text = $page_type =~ /^text\//i;
  if( $page_type_is_text )
    {
    # set charset for TEXT only
    $self->res_set_headers( 'content-charset' => 'UTF-8' );
    $page_data = encode( 'UTF-8', $page_data ) unless $page_fh;
    }

  # preparing body -----------------------------------------------------------

  if( $page_fh )
    {
    $self->res_set_body( $page_fh );
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

##############################################################################

=pod

   pod here

=cut

##############################################################################
1;
###EOF########################################################################
