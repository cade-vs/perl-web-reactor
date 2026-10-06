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
package Web::Reactor::Sessions::Filesystem;
use strict;
use Exception::Sink;
use Web::Reactor::Sessions;
use Fcntl qw( O_CREAT O_EXCL O_WRONLY );
use Data::Tools 1.53; # hash_load_json(), hash_save_json()
use Data::Dumper;

use parent 'Web::Reactor::Sessions';

my $SPLIT_PARTS_CNT = 2;
my $SPLIT_PARTS_LEN = 2;
my $MIN_SES_ID_LEN = $SPLIT_PARTS_CNT * $SPLIT_PARTS_LEN;

sub get_min_ses_id_len { return $MIN_SES_ID_LEN; }

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
#       key  -- key components array reference, from compose_key_from_sid():
#               [ TYPE, SID ] or, for types with a parent, [ TYPE, PSID, SID ]
#       shr  -- session hashref, written as the initial session data
# returns:
#       1 if created, 0 if the session id already exists, undef on storage error
sub _storage_create
{
  my $self = shift;
  my $key  = shift;
  my $shr  = shift;

  my $fn = $self->_key_to_fn( {}, @$key );
  my $F;
  if( sysopen $F, $fn, O_CREAT | O_EXCL | O_WRONLY, 0600 )
    {
    my $j = hash2json( $shr );
    return undef unless $j;
    return undef unless print $F $j;
    return undef unless close $F;
    return 1;
    }
  else
    {
    return $!{EEXIST} ? 0 : undef;
    }
}

# loads session data from the storage
# args:
#       key  -- key components array reference, see _storage_create()
# returns:
#       hashref of session data or undef if error
sub _storage_load
{
  my $self = shift;
  my $key  = shift;

  my $fn = $self->_key_to_fn( { READONLY => 1 }, @$key );
  if( ! -r $fn )
    {
    $self->reo()->log_debug( "session file missing or not readable: $fn" );
    return undef;
    }
  my $shr;
  eval
    {
    $shr = hash_load_json( $fn );
    boom "error: cannot retrieve session data from [$fn]" unless $shr;
    };
  if( $@ )
    {
    $self->reo()->log( "error: retrieving session failed $fn\n($@)" );
    return undef;
    }

#print STDERR Dumper( "******* _storage_load [$fn] *******", $in_data );

  return $shr;
}

# saves session data to the storage
# args:
#       key  -- key components array reference, see _storage_create()
#       shr  -- session hashref to save
# returns:
#       1 if successful, undef or 0 if failed
sub _storage_save
{
  my $self = shift;
  my $key  = shift;
  my $shr  = shift;

  my $fn = $self->_key_to_fn( {}, @$key );

#print STDERR Dumper( "******* _storage_save [$fn] *******", $out_data );

  # the data goes into a temp file first and is renamed over the session file,
  # so a reader never sees a partial file; a failed temp file is removed
  my $tmp = "$fn.tmp.$$.part";
  if( ! hash_save_json( $tmp, $shr ) )
    {
    unlink( $tmp ); # a partial file may be left
    return undef;
    }
  chmod( 0600, $tmp ); # FIXME: must be moved to file_save()
  my $rc = rename( $tmp, $fn );
  unlink( $tmp ) unless $rc; # do not litter the session dir
  return $rc;
}

# deletes session data from the storage
# args:
#       key  -- key components array reference, see _storage_create()
# returns:
#       1 if deleted or it did not exist, undef if failed
sub _storage_delete
{
  my $self = shift;
  my $key  = shift;

  my $fn = $self->_key_to_fn( { READONLY => 1 }, @$key );

  return 1 if unlink( $fn ) or ! -e $fn;

  $self->reo()->log( "error: cannot delete session file: $fn ($!)" );
  return undef;
}

# checks if session exists in the storage
# args:
#       key  -- key components array reference, see _storage_create()
# returns:
#       1 if exists, 0 if not
sub _storage_exists
{
  my $self = shift;
  my $key  = shift;

  my $fn = $self->_key_to_fn( { READONLY => 1 }, @$key );

  return -e $fn ? 1 : 0;
}

# return information about storage configuration, i.e. file path for Filesystem, etc.
# args:
#       none
# returns:
#       information text
sub _storage_debug_info
{
  my $self = shift;

  my $vd = $self->__sess_var_dir();

  return "Web::Reactor::Sessions::Filesystem: session directory: [$vd]";
}

##############################################################################
##
##  helpers
##

# session storage directory: SESS_VAR_DIR or, by default, APP_ROOT/var
sub __sess_var_dir
{
  my $self = shift;

  my $cfg = $self->cfg();

  return $cfg->{ 'SESS_VAR_DIR' } || "$cfg->{ 'APP_ROOT' }/var";
}

# i.e.: _split_dir_components( '1234567890', 3, 3 ) returns '123/456/789/1234567890'
sub _split_dir_components
{
  my $self = shift;

  my $s = shift;
  my $c = shift || $SPLIT_PARTS_CNT; # parts count
  my $l = shift || $SPLIT_PARTS_LEN; # how long is each part

  boom "Web::Reactor::Sessions::Filesystem::_split_dir_components: id [$s] is shorter than [$MIN_SES_ID_LEN] chars" unless length( $s ) >= $MIN_SES_ID_LEN;

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
  boom "invalid key component 0, needs ALPHA type, got [$r]" unless $r =~ /^[A-Z]+$/;

  my $cfg = $self->cfg();

  if( ! $cfg->{ 'SESS_VAR_DIR' } )
    {
    my $app_root = $cfg->{ 'APP_ROOT' };
    boom "missing APP_ROOT" unless -d $app_root; # FIXME: function? get_app_root()
    }
  my $vd = $self->__sess_var_dir();
  dir_path_ensure( $vd ) unless -d $vd;
  boom "missing SESS_VAR_DIR or APP_ROOT/var [$vd]" unless -d $vd;

  while( @key > 0 )
    {
    my $c = shift @key;
    boom "invalid key component needs ALPHANUMERIC with min length of [$MIN_SES_ID_LEN], got [$c]" unless length( $c ) >= $MIN_SES_ID_LEN and $c =~ /^[A-Za-z0-9_]+$/;
    $r .= '/' . $self->_split_dir_components( $c );
    }

  my $dir = $vd . '/' . $r;
  my $chk = $dir;
  $chk =~ s/\/[^\/]*$//;
  dir_path_ensure( $chk ) unless $opt->{ 'READONLY' };

  return $dir . '.wrs2';
}

##############################################################################
1;
###EOF########################################################################
