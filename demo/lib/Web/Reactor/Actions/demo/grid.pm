package Reactor::Actions::demo::grid;
use strict;
use Data::Dumper;
use Web::Reactor::HTML::FormEngine;

sub main
{
  my $reo = shift;

  my $text;

  my $back_href = $reo->args_back();
  $text .= "<a href=?_=$back_href>back</a><p>";

  my $view_href = $reo->args_new( _PN => 'view', TABLE => 'testtable', ID => '123', );
  $text .= "<a href=?_=$view_href>view</a> | this | is | grid<br>";

  my $view_href = $reo->args_new( _PN => 'view', TABLE => 'testtable', ID => '567', );
  $text .= "<a href=?_=$view_href>view</a> | another | grid | grid<br>";

  return $text;
}

1;
