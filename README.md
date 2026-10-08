# NAME

Web::Reactor - perl-based web application machinery

# SYNOPSIS

Startup CGI script example (LEGACY), the same PSGI app run by Plack's CGI
handler:

    #!/usr/bin/perl
    use strict;
    use lib '/opt/perl/reactor/lib';
    use Web::Reactor;
    use Plack::Handler::CGI;

    my %cfg = (
              'APP_NAME'     => 'demo',
              'APP_ROOT'     => '/opt/reactor/demo/',
              'HTML_DIRS'    => [ '/opt/reactor/demo/html/' ],
              'SESS_VAR_DIR' => '/opt/reactor/demo/var/sess/',
              'DEBUG'        => 4,
              );

    my $app = sub { return Web::Reactor->new( shift(), \%cfg )->run() };

    Plack::Handler::CGI->new()->run( $app );

Startup PLACK/PSGI script example (RECOMMENDED):

    #!/usr/bin/perl
    # app.psgi
    use strict;
    use Web::Reactor;

    my %cfg = (
              'APP_NAME'     => 'demo',
              'APP_ROOT'     => '/opt/reactor/demo/',
              'HTML_DIRS'    => [ '/opt/reactor/demo/html/' ],
              'SESS_VAR_DIR' => '/opt/reactor/demo/var/sess/',
              'DEBUG'        => 0,
              );

    my $app = sub {
      my $env = shift;
      my $reactor = Web::Reactor->new( $env, \%cfg );
      return $reactor->run();
    };

    return $app;

Run with: plackup -p 5000 app.psgi
Or with reverse proxy (nginx): plackup --server Starman -p 5000 app.psgi

# INTRODUCTION

Web::Reactor is a perl module which automates as much as possible of all the
routine tasks when implementing web applications, interactive sites, etc.
Main task is to handle all the repetitive work and adding more comfortable
functionality like:

    * setting and recognising web browser cookies (for sessions or other data)
    * handling user and page sessions (storage, cookie management, etc.)
    * hiding html link data and forms data to raise page-to-page transfer safety.
    * preprocessing of text/html, including hiding data, calling actions etc.
    * on-demand loading of 'actions', perl code modules to handle dynamic pages.

Web::Reactor can be extended, though it was not supposed to. There are 4 main
parts of it which can be extended. See section EXTENDING below for details.

# SECURITY FEATURES

Web::Reactor includes several built-in security features:

## HTTPS Enforcement

By default, Web::Reactor requires HTTPS for secure cookie handling. This prevents
downgrade attacks. To disable (NOT RECOMMENDED for production):

    'DISABLE_SECURE_COOKIES' => 1

## Secure Cookie Flags

All session cookies are set with:

    - httponly: Prevents JavaScript access (XSS protection)
    - secure: Only sent over HTTPS (unless DISABLE_SECURE_COOKIES=1)
    - samesite=lax: CSRF protection (cookies not sent on cross-site requests)

## Session Hijacking Prevention

Session validity is checked on each request:

    - Client IP address is tracked and validated
    - User-Agent is tracked and validated

If either changes, the user session is closed, a new one is created and the
"einvalid" page is shown. This protects against session hijacking.

The cookie carries only the id of a cookie session, which points to the user
session. The user session id itself never leaves the server. On login the
cookie session is replaced with a new one (new cookie value), which protects
against session fixation: a cookie known before login is useless after it.

## Session Expiration

Logged-in user sessions expire after a configurable time of inactivity
(default: 600 seconds), the "eexpired" page is shown and a new anonymous
session is created. Anonymous (not logged-in) sessions do not expire:

    'USER_SESSION_EXPIRE' => 600,  # 10 minutes

## Input Validation

All input parameters are validated:

    - Parameter names: alphanumeric, dash, underscore, dot, colon
    - Page names: lowercase alphanumeric, dash, underscore, slash
    - Action names: lowercase alphanumeric, underscore
    - Session IDs: alphanumeric, underscore

Parameters with invalid names are logged and dropped. Invalid page or
action names and malformed session ids, which only client tampering
produces, raise an error (the client gets the generic error page).

## Data Encryption (Optional)

Web::Reactor can encrypt sensitive data with ChaCha20-Poly1305, see cry()
and argsx().
See CRYPTOGRAPHY section below.

## Password Encryption (Optional)

Data such as passwords can be encrypted with an RSA public key through rsa().
Configure RSA\_PUB\_KEY with the name of the public key PEM file.

Web::Reactor, and not Web::Reactor::Reflex or Web::Reactor::Core, also
encrypts password input by itself: the value of every user input parameter
whose name starts with PASS (PASS, PASS2, PASSWORD, ...) or contains PASSWORD
(NEW\_PASSWORD, OLD\_PASSWORD, ...) is replaced with its RSA encryption as hex
text, so the application never sees the plain password. The same parameters
are masked in the debug logs, by all reactors. The rule is kept in
$Web::Reactor::Core::RE\_PASSWORD\_PARAM\_NAMES. Only the backend holding the
private key reads the value back, with decrypt\_hex() of Data::Tools::Crypto::RSA.
Empty values stay empty, and a value that fails to encrypt becomes empty. A password
parameter sent more than once is not supported: it is dropped and logged.
A request with a non-empty password parameter booms when RSA\_PUB\_KEY is not
configured or its file cannot be read, unless DISABLE\_PASSWORD\_ENCRYPT is set, which leaves all user
input as it arrives.

## Content Security Policy (Optional)

Set HTTP\_CSP config to add Content-Security-Policy header:

    'HTTP_CSP' => "default-src 'self'; script-src 'self' 'unsafe-inline'",

# EXAMPLES

HTML page file example:

    <#html_header>

    <$app_name>

    <#menu>

    testing page html file

    action test: <&test>

    <#html_footer>

Action module example, file APP\_ROOT/actions/test.pm (see ACTIONS below):

    package reactor::actions::test;
    use strict;
    use Data::Dumper;
    use Web::Reactor::HTML::Form;

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
      $text .= "<p>reactor::actions::test here!<p>";

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

"Page names" are limited to lowercase letters, digits, "\_" and "-", with "/"
between path parts, and are mapped to a directory with an index.html file
(Web::Reactor::Preprocessor::Tree):

                     page name: admin/users
    html file template will be: HTML_DIRS/<lang>/admin/users/index.html
                                or HTML_DIRS/default/admin/users/index.html

HTML content may include other files (limited the same way, no path):

            include text: <#other_file>
           file included: other_file.html
    directories searched: the page directory and its parents, up to the
                          HTML_DIRS root, in HTML_DIRS/<lang>/ then
                          HTML_DIRS/default/

Page names may be requested from the end user side, but include html files may
be used only from the pages already requested.

# ACTIONS/MODULES/CALLBACKS

Actions are perl modules with a main() function. In the HTML source files they
can be called this way:

    <&test_action arg1=val1 arg2=val2 flag1 flag2...>
    <&test_action>

The default action loader (Web::Reactor::Actions::Files) looks for a file with
the action name in the ACTIONS\_DIRS directories (default: APP\_ROOT/actions):

    APP_ROOT/actions/test_action.pm

and expects the package ACTIONS\_PKGS . name inside (default prefix
"reactor::actions::"), i.e. reactor::actions::test\_action. Action files are
loaded again on their first call in each request, so changed actions are used
without a restart.

The other loader, Web::Reactor::Actions::Packages (REO\_ACT\_CLASS), finds action
packages through @INC (LIB\_DIRS are added there) by "action sets":

    'ACTIONS_SETS' => [ 'demo', 'Base', 'Core' ],

So the packages tried in this example will be:

    Web::Reactor::Actions::demo::test_action
    Web::Reactor::Actions::Base::test_action
    Web::Reactor::Actions::Core::test_action

The first set which has the action wins, this is used to allow overriding of
standard modules or modules you don't have write access to.

Another way to call a module is directly from another module code with:

    $reo->act->call( 'test_action', @args );

The action file (Actions::Files) will look like this:

    package reactor::actions::test_action;
    use strict;

    sub main
    {
      my $reo  = shift; # Web::Reactor object/instance
      my %args = @_; # all args passed to the action

      my $html_args = $args{ 'HTML_ARGS' }; # all
      ...
      return $result_data; # usually html text
    }

$html\_args is hashref with all args given inside the html code if this action
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

    _    -- safe input token: "sid.key" from args() or "~..." from argsx()
    _PN  -- html page name (points to the page template, a-z 0-9 _ - and /)
    _AN  -- action name (points to the action file or package, a-z 0-9 _)
    _P   -- page session
    _R   -- referer (caller) page session
    _T   -- top-level page session (browser window)

Usually those names should not be directly used or visible inside actions code.
More details about how those params are used can be found below.

# USER SESSIONS

WR creates unique session for each connected user. The session is kept by a cookie.
Usually WR needs just this cookie to handle all user/server interaction. The
cookie value is the id of a cookie session, which points to the user session,
so the user session id never reaches the browser. Inside
WR action code, user session is represented as a hash reference. It may hold
arbitrary data. "System" or WR-specific data inside user session has colon as
prefix:

    # $reo is Web::Reactor object (i.e. context) passed to the action/module code
    my $user_session = $reo->get_user_session();
    print STDERR $user_session->{ ':CTIME_STR' };
    # prints in http log the create time in human friendly form

All data put inside user session is automatically saved at the end of the
request. Only sessions which changed are written. When needed it can be
explicitly saved with:

    $reo->save();
    # saves all modified sessions to disk or other storage

Session types:

    USER -- user session, one per connected browser, see get_user_session()
    COOK -- cookie session, its id is the cookie value, points to USER,
            replaced on login, logout and when the user session is closed
    PAGE -- page sessions, stored under the user session, survive login
    LINK -- link data of args() links and forms, stored under the cookie
            session, so links made before login do not work after it
    HOLD -- user hold, kept between logins, see get_user_hold()

On login() the user session stays the same, only the cookie session is
replaced. On logout() the user session is closed and new user, cookie and
page sessions are created.

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

Upon creation, Web::Reactor instance gets hash with config entries/keys.

## Required Config Entries

    APP_NAME      -- lowercase alphanumeric application name (plus underscore)
    APP_ROOT      -- application root directory, must exist

## Optional Config Entries (with defaults)

    LIB_DIRS                  -- Lib directories list (or single string), added to @INC (default: ["$APP_ROOT/lib"])
    ACTIONS_DIRS              -- Action file dirs, Actions::Files (default: ["$APP_ROOT/actions"])
    ACTIONS_PKGS              -- Action package prefix, Actions::Files (default: "reactor::actions::")
    ACTIONS_SETS              -- Action sets, Actions::Packages (default: [$APP_NAME, 'Base', 'Core'])
    HTML_DIRS                 -- HTML template dirs, each with <lang>/ and default/
                                 subdirs (default: ["$APP_ROOT/html"])
    SESS_VAR_DIR              -- Session storage dir (default: "$APP_ROOT/var")
    SESS_CREATE_TIMEOUT       -- seconds create() keeps trying new session ids on a collision (default: 5)
    SESS_CREATE_TIMEOUT_COUNT -- tries before create() gives up (default: 1023)
    DEBUG                     -- Debug level 0-4 (default: 0)
    COOKIE_NAME               -- Session cookie name, lowercased (default: "${APP_NAME}_cookie")
    COOKIE_PATH               -- Cookie path (default: derived from REQUEST_URI)
    USER_SESSION_EXPIRE       -- Session timeout in seconds (default: 600)
    LANG                      -- Language code for translations (default: none)

## Security Config Entries

    DISABLE_SECURE_COOKIES    -- Disable HTTPS enforcement (default: 0, NOT RECOMMENDED)
    CRY_KEY                   -- 32 raw bytes key for cry() and argsx() (required if used)
    RSA_PUB_KEY               -- RSA public key PEM file name for rsa() (required if used)
    DISABLE_PASSWORD_ENCRYPT  -- Do not RSA encrypt PASS* and *PASSWORD* user input, Web::Reactor only (default: 0)
    HTTP_CSP                  -- Content-Security-Policy header (optional)
    CLOUDFLARE                -- behind Cloudflare: client IP from CF-Connecting-IP
    PROXY_REMOTE              -- behind a trusted reverse proxy: client IP from X-Real-IP

The client IP is part of the session hijack check, so behind a proxy set the
matching flag, otherwise every client looks like the proxy. Both are off by
default, so a client cannot fake its address with those headers.

## Extension Config Entries

    REO_SES_CLASS             -- Session storage class (default: Web::Reactor::Sessions::Filesystem)
    REO_PRE_CLASS             -- Preprocessor class (default: Web::Reactor::Preprocessor::Tree)
    REO_ACT_CLASS             -- Actions class (default: Web::Reactor::Actions::Files)
    REO_CRY_CLASS             -- Symmetric cipher class for cry() (default: Data::Tools::Crypto::Symmetric)
    REO_RSA_CLASS             -- RSA class for rsa() (default: Data::Tools::Crypto::RSA)

## Translation Config Entries

    TRANS_DIRS                -- Directories with .tr translation files (array ref)
    TRANS_FILE                -- Specific translation file to load (string)

Page text marks translatable literals as \[~text\] or <~text>, the preprocessor
replaces them with the translation from the loaded LANG, or with the literal
text itself when there is none.

# API FUNCTIONS

This section covers the most commonly used API functions. For comprehensive
documentation, see the method source code and examples in the demo/ directory.

## Input Data Functions

    get_user_input()        -- Get all user (unsafe) input, PASS* and *PASSWORD* values RSA encrypted
    get_safe_input()        -- Get safe input resolved from the _ token (links and forms)
    param( @names )         -- Get and cache safe input parameters
    param_unsafe( @names )  -- Get and cache unsafe user input parameters
    param_peek( @names )    -- Get safe input without caching
    param_save( @names )    -- Get, cache, and save to page session
    get_input_button()      -- Get which form button was clicked
    get_input_button_id()   -- Get form button ID if applicable

## Session Functions

    get_user_session()                  -- Get current user session hashref,
                                           ( id, hashref ) in list context
    get_user_session_id()               -- Get current user session ID
    get_user_session_expire_time()      -- Get expiration timestamp
    get_user_session_expire_time_in()   -- Get remaining time in seconds
    set_user_session_expire_time( $ts ) -- Set expiration timestamp
    set_user_session_expire_time_in( $s ) -- Set expiration in seconds

    get_page_session( $level )          -- Get current page session hashref
    get_page_session_id( $level )       -- Get current page session ID
    get_ref_page_session_id( $level )   -- Get caller page session ID
    get_top_page_session_id( $level )   -- Get top-level page session ID

    get_user_hold()                     -- Get persistent user data (requires login)

    get_cookie_session()                -- Get current cookie session hashref
    get_link_session()                  -- Get current link session hashref,
                                           created on demand, ( id, hashref )
                                           in list context
    new_link_session_key( $len )        -- New unused key in the link session

    sc_add( $shr )                      -- Track a session for save(), the
                                           fingerprint is taken right away
    sc_get( $type, $sid, $psid )        -- Get a tracked session or undef
    sc_remove( $shr )                   -- Stop tracking, storage is untouched
    save()                              -- Write all tracked sessions which
                                           changed, called automatically

## Argument/Link Construction Functions

    args( %data )           -- Create link with safe data only (no page session)
    args_new( %data )       -- Create link for new page with referer
    args_here( %data )      -- Create link staying on same page
    args_back( %data )      -- Create link returning to caller
    args_back_back( %data ) -- Create link returning to caller's caller

## Forwarding Functions

    forward( %data )        -- Forward with safe data (full args)
    forward_new( %data )    -- Forward to new page
    forward_here( %data )   -- Forward staying on same page
    forward_back( %data )   -- Forward returning to caller
    forward_url( $url )     -- Forward to a URL, relative or absolute (302 redirect)

## HTML and Form Functions

    html_hold_set( %vars )  -- Set HTML template variables
    new_form( %opt )        -- Create new form object
    render_page( $name )    -- Load, preprocess and render page template
    render_action( $name )  -- Call action and render its result
    render_data( $data, $type ) -- Render data with mime type, see portray()
    render( $portray_hr )   -- Render portray data, i.e. render( portray( ... ) )

## Login/Logout Functions

    is_logged_in()          -- Check if user is logged in
    login( $user_ident )    -- Mark user as logged in, replaces the cookie session,
                               without an ident there is no user hold
    logout()                -- Log out current user, new user and cookie sessions
    need_login()            -- Require login, forward to login page

## Encryption Functions

    cry()                   -- Symmetric crypto object (CRY_KEY), see CRYPTOGRAPHY API
    rsa()                   -- RSA public key object (RSA_PUB_KEY), see CRYPTOGRAPHY API
    argsx( %args )          -- Encrypted safe input token, carries data in the link

# CRYPTOGRAPHY API

Links and forms do not need encryption: args() keeps their data on the server,
in LINK sessions, and the link carries only an opaque "sid.key" reference.
Encryption is available through two plugs, loaded on first use, for
application data and for the argsx() tokens inherited from Web::Reactor::Reflex.

## Configuration

    my %cfg = (
              'CRY_KEY'     => $key,            # exactly 32 raw bytes, for cry() and argsx()
              'RSA_PUB_KEY' => 'keys/pub.pem',  # RSA public key PEM file name, for rsa()
              );

The plug classes can be replaced with REO\_CRY\_CLASS and REO\_RSA\_CLASS.

## Symmetric Encryption: cry()

    my $cry = $reo->cry(); # Data::Tools::Crypto::Symmetric, ChaCha20-Poly1305

    my $ctext  = $cry->encrypt( $ptext );          # binary
    my $ptext  = $cry->decrypt( $ctext );          # undef if modified or wrong key

    my $hex    = $cry->encrypt_hex( $ptext );      # also _base64() and _base64url()
    my $sealed = $cry->freeze_base64url( \%data ); # serialize and encrypt
    my $hr     = $cry->thaw_base64url( $sealed );  # undef if modified or wrong key

cry() booms if CRY\_KEY is not configured. Encryption is authenticated:
cryptotext modified in any way does not decrypt at all. See
Data::Tools::Crypto::Symmetric and Data::Tools::Crypto for all methods.

## Encrypted Safe Input: argsx()

    my $token = $reo->argsx( _AN => 'transfer', ACCOUNT => $account_id );
    $html .= "<a href='?_=$token'>Process Transfer</a>";

    # on the next request the token is decrypted into the safe input
    my $account_id = $reo->get_safe_input()->{ 'ACCOUNT' };

argsx() tokens start with "~" and carry the data itself, encrypted with
CRY\_KEY, so they need no server-side storage. args() tokens keep the data in
a LINK session instead. Both arrive the same way in get\_safe\_input().

## Public Key Encryption: rsa()

    my $rsa = $reo->rsa(); # Data::Tools::Crypto::RSA with the RSA_PUB_KEY key

    my $ctext = $rsa->encrypt_base64url( $secret ); # only the private key decrypts
    my $ok    = $rsa->verify_base64url( $message, $signature );

rsa() booms if RSA\_PUB\_KEY is not configured or its file cannot be read. The
file is read once per reactor object, on the first rsa() call. The reactor holds only the public
key, decrypting with the private key belongs to the backend. User input
parameters named PASS\* or containing PASSWORD arrive encrypted this way, see
Password Encryption above.

## Security Considerations

    - Keep CRY_KEY secret, generate it with Crypt::PRNG::random_bytes( 32 )
    - Use different keys for different environments (dev, staging, production)
    - Do NOT hardcode keys in source code, use environment variables or config files

# DEPLOYMENT, DIRECTORIES, FILESYSTEM STRUCTURE

## Session Storage Directory

Create and protect the session directory:

    mkdir -p /var/reactor/sessions
    chmod 0700 /var/reactor/sessions
    chown www-data:www-data /var/reactor/sessions

Session files are stored as JSON, one file per session, with .wrs2 extension
and mode 0600.

## Installation

Install via CPAN:

    cpanm Web::Reactor

Or from GitHub:

    git clone git://github.com/cade-vs/perl-web-reactor.git
    cd perl-web-reactor
    perl Makefile.PL
    make test
    make install

## Custom Installation

For development or custom locations:

    perl Makefile.PL PREFIX=/opt/perl/reactor
    make test
    make install

Then use in code:

    use lib '/opt/perl/reactor/lib';
    use Web::Reactor;

# EXTENDING

Web::Reactor is designed to allow extending or replacing the 4 main parts:

## Session Storage

    Base module:    Web::Reactor::Sessions
    Current in use: Web::Reactor::Sessions::Filesystem

Extend by subclassing Web::Reactor::Sessions to use different storage backends
(database, remote servers, memory, etc.). A subclass implements:

    _storage_create( $key, $shr ) -- atomic create, 1 created, 0 id exists,
                                     undef on error, never overwrites
    _storage_load( $key )         -- session hashref or undef
    _storage_save( $key, $shr )   -- true if saved
    _storage_delete( $key )       -- true if deleted or missing
    _storage_exists( $key )       -- true if exists
    _storage_debug_info()         -- storage description for error messages

$key is the key components array reference from compose\_key\_from\_sid().

## HTML Preprocessing

    Base module:    Web::Reactor::Preprocessor
    Current in use: Web::Reactor::Preprocessor::Tree

Extend by subclassing Web::Reactor::Preprocessor to customize HTML processing,
template syntax, or add new markup handlers. A subclass implements:

    load_page( $page_name )         -- page text or undef
    process( $page_name, $text )    -- processed text
    check_page_name( $page_name )   -- booms on an invalid page name

## Actions Execution

    Base module:    Web::Reactor::Actions
    Current in use: Web::Reactor::Actions::Files

Extend by subclassing Web::Reactor::Actions to customize action loading,
execution, or error handling. A subclass implements:

    __find_code_by_name( $name )    -- code reference of the action's main()
                                      or undef (logged) if not found

## Main Module

    Base module:    Web::Reactor
    Current in use: Web::Reactor

The main module handles all logic and is not recommended for modification.
However, the reactor instance is passed to all actions and modules, so you
can add application-specific methods by extending in your application code.

Except main module (Web::Reactor) it is expected that base modules are
subclassed for extension. Inside each of them there are notes on what must
be extended and usage hints.

Current implementations of the modules, shipped with Web::Reactor, can also
be extended and/or modified. However it is suggested checking base modules
first.

# SECURITY BEST PRACTICES

When deploying Web::Reactor applications:

## Configuration Security

1\. Set CRY\_KEY to exactly 32 random raw bytes, for example

    Crypt::PRNG::random_bytes( 32 ), or decode_base64() of: openssl rand -base64 32

2\. Store sensitive config (keys, passwords) in environment variables,
   not in source code or version control

3\. Ensure SESS\_VAR\_DIR has restrictive permissions:

    mkdir -p /var/reactor/sessions
    chmod 0700 /var/reactor/sessions
    chown www-data:www-data /var/reactor/sessions

4\. Disable HTTPS only in development/testing:

    PRODUCTION: DISABLE_SECURE_COOKIES not set or = 0
    DEVELOPMENT: Set DISABLE_SECURE_COOKIES=1 if testing without HTTPS

## Session Security

1\. Set USER\_SESSION\_EXPIRE to reasonable timeout (default 600 = 10 min)

    Shorter for high-security apps (e.g., banking), longer for low-security

2\. Session hijacking detection is automatic (IP + User-Agent checking)

    Sessions are invalidated if either changes

3\. Session data is stored on filesystem in JSON format

    Ensure proper file permissions (0700) on session directory

## Deployment

1\. Use HTTPS in production (enforced by default)

2\. Use Plack with a production server:

    NOT RECOMMENDED: plackup (single process, no reload protection)

    RECOMMENDED:
      - Starman (multi-worker, production-ready)
        plackup --server Starman --workers 4 app.psgi

      - Use reverse proxy (nginx/Apache) with:
        * X-Real-IP header passing (and PROXY_REMOTE => 1 in the config)
        * X-Forwarded-Proto HTTPS enforcement
        * gzip compression

3\. Set Content-Security-Policy to restrict resource loading:

    'HTTP_CSP' => "default-src 'self'",

4\. Form and link CSRF protection is automatic

    Links and forms carry a "_" token which resolves only in the LINK session
    of the same cookie session, use args*() and new_form() to build them

5\. Log security events:

    These are always logged (with any DEBUG level):
    * Invalid input attempts
    * Session hijacking attempts
    * Expired sessions
    * Invalid page/action names

## Input Validation

1\. User input is never automatically trusted

2\. Always use get\_safe\_input() for form data, not get\_user\_input()

3\. Implement application-level validation in action modules:

    if ( $reo->param('amount') < 0 ) {
      $reo->log("error: negative amount not allowed");
      return $reo->render_page( 'error_invalid' );
    }

4\. HTML escape all output in templates to prevent XSS

## Password Security

1\. Encrypt passwords with an RSA public key if needed (optional):

    'RSA_PUB_KEY' => $public_key_pem_file_name

    Web::Reactor encrypts PASS* and *PASSWORD* input parameters with it, see
    Password Encryption above; rsa() gives the key object for anything else.
    Nothing is encrypted in the browser, HTTPS protects the transport.

2\. Never log passwords (application responsibility)

3\. Use bcrypt/argon2 for password hashing (application responsibility)

## Monitoring and Logging

1\. Monitor application logs for:

    * Invalid input attempts
    * Session errors
    * Encryption/decryption failures
    * Unusual IP changes
    * High frequency of requests

2\. Set DEBUG level appropriately:

    0 = no debug (production)
    1 = basic info
    2 = detailed info
    3 = very detailed
    4 = maximum debug (development only)

3\. Implement rate limiting at application level (not provided by framework)

# PROJECT STATUS

Web::Reactor is stable and it is used in many production sites including
banks, insurance, travel and other smaller companies.

API is frozen but it could be extended.

If you are interested in the project or have some notes etc, contact me at:

    Vladi Belperchinov-Shabanski "Cade"
    <cade@noxrun.com>

further contact info, mailing list and github repository is listed below.

# TODO:

The following items are planned for future releases:

    * Add more config validation at startup
    * Implement built-in rate limiting
    * Add more comprehensive error pages
    * Support HTTP/2 Server Push
    * Enhanced debugging with request/response profiling
    * More comprehensive test suite
    * Performance optimizations

See GitHub issues for details: https://github.com/cade-vs/perl-web-reactor/issues

# REQUIRED ADDITIONAL MODULES

Web::Reactor requires the following Perl modules:

## Core Modules (included with Perl)

    * Scalar::Util
    * Hash::Util
    * List::Util
    * Data::Dumper (for debugging)
    * Encode
    * Storable
    * Time::HiRes
    * Fcntl
    * Exporter
    * File::Spec

## CPAN Modules (required)

    * Plack 1.0000+          -- PSGI web framework
    * Cookie::Baker 0.001+   -- Cookie handling
    * Data::Tools 1.53+      -- Data manipulation utilities
    * Exception::Sink 0.01+  -- Exception handling
    * Crypt::PRNG            -- session and link ids (CryptX)
    * Data::Tools::Crypto    -- cry() and rsa() plugs, ChaCha20-Poly1305 and RSA (CryptX)

## CPAN Modules (optional)

    * JavaScript::QuickJS    -- runs the javascript tests (t/test_reactor_js.pl),
                                skipped without it

## GitHub Repositories

    * Exception::Sink
      https://github.com/cade-vs/perl-exception-sink

    * Data::Tools
      https://github.com/cade-vs/perl-data-tools

## Perl Version

    Minimum: Perl 5.10.1 (use parent)
    Tested:  Perl 5.20, 5.24, 5.28, 5.32, 5.36

# DEMO APPLICATION

Documentation will be improved. Meanwhile you can check 'demo' directory inside
distribution tarball or inside the github repository. This is fully functional
(however simple) application. It shows how data is processed, calling pages/views,
inspecting page (calling views) stack, html forms automation, forwarding.

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

    <cade@noxrun.com> <cade@bis.bg> <cade@cpan.org> <shabanski@gmail.com>

    http://cade.noxrun.com

    https://github.com/cade-vs
