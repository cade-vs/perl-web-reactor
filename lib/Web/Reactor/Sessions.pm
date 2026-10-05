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
package Web::Reactor::Sessions;
use strict;
use Exception::Sink;
use Crypt::PRNG;
use Data::Tools 1.24;

use parent 'Web::Reactor::Base';

my $MIN_SES_ID_LEN = 4;
sub get_min_ses_id_len { return $MIN_SES_ID_LEN; }

my @HNS = qw(
    Abby Ada Alexa Alfie Alia Alice Anna Aria Ava Axel Beau Bran Chanel Cali Calla Carys Cole Cruz Dash Dean Demi Dior Dora Drew Eira Eli
    Elise Ella Elle Ellie Elsa Emma Enzo Eva Eve Evie Faye Fia Fifi Fox Freya Gabe Gaia Gia Greer Gwen Gogo Gyro Hugo Ilia Ilse Iris Isla
    Indie Inez Ivan Jace James Joki Juko Juki Jack June Jimmy John Kaia Kali Kate Kaya Kent Kim Kitty Knox Lane Lani Leda Lexi Levi Liam
    Liv Lola Lucia Lucy Luna Lyra Macy Maya Mimi Mia Milo Mina Mira Nash Neo Neve Noel Nola Nora Onyx Orla Owen Pearl Prue Reid Rhea Rhys
    Rose Rimini Rome Rita Ruby Rumi Runa Ryla Siena Sofia Sage Shea Svea Tate Taya Thera Tori Tinko Tina Tupcho Tova Toto Trudi Trina Uma
    Uber Una Uno Viki Vera Voom Veda Vidin Vida Vita Wells Willa Wren Xena Xylo Yael Zezo Zaza Zane Zuki Zooo Zana Zara Zeev Zeno Zera Zoro
    );

our %SESSION_TYPES = (
                       'USER' => undef,
                       'HOLD' => undef,
                       'COOK' => undef,
                       'LINK' => 'COOK',
                       'PAGE' => 'USER',
                     );

##############################################################################
##
##  public interface methods, should be used via Reactor object, see specs
##

# creates a new session of given type, allocates its storage and writes the
# initial session data, the only place where :TYPE, :SID and :PSID are set
# args:
#       type -- session type, one of %SESSION_TYPES
#       psid -- parent session id, required for types with a parent (PAGE,
#               LINK), undef for the rest
#       len  -- session id length (optional, default 73)
# returns:
#       new session hashref with :TYPE, :SID and :PSID set, booms on failure
sub create
{
  my $self = shift;
  my $type = uc shift;
  my $psid = shift; # parent sid
  my $len  = shift || 73; # 21st prime :)

  boom "Web::Reactor::Sessions::create: invalid type, expected ALPHANUMERIC, got [$type]" unless $type =~ /^[A-Z0-9]+$/;
  boom "Web::Reactor::Sessions::create: invalid length, expected len >= $MIN_SES_ID_LEN, got [$len]" unless $len >= $MIN_SES_ID_LEN;

  my $cfg  = $self->cfg();

  my $shr = { ':TYPE' => $type, ':SID' => '?', ':PSID' => $psid };

  my $sid;
  my $ts = time();
  my $to = $cfg->{ 'SESS_CREATE_TIMEOUT'       } ||    5; # seconds
  my $tc = $cfg->{ 'SESS_CREATE_TIMEOUT_COUNT' } || 1023; # count, should not be reached anyway
  while( $tc-- and time() - $ts < $to )
    {
    $sid = $self->create_id( $len );
    $sid = $HNS[rand(@HNS)] . '_' . $sid if $self->reo->is_debug();
    $shr->{ ':SID' } = $sid;

    my $key = $self->compose_key_from_sid( $type, $sid, $psid );
    my $rc = $self->_storage_create( $key, $shr );
    return $shr if $rc;
    next if defined $rc;
    $self->_storage_delete( $key );
    boom "Web::Reactor::Sessions::create: storage error creating session type [$type] parent sid [$psid], key [@$key], " . $self->_storage_debug_info();
    }

  boom "Web::Reactor::Sessions::create: no free id for session type [$type] parent sid [$psid] in time, " . $self->_storage_debug_info();
}

# loads session data from the storage
# args:
#       type -- session type, one of %SESSION_TYPES
#       sid  -- session id
#       psid -- parent session id, required for types with a parent
# returns:
#       session hashref or undef if missing or not readable, booms on an
#       invalid type or malformed sid, see compose_key_from_sid()
sub load
{
  my $self = shift;
  my $type = uc shift;
  my $sid  = shift;
  my $psid = shift;

  my $key = $self->compose_key_from_sid( $type, $sid, $psid );

  return $self->_storage_load( $key );
}

# saves session data to the storage, under the key built from the session's
# own :TYPE, :SID and :PSID
# args:
#       shr  -- session hashref, as returned by create() or load()
# returns:
#       1 if successful, undef or 0 if failed
sub save
{
  my $self = shift;
  my $shr  = shift; # session hashref

  return $self->_storage_save( $self->__shr_to_key( $shr ), $shr );
}

# deletes a session from the storage
# args:
#       shr  -- session hashref, as returned by create() or load()
# returns:
#       1 if deleted or already missing, undef if failed
sub delete
{
  my $self = shift;
  my $shr  = shift; # session hashref

  return $self->_storage_delete( $self->__shr_to_key( $shr ) );
}

# checks if session exists in the storage
# args:
#       shr  -- session hashref, as returned by create() or load()
# returns:
#       1 if exists, 0 if not
sub exists
{
  my $self = shift;
  my $shr  = shift; # session hashref

  return $self->_storage_exists( $self->__shr_to_key( $shr ) );
}

##############################################################################

sub __shr_to_key
{
  my $self = shift;
  my $shr  = shift; # session hashref

  my $type = $shr->{ ':TYPE' };
  my $sid  = $shr->{ ':SID'  };
  my $psid = $shr->{ ':PSID' };

  return $self->compose_key_from_sid( $type, $sid, $psid );
}

##############################################################################
##
##  methods, which must be implemented in sub-classes!
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
sub _storage_create { boom "Web::Reactor::Sessions::*::_storage_create() is not implemented!"; }

# delete session data from the storage
# args:
#       key  -- key components array reference, see _storage_create()
# returns:
#       1 if deleted or already missing, undef if failed
sub _storage_delete   { boom "Web::Reactor::Sessions::*::_storage_delete() is not implemented!"; }

# loads session data from the storage
# args:
#       key  -- key components array reference, see _storage_create()
# returns:
#       hashref of session data or undef if error
sub _storage_load   { boom "Web::Reactor::Sessions::*::_storage_load() is not implemented!"; }

# saves session data to the storage
# args:
#       key  -- key components array reference, see _storage_create()
#       shr  -- session hashref to save
# returns:
#       1 if successful, undef or 0 if failed
sub _storage_save   { boom "Web::Reactor::Sessions::*::_storage_save() is not implemented!"; }

# checks if session exists in the storage
# args:
#       key  -- key components array reference, see _storage_create()
# returns:
#       1 if exists, 0 if not
sub _storage_exists { boom "Web::Reactor::Sessions::*::_storage_exists() is not implemented!"; }

# return information about storage configuration, i.e. file path for Filesystem, etc.
# args:
#       none
# returns:
#       information text
sub _storage_debug_info { boom "Web::Reactor::Sessions::*::_storage_debug_info() is not implemented!"; }

##############################################################################
##
##
##

# return string with new session id with given LEN argument or default length
# args:
#       len  --  session id length (optional, 0 or undef for default length)
#       letters -- letters to be used for session id creation (optional)
#                  must be non-whitespace characters string with no duplicates
# returns:
#       id -- session id string
sub create_id
{
  my $self = shift;
  my $cfg  = $self->cfg();

  my $len = shift() || $cfg->{ 'SESS_LENGTH'  } || 73; # 21st prime :)
  my $let = shift() || $cfg->{ 'SESS_LETTERS' } || 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  return Crypt::PRNG::random_string_from( $let, $len );
}

sub compose_key_from_sid
{
  my $self = shift;
  my $type = uc shift;
  my $sid  = shift;
  my $psid = shift;

  boom "invalid session type [$type]" unless exists $SESSION_TYPES{ $type };
  boom "invalid SID [$sid]"   unless __check_session_id( $sid   );
  boom "invalid PSID [$psid]" if $psid and ! __check_session_id( $psid  );

  if( $SESSION_TYPES{ $type } )
    {
    boom "missing PSID for SID [$sid] type [$type]" unless $psid;
    }
  else
    {
    boom "PSID not applicable for session type [$type]" if $psid;
    }

  my @key;

  push @key, $type;
  push @key, $psid if $psid; # this line is the only reason for this func but yet it checks session attrs
  push @key, $sid;

  return \@key;
}

##############################################################################
##
##  helpers for session in-memory state (cache), obsolete: the cache now lives
##  in Web::Reactor (sc_*), the old code is kept below for reference only
##


=begin comment

# sets current cache session
sub state_set_active
{
  my $self = shift;

  my $type = shift;
  my $sid  = shift;
  my $shr  = shift;

  boom "invalid session type [$type]" unless exists $PARENT_SESSION_TYPES{ $type };

  my $cid = $self->{ 'SID' }{ $type };

  boom( "active [$type] session already set to [$cid] <-- [$sid]" ) if $cid;

  $self->{ 'SID' }{ $type }         = $sid;
  $self->{ 'SHR' }{ $type }{ $sid } = $shr;

  1;
}

# get current session ID by TYPE
sub state_get_sid
{
  my $self = shift;

  my $type = shift;

  boom "invalid session type [$type]" unless exists $PARENT_SESSION_TYPES{ $type };

  return $self->{ 'SID' }{ $type };
}

# gets any cached session
sub state_get_ses
{
  my $self = shift;

  my $type = shift;
  my $sid  = shift; # if not specified will return active session

  boom "invalid session type [$type]" unless exists $PARENT_SESSION_TYPES{ $type };

  $sid ||= $self->{ 'SID' }{ $type };
  my $shr = $self->{ 'SHR' }{ $type }{ $sid };

  return wantarray ? ( $sid, $shr ) : $shr;
}

# adds session to the cache
sub state_add
{
  my $self = shift;

  my $type = shift;
  my $sid  = shift;
  my $shr  = shift;

  boom "invalid session type [$type]" unless exists $PARENT_SESSION_TYPES{ $type };

  boom( "session [$type:$sid] already added" ) if $self->{ 'SHR' }{ $type }{ $sid };

  $self->{ 'SHR' }{ $type }{ $sid } = $shr;

  1;
}

# deactivates current session of given TYPE, the session data stays in the
# cache and is still saved by state_save(), so a new session can be activated
sub state_deactivate
{
  my $self = shift;

  my $type = shift;

  boom "invalid session type [$type]" unless exists $PARENT_SESSION_TYPES{ $type };

  $self->{ 'SID' }{ $type } = undef;

  1;
}

# removes all cached sessions of given TYPE without saving them
sub state_remove_all
{
  my $self = shift;

  my $type = shift;

  boom "invalid session type [$type]" unless exists $PARENT_SESSION_TYPES{ $type };

  $self->{ 'SID' }{ $type } = undef;
  delete $self->{ 'SHR'   }{ $type };
  delete $self->{ 'STATE' }{ $type };

  1;
}

# remove session without saving
sub state_remove
{
  my $self = shift;

  my $type = shift;
  my $sid  = shift;

  boom "invalid session type [$type]" unless exists $PARENT_SESSION_TYPES{ $type };

  $self->{ 'SID' }{ $type } = undef if $self->{ 'SID' }{ $type } eq $sid;
  delete $self->{ 'SHR'   }{ $type }{ $sid };
  delete $self->{ 'STATE' }{ $type }{ $sid };

  1;
}

# updates
sub state_update_fingerprint
{
  my $self = shift;

  my $type = shift;
  my $sid  = shift;
  my $shr  = shift;

  boom "invalid session type [$type]" unless exists $PARENT_SESSION_TYPES{ $type };

  $shr ||= $self->{ 'SHR'   }{ $type }{ $sid };

  $self->{ 'STATE' }{ $type }{ $sid } = hash_fingerprint( $shr );
}

sub state_save
{
  my $self = shift;

  my $state = $self->{ 'STATE' } ||= {}; # get or init state cache
  for my $type ( keys %PARENT_SESSION_TYPES )
    {
    my $type_hr = $self->{ 'SHR' }{ $type } or next;
    for my $sid ( keys %$type_hr )
      {
      my $shr = $type_hr->{ $sid };

      my $newfp  = hash_fingerprint( $shr );
      my $lastfp = $state->{ $type }{ $sid };

      next if $newfp eq $lastfp;

      $self->reo->log_debug( "saving session data [$type:$sid] --> new $newfp <> $lastfp" );

      if( $self->save( $type, $sid, $shr ) )
        {
        $state->{ $type }{ $sid } = $newfp;
        }
      else
        {
        $self->reo->log( "error saving session state for [$type:$sid] --> new $newfp <> $lastfp" );
        }
      }
    }
}

=end comment

=cut

### INTERNAL #################################################################

sub __check_session_id
{
  return $_[0] =~ /^[A-Za-z0-9_]{$MIN_SES_ID_LEN,}$/o;
}


#sub DESTROY
#{
#  my $self = shift;
#
#  print "DESTROY: $self\n";
#}

##############################################################################
1;
###EOF########################################################################
