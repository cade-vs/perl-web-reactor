##############################################################################
##
##  Web::Reactor application machinery
##  2013 (c) Vladi Belperchinov-Shabanski "Cade"
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
                );
use strict;
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
      $r_args = "class=$r_class";
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
      # FIXME: carp croak boom :)
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
        $c_args ||= $cell->{ 'ARGS' };
        $c_args ||= 'class=' . $cell->{ 'CLASS' } if $cell->{ 'CLASS' };
        }
      else
        {
        # FIXME: carp croak boom :)
        next;
        }

      $c_args ||= 'class=' . $c_class;
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
1;
##############################################################################

