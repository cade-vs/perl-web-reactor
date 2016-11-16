##############################################################################
##
##  Web::Reactor application machinery
##  2013-2016 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
##
## HTML Utils
##
##############################################################################
package Web::Reactor::HTML::Utils;
use Exporter;
our @ISA = qw( Exporter );
our @EXPORT = qw(
                html_escape
                html_table

                html_ftree

                html_hover_layer
                html_popup_layer

                html_alink

                html_tabs_table
                );
use strict;
use Exception::Sink;
use Data::Tools;
use Web::Reactor::HTML::Tab;
my %HTML_ESCAPES = (
                   '>' => '&gt;',
                   '<' => '&lt;',
                   );

##############################################################################

sub html_escape
{
  my $s = shift;
  $s =~ s/([<>])/$HTML_ESCAPES{ $1 }/ge;
  return $s;
}

##############################################################################


=pod

takes two-dimensional perl array and formats it in html table

DEMO:

  my @data;

  push @data, [
              '123',
              { ARGS => 'align=right', DATA => 'asd' },
              'qwe'
              ];
  push @data, {
                CLASS => 'grid',
                DATA => [
                        '123',
                        { ARGS  => 'align=center', DATA => 'asd' },
                        { CLASS => 'fmt-img',      DATA => 'qwe' },
                        ],
              };
  push @data, {
              # columns class list (CCL), used only for current row
              # use PCCL for permanent (for the rest of the rows)
              CCL  => [ 'view-name-h', 'view-value-h' ],
              DATA => [ 'name',        'value'        ],
              };
  push @data, {
              PCCL  => [ 'view-name-h', 'view-value-h' ],
              # set only PCCL and skip this row
              SKIP  => YES,
              };

  $text .= html_table( \@data, ARGS => 'width=100%' );

=cut


sub html_table
{
  my $rows = shift;
  my %opt  = @_;

  hash_uc_ipl( \%opt );

  # t_* table attr
  # r_* row   attr
  # c_* cell  attr

  my $t_args;
  $t_args ||= $opt{ 'ARGS' };
  $t_args ||= 'class=' . $opt{ 'CLASS' } if $opt{ 'CLASS' };

  my $tr1 = $opt{ 'TR1' } || $opt{ 'TR-1' } || 'tr-1';
  my $tr2 = $opt{ 'TR2' } || $opt{ 'TR-2' } || 'tr-2';
  my $trh = $opt{ 'TRH' };
  my $tdh = $opt{ 'TDH' };

  my $ccl  = $opt{ 'CCL'  } || undef;
  my $pccl = $opt{ 'PCCL' } || undef;

  my $t_cmt = $opt{ 'COMMENT' };

  my $text;
  $text .= "\n\n\n";
  $text .= "<!--- BEGIN TABLE: $t_cmt --->\n" if $t_cmt;
  $text .= "<table $t_args>\n<tbody>\n";

  my $r_class = $tr1;

  my $row_num = 0;
  for my $row ( @$rows )
    {
    my $cols;
    $r_class = $r_class eq $tr1 ? $tr2 : $tr1;
    my $r_args;

    $r_class = $trh if $trh and $row_num == 0;

    if ( ! ref( $row ) ) # SCALAR
      {
      # fallback
      $row = [ $row ];
      }

    if ( ref( $row ) eq 'ARRAY' )
      {
      $cols  = $row;
      $r_args = "class='$r_class'";
      }
    elsif ( ref( $row ) eq 'HASH' )
      {
      $row      = hash_uc( $row );
      $cols     = $row->{ 'DATA' };
      $r_args ||= $row->{ 'ARGS' };
      $r_args ||= 'class=' . ( $row->{ 'CLASS' } || $r_class );
      $ccl      = $row->{ 'CCL'  } if $row->{ 'CCL'  };
      $pccl     = $row->{ 'PCCL' } if $row->{ 'PCCL' };

      next if $row->{ 'SKIP' };
      }
    else
      {
      boom "invalid row type, expected HASH or ARRAY reference";
      next;
      }

    $text  .= "  <tr $r_args>\n";

    $ccl = $pccl if $pccl and ! $ccl; # use permanent cols class list if permanent specified and not local one

    my $col_num = 0;
    for my $cell ( @$cols )
      {
      my $c_class;
      my $c_args;
      my $val;

      $c_class = $tdh if $tdh and $row_num == 0;
      $c_class = $ccl->[ $col_num ] if $ccl and $ccl->[ $col_num ];

      if ( ! ref( $cell ) ) # SCALAR
        {
        $val = $cell;
        }
      elsif( ref( $cell ) eq 'HASH' )
        {
        $cell    = hash_uc( $cell );
        $val     = $cell->{ 'DATA' };
        $c_args  = $cell->{ 'ARGS' };
        $c_args .= " class='" . $cell->{ 'CLASS' } . "'" if $cell->{ 'CLASS' };
        $c_args .= " width='" . $cell->{ 'WIDTH' } . "'" if $cell->{ 'WIDTH' };
        }
      else
        {
        # FIXME: carp croak boom :)
        next;
        }

      $c_args ||= "class='" . $c_class . "'";
      $text .= "    <td $c_args>$val</td>\n";
      $col_num++;
      }

    $ccl = undef;

    $text  .= "  </tr>\n";
    $row_num++;
    }

  $text .= "</tbody>\n</table>\n";
  $text .= "<!--- END TABLE: $t_cmt --->\n" if $t_cmt;
  $text .= "\n\n\n";

  return $text;
}

##############################################################################

=pod

flat tree, represented by single table with rows

DEMO:

  my $a = [
          'opa',
          'tralala',
          'heyo',
          'yoyo',
          'didi',
          {
          TITLE => 'TITLE:opa',
          DATA  => [
                     'tralala',
                     'heyo',
                     {
                     TITLE => 'TITLE:sesssil',
                     DATA  => [
                              'tralala',
                              'heyo',
                              'yoyo',
                              'didi',
                              ],
                     },
                     'yoyo',
                     'didi',
                     ],
          },
          'heyo',
          'yoyo',
          ];

  print html_ftree( $a, 'ARGS' => 'cellpadding=10 width=100% border=0' );

=cut

my $ftree_item_id;
sub html_ftree
{
  my $data = shift;
  my %opt  = @_;

  my $t_args;
  $t_args ||= $opt{ 'ARGS' };
  $t_args ||= 'class=' . $opt{ 'CLASS' } if $opt{ 'CLASS' };

  $ftree_item_id++;

  my $ftree_table_id = "FTREE_TABLE_$ftree_item_id";

  my $html;

  $html .= "<table id=$ftree_table_id $t_args>";
  $html .= "\n";

  $html .= __html_ftree_branch( $data, $ftree_table_id, $ftree_table_id . '.' );

  $html .= "</table>";
  $html .= "\n";

  return $html;
}

sub __html_ftree_branch
{
  my $data           = shift;
  my $ftree_table_id = shift;
  my $branch_id      = shift;
  my $level          = shift;

  my $html;

  for my $row ( @$data )
    {
    my $label;
    my $data;

    my $r_args; # row args

    if( ref( $row ) eq 'HASH' )
      {
      $label = $row->{ 'LABEL' };
      $data  = $row->{ 'DATA'  };

      $r_args ||= $row->{ 'ARGS' };
      $r_args ||= 'class=' . $row->{ 'CLASS' } if $row->{ 'CLASS' };
      }
    else
      {
      $label = $row;
      }

    $ftree_item_id++;

    my $row_id = $branch_id . $ftree_item_id . '.';

    # $label = "($row_id) $label"; # DEBUG

    my $hidden = $level > 0 ? "style='display: none'" : undef;

    if( ref( $data ) eq 'ARRAY' )
      {
      my $open_code = qq{ onclick='ftree_click( "$ftree_table_id", "$row_id" )' };
      $html .= "<tr id=$row_id $open_code $hidden $r_args><td>$label</td></tr>";
      $html .= __html_ftree_branch( $data, $ftree_table_id, $row_id, $level + 1 );
      }
    else
      {
      $html .= "<tr id=$row_id $hidden $r_args><td>$label</td></tr>";
      }
    $html .= "\n";
    }

  return $html;
}

##############################################################################

sub html_hover_layer
{
  my $reo = shift;
  my %opt  = @_;

  if( ref( $reo ) !~ /^Web::Reactor(::|$)/ )
    {
    boom "missing REO reactor object";
    }

  if( @_ == 1 )
    {
    %opt = ( VALUE => shift() );
    }

  my $value = $opt{ 'VALUE' };
  my $class = $opt{ 'CLASS' } || 'hover-layer';
  my $delay = $opt{ 'DELAY' } || 250;

  my $hover_layer_counter = $reo->html_new_id();
  my $hover_layer_id = "R_HOVER_LAYER_$hover_layer_counter";

  my $html;
  my $handle;

  $handle = qq{ onmouseover='hint_layer_show_delay( this,"$hover_layer_id", $delay, event )' };
  $html   = qq{ <div class=$class id="$hover_layer_id">$value</div> };

  $reo->html_content_accumulator( 'ACCUMULATOR_HTML', $html );

  return $handle;
}

##############################################################################

sub html_popup_layer
{
  my $reo = shift;
  my %opt  = @_;

  if( ref( $reo ) !~ /^Web::Reactor(::|$)/ )
    {
    boom "missing REO reactor object";
    }

  if( @_ == 1 )
    {
    %opt = ( VALUE => shift() );
    }

  my $value  = $opt{ 'VALUE' };
  my $class  = $opt{ 'CLASS' } || 'popup-layer';
  my $delay  = $opt{ 'DELAY' } || 150;
  my $show   = $opt{ 'SHOW' } || 'CLICK';
  my $title  = $opt{ 'TITLE' };
  my $single = $opt{ 'SINGLE' } ? 1 : 0;
  my $title_class = $opt{ 'TITLE_CLASS' } || $class . '-title';

  my $type  = uc $opt{ 'TYPE' };

  my $event;
  my $func = 'return popup_layer_toggle( this, single )';

  $event = $type eq 'CONTEXT' ? 'oncontextmenu' : ( $show eq 'CLICK' ? 'onclick' : 'onmouseover' );
  $func  = "return popup_layer_show_context_mouse( this, event )"     if $type eq 'CONTEXT';
  $func  = "return popup_layer_toggle_with_autohide( this, $single )" if $type =~ 'AUTOHIDE2?';
  $func  = "return popup_layer_show_mouse( this, $single )"           if $show eq 'MOUSE';

  my $popup_layer_id_counter = $reo->html_new_id();
  my $popup_layer_id = "R_POPUP_LAYER_$popup_layer_id_counter";

  my $html;
  my $handle;

  $handle  = qq{ popup_layer_id="$popup_layer_id" $event="$func" };
###  $handle .= qq{ onmouseout="$func" } if $event eq 'onmouseover';
  $html   .= qq{
                <div class=$class id="$popup_layer_id">
                <table cellspacing=0 cellpadding=5>
              };
  if( $title )
    {
    my $closebox = $type eq 'AUTOHIDE' ? '&nbsp;' : qq{ <img popup_layer_id="$popup_layer_id" onclick="popup_layer_hide( this )" src=img/close.png> };
    $html .= qq{
                 <tr>
                     <td class=$title_class><b>$title</b></td>
                     <td align=right class=$title_class>$closebox</td>
                 </tr>
               };
    }
  $html .= qq{
                 <tr>
                     <td colspan=2>$value</td>
                 </tr>
               </table>
               </div>
             };

  if ( $opt{ 'NO_ACCUMULATOR' } )
    {
    return ( $handle, $html );
    }
  else
    {
    $reo->html_content_accumulator( 'ACCUMULATOR_HTML', $html );
    return $handle;
    }
}

##############################################################################

sub html_alink
{
  my $reo   =    shift;
  my $type  = lc shift;
  my $value =    shift;
  my $opts  =    shift;
  my @args  = @_;

  my $href = $reo->args_type( $type, @args );

  my $hint = $opts->{ 'HINT' };
  my $hl_handle = html_hover_layer( $reo, VALUE => $hint, DELAY => 250 ) if $hint;
  
  my $class = $opts->{ 'CLASS' };
  my $a_class = "class='$class'";

  return "<a $a_class href=?_=$href $hl_handle>$value</a>";
}

##############################################################################

=pod

sub html_tabs_table

arguments: array_ref, opt_hash

array_ref is list of hash refs with this content:

    LABEL          -- label text for the this tab handle
    LABEL_TD_ARGS  -- further optional arguments for the label TD
    TEXT           -- text to show when tab handle clicked
    TEXT_TD_ARGS   -- TD element args, same as above
    ON             -- if true, this tab will be initially visible
    TAB_ID         -- html id for this tab

opt_hash is inline with the following items:

    LABELS_TABLE_ARGS -- args for the table containing labels
    TEXT_TABLE_ARGS   -- same as above

    LABEL_CLASS_ON    -- active TD class for tab handle labels
    LABEL_CLASS_OFF   -- inactive TD class for tab handle labels

    ARGS              -- args for containing TABLE element
    VERTICAL          -- if true, tabs will be vertical

    ACTIVE_TAB_FORM_FEEDBACK_ID -- html INPUT element to hold active tab id

example:

  my @tabs;

  for my $z ( 1 .. 5 )
    {
    push @tabs, {
                  LABEL         => "TAB $z",
                  TEXT          => "$z " x 128,
                  LABEL_TD_ARGS => "class=tab-label style='cursor: pointer;'",
                  TEXT_TD_ARGS  => "class=tab-text",
                };
    }

  $html = html_tabs_table( \@tabs, ARGS => "width=70% border=2", VERTICAL => 1 );

=cut

sub html_tabs_table
{
  my $reo = shift;
  my $ar  = shift;
  my %opt = @_;

  my $vert = $opt{ 'VERTICAL' };

  my @label_td;
  my @text_td;

  my $cnt = @$ar;

  my $class_on  = $opt{ 'LABEL_CLASS_ON' };
  my $class_off = $opt{ 'LABEL_CLASS_OFF' };

  my $tab = new Web::Reactor::HTML::Tab(
                                   REO_REACTOR => $reo,
                                   CLASS_ON    => $class_on,
                                   CLASS_OFF   => $class_off,
                                   ACTIVE_TAB_FORM_FEEDBACK_ID => $opt{ 'ACTIVE_TAB_FORM_FEEDBACK_ID' },
                                 );

  for my $e ( @$ar )
    {
    my $label      = $e->{ 'LABEL'         };
    my $label_args = $e->{ 'LABEL_TD_ARGS' };
    my $text       = $e->{ 'TEXT'          };
    my $text_args  = $e->{ 'TEXT_TD_ARGS'  };
    my $on         = $e->{ 'ON'            };
    my $tab_id     = $e->{ 'TAB_ID'        };

    if( ! $vert and $label_args !~ /WIDTH=/i )
      {
      my $w = int( 100 / $cnt );
      $label_args .= " WIDTH=$w%";
      }

    my ( $tab_handle, $tab_html ) = $tab->add( "<TD $text_args>$text</td>", TYPE => 'TR', ON => $on, TAB_ID => $tab_id );

    push @label_td, "<TD $label_args $tab_handle>$label</TD>";
    push @text_td,  $tab_html;
    }
  $tab->finish();

  my $args  = $opt{ 'ARGS' };

  my $text;

  $text .= "<TABLE $args>\n";
  if( $vert )
    {
    my $label_args  = $opt{ 'VERT_LABEL_TD_ARGS' };
    my $text_args   = $opt{ 'VERT_TEXT_TD_ARGS' };

    $label_args .= " WIDTH=50%" if $label_args !~ /WIDTH=/i;

    $text .= "<TR>";
    $text .= "<TD $label_args><TABLE WIDTH=100%>";
    $text .= "<TR>" . join( "</TR><TR>", @label_td ) . "</TR>";
    $text .= "</TABLE></TD>";

    $text .= "<TD $text_args><TABLE WIDTH=100%>";
    $text .= join( '', @text_td );
    $text .= "</TABLE></TD>";

    $text .= "</TR>";
    }
  else
    {
    my $labels_table_args = $opt{ 'LABELS_TABLE_ARGS' };
    $labels_table_args .= " WIDTH=100%" if $labels_table_args !~ /WIDTH=/i;
    $text .= "<TR><TD><TABLE $labels_table_args><TR>" . join( '', @label_td ) . "</TR></TABLE></TD></TR>";
    $text .= join( '', @text_td );
    }
  $text .= "</TABLE>\n";


  return $text;
}

##############################################################################
1;
##############################################################################

