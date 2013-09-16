package Web::Reactor::Actions::demo::getimg;
use strict;
use Data::Dumper;
use Web::Reactor::HTML::FormEngine;

sub main
{
  my $reo = shift;

  open( my $fi, '/tmp/img.jpg' );
  local $/ = undef;
  my $data = <$fi>;
  close( $fi );
  
  $reo->portray( $data, 'jpeg' );
}

1;
