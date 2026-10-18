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
## base class for all reactor's pawns
##
##############################################################################
package Web::Reactor::Base;
use strict;
use Scalar::Util;
use Hash::Util qw( lock_ref_keys );
use Exception::Sink;

sub new
{
  my $class = shift;
  my $reo   = shift;
  my $cfg   = shift;

  $class = ref( $class ) || $class;
  my $self = {};
  bless $self, $class;

  $self->{ 'CFG' } = $cfg;
  $self->__set_reo( $reo );

  return $self;
}

# for subclasses, not used by the framework itself: adds the given keys (undef)
# and locks the object keys, so a typo in a key name dies instead of hiding
sub __lock_self_keys
{
  my $self = shift;

  for my $key ( @_ )
    {
    next if exists $self->{ $key };
    $self->{ $key } = undef;
    }
  lock_ref_keys( $self );
}

sub __set_reo
{
  my $self = shift;

  my $reo = shift;

  # note: well, should be only reactor subclasses, not pawns but...
  if( ref( $reo ) =~ /^Web::Reactor(::|$)/ )
    {
    $self->{ 'REO_REACTOR' } = $reo;
    $self->{ 'HAS_REO'     } = 1; # the link is weak, reo_optional() booms if it is gone # cc20261017-1

    # weaken backlinks to reactor, needed for proper destruction
    Scalar::Util::weaken( $self->{ 'REO_REACTOR' } );
    }
  else
    {
    boom "Web::Reactor object required! missing or wrong class!";
    }

  return 1;
}

sub reo
{
  my $self = shift;

  return ( $self->{ 'REO_REACTOR' } or boom "missing Web::Reactor object" );
}

# # cc20261017-1
# for objects which work also without a reactor (HTML::Form, HTML::Tab):
# returns the reactor object or undef if none was set. an object made with a
# reactor never falls back to working without one: the link is weak, if the
# reactor is gone it booms
sub reo_optional
{
  my $self = shift;

  my $reo = $self->{ 'REO_REACTOR' };
  boom "the reactor object of this " . ref( $self ) . " is gone, it must not outlive it" if ! $reo and $self->{ 'HAS_REO' };
  return $reo;
}

sub cfg
{
  my $self = shift;

  return $self->{ 'CFG' };
}

#sub DESTROY
#{
#  my $self = shift;
#
#  print "DESTROY: Reactor: $self\n";
#}

### EOF ######################################################################
1;
