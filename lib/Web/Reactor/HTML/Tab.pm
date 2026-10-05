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

use parent 'Web::Reactor::Base';

sub new
{
  my $class = shift;
  my %env = @_;

  $class = ref( $class ) || $class;

  my $self = {};

  bless $self, $class;

  # FIXME: move as argument, not env option
  $self->__set_reo( $env{ 'REO_REACTOR' } );
  my $reo = $self->reo();
  $self->{ 'CFG' } = $reo->cfg(); # the reactor config, as Base::new() would set it

  __check_html_id(    'NAME',      $env{ 'NAME'      } ) if defined $env{ 'NAME' };
  __check_html_class( 'CLASS_ON',  $env{ 'CLASS_ON'  } );
  __check_html_class( 'CLASS_OFF', $env{ 'CLASS_OFF' } );

  # a named tab set keeps the same controller id in all requests of the page,
  # so the active tab is restored after a reload, an unnamed one gets a new id
  # each time
  $self->{ 'TABS_LIST'         } = []; # contain tab IDs
  $self->{ 'TAB_CONTROLLER_ID' } = defined $env{ 'NAME' } ? join( '_', 'RE_TAB', $reo->get_uniq_id_scope(), $env{ 'NAME' } ) : 'RE_TAB_' . $reo->create_uniq_id();
  $self->{ 'TAB_COUNTER'       } = 0;

  $reo->html_hold_kit_js( "js/reactor.js" ); # pages show it with <$$kit_head>

  $self->{ 'OPT' } = { @_ };

  #use Data::Dumper;
  #print STDERR Dumper( $self );

  return $self;
}

# returns ( 'handle' code, html text ) handle code to be put inside HTML tag to activate this TAB
sub add
{
  my $self    = shift;
  my $content = shift;
  my %opt     = @_;

  boom "tab set [$self->{ 'TAB_CONTROLLER_ID' }] is already finished, cannot add more tabs" if $self->{ 'FINISHED' };

  my $et = uc $opt{ 'TYPE' }; # html element type TD, TR, DIV
  my $on =    $opt{ 'ON'   }; # is visible?

  my $class        = $opt{ 'CLASS' } || 'reactor_tab';
  my $handle_extra = $opt{ 'HANDLE_CLASS' }; # handle classes kept when the tab is switched
  my $args         = $opt{ 'ARGS'  }; # raw html attributes, not checked, the caller's responsibility

  __check_html_id(    'TAB_ID',       $opt{ 'TAB_ID'    } ) if defined $opt{ 'TAB_ID'    };
  __check_html_id(    'HANDLE_ID',    $opt{ 'HANDLE_ID' } ) if defined $opt{ 'HANDLE_ID' };
  __check_html_class( 'CLASS',        $class );
  __check_html_class( 'HANDLE_CLASS', $handle_extra );

  boom "invalid tab TYPE [$et], can be only one of DIV|TR|TD" unless $et =~ /^(DIV|TR|TD)$/;

  my $tab_controller_id =    $self->{ 'TAB_CONTROLLER_ID' };
  my $tab_counter       = ++ $self->{ 'TAB_COUNTER'       };

  my $handle_id = $opt{ 'HANDLE_ID' } || "${tab_controller_id}_HANDLE_$tab_counter";
  my $tab_id    = $opt{ 'TAB_ID'    } || "${tab_controller_id}_CONTENT_$tab_counter";

  push @{ $self->{ 'TABS_LIST' } }, $tab_id;
  $self->{ 'ANY_ON' } ||= $on;

  my $class_on  = $self->{ 'OPT' }{ 'CLASS_ON' };
  my $class_off = $self->{ 'OPT' }{ 'CLASS_OFF' };

  my $handle;
  my $text;

  my $display = $on ? '' : "style='display: none;'";
  my $handle_class = join ' ', grep { $_ ne '' } ( $handle_extra, $on ? $class_on : $class_off );

  $handle = qq{ class='$handle_class' ID='$handle_id' onclick='return reactor_tab_activate_id( "$tab_id" )' };
  $text   = qq{ <$et id='$tab_id' class='$class' data-controller-id='$tab_controller_id' data-handle-id='$handle_id' $display $args >$content</$et> };

  return ( $handle, $text );
}

# puts tab controller inside the KIT_HTML hold, pages show it with <$$kit_html>
# when no tab was added with ON, the first tab is shown unless another one is
# restored from the browser session. a second call does nothing

sub finish
{
  my $self    = shift;

  return if $self->{ 'FINISHED' }++;

  my $html;

  my $tab_controller_id = $self->{ 'TAB_CONTROLLER_ID' };
  my $tabs_list         = join ',', @{ $self->{ 'TABS_LIST' } };

  return unless @{ $self->{ 'TABS_LIST' } };

  my $class_on    = $self->{ 'OPT' }{ 'CLASS_ON' };
  my $class_off   = $self->{ 'OPT' }{ 'CLASS_OFF' };

  my $default_tab = $self->{ 'ANY_ON' } ? '' : qq{ || "$self->{ 'TABS_LIST' }[ 0 ]"};

  # FIXME: <input hidden> active tab element keeper to be optionally outside element (by id)
  $html = qq{
<DIV class='reactor_tab_controller' id='$tab_controller_id' style='display: none;' data-tabs-list='$tabs_list' data-class-on='$class_on' data-class-off='$class_off'>

  <script type="text/javascript">

    reactor_tab_activate_id( sessionStorage.getItem( 'TABSET_ACTIVE_$tab_controller_id' )$default_tab );

  </script>

</DIV>
};

  my $reo = $self->reo();
  $reo->html_hold_kit_add( 'KIT_HTML', $html );
}

##############################################################################

# ids and class names go into html attributes and into the tab controller
# javascript, so only safe characters are allowed, anything else booms

sub __check_html_id
{
  my $name  = shift;
  my $value = shift;

  boom "invalid tab $name [$value], allowed are A-Z a-z 0-9 _ - . :" unless $value =~ /^[A-Za-z0-9_\-\.:]+$/;
}

sub __check_html_class
{
  my $name  = shift;
  my $value = shift;

  boom "invalid tab $name [$value], allowed are A-Z a-z 0-9 _ - and spaces" unless $value =~ /^[A-Za-z0-9_\- ]*$/;
}

##############################################################################

=pod

=head1 NAME

Web::Reactor::HTML::Tab - switchable tabs (pages of content) for Web::Reactor

=head1 SYNOPSIS

  my $tab = Web::Reactor::HTML::Tab->new( REO_REACTOR => $reo, NAME => 'settings',
                                          CLASS_ON => 'tab-on', CLASS_OFF => 'tab-off' );

  my ( $h1, $t1 ) = $tab->add( $general_html, TYPE => 'DIV', ON => 1 );
  my ( $h2, $t2 ) = $tab->add( $advanced_html, TYPE => 'DIV' );
  $tab->finish();

  $html .= "<span $h1>General</span> <span $h2>Advanced</span>";
  $html .= $t1 . $t2;

=head1 PAGE REQUIREMENTS

The tabs are switched in the browser by C<js/reactor.js>. The page template
must print both deferred kit holds, which are filled while the page is
processed:

  <$$kit_head>   in <head>, loads js/reactor.js (added by new())
  <$$kit_html>   anywhere after the tabs, holds the tab controller (added by
                 finish())

Without them the handles do nothing.

=head1 METHODS

=over 4

=item C<new( REO_REACTOR =E<gt> $reo, %opt )>

Options:

  NAME       -- tab set name, A-Z a-z 0-9 _ - . : only. a named tab set keeps
                its ids in all requests of the page, so the active tab is
                remembered (per browser tab, sessionStorage) across reloads
  CLASS_ON   -- handle class of the active tab
  CLASS_OFF  -- handle class of the other tabs

=item C<add( $content, %opt )>

Returns ( handle attributes, tab html ). Put the handle attributes into the
element which switches to this tab, and the tab html where the tab goes.

  TYPE          -- DIV, TR or TD, the element which holds the tab (required)
  ON            -- the tab is shown at first
  CLASS         -- class of the tab element (default "reactor_tab")
  HANDLE_CLASS  -- other handle classes, kept when the tab is switched
  TAB_ID        -- tab element id (default generated)
  HANDLE_ID     -- handle element id (default generated)
  ARGS          -- raw html attributes for the tab element, not checked

Ids and classes allow only safe characters and boom on anything else.
Booms after C<finish()>.

=item C<finish()>

Puts the tab controller into the C<KIT_HTML> hold. When no tab was added
with C<ON>, the first one is shown unless another one is remembered. Call it
once after the last C<add()>, later calls do nothing.

=back

=cut

1;
###EOF########################################################################
