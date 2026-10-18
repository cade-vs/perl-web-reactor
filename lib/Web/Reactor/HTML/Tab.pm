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
##
## HTML Tabs
##
##############################################################################
package Web::Reactor::HTML::Tab;
use strict;
use Exception::Sink;
use Web::Reactor::HTML::Utils;

use parent 'Web::Reactor::Base';

# new( $reo, %opt ), new( %opt ): the reactor object is optional, see the POD.
# the old new( REO_REACTOR => $reo, %opt ) still works # cc20261017-1
sub new
{
  my $class = shift;
  my $reo   = ( @_ and ( ! defined $_[0] or ref $_[0] ) ) ? shift : undef; # cc20261017-1 a reference (or undef) first is the reactor
  boom "expected even number of options" if @_ % 2; # cc20261017-1
  my %opt   = @_;

  $reo ||= delete $opt{ 'REO_REACTOR' }; # cc20261017-1 the old option

  $class = ref( $class ) || $class;

  my $self = {};

  bless $self, $class;

  if( $reo ) # cc20261017-1
    {
    $self->__set_reo( $reo ); # booms on a non-reactor object
    # the html kit holds (js and controller) and the ids need Web::Reactor::Reflex or above
    boom "HTML::Tab needs a Web::Reactor::Reflex or Web::Reactor object, got [" . ref( $reo ) . "]" unless $reo->can( 'html_hold_kit_js' );
    $reo->html_hold_kit_js( "js/reactor.js" ); # pages show it with <$$kit_head>
    }
  $self->{ 'CFG' } = $reo ? $reo->cfg() : {}; # the reactor config, as Base::new() would set it

  __check_html_id( 'NAME', $opt{ 'NAME' } ) if defined $opt{ 'NAME' };

  # under Web::Reactor (the id scope is the page session) a named tab set keeps
  # the same controller id in all requests of the page, so the active tab is
  # restored after a reload. an unnamed one, or any under Reflex, gets a new id
  # each time. without a reactor a named one keeps its name as the id # cc20261017-1
  my @scope = $reo ? ( $reo->get_uniq_id_scope() ) : ();
  $self->{ 'TABS_LIST'         } = []; # contain tab IDs
  $self->{ 'TAB_CONTROLLER_ID' } = defined $opt{ 'NAME' } ? join( '_', 'RE_TAB', @scope, $opt{ 'NAME' } ) : 'RE_TAB_' . ( $reo ? $reo->create_uniq_id() : html_uniq_id() ); # cc20261017-1
  # only an id which stays the same in the next requests is worth remembering
  # the active tab under (sessionStorage keys of new ids are never read again)
  $self->{ 'PERSIST'           } = defined $opt{ 'NAME' } && ( ! $reo || $reo->isa( 'Web::Reactor' ) ); # cc20261017-1
  $self->{ 'TAB_COUNTER'       } = 0;

  $self->{ 'OPT' } = \%opt; # REO_REACTOR is not in it, only the weak link set by __set_reo()

  #use Data::Dumper;
  #print STDERR Dumper( $self );

  return $self;
}

# returns ( handle attributes text, tab html, handle attributes hashref ), see the POD # cc20261017-1
sub add
{
  my $self    = shift;
  my $content = shift;
  my %opt     = @_;

  boom "tab set [$self->{ 'TAB_CONTROLLER_ID' }] is already finished, cannot add more tabs" if $self->{ 'FINISHED' };
  boom "tab ARGS (raw html attributes) is removed, use ATTRS" if exists $opt{ 'ARGS' }; # cc20261017-1

  my $et = uc $opt{ 'TYPE' }; # html element type TD, TR, DIV
  my $on =    $opt{ 'ON'   }; # is visible?

  my $class        = $opt{ 'CLASS' } || 'reactor_tab';
  my $handle_extra = $opt{ 'HANDLE_CLASS' }; # handle classes kept when the tab is switched

  __check_html_id( 'TAB_ID',    $opt{ 'TAB_ID'    } ) if defined $opt{ 'TAB_ID'    };
  __check_html_id( 'HANDLE_ID', $opt{ 'HANDLE_ID' } ) if defined $opt{ 'HANDLE_ID' };

  boom "invalid tab TYPE [$et], can be only one of DIV|TR|TD" unless $et =~ /^(DIV|TR|TD)$/;

  my $tab_controller_id =    $self->{ 'TAB_CONTROLLER_ID' };

  boom "tab set [$tab_controller_id] already has a tab ON, only one can be shown at first" if $on and $self->{ 'ANY_ON' };

  my $tab_counter       = ++ $self->{ 'TAB_COUNTER'       };

  my $handle_id = $opt{ 'HANDLE_ID' } || "${tab_controller_id}_HANDLE_$tab_counter";
  my $tab_id    = $opt{ 'TAB_ID'    } || "${tab_controller_id}_CONTENT_$tab_counter";

  push @{ $self->{ 'TABS_LIST' } }, $tab_id;
  $self->{ 'ANY_ON' } ||= $on;

  my $class_on  = $self->{ 'OPT' }{ 'CLASS_ON' };
  my $class_off = $self->{ 'OPT' }{ 'CLASS_OFF' };

  # the handle, as attributes for html_element() and as text # cc20261017-1
  my $handle_class = join ' ', grep { $_ ne '' } ( $handle_extra, $on ? $class_on : $class_off );
  my %handle_attrs = ( id => $handle_id, onclick => 'return reactor_tab_activate_id( ' . html_js_str( $tab_id ) . ' )' );
  $handle_attrs{ 'class'           } = $handle_class if $handle_class ne ''; # no empty class attribute
  $handle_attrs{ 'data-class-keep' } = $handle_extra if $handle_extra ne ''; # kept by the tab switch
  my $handle = html_attrs( %handle_attrs );

  # the tab element, ATTRS cannot replace what the tab switch needs # cc20261017-1
  my %attr = html_attrs_filter( $opt{ 'ATTRS' }, qw( id class data-controller-id data-handle-id ) );
  $attr{ 'style' } = join ' ', grep { $_ ne '' } ( 'display: none;', $attr{ 'style' } ) unless $on; # a hidden tab, one style attribute
  my $text = html_element( lc $et, $content, %attr, id => $tab_id, class => $class, 'data-controller-id' => $tab_controller_id, 'data-handle-id' => $handle_id );

  return ( $handle, $text, \%handle_attrs );
}

# puts tab controller inside the KIT_HTML hold, pages show it with <$$kit_html>
# when no tab was added with ON, the first tab is shown unless another one is
# restored from the browser session. a second call does nothing. without a
# reactor object it returns the controller html instead # cc20261017-1

sub finish
{
  my $self    = shift;

  return if $self->{ 'FINISHED' }++;
  return unless @{ $self->{ 'TABS_LIST' } }; # cc20261017-1 before any work

  my $tab_controller_id = $self->{ 'TAB_CONTROLLER_ID' };
  my $tabs_list         = join ',', @{ $self->{ 'TABS_LIST' } };

  my $class_on    = $self->{ 'OPT' }{ 'CLASS_ON' };
  my $class_off   = $self->{ 'OPT' }{ 'CLASS_OFF' };

  # with no ON tab the first tab is the default, also when a remembered tab id
  # is no longer in the page
  my $default_tab = $self->{ 'ANY_ON' } ? '' : $self->{ 'TABS_LIST' }[ 0 ];

  # FIXME: <input hidden> active tab element keeper to be optionally outside element (by id)
  my $restore_js = 'reactor_tab_restore( ' . html_js_str( $tab_controller_id ) . ', ' . html_js_str( $default_tab ) . ' );'; # cc20261017-1
  my $html = "\n" . html_element( 'div', "\n  " . html_element( 'script', "\n    $restore_js\n  ", type => 'text/javascript' ) . "\n",
                                  class => 'reactor_tab_controller', id => $tab_controller_id, style => 'display: none;',
                                  'data-tabs-list' => $tabs_list, 'data-class-on' => $class_on, 'data-class-off' => $class_off,
                                  ( $self->{ 'PERSIST' } ? ( 'data-persist' => 1 ) : () ) ) . "\n"; # cc20261017-1

  my $reo = $self->reo_optional(); # cc20261017-1
  return $html unless $reo; # no page holds, the caller prints it
  $reo->html_hold_kit_add( 'KIT_HTML', $html );
  return undef;
}

##############################################################################

# ids go into html attributes and into the tab controller javascript, so only
# safe characters are allowed, anything else booms. classes are escaped by
# html_element() / html_attrs(), they need no check # cc20261017-1

sub __check_html_id
{
  my $name  = shift;
  my $value = shift;

  boom "invalid tab $name [$value], allowed are A-Z a-z 0-9 _ - . :" unless $value ne '' and html_check_ident( $value );
}

##############################################################################

=pod

=head1 NAME

Web::Reactor::HTML::Tab - switchable tabs (pages of content) for Web::Reactor

=head1 SYNOPSIS

  my $tab = Web::Reactor::HTML::Tab->new( $reo, NAME => 'settings',
                                          CLASS_ON => 'tab-on', CLASS_OFF => 'tab-off' );

  my ( $h1, $t1 ) = $tab->add( $general_html, TYPE => 'DIV', ON => 1 );
  my ( $h2, $t2 ) = $tab->add( $advanced_html, TYPE => 'DIV' );

  # or with html_element() and the handle attributes hashref
  my ( undef, $t3, $ha3 ) = $tab->add( $more_html, TYPE => 'DIV' );

  $tab->finish(); # after the last add()

  $html .= "<span$h1>General</span> <span$h2>Advanced</span>";
  $html .= html_element( 'span', 'More', %$ha3 );
  $html .= $t1 . $t2 . $t3;

=head1 PAGE REQUIREMENTS

The tabs are switched in the browser by C<js/reactor.js>. With a reactor
object the page template must print both deferred kit holds, which are
filled while the page is processed:

  <$$kit_head>   in <head>, loads js/reactor.js (added by new())
  <$$kit_html>   anywhere after the tabs, holds the tab controller (added by
                 finish())

Without them the handles do nothing.

=head1 WITHOUT A REACTOR

new() without the reactor object works too: the ids come from
Web::Reactor::HTML::Utils html_uniq_id() (a named tab set uses its NAME), the
page must load js/reactor.js itself and print the html which finish()
returns (the tab controller) anywhere after the tabs.

=head1 METHODS

=over 4

=item C<new( $reo, %opt )>, C<new( %opt )>

C<$reo> is a Web::Reactor::Reflex or a Web::Reactor object, it is optional
(see WITHOUT A REACTOR). The old C<new( REO_REACTOR =E<gt> $reo, %opt )>
still works.

Options:

  NAME       -- tab set name, A-Z a-z 0-9 _ - . : only. under Web::Reactor a
                named tab set keeps its ids in all requests of the page (the
                id scope is the page session), so the active tab is
                remembered (per browser tab, sessionStorage) across reloads.
                under Web::Reactor::Reflex the scope changes per request,
                so nothing is remembered. without a reactor the NAME itself
                is the id (and the active tab is remembered). unnamed tab
                sets never remember the active tab
  CLASS_ON   -- handle class of the active tab
  CLASS_OFF  -- handle class of the other tabs

=item C<add( $content, %opt )>

Returns ( handle attributes, tab html, handle attributes hashref ). Put the
handle attributes (text with a leading space) into the element which
switches to this tab, or give the hashref to html_element(), and the tab
html where the tab goes.

  TYPE          -- DIV, TR or TD, the element which holds the tab (required)
  ON            -- the tab is shown at first, only one tab may be ON
  CLASS         -- class of the tab element (default "reactor_tab")
  HANDLE_CLASS  -- other handle classes, kept when the tab is switched
  TAB_ID        -- tab element id (default generated)
  HANDLE_ID     -- handle element id (default generated)
  ATTRS         -- { attribute => value } extra attributes of the tab
                   element, escaped, they cannot replace id, class,
                   data-controller-id and data-handle-id. a hidden tab gets
                   display: none merged into a style in it
  ARGS          -- removed (raw html attributes), it booms, use ATTRS

Ids allow A-Z a-z 0-9 _ - . : only and boom on anything else. Classes are
escaped. Booms after C<finish()>.

=item C<finish()>

Puts the tab controller into the C<KIT_HTML> hold, or returns its html
without a reactor object. When no tab was added with C<ON>, the first one is
shown unless another one is remembered. Call it once after the last
C<add()>, later calls do nothing.

=back

=cut

1;
###EOF########################################################################
