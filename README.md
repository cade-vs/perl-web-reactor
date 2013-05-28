NAME
    Web::Reactor perl-based web application machinery.

SYNOPSIS
    Startup CGI script example:

      #!/usr/bin/perl
      use strict;
      use lib '/opt/perl/reactor/lib'; # if Reactor is custom location installed
      use Web::Reactor;

      my %cfg = (
                'APP_NAME'     => 'demo',
                'APP_ROOT'     => '/opt/reactor/demo/',
                'LIB_DIRS'     => [ '/opt/reactor/demo/lib/'  ],
                'HTML_DIRS'    => [ '/opt/reactor/demo/html/' ],
                'SESS_VAR_DIR' => '/opt/reactor/demo/var/sess/',
                'DEBUG'        => 4,
                );

      eval { new Web::Reactor( %cfg )->run(); };
      if( $@ )
        {
        print STDERR "REACTOR CGI EXCEPTION: $@";
        print "content-type: text/html\n\nsystem is temporary unavailable";
        }

    HTML page file example:

      <#html_header>

      <$app_name>

      <#menu>

      testing page html file

      action test: <&test>

      <#html_footer>

    Action module example:

      package Reactor::Actions::demo::test;
      use strict;
      use Data::Dumper;
      use Web::Reactor::HTML::FormEngine;

      sub main
      {
        my $reo = shift; # Web::Reactor object. Provides all API and context.

        my $text; # result html text

        if( $reo->get_input_button() eq 'FORM_CANCEL' )
          {
          # if clicked form button is cancel,
          # return back to the calling/previous page/view with optional data
          return $reo->forward_back( ACTION_RETURN => 'IS_CANCEL' );
          }

        # add some html content
        $text .= "<p>Reactor::Actions::demo::test here!<p>";

        # create link and hide its data. only accessible from inside web app.
        my $grid_href = $reo->args_new( _PN => 'grid', TABLE => 'testtable', );
        $text .= "<a href=?_=$grid_href>go to grid</a><p>";

        # access page session. it will be auto-loaded on demand
        my $page_session_hr = $reo->get_page_session();
        my $fortune = $page_session_hr->{ 'FORTUNE' } ||= `/usr/games/fortune`;
        
    # access input (form) data. $i and $e are hashrefs
        my $i = $reo->get_user_input(); # get plain user input (hashref)
        my $e = $reo->get_safe_input(); # get safe data (never reach user browser)

        $text .= "<p><hr><p>$fortune<hr>";

        my $bc = $reo->args_here(); # session keeper, this is manual use

        $text .= "<form method=post>";
        $text .= "<input type=hidden name=_ value=$bc>";
        $text .= "input <input name=inp>";
        $text .= "<input type=submit name=button:form_ok>";
        $text .= "<input type=submit name=button:form_cancel>";
        $text .= "</form>";

        my $form = $reo->new_form();

        $text .= "<p><hr><p>";

        return $text;
      }

      1;

DESCRIPTION
    Web::Reactor provides automation of most of the usual and frequent tasks
    when constructing a web application. Such tasks include:

      * User session handling (creation, cookies support, storage)
      * Page (web screen/view) session handling (similar to user sessions attributes)
      * Sessions (user/page/etc.) data storage and auto load/ssave
      * Inter-page relations and data transport (hides real data from the end-user)
      * HTML page creation and expansion (i.e. including preprocessing :))
      * Optional HTML forms creation and data handling

    Web::Reactor is designed to allow extending or replacing some parts as:

      * Session storage (data store on filesystem, database, remote or vmem)
      * HTML creation/expansion/preprocessing
      * Page actions/modules execution (can be skipped if custom HTML prep used)

PROJECT STATUS
    At the moment Web::Reactor is in beta. API is mostly frozen but it is
    fairly possible to be changed and/or extended. However drastic changes
    are not planned :)

    If you are interested in the project or have some notes etc, contact me
    at:

      Vladi Belperchinov-Shabanski "Cade"
      <cade@bis.bg> 
      <cade@biscom.net> 
      <cade@cpan.org> 
      <cade@datamax.bg>

    further contact info, mailing list and github repository is listed
    below.

FIXME: TODO:
      * config examples
      * pages example
      * actions example
      * API description (input data, safe data, sessions, forwarding, actions, html)
      * ...

DEMO APPLICATION
    Documentation will be improved shortly, but meanwhile you can check
    'demo' directory inside distribution tarball or inside the github
    repository. This is fully functional (however stupid :)) application. It
    shows how data is processed, calling pages/views, inspecting page
    (calling views) stack, html forms automation, forwarding.

MAILING LIST
      web-reactor@googlegroups.com

GITHUB REPOSITORY
      https://github.com/cade4/perl-web-reactor
      
  git clone git://github.com/cade4/perl-web-reactor.git

AUTHOR
      Vladi Belperchinov-Shabanski "Cade"

      <cade@biscom.net> <cade@datamax.bg> <cade@cpan.org>

      http://cade.datamax.bg

