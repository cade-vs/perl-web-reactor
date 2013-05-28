##############################################################################
##
##  Web::Reactor application machinery
##  2013 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
package Web::Reactor::Actions::Native;
use strict;
use Carp;
use Web::Reactor::Actions;
use Data::Dumper;

our @ISA = qw( Web::Reactor::Actions );

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

  my $ap = $self->__find_act_pkg( $name );

#  print STDERR Dumper( $name, $ap, \%{ $ap } );

  if( ! $ap )
    {
    confess "action package for action name [$name] not found";
    return undef;
    }

  # FIXME: move to global error/log reporting
  print STDERR "reactor::actions::call [$name] action package found [$ap]\n";

  my $cr = \&{ "${ap}::main" }; # call/function reference

  my $text;

  $text = $cr->( $self->{ 'REO_REACTOR' }, \%args );

  print STDERR "reactor::actions::call result: $text\n";

  return $text;
}

sub __find_act_pkg
{
  my $self  = shift;

  my $name = lc shift;

  my $app_name = lc $self->{ 'ENV' }{ 'APP_NAME' };
  my $dirs = $self->{ 'ENV' }{ 'LIB_DIRS' } || [];
  if( @$dirs == 0 )
    {
    my $app_root = $self->{ 'ENV' }{ 'APP_ROOT' };
    $dirs = [ "$app_root/lib" ]; # FIXME: 'act' actions ?
    }

  # action package
  for my $ap ( "Reactor::Actions::${app_name}::${name}", "Reactor::Actions::Base::${name}" )
  {
    my $fn = $ap;
    $fn =~ s/::/\//g;
    # paths
    for my $p ( @$dirs )
      {
      my $ffn = "$p/$fn.pm";
    print STDERR "actions: $ap --> $fn --> $ffn\n";
      next unless -e $ffn;
      # FIXME: check require status!
      require $ffn;
      # print "FOUND ", %INC;
      return $ap;
      }
  }

  return undef;
}

##############################################################################
1;
###EOF########################################################################

