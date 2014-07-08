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

  $self->{ 'TAB_ID' } = "RE_TAB_CTRL_" . Web::Reactor::HTML::Utils::html_next_id(); # tab controller name
  $self->{ 'TABS' } = []; # contain tab IDs

  # rcd_log( "debug: rcd_rec:$self created" );
  $reo->html_content_accumulator_js( "js/review.js" );

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

  my $on = $opt{ 'ON' }; # is visible?
  my $et = uc $opt{ 'TYPE' }; # html element type TD, TR, DIV

  my $class = uc $opt{ 'CLASS' } || 'tab';
  my $arg   = $opt{ 'ARG' };

  croak "TYPE can be only one of DIV|TR|TD" unless $et =~ /^(DIV|TR|TD)$/i;

  my $tab_controller_id = $self->{ 'TAB_ID' };
  my $handle_id = $opt{ 'HANDLE_ID' } || "RE_TAB_HANDLE_" . Web::Reactor::HTML::Utils::html_next_id();
  my $tab_id    = $opt{ 'TAB_ID'    } || "RE_TAB_" . Web::Reactor::HTML::Utils::html_next_id();

  push @{ $self->{ 'TABS' } }, $tab_id;

  my $class_on  = $self->{ 'OPT' }{ 'CLASS_ON' };
  my $class_off = $self->{ 'OPT' }{ 'CLASS_OFF' };

  my $handle;
  my $text;

  my $display = $on ? '' : "style='display: none;'";
  my $handle_class = $on ? $class_on : $class_off;
  $self->{ 'ACTIVE_TAB_ID' } = $tab_id if $on;

  $handle = qq{ CLASS='$handle_class' ID=$handle_id onclick='re_tab_activate( "$tab_controller_id", "$tab_id" )' };
  $text   = qq{ <$et ID=$tab_id CLASS='$class' TAB_HANDLE_ID='$handle_id' $display $arg>$content</$et> };

  return ( $handle, $text );
}

# puts tab controller inside html accumulator

sub finish
{
  my $self    = shift;

  my $html;

  my $tab_controller_id = $self->{ 'TAB_ID' };
  my $tabs_list         = join ',', @{ $self->{ 'TABS' } };
  my $active_tab_id     = $self->{ 'ACTIVE_TAB_ID' };

  my $class_on    = $self->{ 'OPT' }{ 'CLASS_ON' };
  my $class_off   = $self->{ 'OPT' }{ 'CLASS_OFF' };
  my $act_feed_id = $self->{ 'OPT' }{ 'ACTIVE_TAB_FORM_FEEDBACK_ID' };

  my $act_feed_input;
  if( ! $act_feed_id )
    {
    $act_feed_id = "$tab_controller_id\_ACTIVE";
    $act_feed_input = "<input TYPE=hidden ID=$act_feed_id VALUE=$active_tab_id>";
    }
  # FIXME: <input hidden> active tab element keeper to be optionally outside element (by id)
  $html = qq{
<DIV ID=$tab_controller_id STYLE='display: none;' TABS_LIST='$tabs_list' CLASS_ON='$class_on' CLASS_OFF='$class_off' ACTIVE_TAB_FORM_FEEDBACK_ID='$act_feed_id'>
  $act_feed_input

  <script type="text/javascript">

    var atf = document.getElementById( "$act_feed_id" );

    var active_tab_id = atf.value;
    if( active_tab_id )
      re_tab_activate( "$tab_controller_id", active_tab_id );

  </script>

</DIV>
};

  my $reo = $self->{ 'REO_REACTOR' };
  $reo->html_content_accumulator( 'ACCUMULATOR_HTML', $html );
}

1;
