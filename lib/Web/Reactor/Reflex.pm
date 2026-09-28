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

use Web::Reactor::Actions;
use Web::Reactor::Preprocessor;

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
  # $env = $self->env();

  data_tools_set_text_io_encoding( 'UTF-8' );

  boom "invalid APP_NAME [$cfg->{ 'APP_NAME' }]" unless    $cfg->{ 'APP_NAME' } =~ /^[a-z_0-9]+$/;
  boom "invalid LANG     [$cfg->{ 'LANG' }]"     unless    $cfg->{ 'LANG' }     =~ /^([a-z][a-z])?$/;
  boom "invalid APP_ROOT [$cfg->{ 'APP_ROOT' }]" unless -d $cfg->{ 'APP_ROOT' };

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

  return $self->{ "REO_ACT" } ||= $self->__load_and_attach_module( 'ACT', 'Web::Reactor::Actions::Files', $self, $self->cfg() );
}

sub pre
{
  my $self = shift;

  return $self->{ "REO_PRE" } ||= $self->__load_and_attach_module( 'PRE', 'Web::Reactor::Preprocessor::Tree', $self, $self->cfg() );
}

sub cry
{
  my $self = shift;

  return $self->{ "REO_CRY" } if exists $self->{ "REO_CRY" };

  my $key = $self->cfg->{ 'CRY_KEY' };
  boom "symmetric encryption requested but configuration does not have CRY_KEY in it" unless $key;

  return $self->{ "REO_CRY" } = $self->__load_and_attach_module( 'CRY', 'Data::Tools::Crypto::Symmetric', $key );
}

##############################################################################

sub process_request
{
  my $self = shift;
  my $args = @_ / 2; # count of arg pairs
  my %args = @_;

  my $user_input_hr = $self->get_user_input();
  my $safe_input_hr = $self->get_safe_input();

  # TODO/FIXME: the name checks below instantiate act() and pre() on every request,
  #             even when only one of them will be used; cheap after the first
  #             call but no longer lazy. consider class-level check functions.
  my $action_name = lc( $safe_input_hr->{ '_AN' } || $user_input_hr->{ '_AN' } );
  $self->act->check_action_name( $action_name ) if $action_name;

  my $page_name = lc( $safe_input_hr->{ '_PN' } || $user_input_hr->{ '_PN' } );
  $self->pre->check_page_name( $page_name ) if $page_name;

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
    $portray_data->{ 'DATA' } = $self->pre->process( undef, $portray_data->{ 'DATA' } );
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

#-----------------------------------------------------------------------------

sub __import_safe_input
{
  my $self = shift;

  my $user_input_hr = $self->get_user_input();
  my $x = $user_input_hr->{ '__' } or return {};
  ### return {} unless $x =~ s/^~//;

  my $hr = $self->cry->thaw_base64url( $x );
  $self->log( "error: invalid or tampered encrypted safe input token, ignored" ) unless $hr;
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

  return 0 if $lang !~ /^[a-z][a-z]$/; # FIXME: move to init check! verify hash etc. data::tools

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

=head1 NAME

Web::Reactor::Reflex - stateless web application machinery

=head1 SYNOPSIS

  package Web::Reactor::MyApp;
  use parent 'Web::Reactor::Reflex';

  # app.psgi
  my %cfg = (
            APP_NAME => 'myapp',
            APP_ROOT => '/opt/myapp',   # html/ and actions/ live here
            LANG     => 'en',
            CRY_KEY  => $secret,        # symmetric key for link arguments
            );

  my $app = sub { Web::Reactor::MyApp->new( $_[0], \%cfg )->run() };

=head1 DESCRIPTION

Web::Reactor::Reflex is the stateless layer of Web::Reactor. It sits on top of
Web::Reactor::Core, which handles the PSGI request and response, and adds
everything needed to serve pages and run actions without any server side
session storage:

=over 4

=item * page rendering through a pluggable preprocessor (templates, includes,
action calls inside templates, link rewriting)

=item * action dispatch through a pluggable action loader

=item * safe (tamper proof) link arguments, carried inside the URL as an
encrypted token instead of a session key

=item * a per request "HTML hold" of named text chunks that templates refer to

=back

Application classes must live under the C<Web::Reactor::> namespace, this is
checked by the plug modules when they attach to the reactor.

Web::Reactor (the stateful, session based reactor) inherits from this class.

=head1 REQUEST FLOW

C<run()> (inherited from Core) calls C<process_request()>, which:

=over 4

=item 1. reads user input (GET/POST parameters) and safe input (the decrypted
C<_> token, if any)

=item 2. takes the action name from C<_AN> and the page name from C<_PN>, safe
input first, user input second, and validates them through the plugs

=item 3. calls C<render_action( $name )> if an action name is present,
otherwise C<render_page( $name || 'main' )>

=back

Both render helpers hand their output to Core's C<render()>, which sinks
C<RENDER> and returns the PSGI response.

=head1 URL PARAMETERS

=over 4

=item C<_AN>  action name, C<[a-z0-9_]>, case insensitive

=item C<_PN>  page name, C<[a-z0-9_-]> with optional C</> separated path,
case insensitive, defaults to C<main>

=item C<_>    safe input token produced by C<args()>: C<~> followed by the
encrypted, base64url encoded hash of arguments. Values found here override
the same names from user input. An invalid or tampered token is logged and
ignored.

=back

=head1 CONFIG ENTRIES

Validated in C<new()>:

=over 4

=item C<APP_NAME>   required, C<[a-z0-9_]>, also the default action set name

=item C<APP_ROOT>   required, existing directory, base for the defaults below

=item C<LANG>       required, two lowercase letters, selects the C<html/E<lt>langE<gt>>
tree and the translation files

=back

Used by the plugs:

=over 4

=item C<CRY_KEY>       symmetric key for C<args()> and safe input, required if
any link arguments or forwards are used

=item C<HTML_DIRS>     list (or single string) of template roots, default
C<APP_ROOT/html>; see Web::Reactor::Preprocessor::Tree for the layout

=item C<ACTIONS_DIRS>  list of action file directories, default
C<APP_ROOT/actions> (Web::Reactor::Actions::Files)

=item C<ACTIONS_PKGS>  package prefix for action files, default
C<reactor::actions::> (Web::Reactor::Actions::Files)

=item C<LIB_DIRS>      extra directories pushed to C<@INC>, default
C<APP_ROOT/lib> (Web::Reactor::Actions::Packages)

=item C<ACTIONS_SETS>  action set search order, default C<( APP_NAME, Base, Core )>
(Web::Reactor::Actions::Packages)

=item C<REO_ACT_CLASS> action loader class, default C<Web::Reactor::Actions::Files>

=item C<REO_PRE_CLASS> preprocessor class, default C<Web::Reactor::Preprocessor::Tree>

=item C<REO_CRY_CLASS> cipher class, default C<Data::Tools::Crypto::Symmetric>

=item C<TRANS_DIRS>, C<TRANS_FILE>  translation sources for C<load_trans()>

=back

Inherited from Core: C<DEBUG>, C<HTTP_CSP>, C<CLOUDFLARE>, C<PROXY_REMOTE>.

=head1 METHODS

=head2 Plugs

=over 4

=item C<act()>  the action loader object, created on first use

=item C<pre()>  the preprocessor object, created on first use

=item C<cry()>  the cipher object, created on first use

=back

=head2 Rendering

=over 4

=item C<render_page( $page_name )>

Loads the page through C<pre-E<gt>load_page()>, runs it through
C<pre-E<gt>process()> and renders it as C<text/html>. Booms if the page does
not exist or is empty.

=item C<render_action( $action_name )>

Calls the action through C<act-E<gt>call()>. A plain string result is treated
as HTML and processed like a page. A hashref result (see C<portray()> in Core)
is rendered as is, processed only if its type is C<text/html>. Booms if the
action returns nothing.

=item C<forward( %args )>

Redirects (302) to the current script with C<%args> as a safe input token.

=item C<require_post_method()>

Returns if the request is POST, otherwise renders page C<epostrequired>.

=back

=head2 Arguments

=over 4

=item C<args( %args )>

Returns the safe input token for C<%args> (keys uppercased), ready to be used
as the C<_> parameter.

=item C<args_type( $type, %args )>

Same as C<args()>, C<$type> (here/back/new/none) is accepted for template
compatibility and ignored, a stateless reactor has nothing to go back to.

=back

=head2 Input

=over 4

=item C<get_user_input_button()>

Finds the first C<BUTTON:NAME> or C<BUTTON:NAME:ID> parameter, returns
C<( $name, $id )> in list context, C<$name> in scalar context.

=item C<get_lang()>, C<get_app_name()>, C<get_app_root()>

Config accessors, C<get_lang()> returns the language lowercased.

=back

=head2 HTML hold

Named text chunks templates refer to with C<E<lt>$nameE<gt>>. Names are case
insensitive.

=over 4

=item C<html_hold_set( %chunks )>, C<html_hold_get( $name )>,
C<html_hold_del( $name )>, C<html_hold_clear()>, C<html_hold_reset( %chunks )>

=item C<html_hold_kit_add( $name, $text )>

Accumulates unique snippets under C<$name>, the hold value is the sorted
concatenation of all snippets added so far.

=item C<html_hold_kit_js( $url )>, C<html_hold_kit_css( $url )>

Add a script or stylesheet tag to the C<KIT_HEAD> kit.

=item C<set_browser_window_title( $title )>

Strips HTML and sets C<BROWSER_WINDOW_TITLE>.

=back

=head2 Translations

=over 4

=item C<load_trans()>

Loads C<*.tr> files for the current language from C<TRANS_DIRS> (or the
single C<TRANS_FILE>) into the reactor. Returns 1 on success, 0 if the
language is not a two letter code.

=item C<load_trans_file( $file_name )>

Loads one translation file, returns a hashref.

=back

=head1 SEE ALSO

Web::Reactor::Core, Web::Reactor::Preprocessor::Tree,
Web::Reactor::Actions::Files, Web::Reactor::Actions::Packages, Web::Reactor.

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
