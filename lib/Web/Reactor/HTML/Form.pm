##############################################################################
##
##  Web::Reactor application machinery
##  2014-2026 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@noxrun.com> <cade@bis.bg> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
package Web::Reactor::HTML::Form;
use strict;
use Data::Tools 1.53;
use Exception::Sink;

use Web::Reactor::HTML::Utils;

# FIXME: TODO: an abstract GEO(metry) option for all elements, as textarea() GEOMETRY

our $VERSION = '2.14';

use parent 'Web::Reactor::Base';

##############################################################################

# cc20261017-reo-optional
# new( $reo, $cfg, %opt ), new( $reo, %opt ), new( %opt ): the reactor object
# is optional, see the POD (WITHOUT A REACTOR). options:
#   DEBUG -- debug prefixes in the form name and id
sub new
{
  my $class = shift;

  # a reactor object (or undef in its place), then an optional config hash
  my $reo = ( @_ and ( ! defined $_[0] or ( ref $_[0] and ref $_[0] ne 'HASH' ) ) ) ? shift : undef;
  my $cfg = ref $_[0] eq 'HASH' ? shift : undef;
  boom "expected even number of options" if @_ % 2;
  my %opt = @_;

  $class = ref( $class ) || $class;
  my $self = bless {}, $class;

  if( $reo )
    {
    $self->__set_reo( $reo ); # booms on a non-reactor object
    # the hidden names and return values live in the LINK session, which only
    # Web::Reactor has, without it (undef) nothing is hidden or mapped
    boom "HTML::Form needs a Web::Reactor object or none (undef), got [" . ref( $reo ) . "]" unless $reo->can( 'get_link_session' );
    $cfg ||= $reo->cfg();
    }
  $self->{ 'CFG'   } = $cfg || {};
  $self->{ 'DEBUG' } = $opt{ 'DEBUG' };

  return $self;
}

sub create_uniq_id
{
  my $self = shift;

  my $reo = $self->reo_optional(); # cc20261017-reo-optional # cc20261017-2
  return $reo ? $reo->create_uniq_id() : html_uniq_id();
}

# hover layer handle for a HINT option, undef without a reactor object (the
# layer goes into its KIT_HTML hold) # cc20261017-reo-optional
sub __hint
{
  my $self = shift;
  my $hint = shift;

  my $reo = $self->reo_optional(); # cc20261017-2
  return undef unless $hint and $reo;
  return html_hover_layer( $reo, VALUE => $hint, @_ );
}

# the default (Enter key) button: rendered but out of sight, a display: none
# one is not pressed by Enter in some browsers, this works in all of them # cc20261017-reo-optional
my %DEFAULT_BUTTON_ATTRS = (
                           style         => 'position: absolute; left: -10000px; width: 1px; height: 1px; overflow: hidden;',
                           tabindex      => -1,
                           'aria-hidden' => 'true',
                           );

# extra ATTRS never replace these, use NAME and ID, see html_attrs_filter()
my @ATTRS_PROTECTED = qw( name form id );

# the raw html options EXTRA and ARGS are removed, use ATTRS. dies instead of
# ignoring them, so old callers are found
sub __check_removed_options
{
  my $opt = shift;

  for my $o ( qw( EXTRA ARGS ) )
    {
    die "error: Form.pm: $o used but it is removed, use ATTRS, content is [$opt->{ $o }]\n" . Exception::Sink::get_stack_trace() if $opt->{ $o };
    }
  return 1;
}

##############################################################################

sub begin
{
  my $self = shift;

  my %opt = @_;

  my $name      =    $opt{ 'NAME'   };
  my $id        =    $opt{ 'ID'     };
  my $method    = uc $opt{ 'METHOD' } || 'POST';
  my $action    =    $opt{ 'ACTION' } || '?';
  my $default_button = uc $opt{ 'DEFAULT_BUTTON' }; # as button() NAME: upper case, without a "button:" prefix
  $default_button =~ s/^button://i;

  $self->{ 'CLASS_MAP' } = $opt{ 'CLASS_MAP' } || {};

  $method =~ /^(POST|GET)\z/  or boom "METHOD can be either POST or GET";

  $name ||= $self->create_uniq_id(); # cc20261017-reo-optional
  $id   ||= $name . '.' . $self->create_uniq_id();
  html_check_name_boom( $name );
  html_check_name_boom( $id );
  html_check_button_name_boom( $default_button ) if $default_button;

  # debug prefixes are only visible in the html, the form state keeps the real name
  my $html_name = $name;
  if( $self->{ 'DEBUG' } ) # cc20261017-reo-optional own flag, not the reactor debug
    {
    $html_name = "FORM_$name";
    $id        = "FORM_ID_$id";
    }

  $self->{ 'FORM_NAME'  } = $name;
  $self->{ 'FORM_ID'    } = $id;
  $self->{ 'RET_MAP'    } = {}; # return data mapping (combo, checkbox, etc.)
  $self->{ 'RADIO_KEYS' } = {}; # KEY radio values per NAME, see end()

  my %at;

  $at{ 'autocomplete' } = 'off' if $opt{ 'NO_AUTOCOMPLETE' };

  my $text;

  # FIXME: TODO: debug info inside html text, begin formname end etc.

  # state set before begin() is kept, args type defaults to HERE
  $self->state( 'FORM_NAME'  => $name  ); # TODO: replace with _FRO
  $self->state( 'FORM_ID'    => $id    ); # TODO: replace with _FRI
  $self->state( ':ARGS_TYPE' => $self->{ 'FORM_STATE' }{ ':ARGS_TYPE' } || 'HERE' );

  $text .= html_element( 'form', '', name => $html_name, id => $id, action => $action, method => $method, enctype => 'multipart/form-data', %at );

#### REMOVE ###  $text .= "<form name='$form_name' id='$form_id' action='$action' method='$method' enctype='multipart/form-data' $options></form>";
#### REMOVE ###  ### $text .= "<input style='display: none;' name='__avoidiebug__' form='$form_id'>"; # stupid IE bugs
  if( $default_button )
    {
    $text .= html_element( 'input', undef, form => $id, type => 'image', name => "button:$default_button", src => 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQI12NgYGBgAAAABQABXvMqOgAAAABJRU5ErkJggg==', onDblClick => 'return false;', %DEFAULT_BUTTON_ATTRS ); # cc20261017-reo-optional
#### REMOVE ###      $text .= "<input style='display: none;' type='image' name='BUTTON:$default_button' src='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQI12NgYGBgAAAABQABXvMqOgAAAABJRU5ErkJggg==' border=0 height=0 width=0 onDblClick='return false;' form='$form_id'>"
    }
  return $text;
}

sub state
{
  my $self = shift;

  $self->{ 'FORM_STATE'  } = { %{ $self->{ 'FORM_STATE'  } || {} }, @_ };

  return undef;
}

sub state_new
{
  my $self = shift;

  return $self->state( @_, ':ARGS_TYPE' => 'NEW' );
}

sub state_here
{
  my $self = shift;

  return $self->state( @_, ':ARGS_TYPE' => 'HERE' );
}

sub state_back
{
  my $self = shift;

  return $self->state( @_, ':ARGS_TYPE' => 'BACK' );
}

sub state_none
{
  my $self = shift;

  return $self->state( @_, ':ARGS_TYPE' => 'NONE' );
}

sub end
{
  my $self = shift;

  my $text;

  # $text .= "</form>";

# FIXME: TODO: debug info inside html text, begin formname end etc.

  my $reo = $self->reo_optional(); # cc20261017-reo-optional # cc20261017-2

  my $form_id = $self->{ 'FORM_ID' };

  # the form state is used once, a reused form object starts with a clean state
  my %state     = %{ delete $self->{ 'FORM_STATE' } || {} };
  my $args_type = delete $state{ ':ARGS_TYPE' } || 'HERE';

  if( ! $reo ) # cc20261017-reo-optional
    {
    # no link session: nothing is hidden, the state goes as plain hidden inputs
    for my $k ( sort keys %state )
      {
      boom "form state [$k] without a reactor object can hold only plain values" if ref $state{ $k };
      $text .= html_element( 'input', undef, form => $form_id, type => 'hidden', name => uc $k, value => $state{ $k } );
      }
    $text .= "\n";
    return $text;
    }

  # a KEY radio in a NAME group which also has RET radios is mapped to itself,
  # the posted value of a mapped name is looked up in the return map, an
  # unmapped key would arrive as undef. groups of KEY radios only stay plain
  my $rkeys = delete $self->{ 'RADIO_KEYS' } || {};
  for my $n ( sort keys %$rkeys )
    {
    next unless $self->{ 'RET_MAP' }{ 'DATA' }{ $n };
    $self->__ret_map_data( $n, map { $_ => $_ } sort keys %{ $rkeys->{ $n } } );
    }

  my $link_shr = $reo->get_link_session();
  $link_shr->{ 'FORM_RET_MAP' }{ $form_id } = $self->{ 'RET_MAP' };

  my $state_keeper = $reo->args_type( $args_type, %state );

##### REMOVE #####  #$text .= "<input type=hidden name='_' value='$state_keeper' form='$form_id'>";
  $text .= html_element( 'input', undef, form => $form_id, type => 'hidden', name => '_', value => $state_keeper );

  $text .= "\n";
  return $text;
}


sub __ret_map_name
{
  my $self = shift;
  my $name = shift; # input element name to be hidden

  my $key = uc $self->create_uniq_id(); # upper case
  $self->{ 'RET_MAP' }{ 'NAME' }{ $key } = $name;
  return $key;
}

# $self->__ret_map_data( $input_element_name, visible_key1 => return_value1, visible_key2 => return_value2, ... );
sub __ret_map_data
{
  my $self = shift;
  my $name = shift; # input element name

  $self->{ 'RET_MAP' }{ 'DATA' }{ $name } ||= {};

  if( @_ > 0 )
    {
    boom "expected even number of arguments" unless @_ % 2 == 0;
    %{ $self->{ 'RET_MAP' }{ 'DATA' }{ $name } } = ( %{ $self->{ 'RET_MAP' }{ 'DATA' }{ $name } }, @_ );
    }

  return $self->{ 'RET_MAP' }{ 'DATA' }{ $name };
}

##############################################################################
# classic html input checkbox

sub checkbox
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $class =    $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'CHECKBOX' } || 'checkbox';
  my $value =    $opt{ 'VALUE' } ? 1 : 0;
  my $id    =    $opt{ 'ID'    }; # of the visible checkbox, i.e. for <label for=...>

  __check_removed_options( \%opt );

  html_check_name_boom( $name );
  html_check_ident_boom( $id );

  my %options;
  $options{ 'checked' } = undef if $value; # bare attribute
  $options{ 'id'      } = $id   if $id ne '';

  my $text;

  my $ch_id = $self->create_uniq_id(); # checkbox data holder

  my $form_id = $self->{ 'FORM_ID' };
  #print STDERR "ccccccccccccccccccccc CHECKBOX [$name] [$value]\n";
  $text .= "\n";
  $text .= html_element( 'input', undef, type => 'hidden', name => $name, id => $ch_id, value => $value, form => $form_id );
  $text .= html_element( 'input', undef, %options, type => 'checkbox', 'data-checkbox-input-id' => $ch_id, form => $form_id, onclick => 'reactor_form_checkbox_toggle(this)', class => $class, html_attrs_filter( $opt{ 'ATTRS' }, @ATTRS_PROTECTED, qw( type onclick data-checkbox-input-id ) ) );
  $text .= "\n";

  return $text;
}

##############################################################################
# multi-stages css-styled checkbox

sub checkbox_multi
{
  my $self = shift;

  my %opt = @_;

  my $name   = uc $opt{ 'NAME'   };
  my $class  =    $opt{ 'CLASS'  } || $self->{ 'CLASS_MAP' }{ 'CHECKBOX_MULTI' }; # cc20261017 no default class, the LABELS carry their own
  my $value  =    $opt{ 'VALUE'  };
  my $stages =    $opt{ 'STAGES' } || 2;
  my $labels =    $opt{ 'LABELS' } || [ 'x', '&radic;' ];
  my $hint   =    $opt{ 'HINT'   };
  my $id     =    $opt{ 'ID'     };

  __check_removed_options( \%opt );

  html_check_name_boom( $name );
  html_check_ident_boom( $id );

  $value = abs( int( $value ) );
  $value = 0 if $value >= $stages;

  my $text;

  my $labels_spans;
  for my $s ( 0 .. $stages - 1 )
    {
    my $display = $value == $s ? 'inline' : 'none';
    # stages without a label show the stage number
    $labels_spans .= html_element( 'span', $labels->[$s] // $s, style => "display: $display" );
    }

  my %options;
  my $hint_js = $self->__hint( $hint ); # cc20261017-reo-optional
  $options{ 'onmouseover' } = $hint_js if $hint_js; # cc20261017-reo-optional
  $options{ 'class'       } = $class if $class ne ''; # cc20261017

  my $cb_id = $self->create_uniq_id(); # checkbox id
  my $el_id = $id || $self->create_uniq_id(); # checkbox label element id

  my $form_id = $self->{ 'FORM_ID' };
  $text .= html_element( "input", undef, type => 'hidden', name => $name, id => $cb_id, value => $value, form => $form_id );
  $text .= html_element( "span", $labels_spans, %options, id => $el_id, 'data-stages' => $stages, 'data-checkbox-input-id' => $cb_id, onclick => 'reactor_form_multi_checkbox_toggle(this)', html_attrs_filter( $opt{ 'ATTRS' }, @ATTRS_PROTECTED, qw( onclick data-stages data-checkbox-input-id ) ) );
#  $text .= html_element( "script", "reactor_form_multi_checkbox_setup_id( '$el_id' )" );
  $text .= "\n";

# print STDERR $text;

  return $text;
}

##############################################################################

sub checkbox_3state
{
  my $self = shift;

  my %args = @_; # to fix uneven args
  return $self->checkbox_multi( %args, STAGES => 3, LABELS => $args{ 'LABELS' } || [ '?', '&radic;', 'x' ] );
}

##############################################################################

sub radio
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $class =    $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'RADIO' } || 'radio';
  my $on    =    $opt{ 'ON'    }; # active?
  my $ret   =    $opt{ 'RET'   }; # map return value!
  my $key   =    $opt{ 'KEY'   };
  my $id    =    $opt{ 'ID'    };

  __check_removed_options( \%opt );

  html_check_name_boom( $name );
  html_check_ident_boom( $id );

  my $text;

  my $hide = defined $ret && $self->reo_optional(); # RET is mapped only with a link session # cc20261017-reo-optional # cc20261017-2
  my $val  = $hide ? $self->create_uniq_id() : defined $ret ? $ret : $key // '';

  my %options;
  $options{ 'checked' } = undef if $on; # bare attribute
  $options{ 'id'      } = $id   if $id ne '';

  my $form_id = $self->{ 'FORM_ID' };
  $text .= html_element( 'input', undef, %options, type => 'radio', name => $name, value => $val, class => $class, form => $form_id, html_attrs_filter( $opt{ 'ATTRS' }, @ATTRS_PROTECTED, qw( type value ) ) );

  $self->__ret_map_data( $name, $val => $ret ) if $hide; # cc20261017-reo-optional
  $self->{ 'RADIO_KEYS' }{ $name }{ $val } = 1 if ! defined $ret and $self->reo_optional(); # mapped in end() if the group has RET radios

  $text .= "\n";
  return $text;
}

##############################################################################

# select() DATA, see the POD of select()
sub select
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $id    =    $opt{ 'ID'    };
  my $class =    $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'SELECT' } || 'select';
  my $rows  =    $opt{ 'SIZE'  } || $opt{ 'ROWS'  } || 1;

  __check_removed_options( \%opt );

  html_check_name_boom( $name );
  html_check_ident_boom( $id );

  my $data     = $opt{ 'DATA'     }; # array reference or hash reference, see the POD of select()
  my $selected = $opt{ 'SELECTED' }; # selected return value, hashref or arrayref of them
  my $sel_data;

  $selected = { map { $_ => 1 } @$selected } if ref( $selected ) eq 'ARRAY';

  my %at;

  $at{ 'form'  } = $self->{ 'FORM_ID' };
  my $hide = $self->reo_optional(); # names and values are mapped only with a link session # cc20261017-reo-optional # cc20261017-2

  $at{ 'name'  } = $hide ? $self->__ret_map_name( $name ) : $name; # cc20261017-reo-optional
  $at{ 'class' } = $class;
  $at{ 'id'    } = $id   if $id ne '';
  $at{ 'size'  } = $rows if $rows > 1;

  if( ref($data) eq 'HASH' )
    {
    $sel_data = [];
    while( my ( $k, $v ) = each %$data )
      {
      my %e = ( 'KEY' => $k );
      if( ref($v) eq 'HASH' )
        {
        %e = ( %e, %$v );
        }
      else
        {
        $e{ 'LABEL' } = $v;
        }
      hash_uc_ipl( \%e );
      push @$sel_data, \%e;
      }
    @$sel_data = sort { $a->{ 'ORDER' } <=> $b->{ 'ORDER' } or $a->{ 'KEY' } cmp $b->{ 'KEY' } } @$sel_data;
    }
  elsif( ref($data) eq 'ARRAY' )
    {
    # copies, the caller's data is not changed
    $sel_data = [ map { my %e = %$_; hash_uc_ipl( \%e ); \%e } @$data ];
    }
  else
    {
    boom "DATA must be either ARRAY or HASH reference";
    }

  my $text;

  my $on_change = html_submit_on_change_js( $opt{ 'SUBMIT_ON_CHANGE' } );
  $at{ 'onChange' } = $on_change if $on_change;

  $at{ 'multiple' } = 'multiple' if $opt{ 'MULTIPLE' };
  $at{ 'disabled' } = 'disabled' if $opt{ 'DISABLED' }; # cc20261017

  my $opt_text;
  for my $hr ( @$sel_data )
    {
    my $key    = $hr->{ 'KEY'   };
    my $value  = $hr->{ 'VALUE' };
    my $label  = $hr->{ 'LABEL' } // '';

    $value = $key if ! defined $value and $key ne '*';

    my %at_opt;
    $at_opt{ 'selected' } = 'selected' if $hr->{ 'SELECTED' } or ( ref( $selected ) ? $selected->{ $value } : defined $selected && $selected eq $value );

    $key = $self->create_uniq_id() if $key eq '*';
    $key = $value                  if $key eq ''; # the value is visible, still mapped so mixed options work

    $self->__ret_map_data( $name, $key => $value ) if $hide; # cc20261017-reo-optional

    $at_opt{ 'value' } = $hide ? $key : $value; # cc20261017-reo-optional
#print STDERR "sssssssssssssssssssssssss COMBO [$name] [$value] [$key] $sel\n";
    #$opt_text .= "<option value='$val_id' $sel>$value$pad</option>\n";
    $opt_text .= html_element( 'option', $label, %at_opt );
    }

#    $text .= "<select class='$class' id='$id' name='$name' size='$rows' $multiple form='$form_id' $args $extra $options>";
  $text .= html_element( 'select', $opt_text, %at, html_attrs_filter( $opt{ 'ATTRS' }, @ATTRS_PROTECTED ) );
# print STDERR "FOOOOOOOOOOOOOOOOOOOOOORM[$text](@$sel){@$order}";

  $text .= "\n";
  return $text;
}

# combo is a select with one row, which is the select() default
sub combo
{
  my $self = shift;

  return $self->select( @_ );
}

##############################################################################

sub textarea
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $id    =    $opt{ 'ID'    };
  my $class =    $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'TEXTAREA' } || 'textarea';
  my $data  =    $opt{ 'VALUE' };
  my $rows  =    $opt{ 'ROWS'  } || 10;
  my $cols  =    $opt{ 'COLS'  } || 50;
  my $maxl  =    $opt{ 'MAXLEN'  } || $opt{ 'MAX' };
  my $geo   =    $opt{ 'GEOMETRY' }  || $opt{ 'GEO' };

  __check_removed_options( \%opt );

  html_check_name_boom( $name );
  html_check_ident_boom( $id );

  ( $cols, $rows ) = ( $1, $2 ) if $geo =~ /(\d+)[\*\/\\](\d+)/;


  my %options;

  $options{ 'id'        } = $id             if $id ne '';
  $options{ 'disabled'  } = 'disabled'      if $opt{ 'DISABLED' };
  $options{ 'maxlength' } = $maxl           if $maxl > 0;
  $options{ 'readonly'  } = 'readonly'      if $opt{ 'READONLY' } || $opt{ 'RO' };
  $options{ 'required'  } = 'required'      if $opt{ 'REQUIRED' } || $opt{ 'REQ' };
  $options{ 'onFocus'   } = "this.value=''" if $opt{ 'FOCUS_AUTO_CLEAR' };

  my $text;
  my $form_id = $self->{ 'FORM_ID' };

  # the html parser drops one line feed right after <textarea>, a value which
  # starts with one gets an extra one, so it keeps its leading empty line
  $data = "\n" . $data if $data =~ /\A\r?\n/;
  $text .= html_element_e( 'textarea', $data, %options, class => $class, name => $name, rows => $rows, cols => $cols, form => $form_id, html_attrs_filter( $opt{ 'ATTRS' }, @ATTRS_PROTECTED ) );

  $text .= "\n";
  return $text;
}

##############################################################################

sub input
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'    };
  my $id    =    $opt{ 'ID'      };
  my $class =    $opt{ 'CLASS'   } || $self->{ 'CLASS_MAP' }{ 'INPUT' } || 'line';
  my $value =    $opt{ 'VALUE'   } // "";
  # FIXME: default data?
  my $size  =    $opt{ 'SIZE'    } || $opt{ 'WIDTH' };
  my $maxl  =    $opt{ 'MAXLEN'  } || $opt{ 'MAX' };

  my $len   =    $opt{ 'LEN'     }; # sets both size and maxlength
  my $hid   =    $opt{ 'HIDDEN'  };
  my $ret   =    $opt{ 'RET'     } // $opt{ 'RETURN'  }; # if return value should be mapped, works only with HIDDEN, 0 is a value too

  my $phi   =    $opt{ 'PH' } || $opt{ 'PHI' };

  my $clear =    $opt{ 'DISABLED' } ? undef : $opt{ 'CLEAR'   };

  my $datalist    = $opt{ 'DATALIST'              }; # array ref of { KEY, VALUE, LABEL } hashes, upper-case keys
  my $datalist_sv = $opt{ 'DATALIST_SELECTED_VALUE' } // $opt{ 'DATALIST_SELECTED_KEY' }; # VALUE of the selected item, DATALIST_SELECTED_KEY is the old name

  __check_removed_options( \%opt );

  html_check_name_boom( $name );
  html_check_ident_boom( $id );

  $size = $maxl = $len if $len > 0;

  # the clear tag and the datalist need the id of the visible input
  $id = $self->create_uniq_id() if $id eq '' and ( $clear or $datalist );

  my %options;

  $options{ 'type'     } = $opt{ 'TYPE' } if $opt{ 'TYPE' };
  $options{ 'disabled' } = 'disabled' if $opt{ 'DISABLED' };
  $options{ 'size'     } = $size      if $size > 0;
  $options{ 'maxlength'} = $maxl      if $maxl > 0;
  $options{ 'id'       } = $id        if $id ne '';
  $options{ 'type'     } = 'password' if $opt{ 'PASS' } || $opt{ 'PASSWORD' };
  $options{ 'type'     } = 'hidden'   if $hid; # FIXME: handle TYPE better
  $options{ 'readonly' } = 'readonly' if $opt{ 'READONLY' } || $opt{ 'RO' };
  $options{ 'required' } = 'required' if $opt{ 'REQUIRED' } || $opt{ 'REQ' };

  $options{ 'placeholder'  } = $phi   if $phi;
  $options{ 'autocomplete' } = 'off'  if $opt{ 'NO_AUTOCOMPLETE' };

  $options{ 'onFocus'  } = "this.value=''" if $opt{ 'FOCUS_AUTO_CLEAR' };

  if( $hid and defined $ret and $self->reo_optional() ) # cc20261017-reo-optional # cc20261017-2
    {
    # if input is hidden and return value mapping requested, VALUE is not used!
    $value = $self->create_uniq_id();
    $self->__ret_map_data( $name, $value => $ret );
    }
  elsif( $hid and defined $ret ) # cc20261017-reo-optional
    {
    $value = $ret; # no link session, nothing is hidden
    }

  my $clear_tag;
  if( $clear )
    {
    my %clear_hint; # cc20261017-reo-optional
    my $clear_hint_js = $self->__hint( '[~Clear field]' );
    $clear_hint{ 'onmouseover' } = $clear_hint_js if $clear_hint_js;

    # a datalist input clears its hidden key too
    my $id_js    = html_js_str( $id );
    my $clear_js = $datalist ? "set_value( $id_js, '' ); reactor_datalist_change( q( $id_js ), 0 ); return false;" : "return set_value( $id_js, '' )";

    if( $clear =~ /^[a-z_\-0-9\/]+\.(png|jpg|jpeg|gif|svg)\z/ )
      {
      $clear_tag = html_element( 'img', undef, class => 'icon-clear', onClick => $clear_js, src => $clear, %clear_hint ); # cc20261017-reo-optional
      }
    else
      {
      my $s = $clear eq 1 ? '&times;' : $clear;
      $clear_tag = html_element( 'span', $s, class => 'icon-clear', onClick => $clear_js, %clear_hint ); # cc20261017-reo-optional
      }
    }

  my $text;

  my $form_id = $self->{ 'FORM_ID' };

  if( $datalist )
    {
    my $on_change = html_submit_on_change_js( $opt{ 'SUBMIT_ON_CHANGE' } );

    my $hide        = $self->reo_optional(); # names and values are mapped only with a link session # cc20261017-reo-optional # cc20261017-2
    my $name_hidden = $hide ? $self->__ret_map_name( $name ) : $name; # cc20261017-reo-optional

    my $empty_key   = $opt{ 'EMPTY_KEY' }; # never undef in the html, javascript would send "undefined"
    my $input_id    = $self->create_uniq_id();
    my $datalist_id = $self->create_uniq_id();
    $class .= " search_list";

    my $datalist_key;
    my $datalist_label;

    my $datalist_text;
    for my $e ( @$datalist )
      {
      my $k = $e->{ 'KEY'   }; # html-visible key, which is returned
      my $v = $e->{ 'VALUE' }; # actual value, if key is given or generated, return map is used key => value
      my $l = str_html_unescape( $e->{ 'LABEL' } ); # html label as in select(), the datalist shows its text: character references decoded # cc20261017-item-85

      $v = $k if ! defined $v and $k ne '*'; # VALUE missing: KEY is returned, as in select()

      $k = $self->create_uniq_id() if $k eq '*';
      $k = $v                      if $k eq ''; # the value is visible, still mapped so mixed entries work

      $self->__ret_map_data( $name, $k => $v ) if $hide; # cc20261017-reo-optional
      $k = $v unless $hide; # the value itself is sent # cc20261017-reo-optional

      ( $datalist_key, $datalist_label ) = ( $k, $l ) if defined $datalist_sv and $v eq $datalist_sv; # no selection selects nothing
      $datalist_text .= html_element( 'option', undef, name => $l, value => $l, 'data-key' => $k );
      }

    $datalist_text = html_element( 'datalist', $datalist_text, id => $datalist_id );

    # the hidden key input carries the value, a disabled datalist sends none
    my @disabled = $opt{ 'DISABLED' } ? ( disabled => 'disabled' ) : ();
    $text .= html_element( 'input', undef, id => $input_id, type => 'hidden', name => $name_hidden, value => $datalist_key, form => $form_id, @disabled );
    $text .= html_element( 'input', undef, %options, class => $class, value => $datalist_label, form => $form_id, list => $datalist_id, 'data-input-id' => $input_id, 'data-empty-key' => $empty_key // '', onChange => "reactor_datalist_change( this, 0 ); $on_change; return", html_attrs_filter( $opt{ 'ATTRS' }, @ATTRS_PROTECTED, qw( value list data-input-id data-empty-key onchange ) ) ) . $clear_tag;
    $text .= $datalist_text;
    }
  else
    {
#    $text .= "<input class='$class' name='$name' value='$value' $options form='$form_id' $args>$clear_tag";
    $text .= html_element( 'input', undef, %options, class => $class, name => $name, value => $value, form => $form_id, html_attrs_filter( $opt{ 'ATTRS' }, @ATTRS_PROTECTED, qw( value ) ) ) . $clear_tag;
    }

  $text .= "\n";
  return $text;
}

##############################################################################

sub file_upload
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'    };
  my $id    =    $opt{ 'ID'      };
  my $class =    $opt{ 'CLASS'   } || $self->{ 'CLASS_MAP' }{ 'FILE_UPLOAD' } || 'file_upload';

  __check_removed_options( \%opt );

  html_check_name_boom( $name );
  html_check_ident_boom( $id );

  my %options;

  $options{ 'multiple' } = 'multiple' if $opt{ 'MULTI' };
  $options{ 'id'       } = $id        if $id ne '';

  my $text;

  my $form_id = $self->{ 'FORM_ID' };

  $text .= html_element( 'input', undef, %options, class => $class, name => $name, type => 'file', form => $form_id, html_attrs_filter( $opt{ 'ATTRS' }, @ATTRS_PROTECTED, qw( type ) ) );

  $text .= "\n";
  return $text;
}

sub file_upload_multi
{
  my $self = shift;
  return $self->file_upload( @_, MULTI => 1 );
}


##############################################################################

sub button
{
  my $self = shift;

  my %opt = @_;

  my $name    = uc $opt{ 'NAME'    };
  my $id      =    $opt{ 'ID'      };
  my $class   =    $opt{ 'CLASS'   } || $self->{ 'CLASS_MAP' }{ 'BUTTON' } || 'button';
  my $value   =    $opt{ 'VALUE'   };
  my $confirm =    $opt{ 'CONFIRM' };
  my $hint    =    $opt{ 'HINT'    }; # hover layer text, see html_hover_layer()

  __check_removed_options( \%opt );

  $name =~ s/^button://i;
  html_check_button_name_boom( $name ); # Reflex get_user_input_button() reads it back
  html_check_ident_boom( $id );

  my %options;

  if( $opt{ 'DISABLED' } )
    {
    $options{ 'disabled' } = 'disabled';
    $class   .= " disabled-button";
    }

  $options{ 'id'      } = $id                       if $id ne '';
  $options{ 'onClick' } = html_confirm_js( $confirm ) if $confirm;
  # a disabled button has no hint, as html_alink()
  my $hint_js = $opt{ 'DISABLED' } ? undef : $self->__hint( $hint, DELAY => 1000 ); # cc20261017-reo-optional
  $options{ 'onmouseover' } = $hint_js if $hint_js; # cc20261017-reo-optional

  my $text;


  my $form_id = $self->{ 'FORM_ID' };
#  $text .= "<input class='$class' id='$id' type='submit' name='button:$name' value='$value' onDblClick='return false;' form='$form_id' $options $args>";
  #$text .= "<button class='$class' id='$id' type='submit' name='button:$name' value='1' onDblClick='return false;' form='$form_id' $options $args>$value</button>";

  $text .= html_element( 'button', $value, %options, form => $form_id, class => $class, name => "button:$name", onDblClick => 'return false;', html_attrs_filter( $opt{ 'ATTRS' }, @ATTRS_PROTECTED ) );

  $text .= "\n";
  return $text;
}

sub image_button
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $id    =    $opt{ 'ID'    };
  my $class =    $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'IMAGE_BUTTON' } || 'image_button';
  my $src   =    $opt{ 'SRC'   } || $opt{ 'IMG'  };
  my $confirm =    $opt{ 'CONFIRM' };
  my $hint    =    $opt{ 'HINT'    }; # hover layer text, see html_hover_layer()

  __check_removed_options( \%opt );

  $name =~ s/^button://i;
  html_check_button_name_boom( $name ); # Reflex get_user_input_button() reads it back
  html_check_ident_boom( $id );

  my %options;

  if( $opt{ 'DISABLED' } ) # as button()
    {
    $options{ 'disabled' } = 'disabled';
    $class   .= " disabled-button";
    }

  for my $o ( qw( HEIGHT WIDTH ONMOUSEOVER ) )
    {
    my $e = $opt{ $o };
    $options{ $o }  = $e if $e ne '';
    }

  $options{ 'id'      } = $id                       if $id ne '';
  $options{ 'onClick' } = html_confirm_js( $confirm ) if $confirm;
  # HINT replaces ONMOUSEOVER (same key), a disabled button has no hint, as html_alink()
  my $hint_js = $opt{ 'DISABLED' } ? undef : $self->__hint( $hint, DELAY => 1000 ); # cc20261017-reo-optional
  $options{ 'ONMOUSEOVER' } = $hint_js if $hint_js; # cc20261017-reo-optional

  my $text;

  my $form_id = $self->{ 'FORM_ID' };

  ### $text .= "<input class='$class' id='$id' type='image' name='button:$name' src='$src' border=0 $options onDblClick='return false;'>";
  $text .= html_element( 'input', undef, %options, type => 'image', form => $form_id, class => $class, name => "button:$name", src => $src, onDblClick => 'return false;', html_attrs_filter( $opt{ 'ATTRS' }, @ATTRS_PROTECTED, qw( type ) ) );

  $text .= "\n";
  return $text;
}

sub image_button_default
{
  my $self = shift;

  my %opt = @_;

  # out of sight as the begin() DEFAULT_BUTTON, no browser detection # cc20261017-reo-optional
  # the caller's names are lower-cased first, so STYLE or TabIndex cannot win over the defaults
  my %attrs = map { lc( $_ ) => $opt{ 'ATTRS' }{ $_ } } keys %{ $opt{ 'ATTRS' } || {} };
  $opt{ 'ATTRS' } = { %attrs, %DEFAULT_BUTTON_ATTRS };

  return $self->image_button( %opt );
}

sub get_id
{
  my $self = shift;

  return $self->{ 'FORM_ID'   };
}

=head1 NAME

Web::Reactor::HTML::Form - html forms with hidden names and return values

=head1 SYNOPSIS

  my $form = $reo->new_form(); # or Web::Reactor::HTML::Form->new( $reo )

  $text .= $form->begin( NAME => 'try1', DEFAULT_BUTTON => 'OK' );

  $text .= $form->input( NAME => 'line_one', VALUE => 'text', CLEAR => 1 );

  $text .= 'cb1' . $form->checkbox( NAME => 'cb1', VALUE => 1 );
  $text .= 'cb3' . $form->checkbox_3state( NAME => 'cb3', VALUE => 0 );

  $text .= 'r1' . $form->radio( NAME => 'r1', KEY => 1 );
  $text .= 'r2' . $form->radio( NAME => 'r1', KEY => 2, ON => 1 );
  $text .= 'r3' . $form->radio( NAME => 'r2', RET => 'asd', ON => 1 );
  $text .= 'r4' . $form->radio( NAME => 'r2', RET => 'qwe' );

  my $data = {
             'one' => 'This is test one',
             'opa' => 'Opa test ooooooe',
             };

  $text .= $form->select( NAME => 'sel2', DATA => $data, SELECTED => [ 'opa' ], SIZE => 4 );

  $text .= $form->button( NAME => 'OK', VALUE => 'Save', CONFIRM => 1, HINT => 'save the data' );
  $text .= $form->end();

=head1 DESCRIPTION

all elements belong to the form started by begin() through the html "form"
attribute, so they can be placed anywhere in the page. element names are
upper-cased, the submitted values come in the user input under them.

with a reactor, select(), the DATALIST of input(), radio() with RET and a
hidden input() with RET do not send their return values to the browser, only
keys: random ones for KEY "*" and RET, the given KEY otherwise (an empty KEY
uses the VALUE). select() and the DATALIST also hide their NAME. the real
names and values are kept in the link session (the return map, stored by
end()) and come back in the safe input under the element NAME, so they cannot
be forged. several
selected values of a MULTIPLE select come as "@NAME" (array reference).

a clicked button comes as get_input_button(): its NAME, or for a NAME like
"REDIRECT:OK" the part before the ":" ("REDIRECT"), and get_input_button_id()
gives the part after it ("OK"), see Web::Reactor.

=head1 WITHOUT A REACTOR

the reactor object is optional (new() without it), for forms outside
Web::Reactor pages or without sessions. then:

  - ids come from Web::Reactor::HTML::Utils html_uniq_id()
  - nothing is hidden: there is no link session, select(), the DATALIST
    of input(), radio() with RET and a hidden input() with RET send the
    real values under the real names
  - end() writes the form state (state() data, FORM_NAME, FORM_ID) as
    plain hidden inputs, there is no state keeper "_"
  - HINT options are ignored, the hover layers need the reactor page holds

=head1 OPTIONS OF ALL ELEMENTS

  NAME      -- element name, required: letters, digits, "_", ":" and "."
               (html_check_name()), upper-cased
  ID        -- html id, optional (html_check_ident())
  CLASS     -- css class, default from the CLASS_MAP of begin(), else a
               built-in one (checkbox, radio, select, textarea, line,
               file_upload, button, image_button; checkbox_multi has none)
  ATTRS     -- { attribute => value, ... } extra html attributes, escaped,
               they win over the generated ones except name, form, id and
               the ones the element needs to work (html_attrs_filter())
  DISABLED  -- the element is disabled: input, textarea, select, button and
               image_button (a disabled element sends no value)

  EXTRA and ARGS (raw html attributes) are removed, they die, use ATTRS.

=head1 METHODS

=head2 new( $reo, $cfg, %opt ), new( $reo, %opt ), new( %opt )

creates a form object. $reo is the Web::Reactor object or undef (or
missing): without it nothing is hidden or mapped, see WITHOUT A REACTOR. a
Web::Reactor::Reflex or Core object booms, they have no LINK session for the
return map. $cfg defaults to the reactor config.
Web::Reactor new_form() gives the same as new( $reo ). options:

  DEBUG       -- the form name and id get FORM_ and FORM_ID_ prefixes in the
                 html (the reactor debug level is not used)

=head2 begin( %opt )

starts the form, returns its html:

  NAME            -- form name (random if missing), it comes back as
                     get_input_form_name()
  ID              -- form html id (from NAME if missing), letters, digits,
                     "_", ":" and "." only (html_check_name()), stricter
                     than the element ids
  METHOD          -- POST (default) or GET
  ACTION          -- form action url (default "?")
  DEFAULT_BUTTON  -- button NAME the Enter key presses
  NO_AUTOCOMPLETE -- no browser autocomplete for the form
  CLASS_MAP       -- { CHECKBOX, CHECKBOX_MULTI, RADIO, SELECT, TEXTAREA,
                     INPUT, FILE_UPLOAD, BUTTON, IMAGE_BUTTON } default
                     classes for the elements

=head2 state( %data ), state_new( %data ), state_here( %data ), state_back( %data ), state_none( %data )

data for the form state keeper link (the hidden "_" input written by end()),
it comes back in the safe input. the _new/_here/_back/_none variants also set
the link type (see Web::Reactor args_type()), HERE is the default. it can be
called before or after begin().

=head2 end()

ends the form: writes the state keeper and stores the return map, returns
the html. the form state is cleared, the object can begin() a new form.

=head2 checkbox( NAME, VALUE, %opt )

classic checkbox, sends 1 or 0. VALUE true makes it checked.

=head2 checkbox_multi( NAME, VALUE, STAGES, LABELS, HINT, %opt ), checkbox_3state( ... )

checkbox with STAGES states (default 2), a click goes to the next one,
sends the state number 0 .. STAGES-1. LABELS is an array ref with the html
for each state (a state without a label shows its number), HINT is a hover
layer text. checkbox_3state() has 3 stages and "?", "&radic;", "x" labels.

=head2 radio( NAME, KEY or RET, ON, %opt )

one radio button of the NAME group. KEY is the sent value, or RET a return
value which is mapped (the browser sees a random key). ON makes it checked.

=head2 select( NAME, DATA, SELECTED, %opt ), combo( ... )

drop-down or list:

  $data = [
           {
           KEY      => string      # visible html key, '*' generates one, empty uses VALUE
           VALUE    => string      # return value, kept in the link session (sent as is without a reactor)
           LABEL    => string      # visible text for this key/value
           SELECTED => bool        # this option is selected
           },
         ];

  $data = {
           KEY => {
                  VALUE => string      # return value, kept in the link session (sent as is without a reactor)
                  LABEL => string      # visible text for this key/value
                  ORDER => \d+         # sort order, then by KEY
                  },
           KEY => label_string,
          };

if VALUE is missing, KEY will be returned. array data keeps its order, hash
data is sorted by ORDER and KEY.

  SELECTED          -- selected return value, or hash or array ref of them
  SIZE, ROWS        -- visible rows, 1 (default) is a drop-down
  MULTIPLE          -- several values can be selected
  SUBMIT_ON_CHANGE  -- 1 submits the form on change, a string is javascript
                       to run (html_submit_on_change_js())

=head2 textarea( NAME, VALUE, %opt )

  ROWS, COLS        -- size (default 10 rows, 50 columns)
  GEOMETRY, GEO     -- "COLS*ROWS" (also "/" or "\" between)
  MAXLEN, MAX       -- maximum length
  READONLY, RO      -- read only
  REQUIRED, REQ     -- required
  FOCUS_AUTO_CLEAR  -- cleared on focus

=head2 input( NAME, VALUE, %opt )

text line or other input:

  SIZE, WIDTH       -- visible size
  MAXLEN, MAX       -- maximum length
  LEN               -- sets both SIZE and MAXLEN
  TYPE              -- input type
  PASS, PASSWORD    -- password input
  HIDDEN            -- hidden input
  RET, RETURN       -- with HIDDEN: return value, mapped, VALUE is not used
  PH, PHI           -- placeholder text
  CLEAR             -- clear button: 1 (a cross), a text or an image file name
  NO_AUTOCOMPLETE   -- no browser autocomplete
  READONLY, RO; REQUIRED, REQ; FOCUS_AUTO_CLEAR -- as for textarea()

  DATALIST          -- [ { KEY, VALUE, LABEL }, ... ] search list, the LABEL is
                       shown and searched, the VALUE is returned (mapped as
                       for select(), KEY "*" generates the key, an empty
                       one uses the VALUE).
                       a datalist shows plain text: the character references
                       of the LABEL are decoded (Data::Tools
                       str_html_unescape(): numeric ones and the common
                       named ones), tags stay as text # cc20261017-item-85
  DATALIST_SELECTED_VALUE -- VALUE of the selected entry (the old name
                       DATALIST_SELECTED_KEY still works)
  EMPTY_KEY         -- key sent when the text matches no entry. with a
                       reactor it is mapped like the entry keys: the app
                       gets the VALUE of the entry with that key, undef if
                       no entry has it
  SUBMIT_ON_CHANGE  -- as for select()

=head2 file_upload( NAME, MULTI, %opt ), file_upload_multi( ... )

file upload input, MULTI allows several files, see Web::Reactor
get_user_uploads().

=head2 button( NAME, VALUE, %opt )

submit button, VALUE is its html content. NAME is "NAME" or "NAME:ID", see
Web::Reactor::HTML::Utils html_check_button_name(), the same for image_button()
and the DEFAULT_BUTTON of begin().

  CONFIRM           -- question before submit, 1 asks the default one
                       (html_confirm_js())
  HINT              -- hover layer text (not on a disabled button, needs the
                       reactor object)

=head2 image_button( NAME, SRC, %opt ), image_button_default( ... )

image submit button, SRC (or IMG) is the image url. HEIGHT, WIDTH and
ONMOUSEOVER are image attributes, CONFIRM, HINT and DISABLED as for
button(). image_button_default() is
one for the default (Enter) button, rendered but out of sight as the
DEFAULT_BUTTON of begin() (a display: none button is not pressed by Enter in
some browsers).

=head2 get_id()

returns the form html id.

=cut

##############################################################################
1;
##############################################################################
