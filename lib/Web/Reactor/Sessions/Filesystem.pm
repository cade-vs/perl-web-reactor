##############################################################################
##
##  Web::Reactor application machinery
##  2013 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
package Web::Reactor::Sessions::Filesystem;
use strict;
use Web::Reactor::Sessions;
use Web::Reactor::Utils;
use POSIX;
use Storable qw( freeze thaw lock_store lock_retrieve );
use Data::Dumper; 
use Carp;

our @ISA = qw( Web::Reactor::Sessions );

##############################################################################
##
##  internal storage methods
##  they are all internal to this package
##

# create new session storage indexed by the given key components
# it is important that this function try to do atomic create in the storage.
# it must (and expected to) fail if session with the same key exists and never
# overwrite existing session storage!
# args:
#       @key (i.e. @_) -- key components array, usually filled with 2 or 3 elements
#                         when 2: TYPE, SESS7c87y32d78asa4
#                         when 3: TYPE, SESS187yc5v87thccf, SESS2jdhfh74yc3847
#                         usually it is simple to $key = join '.' @_;
#
# returns:
#       1 if successful or 0 or undef if not possible or session id already exists
sub _storage_create
{
  my $self = shift;
  
  my $fn = $self->_key_to_fn( {}, @_ );
  my $F;
  if( sysopen $F, $fn, O_CREAT | O_EXCL, oct(600) )
    {
    close $F;
    return 1;
    }
  else
    {
    return 0;
    }  
}

# loads session data from the storage
# args:
#       @key (i.e. @_) -- key components array, example: $key = join '.' @_;
# returns:
#       hashref of session data or undef if error
sub _storage_load
{
  my $self = shift;
  
  my $fn = $self->_key_to_fn( { READONLY => 1 }, @_ );
  if( ! -r $fn )
    {
    carp "error: session file not readable: $fn";
    return undef;
    }
  my $in_data;
  eval
    {
    $in_data = lock_retrieve( $fn );
    die "error: cannot retrieve session data from [$fn]" unless $in_data;
    };
  if ($@)
    {
    carp "error: retrieving session failed $fn\n($@)"; # FIXME: must not be fatal
    return undef;
    }

  return $in_data;
}

# saves session data to the storage
# args:
#       data -- hashref of session data
#       @key (i.e. @_) -- key components array, example: $key = join '.' @_;
# returns:
#       1 if successful, 0 or undef if failed
sub _storage_save
{
  my $self = shift;
  my $out_data = shift;
  
  my $fn = $self->_key_to_fn( {}, @_ );

  return lock_store( $out_data, $fn );
}

# checks if session exists in the storage
# args:
#       @key (i.e. @_) -- key components array, example: $key = join '.' @_;
# returns:
#       1 if exists, 0 or undef if not
sub _storage_exists
{
  my $self = shift;
  
  my $fn = $self->_key_to_fn( { READONLY => 1 }, @_ );
  
  return -e $fn ? 1 : 0;
}

##############################################################################
##
##  helpers
##

# i.e.: _split_dir_components( '1234567890', 3, 3 ) returns '123/456/789/0'
sub _split_dir_components
{
  my $self = shift;
  
  my $s = shift;
  my $c = shift; # parts count
  my $l = shift || 2; # how long is each part
  
  die "Web::Reactor::Sess::Filesystem:_split_dir_components: parts*length > length(s)-1" if $c * $l > length( $s ) - 1;

  my $r; # result
  
  for my $p ( 0 .. $c-1 )
    {
    $r .= substr( $s, $p * $l, $l ) . '/';
    }
  # $r .= substr( $s, $c * $l );  
  $r .= $s;  
  
  return $r;  
}

sub _key_to_fn
{
  my $self = shift;
  my $opt  = shift;
  my @key  = @_;

  my $r = shift @key; # this should be type
  confess "invalid key component 0, needs ALPHANUMERIC type, got [$r]" unless $r =~ /^[A-Z]+$/;
  
  my $vd = $self->{ 'ENV' }{ 'SESS_VAR_DIR' };
  confess "missing SESS_VAR_DIR" unless $vd;

  while( @key > 0 )
    {
    my $c = shift @key;
    confess "invalid key component needs ALPHANUMERIC, got [$c]" unless $c =~ /^[A-Za-z0-9]+$/;
    $r .= '/' . $self->_split_dir_components( $c, 2, 2 );
    }

  my $dir = $vd . '/' . $r;
  my $chk = $dir;
  $chk =~ s/\/[^\/]*$//;
  dir_path_check( $chk ) unless $opt->{ 'READONLY' };

  return $dir . '.wrs';
}

##############################################################################
1;
###EOF########################################################################
