##############################################################################
##
##  Web::Reactor application machinery
##  2013-2016 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
package Web::Reactor::Actions::Base::expire_hint;
use strict;

sub main
{
  my $reo = shift;

  #return undef unless $reo->is_logged_in();
  return undef unless $reo->get_user_session_expire_time();

  my $exp_time = $reo->get_user_session_expire_time_in() or return undef;

  my $text;
  
  $text .= <<END;

  <small id=small_expire_time_hint class=small_expire_time_hint></small>

  <script type="text/javascript">

  var page_expire_time = $exp_time;
  var page_expire_timeout = 5;

  function print_expire_time()
  {
    var el = document.getElementById( 'small_expire_time_hint' );

    if( page_expire_time > 0 )
      {
      var m = Math.floor( page_expire_time / 60 );
      var s = Math.floor( page_expire_time % 60 );
      el.innerHTML = 'page will expire in ' + m + 'min ' + s + 'sec';
      setTimeout( 'print_expire_time()', page_expire_timeout * 1000 );
      page_expire_time -= page_expire_timeout;
      }
    else
      {
      el.innerHTML = 'Page expired!'
      }
  }

  print_expire_time();

  </script>


END

  return $text;
};

1;
