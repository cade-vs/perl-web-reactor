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

our $VERSION = '3.33';


##############################################################################

sub new
{
  my $class = shift;
  my $env   = shift;
  my $cfg   = shift;

  die "expected first  argument to be ENV hash reference" unless ref $env eq 'HASH';
  die "expected second argument to be CFG hash reference" unless ref $cfg eq 'HASH';

  $class = ref( $class ) || $class;
  my $self = {};
  bless $self, $class;

  $self->{ 'CFG' }                    = dclone( $cfg );
  $self->{ 'CFG' }{ 'CHARSET' }       = 'UTF-8'; # force UTF-8 always
  $self->{ 'IN'  }{ 'ENV'         }   = $env = { %$env }; # including headers
  $self->{ 'IN'  }{ 'ENV'         }{ ':CLIENT_IP' } = $self->get_client_ip(); # this is always end-point client browser IP, reglardless of claudflare proxy etc.

  $self->set_debug( $cfg->{ 'DEBUG' } );

  $self->log_debug( "\n\n\n\n\n" . ( '*' x 64 ) ) if $self->is_debug();
  $self->log_dumper( "debug: *** BEGIN *** obj [$self] *** setup (ENV & CFG): ", $env, $cfg ) if $self->is_debug() > 3;

  $self->{ 'PLACK' } = Plack::Request->new( $env );

  srand();

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
  # NOTE: failures below answer with HTTP 200 on purpose for now, so proxies and
  #       caches do not replace the message; consider 500/503 for monitoring later
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
  my $level = abs(int(shift // 0));

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

sub cfg
{
  my $self = shift;

  return $self->{ 'CFG' };
}

sub plack
{
  my $self = shift;

  return ( $self->{ 'PLACK' } || die "missing PLACK object" );
}

sub env
{
  my $self  = shift;

  return $self->{ 'IN'  }{ 'ENV' };
}

### REQUEST/INPUT STATE ######################################################

sub get_client_ip
{
  my $self  = shift;

  my $cfg = $self->cfg();
  my $env = $self->env();

  my $client_ip;

  $client_ip ||= $env->{ 'HTTP_CF_CONNECTING_IP' } if $cfg->{ 'CLOUDFLARE'   };
  $client_ip ||= $env->{ 'HTTP_X_REAL_IP'        } if $cfg->{ 'PROXY_REMOTE' };
  $client_ip ||= $env->{ 'REMOTE_ADDR' };

  return $client_ip;
}

sub get_request_scheme
{
  my $self   = shift;

  # REQUEST_SCHEME is CGI/Apache only, PSGI guarantees psgi.url_scheme instead
  my $env = $self->{ 'IN' }{ 'ENV' };
  return lc( $env->{ 'REQUEST_SCHEME' } || $env->{ 'psgi.url_scheme' } );
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
  my $name = lc shift;

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

sub get_user_input
{
  my $self  = shift;

  return $self->{ 'USER_INPUT_HR'  } ||= $self->__import_user_input();
}

sub get_user_uploads
{
  my $self  = shift;

  return $self->{ 'USER_UPLOADS_HR'  } ||= $self->__import_user_uploads();
}

sub get_user_postdata_fh
{
  my $self = shift;

  return $self->plack()->body();
}

sub get_user_postdata_body
{
  my $self = shift;

  my $fh = $self->get_user_postdata_fh();

  local $/ = undef;
  return <$fh>;
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

  my $cookies = $self->{ 'OUT' }{ 'COOKIES' } || {};
  for my $k ( keys %$cookies )
    {
    push @ho, 'set-cookie', $cookies->{ $k };
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

sub __import_user_input
{
  my $self = shift;

  my $input_user_hr = {};

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
      $input_user_hr->{ '@' . $n } = \@v;
      }
    else
      {
      $input_user_hr->{ $n } = $v[0];
      }

    $self->log_debug( "debug: input param [$n] value [$v[0]] array [@v]" );
    }

  return $input_user_hr;
}

sub __import_safe_input
{
  my $self = shift;

  return {}; # not implemented in base
}

sub __import_user_uploads
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
  my $http_csp = $self->cfg->{ 'HTTP_CSP' }; # || " default-src 'self' ";
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

  boom "portray needs mime type xxx/xxx as arg 2, got [$type]" unless $type =~ /^[a-z\-_0-9]+\/[a-z\-_0-9\.\+]+$/;

  return { DATA => $data, TYPE => $type, @_ };
}

##############################################################################

sub forward_url
{
  my $self = shift;
  my $url  = shift;

  # FIXME: use render+portray
  $self->res_set_headers( status => 302, location => $url );
  $self->res_set_body( '' );

  sink 'RENDER';
}

##############################################################################

=pod

=head1 NAME

Web::Reactor::Core - PSGI request/response foundation for Web::Reactor

=head1 SYNOPSIS

  package Web::Reactor::Hello;
  use parent 'Web::Reactor::Core';

  sub process_request
  {
    my $self = shift;

    my $in   = $self->get_user_input();
    my $name = $in->{ 'NAME' } || 'world';

    $self->render( $self->portray( "<h1>hello $name</h1>", 'html' ) );
  }

  # app.psgi
  my $app = sub { Web::Reactor::Hello->new( $_[0], { DEBUG => 0 } )->run() };

=head1 DESCRIPTION

Web::Reactor::Core is the lowest layer of Web::Reactor. It wraps one PSGI
request: it reads the environment, parameters, uploads, headers and cookies,
collects the response status, headers, cookies and body, and turns them into
the PSGI response triplet. It knows nothing about pages, actions, templates
or sessions; those live in the subclasses:

=over 4

=item Web::Reactor::Reflex  stateless pages, actions, templates, safe links

=item Web::Reactor          stateful, adds user, page and link sessions

=back

One object is created per request and discarded afterwards. Subclasses
implement C<process_request()> and end it by calling C<render()> or
C<forward_url()>, both of which sink the C<RENDER> exception that C<run()>
catches to build the response.

=head1 REQUEST LIFECYCLE

=over 4

=item 1. C<new( $env, $cfg )>

Copies the config (deep) and the PSGI environment (shallow), forces
C<CHARSET> to C<UTF-8>, resolves the client IP into C<$env-E<gt>{':CLIENT_IP'}>,
sets the debug level from C<DEBUG> and creates the Plack::Request object.

=item 2. C<run( @args )>

Calls C<process_request( @args )> inside an eval and inspects the outcome:

  RENDER sink      -> [ status || 200, headers, body ] from the res_* state
  any other error  -> logged, "system is currently unavailable (*)"
  no sink at all   -> logged, "system is currently unavailable (!)"

Both failure responses use HTTP 200 on purpose, so proxies and caches do not
replace the message with their own error page.

=item 3. C<process_request( @args )>

Must be implemented by the subclass. The base version dies. C<@args> is an
optional list of name/value pairs a caller may force into the request.

=back

=head1 CONFIG ENTRIES

=over 4

=item C<DEBUG>         debug level, 0 (default) to 4; see "Logging" under METHODS

=item C<CHARSET>       always overwritten with C<UTF-8>

=item C<CLOUDFLARE>    true when behind Cloudflare, trust C<CF-Connecting-IP>
for the client address

=item C<PROXY_REMOTE>  true when behind a trusted reverse proxy, trust
C<X-Real-IP> for the client address

=item C<HTTP_CSP>      Content-Security-Policy header value sent with every
C<render()>, none if empty

=back

Both proxy flags are off by default, so a client cannot spoof its address by
sending those headers directly.

=head1 METHODS

=head2 Construction and dispatch

=over 4

=item C<new( \%env, \%cfg )>

Dies unless both arguments are hash references.

=item C<run( @args )>

Returns the PSGI response array reference. Never dies.

=item C<process_request( @args )>

Abstract, see L</REQUEST LIFECYCLE>.

=back

=head2 Debug level

=over 4

=item C<set_debug( $level )>, C<is_debug()>, C<inc_debug( $step )>

Non-negative integer, kept on the object. C<is_debug()> returns 0 when unset.

=back

=head2 Accessors

=over 4

=item C<cfg()>    the config hash reference (the copy, not the caller's)

=item C<env()>    the PSGI environment hash reference (the copy)

=item C<plack()>  the Plack::Request object

=back

=head2 Request state

=over 4

=item C<get_client_ip()>

Client address honouring the proxy flags above, falls back to C<REMOTE_ADDR>.
Also available as C<env-E<gt>{':CLIENT_IP'}>.

=item C<get_request_scheme()>

C<http> or C<https>, lowercased, from C<REQUEST_SCHEME> or, under PSGI,
C<psgi.url_scheme>.

=item C<get_request_uri()>, C<get_request_method()>, C<get_request_path_info()>

Straight from the environment.

=item C<get_headers()>

Hash reference of request headers keyed by their real, lowercase names:
C<content-type>, C<x-forwarded-for>, and so on. The CGI mangling (uppercase,
underscores, C<HTTP_> prefix) is undone. Built once per request.

=item C<get_header( $name )>

One header by name, case insensitive.

=item C<get_cookies()>, C<get_cookie( $name )>

Parsed C<Cookie> header, via Cookie::Baker. Cookie names are case sensitive.

=back

=head2 Request input

=over 4

=item C<get_user_input()>

Hash reference of GET and POST parameters, built once per request:

=over 4

=item * names are uppercased, so C<?page=1> arrives as C<PAGE>

=item * names outside C<[A-Za-z0-9_.:-]> are logged and dropped

=item * values are UTF-8 decoded and NUL bytes removed

=item * a parameter sent more than once is stored as an array reference under
C<@NAME>, a single one as a scalar under C<NAME>

=back

=item C<get_safe_input()>

Hash reference of trusted input. Empty in the base class; Reflex fills it from
the encrypted C<_> token.

=item C<get_user_uploads()>

Hash reference, uppercase field name to array reference of Plack::Request::Upload
objects, one entry per field even for a single file.

=item C<get_user_postdata_fh()>, C<get_user_postdata_body()>

The raw request body as a file handle or as one string. Usable after
C<get_user_input()> as well, Plack buffers the input.

=back

=head2 Response state

All C<res_*> calls only record state; nothing is sent until C<run()> returns.

=over 4

=item C<res_set_status( $code )>, C<res_get_status()>

HTTP status, defaults to 200 when unset.

=item C<res_set_headers( %headers )>

Records headers, names lowercased, later calls overwrite earlier ones for
the same name. Booms on a CR or LF in a name or value. Two names are special:
C<status> sets the HTTP status instead, C<content-charset> is appended to
C<content-type> as C<; charset=...> when the response is built.

=item C<res_get_headers_ar()>

Flattens the recorded headers into the PSGI array. C<content-type> defaults to
C<application/octet-stream> and is dropped when a C<location> header is
present. One C<set-cookie> line is added per cookie.

=item C<res_set_cookie( $name, %options )>

Records a response cookie. C<%options> are passed to Cookie::Baker's
C<bake_cookie>: C<value>, C<path>, C<domain>, C<expires>, C<secure>,
C<httponly>, C<samesite>. One cookie per name.

=item C<res_set_body( $body )>, C<res_get_body()>

Body as a string of bytes or a file handle. A string is wrapped in an array
reference for PSGI, a file handle is passed through.

=back

=head2 Rendering

=over 4

=item C<render( \%portray )> or C<render( %portray )>

Builds the response from a portray hash and sinks C<RENDER>, so it never
returns. Keys:

  DATA              body text (or bytes for non-text types)
  FH                body file handle, takes priority over DATA
  TYPE              MIME type, default application/octet-stream
  FILE_NAME         adds a Content-Disposition header, see below
  DISPOSITION_TYPE  inline (default) or attachment

For C<text/*> types the charset header is set to UTF-8 and DATA is encoded
from characters to bytes; a FH is sent as is. FILE_NAME is sanitized for
header injection and, when it contains non-ASCII, sent both as an ASCII
fallback and as an RFC 5987 C<filename*> parameter. C<HTTP_CSP> from the
config is added when set.

=item C<portray( $data, $type, %extra )>

Returns a portray hash for C<render()>. C<$type> is a MIME type or one of the
shortcuts C<html>, C<text>, C<txt>, C<jpeg>, C<png>, C<bin>. Booms on
anything that is not C<type/subtype>. C<%extra> is merged in, so
C<FILE_NAME> and C<DISPOSITION_TYPE> go here.

=item C<forward_url( $url )>

Records a 302 redirect with an empty body and sinks C<RENDER>.

=back

=head2 Logging

=over 4

=item C<log( @text )>

Writes to STDERR with a newline. Subclasses override this to route logs
elsewhere; every other log method ends up here.

=item C<log_debug( @text )>

Logged when the debug level is 1 or more, prefixed with C<debug:> if not
already.

=item C<log_debug2( @text )>

Same at level 2 or more.

=item C<log_stack( @text )>

C<log_debug> plus a stack trace.

=item C<log_dumper( @data )>

C<log_debug> of Data::Dumper output, keys sorted.

=back

=head1 OVERRIDABLE INTERNALS

These are called by the input methods and may be replaced in a subclass to
change policy:

=over 4

=item C<__import_user_input()>, C<__import_safe_input()>, C<__import_user_uploads()>

Build the three input hashes. The results are cached on the object by the
public getters.

=item C<__input_param_name_check( $name )>

Returns the name if acceptable, undef otherwise.

=item C<__input_param_invalid_value( $name, $value )>

Return 1 to drop the parameter (all of its values), 0 to keep it. Default
keeps everything.

=item C<__input_param_make_safe_value( $name, $value )>

Cleans one value, default strips NUL bytes.

=back

=head1 SEE ALSO

Web::Reactor::Reflex, Web::Reactor, Plack::Request, Cookie::Baker,
Exception::Sink.

=head1 AUTHOR

  Vladi Belperchinov-Shabanski "Cade"
  <cade@noxrun.com>
  http://cade.noxrun.com

=head1 LICENSE

GPLv2, see COPYING.

=cut

##############################################################################
1;
###EOF########################################################################
