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
package Web::Reactor::Sessions::Dummy;
use strict;
use Exception::Sink;
use Web::Reactor::Sessions;

use parent 'Web::Reactor::Sessions';

##############################################################################
##
##  dummy storage methods
##  nothing is stored: create, save and delete succeed, load finds nothing and
##  no session exists, so every request starts with new sessions
##

sub _storage_create
{
  return 1
}

sub _storage_load
{
  return undef;
}

sub _storage_save
{
  return 1
}

sub _storage_delete
{
  return 1
}

sub _storage_exists
{
  return 0
}

sub _storage_debug_info
{
  return "Web::Reactor::Sessions::Dummy: no storage";
}

##############################################################################
1;
###EOF########################################################################
