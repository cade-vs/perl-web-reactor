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
##
##  Adapted from Web::Reactor::Actions::Decor
##  Decor application machinery core
##  Copyright (c) 2014-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com> <cade@bis.bg> <cade@cpan.org>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-decor
##
##############################################################################
package Web::Reactor::Actions::Files;
use strict;
use Exception::Sink;
use Web::Reactor::Actions;
use Data::Dumper;

use parent 'Web::Reactor::Actions';

sub __find_code_by_name
{
  my $self = shift;
  my $name = lc shift;

  my $act_cache = $self->{ 'Web::Reactor::Actions::Files' }{ 'CACHE' } ||= {};

  return $act_cache->{ $name } if exists $act_cache->{ $name };

  my $reo = $self->reo();
  my $cfg = $self->cfg();

  my $dirs = $cfg->{ 'ACTIONS_DIRS' } || [ $cfg->{ 'APP_ROOT' } . '/actions' ];
  my $pkgs = $cfg->{ 'ACTIONS_PKGS' } || 'reactor::actions::';

  my $found;
  for my $dir ( @$dirs )
    {
    my $file = "$dir/$name.pm"; # TODO: subdirs?
    next unless -e $file;
    $found = $file;
    last;
    }

  # TODO: cache for missing ones
  return undef unless $found;

  my $ap = $pkgs . $name;

  eval
    {
    # the action file is loaded again on its first call in each request (the
    # act object and its cache live per request), so changed action files are
    # picked up without a server restart
    delete $INC{ $found };
    require $found;
    };

  if( ! $@ )
    {
    $reo->log_debug( "status: load action ok: $ap [$found]" );
    # file loaded but declares no main() (or a different package than ACTIONS_PKGS expects)
    if( ! defined &{ "${ap}::main" } )
      {
      $act_cache->{ $name } = undef;
      $reo->log( "error: action file [$found] loaded but package [$ap] has no main() sub, check ACTIONS_PKGS" );
      return undef;
      }
    my $code = $act_cache->{ $name } = \&{ "${ap}::main" }; # call/function reference
    return $code;
    }
  elsif( $@ =~ /^Can't locate / )
    {
    # the action file exists, so the missing file is a module it uses
    $act_cache->{ $name } = undef;
    $reo->log( "error: action file loaded but a module it uses cannot be found: $ap [$found] $@" );
    }
  else
    {
    # the action file fails to compile or to load, do not try it again in
    # this request
    $act_cache->{ $name } = undef;
    $reo->log( "error: load action failed: $ap [$found] $@" );
    }

  return undef;
}

##############################################################################
1;
###EOF########################################################################

