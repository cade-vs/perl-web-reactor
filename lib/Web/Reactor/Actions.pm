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
package Web::Reactor::Actions;
use strict;

use Data::Dumper;
use Exception::Sink;

use parent 'Web::Reactor::Base';

sub new
{
  my $class = shift;

  $class = ref( $class ) || $class;
  my $self = $class->SUPER::new( @_ );

  my $reo = $self->reo();
  my $cfg = $self->cfg();

  my $dirs = $cfg->{ 'LIB_DIRS' };

  # FIXME: common directories setup code?
  # single directory (scalar) specified, convert to list
  $dirs = [ $dirs ] if ! ref( $dirs ) and $dirs;
  # nothing specified, set default
  $dirs = [ $reo->get_app_root() . '/lib/' ] if ! $dirs or @{ $dirs } < 1;

  for my $lib_dir ( @$dirs )
    {
    next unless -d $lib_dir;
    next if grep { $_ eq $lib_dir } @INC; # persistent servers call new() per request
    push @INC, $lib_dir;
    }

  # remove '.'
  @INC = grep { $_ ne '.' } @INC;

  return $self;
}

# calls an action (function) by name
# args:
#       name   -- function/action name
#       %args  -- array used as named hash arguments
# args hash keys:
#       HTML_ARGS -- hash reference of the action tag arguments, set by
#                    Web::Reactor::Preprocessor::Tree for <&action ...> tags,
#                    other callers may pass any named arguments
# returns:
#       action result: text to be replaced in output, or portray data (see
#       Web::Reactor::Core::portray()), undef if the action failed
sub call
{
  my $self  = shift;

  my $name = lc shift;
  my %args = @_;

  $self->check_action_name( $name );

  my $code = $self->__find_code_by_name( $name );

#  print STDERR Dumper( 'Web::Reactor::Actions::call()', $name, $code, \%args );

  boom "code for action name [$name] not found" unless $code;

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
    $reo->log( "error: action code call failed: $name: $@\nwith args: " . Dumper( \%args ) );
    return undef;
    }

  # print STDERR "reactor::actions::call result: $data\n";

  return $data;
}

sub __find_code_by_name
{
  boom "Web::Reactor::Actions::*::__find_code_by_name() is not implemented!";
}

#sub DESTROY
#{
# my $self = shift;
#
# print "DESTROY: Reactor: $self\n";
#}

##############################################################################

sub check_action_name
{
  my $self = shift;
  boom "invalid action name [$_[0]]" unless $_[0] =~ /^[a-z0-9_]+$/;
}

##############################################################################
1;
###EOF########################################################################
