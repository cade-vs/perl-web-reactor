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
## HTML Layout
##
##############################################################################
package Web::Reactor::HTML::Layout;
use strict;

use Exception::Sink;
use Data::Tools;

use Exporter;
our @ISA    = qw( Exporter );
our @EXPORT = qw( 

                html_table

                html_layout_grid
                html_layout_hbox
                html_layout_vbox

                html_layout_hbox_flex

                html_layout_2lr
                html_layout_2lr_flex
                
                
                html_hbox
                html_vbox

                );

### LAYOUT ###################################################################

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
              SKIP  => 1,
              # row will also be skipped if missing DATA, regardless of SKIP
              };
  push @data, [ \'grid', '123', 'asd' ];          # scalar ref first: row class, then the cells
  push @data, [ { CID => '1.2' }, '123', 'asd' ]; # hash ref first: row options, then the cells
  push @data, {
              '-NODISPLAY' => 1,                                # rendered hidden
              DATA         => [ { WIDTH => '20%', DATA => 'w' } ], # cell width attribute
              };

  $text .= html_table( \@data, ARGS => 'width=100%' );

table options:

  ARGS     -- raw table attributes
  CLASS    -- table class, used when there are no ARGS
  TR1, TR2 -- row stripe classes (default tr-1, tr-2)
  TRH, TDH -- class of the first rendered row and of its cells
  CCL      -- columns class list for the first rendered row only
  PCCL     -- columns class list for all rows
  COMMENT  -- html comment around the table

row keys (hash row):

  DATA        -- the cells (array ref), a row without DATA is skipped
  CLASS       -- row class, else the stripe class
  ARGS        -- raw row attributes, a class in it wins over the stripe class
                 and a style in it gets display: none merged for -NODISPLAY
  CID         -- collapse id, see below
  CCL, PCCL   -- columns class list for this row / from this row on
  SKIP        -- skip the row, it only sets PCCL
  -NODISPLAY  -- the row is rendered hidden (display: none)

cell keys (hash cell):

  DATA   -- cell text
  CLASS  -- cell class, else the column class
  ARGS   -- raw cell attributes, a class in it wins over the column class
  WIDTH  -- cell width attribute


collapse identifier for rows

  CID=id.id.id+

the first cell of a row with a CID toggles the rows whose CID starts with it
(ctable_row_click() in js/reactor.js, the page must load it). nested rows
start visible unless they are also marked -NODISPLAY.

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
  $t_args ||= "class='" . $opt{ 'CLASS' } . "'" if $opt{ 'CLASS' };

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

  my $r_class = $tr2; # class of the last rendered row, so the first one gets TR1

  my $row_num = 0;
  for my $row_in ( @$rows )
    {
    my $row = $row_in; # a copy, the caller's data is not changed
    my $cols;
    my $row_class = ( $trh and $row_num == 0 ) ? $trh : ( $r_class eq $tr1 ? $tr2 : $tr1 );
    my $r_args;
    my $cid;
    my $display;

    if ( ! ref( $row ) ) # SCALAR
      {
      # fallback
      $row = [ $row ];
      }

    my $rr0 = ref $row eq 'ARRAY' ? ref $row->[ 0 ] : 0; # row ref at pos 0
    if( $rr0 )
      {
      $row = { CLASS => ${ $row->[ 0 ] }, DATA => [ @{ $row }[ 1 .. @$row - 1 ] ] } if $rr0 eq 'SCALAR';
      $row = { %{ $row->[ 0 ] }, DATA => [ @{ $row }[ 1 .. @$row - 1 ] ] } if $rr0 eq 'HASH';
      }

    if ( ref( $row ) eq 'ARRAY' )
      {
      $cols  = $row;
      $r_args = "class='$row_class'";
      }
    elsif ( ref( $row ) eq 'HASH' )
      {
      $row      = hash_uc( $row );
      $display  = "style='display: none'" if $row->{ '-NODISPLAY' };
      $cols     = $row->{ 'DATA'   };
      $cid      = $row->{ 'CID'    };
      $r_args  = $row->{ 'ARGS'   };
      # the row CLASS or the stripe class, unless ARGS already sets one
      my $rc = $row->{ 'CLASS' } || $row_class;
      $r_args .= " class='$rc'" if $rc ne '' and $r_args !~ /(?<![\w-])class\s*=/i; # TODO: FIXME: !!! move to html_element
      $pccl     = $row->{ 'PCCL' } if $row->{ 'PCCL' };

      # a skipped row sets only PCCL, its own CCL is not used and the table
      # CCL option stays for the first rendered row
      next if $row->{ 'SKIP' } or ! $cols;

      $ccl      = $row->{ 'CCL'  } if $row->{ 'CCL'  };
      }
    else
      {
      boom "invalid row type, expected HASH or ARRAY reference";
      }

    $r_class = $row_class; # the row is rendered, the stripe moves on

    $r_args .= qq{ data-cid='$cid'} if $cid;
    if( $display )
      {
      # into a style already in ARGS (quoted or not), so the row has only one style attribute
      $r_args =~ s/(?<![\w-])style\s*=\s*(['"])/style=$1display: none; /i
        or $r_args =~ s/(?<![\w-])style\s*=\s*([^\s'">]+)/style='display: none; $1'/i
        or $r_args .= " $display";
      }
    $text  .= "  <tr $r_args>\n";

    $ccl = $pccl if $pccl and ! $ccl; # use permanent cols class list if permanent specified and not local one

    my $cn = 0; # column index number
    for my $cell_in ( @$cols )
      {
      my $cell = $cell_in; # a copy, the caller's data is not changed
      my $c_class;
      my $c_args;
      my $val;

      $c_class = $tdh if $tdh and $row_num == 0;
      $c_class = $ccl->[ $cn ] if $ccl and $ccl->[ $cn ];

      if ( ! ref( $cell ) ) # SCALAR
        {
        $val = $cell;
        }
      elsif( ref( $cell ) eq 'HASH' )
        {
        $cell    = hash_uc( $cell );
        $val     = $cell->{ 'DATA' };
        $c_args  = $cell->{ 'ARGS' };
        $c_class = $cell->{ 'CLASS' } if $cell->{ 'CLASS' };
        $c_args .= " width='" . $cell->{ 'WIDTH' } . "'" if $cell->{ 'WIDTH' };
        }
      elsif( ref( $cell ) eq 'ARRAY' )
        {
        # FIXME: [ format, value ] cells, the format (first element) is not
        #        implemented yet, only the value is used
        $val = $cell->[ 1 ];
        }
      else
        {
        # FIXME: carp croak boom :)
        next;
        }

      # the cell CLASS or the column class, unless ARGS already sets one
      $c_args .= " class='$c_class'" if $c_class ne '' and $c_args !~ /(?<![\w-])class\s*=/i;
      $c_args .= qq{ onclick='ctable_row_click( this )' data-cid='$cid'} if $cn == 0 and $cid;
      $text .= "    <td $c_args>$val</td>\n";
      $cn++;
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

sub html_layout_grid
{
  my $data = shift;
  
  my $text;
  
  $text .= "<table border=0 cellspacing=0 cellpadding=0 width=100%>";

  for my $row ( @$data )
    {
    my $row_args;
    my $cols = $row; # copies, the caller's data is not changed
    if( ref( $row ) eq 'HASH' )
      {
      $row_args = $row->{ 'ARGS' };
      $cols     = $row->{ 'DATA' };
      }
    
    $text .= "<tr $row_args>";
    for my $col ( @$cols )
      {
      my $col_args;
      my $val = $col;
      if( ref( $col ) eq 'HASH' )
        {
        $col_args = $col->{ 'ARGS' };
        $val      = $col->{ 'DATA' };
        }
      $text .= "<td $col_args>$val</td>";
      }
    $text .= "</tr>";
    }
  
  $text .= "</table>";
  
  return $text;
}

sub html_layout_hbox
{
  my $data = shift;
  
  return html_layout_grid( [ { DATA => $data, ARGS => "valign=top" } ] );
}

sub html_layout_hbox_flex
{
  my $opt;
  $opt = ${ shift() } if ref( $_[0] ) eq 'SCALAR';
  my @data = @_;
  
  my @opt = split /,/, $opt;
  
  my $text;
  
  $text .= "<div style='display: flex;'>";
  
  while( @data )
    {
    my $data = shift @data;
    my $flex = shift @opt || 1;
    $text .= "<div style='flex:$flex; padding: 1em'>$data</div>";
    }
  
  $text .= "</div>";
  
  return $text;
}

sub html_layout_vbox
{
  my $data = shift;
  
  my @data;
  push @data, [ $_ ] for @$data;

  return html_layout_grid( \@data );
}

#-----------------------------------------------------------------------------

=pod

formats pair for left/right boxes aligned within specific width

format is: 'left-spec=right-spec'

left-spec  is formatting for the left data.
right-spec is formatting for the right data.

both specs are:

align-symbol . width-len%

examples:

<50%=50%>   -- left is left aligned, right is right aligned, equal length
<=>         -- the same
>20=>       -- left is right aligned, 20% width, right is right aligned, 80% 
=1%         -- same as 99=1 or 99%=1% (no alignment)

using '==' instead of '=' enables no-word-wrap style

=cut

sub html_layout_2lr
{
  my $ld = shift; # left data
  my $rd = shift; # right data
  my $fm = shift || '<=>'; # format: '[<>]nn%=nn%[<>]'
  
  my $la; # left  align
  my $ra; # right align
  my $lw; # left  width
  my $rw; # right width
  my $nw; # no-wrap
  if( $fm =~ /^([<>]?)((\d+)%?)?=(=)?((\d+)%?)?([<>]?)$/ )
    {
    $la = $1;
    $lw = $3;
    $nw = $4;
    $rw = $6;
    $ra = $7;
    }
  else
    {
    boom "invalid format [$fm]";
    }  
  
  $la = { '<' => 'align=left', '>' => 'align=right' }->{ $la };
  $ra = { '<' => 'align=left', '>' => 'align=right' }->{ $ra };

  $lw = $rw = 50 if $lw == 0 and $rw == 0;
  $lw = int( 100 - $rw ) if $lw == 0 and $rw > 0;
  $rw = int( 100 - $lw ) if $rw == 0 and $lw > 0;
  
  $lw = "width=$lw%";
  $rw = "width=$rw%";

  $nw = "style='white-space: nowrap'" if $nw;

  return "<table width=100% cellspacing=0 cellpadding=0 border=0 $nw><tr><td $la $lw>$ld</td><td $ra $rw>$rd</td></tr></table>";
}

sub html_layout_2lr_flex
{
  my $ld = shift; # left data
  my $rd = shift; # right data
  my $fm = shift; # format: '[<>]nn%=nn%[<>]', see html_layout_2lr()

  # without a format: left takes the room, right is as narrow as its content
  return "<div style='display: flex;'><div style='flex: 99; text-align: left; align-content: center;'>$ld</div><div style='flex: 1; text-align: right; white-space: nowrap; align-content: center;'>$rd</div></div>" unless $fm;

  my $la;  # left  align
  my $ra;  # right align
  my $lw;  # left  width
  my $rw;  # right width
  my $nw;  # no-wrap
  my $acl; # left  content-align
  my $acr; # right content-align
  
  if( $fm =~ /^([<>]?)((\d+)%?)?=(=)?((\d+)%?)?([<>]?)$/ )
    {
    $la = $1;
    $lw = $3;
    $nw = $4;
    $rw = $6;
    $ra = $7;
    }
  else
    {
    boom "invalid format [$fm]";
    }  
  
  $acl = "align-content: center";
  $acr = "align-content: center";
  
  $la = { '<' => 'text-align: left', '>' => 'text-align: right' }->{ $la };
  $ra = { '<' => 'text-align: left', '>' => 'text-align: right' }->{ $ra };

  $lw = $rw = 50 if $lw == 0 and $rw == 0;
  $lw = int( 100 - $rw ) if $lw == 0 and $rw > 0;
  $rw = int( 100 - $lw ) if $rw == 0 and $lw > 0;
  
  $lw = "flex: $lw";
  $rw = "flex: $rw";

  $nw = "white-space: nowrap" if $nw;

  my $ls = join '; ', grep { $_ ne '' } ( $lw, $la, $acl, $nw );
  my $rs = join '; ', grep { $_ ne '' } ( $rw, $ra, $acr, $nw );

  return "<div style='display: flex;'><div style='$ls'>$ld</div><div style='$rs'>$rd</div></div>";
}

##############################################################################

=pod

html_hbox( $format, @values ), html_vbox( $format, @values )

returns a flex box (row or column) with one cell per value. the format has
one spec per cell, separated by "," or ";":

  class:spec  -- optional class name for the cell, before ":"
  <  >  |     -- text align left, right, center
  n           -- no wrap
  w           -- wrap
  p           -- preformatted (white-space: pre)
  =           -- the cell takes all the free room
  xN          -- the spec is used for N cells

cells beyond the specs get flex 1, centered content.

example:

  html_hbox( 'label:<n,=,btn:>x2', $label, $text, $ok, $cancel );

=cut

my %__HTML_BOX_ALIGN = (
                       '>' => 'text-align: right; ',
                       '<' => 'text-align: left; ',
                       '|' => 'text-align: center; ',
                       );

my %__HTML_BOX_FMT_CACHE;

sub __html_box_fmt_parse
{
  my $fmt = shift;
  my @fmt;

  return $__HTML_BOX_FMT_CACHE{ $fmt } if exists $__HTML_BOX_FMT_CACHE{ $fmt };

#print "[$fmt]\n";
  for my $f ( split /[,;]/, $fmt )
    {
#print "    [$f]\n";
    my $arg;
    # the class prefix is taken off first, so its letters are not read as flags
    $arg .= "class='$1' "            if $f =~ s/^([^:]+)://;

    my $wid = 1;
    $wid  = 1000                    if $f =~ /=/;

    my $sty;
    $sty .= "white-space: nowrap; " if $f =~ /n/i;
    $sty .= "white-space: normal; " if $f =~ /w/i;
    $sty .= "white-space:    pre; " if $f =~ /p/i;
    $sty .= $__HTML_BOX_ALIGN{ $1 } if $f =~ /([<>\|])/;

    $sty .= "align-content: center; ";
    
    my $rep = 1;
    $rep = $1 if $f =~ /x(\d+)/;
    
    my $div = "$arg style='flex: $wid; $sty'";
#print "    {$div}\n\n";
    push @fmt, $div for 1 .. $rep;
    }
  
  $__HTML_BOX_FMT_CACHE{ $fmt } = \@fmt; # FIXME: TODO: avoid overfill
  return \@fmt;
}

sub __html_hbox
{
  my $dir = shift;
  my $fmt = shift;
 
  $fmt = __html_box_fmt_parse( $fmt );
  
  my $text;
  
  $text .= "<div style='display: flex; flex-direction: $dir; align-content: center; '>\n";
  my $c;
  for my $d ( @_ )
    {
    # cells beyond the format specs get the default spec
    my $cf = $fmt->[ $c ] // "style='flex: 1; align-content: center; '";
    $text .= "<div $cf>$d</div>\n";
    $c++;
    }
  $text .= "</div>\n";
  
  return $text;
}

sub html_hbox
{
  return __html_hbox( 'row', @_ );
}

sub html_vbox
{
  return __html_hbox( 'column', @_ );
}

### EOF ######################################################################
1;
