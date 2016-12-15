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
## HTML Layout
##
##############################################################################
package Web::Reactor::HTML::Layout;
use strict;

use Exception::Sink;
use Data::Tools;
use Web::Reactor::HTML::Utils;

use Exporter;
our @ISA    = qw( Exporter );
our @EXPORT = qw( 

                html_layout_grid
                html_layout_hbox
                html_layout_vbox

                );

### LAYOUT ###################################################################

sub html_layout_grid
{
  my $data = shift;
  
  my $text;
  
  $text .= "<table border=0 cellspacing=0 cellpadding=0 width=100%>";

  for my $r ( @$data )
    {
    $text .= "<tr>";
    for my $c ( @$r )
      {
      $text .= "<td>$c</td>";
      }
    $text .= "</tr>";
    }
  
  $text .= "</table>";
  
  return $text;
}

sub html_layout_hbox
{
  my $data = shift;
  
  return html_layout_grid( [ $data ] );
}

sub html_layout_vbox
{
  my $data = shift;
  
  my @data;
  push @data, [ $_ ] for @$data;

  return html_layout_grid( \@data );
}

### EOF ######################################################################
1;
