##############################################################################
##
##  Web::Reactor application machinery
##  2013 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
package Web::Reactor::Prep::Expander;
use strict;
use Web::Reactor::Prep;

our @ISA = qw( Web::Reactor::Prep );

sub new
{
  my $class = shift;
  my %env = @_;
  
  $class = ref( $class ) || $class;
  my $self = {
             'ENV'       => \%env,
             };
  bless $self, $class;
  # rcd_log( "debug: rcd_rec:$self created" );
  
  return $self;
}


##############################################################################
1;
###EOF########################################################################
