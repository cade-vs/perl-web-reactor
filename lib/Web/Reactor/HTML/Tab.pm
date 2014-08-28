##############################################################################
##
##  Web::Reactor application machinery
##  2013 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
#
# HTML Tabs
#
##############################################################################
package Web::Reactor::HTML::Tab;
use strict;
use Carp;
use Web::Reactor::HTML::Utils;

sub new
{
  my $class = shift;
  my %env = @_;

  $class = ref( $class ) || $class;

  my $self = {
             'ENV'        => \%env,
             };

  my $reo = $env{ 'REO_REACTOR' };
  if( ref( $reo ) =~ /^Web::Reactor(::|$)/ )
    {
    $self->{ 'REO_REACTOR' } = $reo;
    }
  else
    {
    confess "missing REO reactor object";
    }

  bless $self, $class;

  $self->{ 'TABS_LIST'         } = []; # contain tab IDs
  $self->{ 'TAB_CONTROLLER_ID' } = join '_', ( 'RE_TAB', $reo->get_page_session_id(), ( $env{ 'NAME' } || $reo->html_new_id() ) );
  $self->{ 'TAB_COUNTER'       } = 0;

  $reo->html_content_accumulator_js( "js/reactor.js" );

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
  my $args  = $opt{ 'ARGS'  };

  croak "TYPE can be only one of DIV|TR|TD" unless $et =~ /^(DIV|TR|TD)$/i;

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

  $handle = qq{ class='$handle_class' ID=$handle_id onclick='reactor_tab_activate_id( "$tab_id" )' };
  $text   = qq{ <$et id=$tab_id class='$class' data-controller-id='$tab_controller_id' data-handle-id='$handle_id' $display $args >$content</$et> };

  return ( $handle, $text );
}

# puts tab controller inside html accumulator

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
<DIV class='reactor_tab_controller' id=$tab_controller_id style='display: none;' data-tabs-list='$tabs_list' data-class-on='$class_on' data-class-off='$class_off'>

  <script type="text/javascript">

    reactor_tab_activate_id( sessionStorage.getItem( 'TABSET_ACTIVE_$tab_controller_id' ) );

  </script>

</DIV>
};

  my $reo = $self->{ 'REO_REACTOR' };
  $reo->html_content_accumulator( 'ACCUMULATOR_HTML', $html );
}

1;
