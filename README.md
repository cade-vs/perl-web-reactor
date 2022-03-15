# NAME

Web::Reactor perl-based web application machinery.

# SYNOPSIS

Startup CGI script example:

    #!/usr/bin/perl
    use strict;
    use lib '/opt/perl/reactor/lib'; # if Reactor is custom location installed
    use Web::Reactor;

    my %cfg = (
              'APP_NAME'     => 'demo',
              'APP_ROOT'     => '/opt/reactor/demo/',
              'LIB_DIRS'     => [ '/opt/reactor/demo/lib/'  ],
              'ACTIONS_SETS' => [ 'demo', 'Base', 'Core' ],
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

# INTRODUCTION

Web::Reactor is a perl module which automates as much as possible of the all
routine tasks when implementing web applications, interactive sites, etc.
Main task is to handle all the repetative work and adding more comfortable
functionality like:

    * setting and recognising web browser cookies (for sessions or other data)
    * handling user and page sessions (storage, cookie management, etc.)
    * hiding html link data and forms data to rise page-to-page transfer safety.
    * preprocessing of text/html, including hiding data, calling actions etc.
    * on-demand loading of 'actions', perl code modules to handle dynamic pages.

Web::Reactor can be extended, though it was not supposed to. There are 4 main
parts of it which can be extended. See section EXTENDING below for details.

# EXAMPLES

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

# PAGE NAMES, HTML FILE TEMPLATES, PAGE INSTANCES

Web::Reactor has a notion of a "page" which represents visible output to the
end user browser. It has (i.e. uses) the following attributes:

    * html file template (page name)
    * page session data
    * actions code (i.e. callbacks) used inside html text

All of those represent "page instance" and produce end user html visible page.

"Page names" are strictly limited to be alphanumeric and are mapped to file
(or other storage) html content:

                     page name: example
    html file template will be: page_example.html

HTML content may include other files (also limited to be alphanumeric):

            include text: <#other_file>
           file included: other_file.html
    directories searched: 'HTML_DIRS' from Web::Reactor parameters.

Page names may be requested from the end user side, but include html files may
be used only from the pages already requested.

# ACTIONS/MODULES/CALLBACKS

Actions are loaded and executed by package names. In the HTML source files they
can be called this way:

    <&test_action arg1=val1 arg2=val2 flag1 flag2...>
    <&test_action>

This will instruct Reactor action handler to look for this package name inside
standard or user-added library directories:

    Web/Reactor/Actions/*/test_action.pm

Asterisk will be replaced with the name of the used "action sets" give in config
hash:

       'ACTIONS_SETS' => [ 'demo', 'Base', 'Core' ],

So the result list in this example will be:

    Web/Reactor/Actions/demo/test_action.pm
    Web/Reactor/Actions/Base/test_action.pm
    Web/Reactor/Actions/Core/test_action.pm

This is used to allow overriding of standard modules or modules you dont have
write access to.

Another way to call a module is directly from another module code with:

    $reo->action_call( 'test_action', @args );

The package file will look like this:

    package Web/Reactor/Actions/demo/test_action;
    use strict;

    sub main
    {
      my $reo  = shift; # Web::Reactor object/instance
      my %args = @_; # all args passed to the action

      my $html_args = $args{ 'HTML_ARGS' }; # all
      ...
      return $result_data; # usually html text
    }

$html\_args is hashref with all args give inside the html code if this action
is called from a html text. If you look the example above:

    <&test_action arg1=val1 arg2=val2 flag1 flag2...>

The $html\_args will look like this:

    $html_args = {
                 'arg1'  => 'val1',
                 'arg2'  => 'val2',
                 'flag1' => 1,
                 'flag2' => 1,
                 };

# HTTP PARAMETERS NAMES

Web::Reactor uses underscore and one or two letters for its system http/html
parameters. Some of the system params are:

    _PN  -- html page name (points to file template, restricted to alphanumeric)
    _AN  -- action name (points to action package name, restricted to alphanumeric)
    _P   -- page session
    _R   -- referer (caller) page session

Usually those names should not be directly used or visible inside actions code.
More details about how those params are used can be found below.

# USER SESSIONS

WR creates unique session for each connected user. The session is kept by a cookie.
Usually WR needs justthis cookie to handle all user/server interaction. Inside
WR action code, user session is represented as a hash reference. It may hold
arbitrary data. "System" or WR-specific data inside user session has colon as
prefix:

    # $reo is Web::Reactor object (i.e. context) passed to the action/module code
    my $user_session = $reo->get_user_session();
    print STDERR $user_session->{ ':CTIME_STR' };
    # prints in http log the create time in human friendly form

All data saved inside user session is automatically saved. When needed it can
be explicitly with:

    $reo->save();
    # saves all modified context to disk or other storage

# PAGE SESSIONS

Each page presented to the user has own session. It is very similar to the user
session (it is hash reference, may hold any data, can be saved with $reo->save()).
It is expected that page sessions hold all context data needed for any page to
display properly. To preserve page session it is needed that it is included
in any link to this page instance or in any html form used.

When called for the first time, each page request needs page name (\_PN). Afterwards
a unique page session is created and page name is saved inside. At this moment
this page instance can be accessed (i.e. given control to) only with a page
session id (\_P):

    $page_sid = ...; # taken from somewhere
    # to pass control to the page instance:
    $reo->forward( _P => $page_sid );
    # the page instance will pull data from its page session and display in
    # its last known state

Not always page session are needed. For example, when forward to the caller is
needed, you just need to:

    $reo->forward_back();
    # this is equivalent to
    my $ref_page_sid = $reo->get_ref_page_session_id();
    $reo->forward( _P => $ref_page_sid );

Each page instance knows the caller page session and can give control back to.
However it may pass more data when returning back to the caller:

    $reo->forward_back( MORE_DATA => 'is here', OPTIONS_LIST => \@list );

When new page instance has to be called (created):

    $reo->forward_new( _PN => 'some_page_name' );

# CONFIG ENTRIES

Upon creation, Web:Reactor instance gets hash with config entries/keys:

    * APP_NAME      -- alphanumeric application name (plus underscore)
    * APP_ROOT      -- application root dir, used for app components search
    * LIB_DIRS      -- directories from which actions and other libs are loaded
    * ACTIONS_SETS  -- list of action "sets", appended to ACTIONS_DIRS
    * HTML_DIRS     -- html file inlude directories
    * SESS_VAR_DIR  -- used by filesystem session handling to store sess data
    * DEBUG         -- positive number, enables debugging with verbosity level

Some entries may be omitted and default values are:

    * LIB_DIRS      -- [ "$APP_ROOT/lib"  ]
    * ACTIONS_SETS  -- [ $APP_NAME, 'Base', 'Core' ]
    * HTML_DIRS     -- [ "$APP_ROOT/html" ]
    * SESS_VAR_DIR  -- [ "$APP_ROOT/var"  ]
    * DEBUG         -- 0

# API FUNCTIONS

    # TODO: input
    # TODO: sessions
    # TODO: arguments, constructing links
    # TODO: forwarding
    # TODO: html, forms, session keeping

# DEPLOYMENT, DIRECTORIES, FILESYSTEM STRUCTURE

    # TODO: install, cpan, manual, github, custom locations
    # TODO: sessions dir, custom storage/session handling

# EXTENDING

Web::Reactor is designed to allow extending or replacing the 4 main parts:

    * Session storage (data store on filesystem, database, remote or vmem)

      base module:    Web::Reactor::Sessions
      current in use: Web::Reactor::Sessions::Filesystem

    * HTML creation/expansion/preprocessing

      base module:    Web::Reactor::Preprocessor
      current in use: Web::Reactor::Preprocessor::Native

    * Actions/modules execution (can be skipped if custom HTML prep used)

      base module:    Web::Reactor::Actions
      current in use: Web::Reactor::Actions::Native

    * Main Web::Reactor modules, which controlls all the functionality.

      base module:    Web::Reactor
      current in use: Web::Reactor

Except main module (Web::Reactor) is is expected that base modules are
subclassed for extension. Inside each of them there are notes on what must
be extended and usage hints.

Current implementations of the modules, shipped with Web::Reactor, can also
be extended and/or modified. However it is suggested checking base modules
first.

Main module (Web::Reactor) handles all of the logic. It is not expected to
be modified since it is designed to handle tightly all the parts. However,
there are few things which can be modified but it is recommended to contact
authors for an advice first. On the other hand, the main module instance is
always passed as argument to all other modules/actions so it is good idea
to add specific functionality which will be readily available everywhere.

# PROJECT STATUS

Web::Reactor is stable and it is used in many production sites including
banks, insurance, travel and other smaller companies.

API is frozen but it could be extended

If you are interested in the project or have some notes etc, contact me at:

    Vladi Belperchinov-Shabanski "Cade"
    <cade@noxrun.com>
    <cade@cpan.org>
    <shabanski@gmail.com>

further contact info, mailing list and github repository is listed below.

# FIXME: TODO:

    * config examples
    * pages example
    * actions example
    * API description (input data, safe data, sessions, forwarding, actions, html)
    * ...

# REQUIRED ADDITIONAL MODULES

Reactor uses mostly perl core modules but it needs few others:

    * CGI
    * Scalar::Util
    * Hash::Util
    * Data::Dumper (for debugging)
    * Exception::Sink
    * Data::Tools

All modules are available with the perl package or from CPAN.

Additionally, several are available and from github:

    * Exception::Sink
    https://github.com/cade-vs/perl-exception-sink

    * Data::Tools
    https://github.com/cade-vs/perl-data-tools

# DEMO APPLICATION

Documentation will be improved. Meanwhile you can check 'demo'
directory inside distribution tarball or inside the github repository. This is
fully functional (however stupid :)) application. It shows how data is processed,
calling pages/views, inspecting page (calling views) stack, html forms automation,
forwarding.

Additionally you may check DECOR information systems infrastructure, which uses
Web::Reactor for its main web interface:

    https://github.com/cade-vs/perl-decor

# MAILING LIST

    web-reactor@googlegroups.com

# GITHUB REPOSITORY

    https://github.com/cade-vs/perl-web-reactor

    git clone git://github.com/cade-vs/perl-web-reactor.git

# AUTHOR


    Vladi Belperchinov-Shabanski "Cade"
          <cade@noxrun.com> <cade@bis.bg> <cade@cpan.org>
    http://cade.noxrun.com
    http://github.com/cade-vs

## EOF
