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
use Data::Tools 1.53; # hash_load_json(), hash_save_json(), hash2json(), dir_path_ensure()
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
# overwrite existing session storage! a file it created but could not write
# is removed here, see Sessions::_storage_create()
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
    return 1 if $j and print( $F $j ) and close( $F );
    close( $F );
    unlink( $fn ); # only the file created here, a partial session
    return undef;
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
#       hashref of session data or undef if missing, not readable or on error
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
#       1 if saved, 0 if closed or missing (not saved), undef on storage
#       error, see Sessions::save()
sub _storage_save
{
  my $self = shift;
  my $key  = shift;
  my $shr  = shift;

  my $fn = $self->_key_to_fn( {}, @$key );

#print STDERR Dumper( "******* _storage_save [$fn] *******", $out_data );

  return 0 if $self->_storage_is_closed( $key ); # closed for good, see Sessions::close()

  return 0 unless -e $fn; # deleted meanwhile (or never created), only create() creates

  # the data goes into a temp file first and is renamed over the session file,
  # so a reader never sees a partial file; a failed temp file is removed
  my $tmp = "$fn.tmp.$$.part";
  my $rc = hash_save_json( $tmp, $shr ) && chmod( 0600, $tmp ) && rename( $tmp, $fn ); # FIXME: chmod must be moved to file_save()
  return 1 if $rc;

  unlink( $tmp ); # a partial or not renamed temp file, do not litter the session dir
  return undef;
}

# marks the session closed for good: a separate close mark file next to the
# session file, with the close fields as json, a save never touches it
# args:
#       key    -- key components array reference, see _storage_create()
#       fields -- hashref of the close fields (optional, an empty mark without)
# returns:
#       1 if closed (also if it was closed before, the first close mark stays),
#       undef on storage error
sub _storage_close
{
  my $self   = shift;
  my $key    = shift;
  my $fields = shift;

  my $fn = $self->_key_to_fn_closed( {}, @$key );
  my $F;
  if( sysopen $F, $fn, O_CREAT | O_EXCL | O_WRONLY, 0600 )
    {
    my $j = $fields ? hash2json( $fields ) : '';
    return ( defined $j and print( $F $j ) and close( $F ) ) ? 1 : undef; # a mark without its fields still closes
    }
  return $!{EEXIST} ? 1 : undef; # closed before, the first close stays
}

# checks the close mark, see Sessions::close() and Sessions::_storage_is_closed()
# args:
#       key  -- key components array reference, see _storage_create()
#       hr   -- hashref, gets the close fields of the close mark (optional)
# returns:
#       undef if not closed, else hr (with the fields which could be read) or
#       1 without hr
sub _storage_is_closed
{
  my $self = shift;
  my $key  = shift;
  my $hr   = shift;

  my $fn = $self->_key_to_fn_closed( { READONLY => 1 }, @$key );
  return undef unless -e $fn;
  return 1 unless $hr;

  my $data = -s $fn ? eval { hash_load_json( $fn ) } : undef; # an empty or unreadable mark still closes
  @$hr{ keys %$data } = values %$data if $data;
  return $hr;
}

# the close mark file name, the session file name with .closed
sub _key_to_fn_closed
{
  my $self = shift;

  my $fn = $self->_key_to_fn( @_ );
  return $fn . '.closed';
}

# deletes session data from the storage
# args:
#       key  -- key components array reference, see _storage_create()
# returns:
#       1 if deleted or it did not exist, undef if failed. the session file goes
#       first, then its close mark: if the session cannot be deleted, it keeps
#       its mark and stays closed
sub _storage_delete
{
  my $self = shift;
  my $key  = shift;

  my $fn  = $self->_key_to_fn( { READONLY => 1 }, @$key );
  my $cfn = $self->_key_to_fn_closed( { READONLY => 1 }, @$key );

  for my $f ( $fn, $cfn ) # the close mark goes with the session
    {
    next if unlink( $f ) or ! -e $f;
    $self->reo()->log( "error: cannot delete session file: $f ($!)" );
    return undef;
    }

  return 1;
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

  my $m = $c * $l; # all parts must be full
  boom "Web::Reactor::Sessions::Filesystem::_split_dir_components: id [$s] is shorter than [$m] chars" unless length( $s ) >= $m;

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
  boom "invalid key component 0, needs ALPHA type, got [$r]" unless $r =~ /^[A-Z]+\z/;

  my $cfg = $self->cfg();

  if( ! $cfg->{ 'SESS_VAR_DIR' } )
    {
    my $app_root = $cfg->{ 'APP_ROOT' };
    boom "missing APP_ROOT or not a directory [$app_root]" unless -d $app_root; # FIXME: function? get_app_root()
    }
  my $vd = $self->__sess_var_dir();
  dir_path_ensure( $vd ) unless -d $vd;
  boom "missing SESS_VAR_DIR or APP_ROOT/var [$vd]" unless -d $vd;

  while( @key > 0 )
    {
    my $c = shift @key;
    boom "invalid key component needs [A-Za-z0-9_] with min length of [$MIN_SES_ID_LEN], got [$c]" unless length( $c ) >= $MIN_SES_ID_LEN and $c =~ /^[A-Za-z0-9_]+\z/; # \z: no trailing newline
    $r .= '/' . $self->_split_dir_components( $c );
    }

  my $fn  = $vd . '/' . $r; # session file name without extension
  my $dir = $fn;
  $dir =~ s/\/[^\/]*\z//;
  dir_path_ensure( $dir ) unless $opt->{ 'READONLY' };

  return $fn . '.wrs2';
}

##############################################################################
1;
###EOF########################################################################
