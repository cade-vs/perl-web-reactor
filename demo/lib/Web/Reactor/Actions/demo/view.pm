##############################################################################
##
##  Web::Reactor application machinery
##  2013-2016 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
package Web::Reactor::Actions::demo::view;
use strict;
use Data::Dumper;
use Web::Reactor::HTML::FormEngine;

sub main
{
  my $reo = shift;

  my $text;

  my $e = $reo->get_safe_input();
  my $table = $e->{ 'TABLE' };
  my $id    = $e->{ 'ID'    };


  my $back_href = $reo->args_back();
  $text .= "<a href=?_=$back_href>back</a><p>";

  $text .= "show record $id from table $table<p>";

  return $text;
}

1;
