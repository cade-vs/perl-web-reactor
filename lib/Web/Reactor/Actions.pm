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
package Web::Reactor::Actions;
use strict;

use Exception::Sink;

use parent 'Web::Reactor::Base';

sub new
{
  my $class = shift;

  $class = ref( $class ) || $class;
  my $self = $class->SUPER::new( @_ );

  return $self;
}

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


  die "invalid action name, expected ALPHANUMERIC, got [$name]" unless $name =~ /^[a-z_0-9]+$/;

  my $code = $self->__find_code_by_name( $name );

#  print STDERR Dumper( 'Web::Reactor::Actions::call()', $name, $code, \%args );

  boom "code for action name [$name] not found" unless $code;

  # FIXME: move to global error/log reporting
  #print STDERR "reactor::actions::call [$name] action package found [$ap]\n";

  my $data;

  eval
    {
    $data = $code->( $self->reo(), %args );
    };
  if( surface( 'RENDER' ) )
    {
    dive();
    }
  elsif( surface( '*' ) )
    {
    my $reo = $self->reo();
    my @args = %args;
    $reo->log( "error: action code call failed: $name( @args ): $@" );
    return undef;
    }

  # print STDERR "reactor::actions::call result: $data\n";

  return $data;
}

sub __find_code_by_name
{
  die "Web::Reactor::Actions::__find_code_by_name() must be implemented in subclasses!";
}

#sub DESTROY
#{
# my $self = shift;
#
# print "DESTROY: Reactor: $self\n";
#}

##############################################################################
1;
###EOF########################################################################
