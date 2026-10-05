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

  __check_html_id(    'NAME',      $env{ 'NAME'      } ) if defined $env{ 'NAME' };
  __check_html_class( 'CLASS_ON',  $env{ 'CLASS_ON'  } );
  __check_html_class( 'CLASS_OFF', $env{ 'CLASS_OFF' } );

  $self->{ 'TABS_LIST'         } = []; # contain tab IDs
  $self->{ 'TAB_CONTROLLER_ID' } = join '_', ( 'RE_TAB', $reo->get_uniq_id_scope(), ( $env{ 'NAME' } || $reo->create_uniq_id() ) );
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

  my $et = uc $opt{ 'TYPE' }; # html element type TD, TR, DIV
  my $on =    $opt{ 'ON'   }; # is visible?

  my $class = $opt{ 'CLASS' } || 'reactor_tab';
  my $args  = $opt{ 'ARGS'  }; # raw html attributes, not checked, the caller's responsibility

  __check_html_id(    'TAB_ID',    $opt{ 'TAB_ID'    } ) if defined $opt{ 'TAB_ID'    };
  __check_html_id(    'HANDLE_ID', $opt{ 'HANDLE_ID' } ) if defined $opt{ 'HANDLE_ID' };
  __check_html_class( 'CLASS',     $class );

  boom "TYPE can be only one of DIV|TR|TD" unless $et =~ /^(DIV|TR|TD)$/i;

  my $tab_controller_id =    $self->{ 'TAB_CONTROLLER_ID' };
  my $tab_counter       = ++ $self->{ 'TAB_COUNTER'       };
  
  my $handle_id = $opt{ 'HANDLE_ID' } || "${tab_controller_id}_HANDLE_$tab_counter";
  my $tab_id    = $opt{ 'TAB_ID'    } || "${tab_controller_id}_CONTENT_$tab_counter";

  push @{ $self->{ 'TABS_LIST' } }, $tab_id;

  my $class_on  = $self->{ 'OPT' }{ 'CLASS_ON' };
  my $class_off = $self->{ 'OPT' }{ 'CLASS_OFF' };

  my $handle;
  my $text;

  my $display = $on ? '' : "style='display: none;'";
  my $handle_class = $on ? $class_on : $class_off;

  $handle = qq{ class='$handle_class' ID='$handle_id' onclick='return reactor_tab_activate_id( "$tab_id" )' };
  $text   = qq{ <$et id='$tab_id' class='$class' data-controller-id='$tab_controller_id' data-handle-id='$handle_id' $display $args >$content</$et> };

  return ( $handle, $text );
}

# puts tab controller inside the KIT_HTML hold, pages show it with <$$kit_html>

sub finish
{
  my $self    = shift;

  my $html;

  my $tab_controller_id = $self->{ 'TAB_CONTROLLER_ID' };
  my $tabs_list         = join ',', @{ $self->{ 'TABS_LIST' } };

  my $class_on    = $self->{ 'OPT' }{ 'CLASS_ON' };
  my $class_off   = $self->{ 'OPT' }{ 'CLASS_OFF' };

  # FIXME: <input hidden> active tab element keeper to be optionally outside element (by id)
  $html = qq{
<DIV class='reactor_tab_controller' id='$tab_controller_id' style='display: none;' data-tabs-list='$tabs_list' data-class-on='$class_on' data-class-off='$class_off'>

  <script type="text/javascript">

    reactor_tab_activate_id( sessionStorage.getItem( 'TABSET_ACTIVE_$tab_controller_id' ) );

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

1;
###EOF########################################################################
