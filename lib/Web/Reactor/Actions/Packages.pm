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
package Web::Reactor::Actions::Packages;
use strict;
use Exception::Sink;
use Web::Reactor::Actions;
use Data::Dumper;

use parent 'Web::Reactor::Actions';

sub __find_code_by_name
{
  my $self = shift;
  my $name = lc shift;

  my $act_cache = $self->{ 'Web::Reactor::Actions::Packages' }{ 'CACHE' } ||= {};

  return $act_cache->{ $name } if exists $act_cache->{ $name };

  my $reo = $self->reo();
  my $cfg = $self->cfg();

  my $app_name = $cfg->{ 'APP_NAME' };
  # action packages are found via require() through @INC, LIB_DIRS are pushed there by Web::Reactor::Actions::new()

  # actions sets list
  my @asl = @{ $cfg->{ 'ACTIONS_SETS' } || [] };
  @asl = ( $app_name, "Base", "Core" ) unless @asl > 0;

  # action package
  for my $asl ( @asl )
    {
    my $ap = 'Web::Reactor::Actions::' . $asl . '::' . $name;

    # print STDERR "testing action: $ap\n";
    my $fn = $ap;
    $fn =~ s/::/\//g;
    $fn .= '.pm';
    eval
      {
      require $fn;
      };
    if( ! $@ )
      {
      # package loaded but has no main(): a reference to an undefined sub would
      # only fail later inside call() with a generic "Undefined subroutine"
      if( ! defined &{ "${ap}::main" } )
        {
        $act_cache->{ $name } = undef;
        $reo->log( "error: action package [$ap] loaded from [$fn] but has no main() sub" );
        return undef;
        }
      my $code = $act_cache->{ $name } = \&{ "${ap}::main" }; # call/function reference

      #print STDERR "LOADED! action: $ap: $fn\n";
      return $code;
      }
    elsif( $@ =~ /^Can't locate \Q$fn\E in \@INC/ )
      {
      # this action package does not exist in this set, try the next one,
      # this is the normal fallback, so it is only a debug message
      $act_cache->{ $name } = undef;
      $reo->log_debug( "debug: action not in set [$asl]: $ap [$fn]" );
      }
    elsif( $@ =~ /^Can't locate \S+\.pm in \@INC/ ) # not "Can't locate object method"
      {
      # the action package exists but a module it uses is missing: stop here,
      # the same action in the next set must not run in its place
      $act_cache->{ $name } = undef;
      $reo->log( "error: action package [$ap] loaded from [$fn] but a module it uses cannot be found: $@" );
      return undef;
      }
    else
      {
      # the action package exists but fails to compile or to load: stop here,
      # the same action in the next set must not run in its place
      $act_cache->{ $name } = undef;
      $reo->log( "error: load action failed: $ap [$fn] $@" );
      return undef;
      }
    }

  $reo->log( "error: action [$name] not found in any of the action sets [@asl]" );
  return undef;
}

##############################################################################
1;
###EOF########################################################################
