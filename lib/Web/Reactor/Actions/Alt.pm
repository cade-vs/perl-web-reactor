##############################################################################
##
##  Web::Reactor application machinery
##  2013-2018 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  Adapted from Web::Reactor::Actions::Decor
##  Decor application machinery core
##  2014-2018 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
package Web::Reactor::Actions::Alt;
use strict;
use Exception::Sink;
use Web::Reactor::Actions;
use Data::Dumper;

use parent 'Web::Reactor::Actions';

# calls an action (function) by name
# args:
#       name   -- function/action name
#       %args  -- array used as named hash arguments
# args hash keys:
#       ARGS   -- hash reference of attributes/arguments passed to the action
# returns:
#       result text to be replaced in output
sub call
{
  my $self  = shift;

  my $name = lc shift;
  my %args = @_;

  my $reo = $self->get_reo();
  
  if( $name !~ /^[a-z_\-0-9]+$/ )
    {
    $reo->log( "error: invalid action name [$name] expected ALPHANUMERIC" );
    return undef;
    }

  my $cr = $self->__load_action_file( $name );

  if( ! $cr )
    {
    $reo->log( "error: cannot load action [$name]" );
    return undef;
    }

  my $data = $cr->( $reo, %args );

  return $data;
}

sub __load_action_file
{
  my $self  = shift;

  my $name = shift;

  my $reo = $self->get_reo();
  
  return $self->{ 'ACTIONS_CODE_CACHE' }{ $name } if exists $self->{ 'ACTIONS_CODE_CACHE' }{ $name };
  
  my $dirs = $self->{ 'ENV' }{ 'ACTIONS_DIRS' } || [];
  my $pkgs = $self->{ 'ENV' }{ 'ACTIONS_PKGS' } || 'reactor::actions::';
  
  my $found;
  for my $dir ( @$dirs )
    {
    my $file = "$dir/$name.pm"; # TODO: subdirs?
    next unless -e $file;
    $found = $file;
    last;
    }

  return undef unless $found;

  my $ap = $pkgs . $name;

  eval
    {
    delete $INC{ $found };
    require $found;
    };

  if( ! $@ )  
    {
    $reo->log_debug( "status: load action ok: $ap [$found]" );
    $self->{ 'ACTIONS_CODE_CACHE' }{ $name } = $cr = \&{ "${ap}::main" }; # call/function reference
    return $cr;
    }
  elsif( $@ =~ /Can't locate $found/)
    {
    $reo->log( "error: action not found: $ap [$found]" );
    }
  else
    {
    $reo->log( "error: load action failed: $ap: $@ [$found]" );
    }  

  return undef;
}

##############################################################################
1;
###EOF########################################################################

