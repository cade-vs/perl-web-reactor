##############################################################################
##
##  Web::Reactor application machinery
##  Copyright (c) 2013-2022 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com> <cade@bis.bg> <cade@cpan.org>
##  http://cade.noxrun.com
##  
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
package Web::Reactor::Sessions::Dummy;
use strict;
use Exception::Sink;
use Web::Reactor::Sessions;

use parent 'Web::Reactor::Sessions';

##############################################################################
##
##  dummy storage methods
##  they are all no-ops
##

sub _storage_create
{
  return 1
}

sub _storage_load
{
  return {};
}

sub _storage_save
{
  return 1
}

sub _storage_exists
{
  return 1
}

sub _storage_debug_info 
{ 
}

##############################################################################
1;
###EOF########################################################################
