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
package Web::Reactor::Preprocessor;
use strict;
use Exception::Sink;

use parent 'Web::Reactor::Base';

# loads the page text itself, called by Web::Reactor::Reflex::render_page()
# args:
#       $page_name  -- page name (path), it should be sanitized
#
# returns:
#       page text or undef if not found
sub load_page { boom "Web::Reactor::Preprocessor::*::load_page() is not implemented!"; }

# preprocesses page text to include sub-pages or execute actions inside
# args:
#       $page_name  -- page name, used to find included files
#       $page_text  -- page text, already loaded with load_page(), or any
#                      text to be processed in the context of $page_name
#       $opt        -- options hashref (optional), also carries state between
#                      passes
#       $ctx        -- processing context hashref (optional), internal to
#                      nested processing
#
# returns:
#       preprocessed page text
sub process { boom "Web::Reactor::Preprocessor::*::process() is not implemented!"; }

#sub DESTROY
#{
#  my $self = shift;
#
#  print "DESTROY: $self\n";
#}

##############################################################################

# checks the page name and booms if it is not valid, called by the reactor on
# the requested page name before any lookup
# args:
#       $page_name  -- page name (path) to check
#
# returns:
#       nothing, booms on an invalid page name
sub check_page_name { boom "Web::Reactor::Preprocessor::*::check_page_name() is not implemented!"; }

##############################################################################
1;
###EOF########################################################################
