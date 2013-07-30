##############################################################################
##
##  Web::Reactor application machinery
##  2013 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
package Web::Reactor::HTML::Form;
use strict;
use Exporter;
use Carp;
use Data::Tools;
use Exception::Sink;

# FIXME: TODO: use common func to add html elements common tags: ID,DISABLED,etc.
# FIXME: TODO: ...including abstract ones as GEO(metry)
# FIXME: TODO: change VALUE to be html value (currently it is DATA), and DISPLAY to be visible text (currently it is VALUE)

##############################################################################

sub new
{
  my $class = shift;
  my %env = @_;

  $class = ref( $class ) || $class;
  my $self = {
             'ENV'        => \%env,
             };

  my $reo = $env{ 'REO_REACTOR' };
  if( ref( $reo ) =~ /^Web::Reactor(::|$)/ )
    {
    $self->{ 'REO_REACTOR' } = $reo;
    }
  else
    {
    confess "missing REO reactor object";
    }

  bless $self, $class;

  return $self;
}

##############################################################################

sub html_new_id
{
  my $self = shift;

  $self->{ 'HTML_ID_COUNTER' }++;
  return $self->{ 'HTML_ID_COUNTER' };
}

##############################################################################

sub begin
{
  my $self = shift;

  my %opt = @_;

  my $form_name = uc $opt{ 'NAME'   };
  my $method    = uc $opt{ 'METHOD' } || 'POST';
  my $action    =    $opt{ 'ACTION' } || '?';

  $self->{ 'CLASS_MAP' } = $opt{ 'CLASS_MAP' } || {};

  $form_name =~ /^[A-Z_0-9:]+$/ or confess "invalid or empty NAME attribute";
  $method    =~ /^(POST|GET)$/  or confess "METHOD can either POST or GET";

  $self->{ 'FORM_NAME' } = $form_name;
  $self->{ 'RADIO'     } = {};
  $self->{ 'RET_MAP'   } = {}; # return data mapping (combo, checkbox, etc.)

  my $text;

# FIXME: TODO: debug info inside html text, begin formname end etc.

  my $reo = $self->{ 'REO_REACTOR' };

  my $page_session = $reo->get_page_session();
  $page_session->{ ':FORM_DEF' }{ $form_name } = {};

  my $state_keeper = $reo->args_here( FORM_NAME => $form_name ); # keep state and more args
  $text .= "<form action='$action' method='$method' enctype='multipart/form-data'>";
  $text .= "<input type=hidden name=_ value=$state_keeper>";

  return $text;
}

sub end
{
  my $self = shift;

  my $text;

  $text .= $self->end_radios();
  $text .= "</form>";

# FIXME: TODO: debug info inside html text, begin formname end etc.

  my $reo = $self->{ 'REO_REACTOR' };
  my $page_session = $reo->get_page_session();

  my $form_name = $self->{ 'FORM_NAME' };
  $page_session->{ ':FORM_DEF' }{ $form_name }{ 'RET_MAP' } = $self->{ 'RET_MAP' };

  return $text;
}

sub __set_ret_map
{
  my $self = shift;
  my $name = shift; # entry input name

  $self->{ 'RET_MAP' }{ $name } ||= {};

  if( @_ > 0 )
    {
    confess "expected even number of arguments" unless @_ % 2 == 0;
    %{ $self->{ 'RET_MAP' }{ $name } } = ( %{ $self->{ 'RET_MAP' }{ $name } }, @_ );
    }

  $self->{ 'RET_MAP' }{ $name };
}

##############################################################################

sub checkbox
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $class = uc $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'CHECKBOX' } || 'checkbox';
  my $value =    $opt{ 'VALUE' };

  $name =~ /^[A-Z_0-9:]+$/ or croak "invalid or empty NAME attribute [$name]";

  my $options;
  $options .= $value ? " checked " : undef;

  my $text;

#print STDERR "ccccccccccccccccccccc CHECKBOX [$name] [$value]\n";
  $text .= "<input type='checkbox' name='$name' value='1' $options>";

  return $text;
}

sub cb
{
  my $self = shift;
  return $self->checkbox( @_ );
}

##############################################################################

sub radio
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $class = uc $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'RADIO' } || 'radio';
  my $on    =    $opt{ 'ON'    }; # active?
  my $val   =    $opt{ 'VAL'   };
  my $ret   =    $opt{ 'RET'   } || $opt{ 'RETURN' } || 1; # map return value!

  $name =~ /^[A-Z_0-9:]+$/ or croak "invalid or empty NAME attribute [$name]";

  my $text;

  my $checked = $on ? 'checked' : undef;
  $text .= "<input type='radio' $checked name='$name' value='$val'>";

  $self->__set_ret_map( $name, $val => $ret ) if defined $ret;
  $self->{ 'RET_MAP' }{ $val } = $ret;

  return $text;
}

sub end_radios
{
  my $self = shift;

  my $text;

  # nothing for now

  return $text;
}

##############################################################################
=pod

$form->select( DATA => $data );

$data = [
         {
         KEY   => string
         VALUE => string
         ORDER => \d+
         },
       ];

$data = {
         KEY => {
                KEY   => string
                VALUE => string
                ORDER => \d+
                },
         KEY => value...,
        };

=cut

sub select
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $class = uc $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'SELECT' } || 'select';
  my $rows  =    $opt{ 'SIZE'  } || $opt{ 'ROWS'  } || 1;

  $name =~ /^[A-Z_0-9:]+$/ or croak "invalid or empty NAME attribute [$name]";

  my $data   = $opt{ 'DATA'     }; # array reference or hash reference, inside hashesh are the same
  my $sel_hr = $opt{ 'SELECTED' }; # hashref with selected keys (values are true's)
  my $sel_data;

  if( ref($data) eq 'HASH' )
    {
    $sel_data = [];
    my %res;
    while( my ( $k, $v ) = each %$data )
      {
      my %e = ( KEY => $k );
      if( ref($v) eq 'HASH' )
        {
        %e = ( %e, %$v );
        }
      else
        {
        $e{ 'VALUE' } = $v;
        }
      push @$sel_data, \%e;
      }
    # FIXME: @$sel_data = sort { ... } @$sel_data;
    }
  elsif( ref($data) eq 'ARRAY' )
    {
    $sel_data = $data;
    }
  else
    {
    boom "DATA must be either ARRAY or HASH reference";
    }
  hash_uc_ipl( $_ ) for @$sel_data;

  my $text;

  if( $opt{ 'RADIO' } )
    {
    for my $hr ( @$sel_data )
      {
      my $sel   = $hr->{ 'SELECTED' } ? 'selected' : ''; # is selected?
      my $key   = $hr->{ 'KEY'      };
      my $value = $hr->{ 'VALUE'    };

      $sel = 'selected' if $sel_hr and $sel_hr->{ $key };
#print STDERR "sssssssssssssssssssssssss RADIO [$name] [$value] [$key] $sel\n";
      $text .= $self->radio( NAME => $name, RET => $key, ON => $sel ) . " $value";
      $text .= "<br>" if $opt{ 'RADIO' } != 2;
      }
    # FIXME: kakvo stava ako nqma dadeno selected pri submit na formata?
    }
  else
    {
    my $multiple = 'multiple' if $opt{ 'MULTIPLE' };
    $text .= "<select class='$class' name='$name' size='$rows' $multiple>";

    my $pad = '&nbsp;' x 3;
    for my $hr ( @$sel_data )
      {
      my $sel   = $hr->{ 'SELECTED' } ? 'selected' : ''; # is selected?
      my $key   = $hr->{ 'KEY'      };
      my $value = $hr->{ 'VALUE'    };
      my $id = $self->html_new_id();
      $self->__set_ret_map( $name, $id => $key );

      $sel = 'selected' if $sel_hr and $sel_hr->{ $key };
#print STDERR "sssssssssssssssssssssssss RADIO [$name] [$value] [$key] $sel\n";
      $text .= "<option value='$id' $sel>$value$pad</option>";
      }

    $text .= "</select>";
    }
# print STDERR "FOOOOOOOOOOOOOOOOOOOOOORM[$text](@$sel){@$order}";
  return $text;
}

sub combo
{
  my $self = shift;

  my %opt = @_;
  $opt{ 'ROWS'  } ||= 1;
  $self->select( %opt );
}

##############################################################################

sub textarea
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $class = uc $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'TEXTAREA' } || 'textarea';
  my $id    =    $opt{ 'ID'    };
  my $data  =    $opt{ 'VALUE' };
  my $rows  =    $opt{ 'ROWS'  } || 10;
  my $cols  =    $opt{ 'COLS'  } ||  5;
  my $geo   =    $opt{ 'GEOMETRY' }  || $opt{ 'GEO' };

  $name =~ /^[A-Z_0-9:]+$/ or croak "invalid or empty NAME attribute [$name]";

  ( $cols, $rows ) = ( $1, $2 ) if $geo =~ /(\d+)[\*\/\\](\d+)/i;

  my $options;

#  $options .= "SIZE='$size' "      if $size > 0;
#  $options .= "MAXLENGTH='$maxl' " if $maxl > 0;
  $options .= $opt{ 'DISABLED' } ? 'disabled ' : '';
  $options .= "onFocus=\"this.value=''\" " if $opt{ 'FOCUS_AUTO_CLEAR' };
#  $options .= "ID='$id' "   if $id ne '';
#  $options .= "ID='$name' " if $opt{ 'NAME_ID' };

#  my $extra = $opt{ 'EXTRA' };
#  $options .= " $extra ";

  $data = str_html_escape( $data );

  my $text;

  $text .= "<textarea class='$class' name='$name' rows='$rows' cols='$cols' $options>$data</textarea>";

  return $text;
}

##############################################################################

sub input
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $class = uc $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'INPUT' } || 'line';
  my $value =    $opt{ 'VALUE' };
  my $id    =    $opt{ 'ID' };
  # FIXME: default data?
  my $size  =    $opt{ 'SIZE'    } || $opt{ 'LEN' } || $opt{ 'WIDTH' };
  my $maxl  =    $opt{ 'MAXLEN'  } || $opt{ 'MAX' };

  my $len   =    $opt{ 'LEN' };

  $size = $maxl = $len if $len > 0;

  my $options;

  $options .= "size='$size' "      if $size > 0;
  $options .= "maxlength='$maxl' " if $maxl > 0;
  $options .= $opt{ 'DISABLED' } ? 'disabled ' : '';
  #$options .= "onFocus=\"this.value=''\" " if $opt{ 'FOCUS_AUTO_CLEAR' };
  $options .= "ID='$id' "   if $id ne '';
  #$options .= "ID='$name' " if $opt{ 'NAME_ID' } or $id eq '';
  $options .= "type='password' " if $opt{ 'PASS' } || $opt{ 'PASSWORD' };

#  my $extra = $opt{ 'EXTRA' };
  #$options .= " $extra ";

  $value = str_html_escape( $value );

  $name =~ /^[A-Z_0-9:]+$/ or croak "invalid or empty NAME attribute [$name]";
  my $text;

  $text .= "<input class='$class' name='$name' value='$value' $options>";

  return $text;
}

##############################################################################

# TODO: include button support
sub button
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $class = uc $opt{ 'CLASS' } || 'button';
  my $value =    $opt{ 'VALUE' };

  $value =~ s/'//g;
  $value = str_html_escape( $value );

  $name =~ /^[A-Z_0-9:]+$/ or croak "invalid or empty NAME attribute [$name]";
  my $text;
  
  $name =~ s/^button://i;

  $text .= "<input class='$class' type='submit' name='button:$name' value='$value' onDblClick='return false;' >";

  return $text;
}

sub image_button
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $class = uc $opt{ 'CLASS' } || 'image_button';
  my $src   =    $opt{ 'SRC'   } || $opt{ 'IMG' };
  my $extra =    $opt{ 'EXTRA' };

  my $options;

  # FIXME: make this for all entries! common func?
  for my $o ( qw( HEIGHT WIDTH ONMOUSEOVER ) )
    {
    my $e = $opt{ $o };
    # FIXME: escape? $e
    $options .= "$o='$e' " if $e ne '';
    }

  $name =~ /^[A-Z_0-9:]+$/ or croak "invalid or empty NAME attribute [$name]";
  my $text;

  $text .= "<input class='$class' type='image' name='$name' src='$src' border=0 $options onDblClick='return false;' >";

  return $text;
}

sub image_button_default
{
  my $self = shift;

  my %opt = @_;

  my $reo = $self->{ 'REO_REACTOR' };
  my $user_session = $reo->get_user_session();
  my $user_agent = $user_session->{ ':HTTP_ENV_HR' }{ 'HTTP_USER_AGENT' };

  my $default_class = 'hidden';
  $default_class = 'hidden2' if $user_agent =~ /MSIE|Safari/;

  $opt{ 'HEIGHT' } = 0;
  $opt{ 'WIDTH'  } = 0;
  $opt{ 'CLASS'  } = $opt{ 'CLASS'  } || $default_class;

  $self->image_button( %opt );
}

=pod

  my $form = new Review::HTML::Form;

  $text .= $form->image_submit_default( NAME => 'def_but', SRC => 'img/empty.png' );

  $text .= $form->line( NAME => 'line_one', DATA => ( $I{ 'LINE_ONE' } || 'ne se chete' ) );

  $text .= $form->begin( NAME => 'try1' );
  $text .= 'cb1' . $form->cb( NAME => 'cb1', VAL => 1 );
  $text .= 'cb2' . $form->cb( NAME => 'cb2', VAL => 0 );
  $text .= 'cb3' . $form->cb( NAME => 'cb3', VAL => 0, MAX => 3, RET => [ 'qwe', 'asd', '[-]' ] );
  $text .= "<p>";

  $text .= "<hr noshade>";
  $text .= 'r1' . $form->radio( NAME => 'r1' );
  $text .= 'r2' . $form->radio( NAME => 'r1' );
  $text .= 'r3' . $form->radio( NAME => 'r1', ON => 1 );
  $text .= 'r4' . $form->radio( NAME => 'r1' );
  $text .= 'r5' . $form->radio( NAME => 'r1' );
  $text .= "<hr noshade>";
  $text .= 'r1' . $form->radio( NAME => 'r2', ON => 1 );
  $text .= 'r2' . $form->radio( NAME => 'r2', RET => 'asd' );
  $text .= 'r3' . $form->radio( NAME => 'r2', RET => 'qwe' );
  $text .= 'r4' . $form->radio( NAME => 'r2', RET => 'zxc' );
  $text .= 'r5' . $form->radio( NAME => 'r2', RET => '[-]' );
  $text .= "<hr noshade>";

  my $data = {
             'one' => 'This is test one',
             'opa' => 'Opa test ooooooe',
             'two' => 'Test two tralala',
             'tra' => 'Tralala again+++',
             };

  $text .= $form->select( NAME => 'sel2', DATA => $data, SELECTED => [ 'opa' ], ROWS => 4 );

  $text .= "<p>";
  $text .= $form->button( NAME => 'bbb', VALUE => '"%!@#$&^' );
  $text .= $form->end();

=cut

##############################################################################
1;
##############################################################################
