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
use Data::Tools 1.31;
use Exception::Sink;

use Web::Reactor::HTML::Utils;

# FIXME: TODO: use common func to add html elements common tags: ID,DISABLED,etc.
# FIXME: TODO: ...including abstract ones as GEO(metry)
# FIXME: TODO: change VALUE to be html value (currently it is DATA), and DISPLAY to be visible text (currently it is VALUE)

our $VERSION = '2.14';

use parent 'Web::Reactor::Base';

##############################################################################

# new constructor inherited from 'Web::Reactor::Base'

##############################################################################

sub create_uniq_id
{
  my $self = shift;

  return $self->reo()->create_uniq_id();
}

# optional identifiers (ID, etc.), empty or undef is allowed
sub __check_ident
{
  for( @_ )
    {
    /^([a-zA-Z0-9_:.]+|)$/ or boom "invalid IDENTIFIER [$_]";
    }
  return 1;
}

# element names, must not be empty
sub __check_name
{
  for( @_ )
    {
    /^[a-zA-Z0-9_:.]+$/ or boom "invalid or empty NAME [$_]";
    }
  return 1;
}

# javascript string literal, double quoted, for inline event handlers
# (html_element() escapes the attribute value itself)
sub __js_str
{
  my $s = shift;

  $s =~ s/([\\"'])/\\$1/g;
  $s =~ s/\n/\\n/g;
  $s =~ s/\r/\\r/g;

  return qq["$s"];
}

# onclick handler for the CONFIRM option, undef if no confirmation is needed
sub __confirm_js
{
  my $confirm = shift;

  return undef unless $confirm;
  $confirm = "[~Are you sure?]" if $confirm eq '1';
  return "return confirm(" . __js_str( $confirm ) . ");";
}

# onchange handler for the SUBMIT_ON_CHANGE option:
#   positive number -- submit the form
#   other string    -- javascript code to run
#   false           -- undef, no handler
sub __submit_on_change_js
{
  my $soc = shift;

  return undef unless $soc;
  return 'this.form.submit()' if $soc =~ /^\d+$/;
  return $soc;
}

# the ATTRS option of all elements: { attribute => value, ... } extra html
# attributes, escaped by html_element(). they are given last, so they win
# over the generated ones, except name, form and id (use NAME and ID) and the
# ones the element needs to work (@keep)
# returns:
#       attribute name/value pairs, empty without ATTRS
sub __attrs
{
  my $opt  = shift;
  my @keep = @_;

  my $attrs = $opt->{ 'ATTRS' } or return ();
  boom "ATTRS must be a HASH reference" unless ref( $attrs ) eq 'HASH';

  my %ah = %$attrs;
  hash_lc_ipl( \%ah );
  delete @ah{ 'name', 'form', 'id', map { lc } @keep };

  return %ah;
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
  my $default_button =    $opt{ 'DEFAULT_BUTTON' };

  $self->{ 'CLASS_MAP' } = $opt{ 'CLASS_MAP' } || {};

  $method =~ /^(POST|GET)$/  or boom "METHOD can be either POST or GET";

  my $reo = $self->reo();

  $name ||= $reo->create_uniq_id();
  $id   ||= $name . '.' . $reo->create_uniq_id();
  __check_name( $name, $id );

  # debug prefixes are only visible in the html, the form state keeps the real name
  my $html_name = $name;
  if( $reo->is_debug() )
    {
    $html_name = "FORM_$name";
    $id        = "FORM_ID_$id";
    }

  $self->{ 'FORM_NAME'  } = $name;
  $self->{ 'FORM_ID'    } = $id;
  $self->{ 'RET_MAP'    } = {}; # return data mapping (combo, checkbox, etc.)

  my %at;

  $at{ 'autocomplete' } = 'off' if $opt{ 'NO_AUTOCOMPLETE' };

  my $text;

  # FIXME: TODO: debug info inside html text, begin formname end etc.

  # state set before begin() is kept, args type defaults to HERE
  $self->state( 'FORM_NAME'  => $name  ); # TODO: replace with _FRO
  $self->state( 'FORM_ID'    => $id    ); # TODO: replace with _FRI
  $self->state( ':ARGS_TYPE' => $self->{ 'FORM_STATE' }{ ':ARGS_TYPE' } || 'HERE' );

  $text .= html_element( 'FORM', '', name => $html_name, id => $id, action => $action, method => $method, enctype => 'multipart/form-data', %at );

#### REMOVE ###  $text .= "<form name='$form_name' id='$form_id' action='$action' method='$method' enctype='multipart/form-data' $options></form>";
#### REMOVE ###  ### $text .= "<input style='display: none;' name='__avoidiebug__' form='$form_id'>"; # stupid IE bugs
  if( $default_button )
    {
    $text .= html_element( 'INPUT', undef, form => $id, type => 'image', name => "button:$default_button", src => 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQI12NgYGBgAAAABQABXvMqOgAAAABJRU5ErkJggg==', border => 0, height => 0, width => 0, style => 'display: none;', onDblClick => 'return false;' );
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

  my $reo = $self->reo();

  my $form_id = $self->{ 'FORM_ID' };

  my $link_shr = $reo->get_link_session();
  $link_shr->{ 'FORM_RET_MAP' }{ $form_id } = $self->{ 'RET_MAP' };

  # the form state is used once, a reused form object starts with a clean state
  my %state     = %{ delete $self->{ 'FORM_STATE' } || {} };
  my $args_type = delete $state{ ':ARGS_TYPE' } || 'HERE';

  my $state_keeper = $reo->args_type( $args_type, %state );

##### REMOVE #####  #$text .= "<input type=hidden name='_' value='$state_keeper' form='$form_id'>";
  $text .= html_element( 'INPUT', undef, form => $form_id, type => 'hidden', name => '_', value => $state_keeper );

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

die "error: Form.pm: EXTRA used but it is removed, content is [$opt{ 'EXTRA' }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'EXTRA' };
die "error: Form.pm: ARGS used but it is removed, content is [$opt{ 'ARGS'   }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'ARGS'   };

  __check_name( $name );

  my %options;
  $options{ 'checked' } = undef if $value; # bare attribute

  my $text;

  my $ch_id = $self->create_uniq_id(); # checkbox data holder

  my $form_id = $self->{ 'FORM_ID' };
  #print STDERR "ccccccccccccccccccccc CHECKBOX [$name] [$value]\n";
  $text .= "\n";
  $text .= html_element( 'input', undef, type => 'hidden', name => $name, id => $ch_id, value => $value, form => $form_id );
  $text .= html_element( 'input', undef, %options, type => 'checkbox', 'data-checkbox-input-id' => $ch_id, form => $form_id, onclick => 'reactor_form_checkbox_toggle(this)', class => $class, __attrs( \%opt, qw( type onclick data-checkbox-input-id ) ) );
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
  my $class  =    $opt{ 'CLASS'  } || $self->{ 'CLASS_MAP' }{ 'CHECKBOX' } || 'checkbox';
  my $value  =    $opt{ 'VALUE'  };
  my $stages =    $opt{ 'STAGES' } || 2;
  my $labels =    $opt{ 'LABELS' } || [ 'x', '&radic;' ];
  my $hint   =    $opt{ 'HINT'   };
  my $id     =    $opt{ 'ID'     };

die "error: Form.pm: EXTRA used but it is removed, content is [$opt{ 'EXTRA' }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'EXTRA' };
die "error: Form.pm: ARGS used but it is removed, content is [$opt{ 'ARGS'   }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'ARGS'   };

  __check_name( $name );
  __check_ident( $id );

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
  $options{ 'onmouseover' } = html_hover_layer( $self->reo(), VALUE => $hint ) if $hint;

  my $cb_id = $self->create_uniq_id(); # checkbox id
  my $el_id = $id || $self->create_uniq_id(); # checkbox label element id

  my $form_id = $self->{ 'FORM_ID' };
  $text .= html_element( "input", undef, type => 'hidden', name => $name, id => $cb_id, value => $value, form => $form_id );
  $text .= html_element( "span", $labels_spans, %options, id => $el_id, class => $class, 'data-stages' => $stages, 'data-checkbox-input-id' => $cb_id, onclick => 'reactor_form_multi_checkbox_toggle(this)', __attrs( \%opt, qw( onclick data-stages data-checkbox-input-id ) ) );
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

die "error: Form.pm: EXTRA used but it is removed, content is [$opt{ 'EXTRA' }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'EXTRA' };
die "error: Form.pm: ARGS used but it is removed, content is [$opt{ 'ARGS'   }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'ARGS'   };

  __check_name( $name );

  my $text;

  my $val = defined $ret ? $self->create_uniq_id() : $key // '';

  my %options;
  $options{ 'checked' } = undef if $on; # bare attribute

  my $form_id = $self->{ 'FORM_ID' };
  $text .= html_element( 'input', undef, %options, type => 'radio', name => $name, value => $val, class => $class, form => $form_id, __attrs( \%opt, qw( type value ) ) );

  $self->__ret_map_data( $name, $val => $ret ) if defined $ret;

  $text .= "\n";
  return $text;
}

##############################################################################
=pod

$form->select( NAME => $name, DATA => $data, SELECTED => $selected );

$data = [
         {
         KEY      => string      # visible html key, '*' or empty generates one
         VALUE    => string      # return value, safely stored or encrypted
         LABEL    => string      # visible text for this key/value
         SELECTED => bool        # this option is selected
         },
       ];

$data = {
         KEY => {
                VALUE => string      # return value, safely stored or encrypted
                LABEL => string      # visible text for this key/value
                ORDER => \d+         # sort order, then by KEY
                },
         KEY => label_string,
        };

if VALUE is missing, KEY will be returned

array data keeps its order, hash data is sorted by ORDER and KEY

$selected is a return value, or a hashref or arrayref of selected return values

=cut

sub select
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $id    =    $opt{ 'ID'    };
  my $class =    $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'SELECT' } || 'select';
  my $rows  =    $opt{ 'SIZE'  } || $opt{ 'ROWS'  } || 1;

  __check_name( $name );
  __check_ident( $id );

  my $data     = $opt{ 'DATA'     }; # array reference or hash reference, inside hashesh are the same
  my $selected = $opt{ 'SELECTED' }; # selected return value, hashref or arrayref of them
  my $sel_data;

  $selected = { map { $_ => 1 } @$selected } if ref( $selected ) eq 'ARRAY';

  my %at;

  $at{ 'form'  } = $self->{ 'FORM_ID' };
  $at{ 'name'  } = $self->__ret_map_name( $name );
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

  my $on_change = __submit_on_change_js( $opt{ 'SUBMIT_ON_CHANGE' } );
  $at{ 'onChange' } = $on_change if $on_change;

  $at{ 'multiple' } = 'multiple' if $opt{ 'MULTIPLE' };

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

    $self->__ret_map_data( $name, $key => $value );

    $at_opt{ 'value' } = $key;
#print STDERR "sssssssssssssssssssssssss COMBO [$name] [$value] [$key] $sel\n";
    #$opt_text .= "<option value='$val_id' $sel>$value$pad</option>\n";
    $opt_text .= html_element( 'OPTION', $label, %at_opt );
    }

#    $text .= "<select class='$class' id='$id' name='$name' size='$rows' $multiple form='$form_id' $args $extra $options>";
  $text .= html_element( 'SELECT', $opt_text, %at, __attrs( \%opt ) );
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

die "error: Form.pm: EXTRA used but it is removed, content is [$opt{ 'EXTRA' }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'EXTRA' };
die "error: Form.pm: ARGS used but it is removed, content is [$opt{ 'ARGS'   }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'ARGS'   };

  __check_name( $name );
  __check_ident( $id );

  ( $cols, $rows ) = ( $1, $2 ) if $geo =~ /(\d+)[\*\/\\](\d+)/;


  my %options;

  $options{ 'id'        } = $id             if $id ne '';
  $options{ 'disabled'  } = 'disabled'      if $opt{ 'DISABLED' };
  $options{ 'maxlength' } = $maxl           if $maxl > 0;
  $options{ 'readonly'  } = 'readonly'      if $opt{ 'READONLY' } || $opt{ 'RO' };
  $options{ 'required'  } = 'required'      if $opt{ 'REQUIRED' } || $opt{ 'REQ' };
  $options{ 'onFocus'   } = "this.value=''" if $opt{ 'FOCUS_AUTO_CLEAR' };

  # never undef, html_element() would make a self-closed <textarea/>
  $data = str_html_escape( $data // '' );

  my $text;
  my $form_id = $self->{ 'FORM_ID' };

  $text .= html_element( 'textarea', $data, %options, class => $class, name => $name, rows => $rows, cols => $cols, form => $form_id, __attrs( \%opt ) );

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
  my $ret   =    $opt{ 'RET'     } || $opt{ 'RETURN'  }; # if return value should be mapped, works only with HIDDEN

  my $phi   =    $opt{ 'PH' } || $opt{ 'PHI' };

  my $clear =    $opt{ 'DISABLED' } ? undef : $opt{ 'CLEAR'   };

  my $datalist    = $opt{ 'DATALIST'              }; # array ref with 'key', 'value' and 'label' hash
  my $datalist_sv = $opt{ 'DATALIST_SELECTED_VALUE' } // $opt{ 'DATALIST_SELECTED_KEY' }; # VALUE of the selected item, DATALIST_SELECTED_KEY is the old name

die "error: Form.pm: EXTRA used but it is removed, content is [$opt{ 'EXTRA' }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'EXTRA' };
die "error: Form.pm: ARGS used but it is removed, content is [$opt{ 'ARGS'   }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'ARGS'   };

  __check_name( $name );
  __check_ident( $id );

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

  if( $hid and defined $ret )
    {
    # if input is hidden and return value mapping requested, VALUE is not used!
    $value = $self->create_uniq_id();
    $self->__ret_map_data( $name, $value => $ret );
    }

  my $clear_tag;
  if( $clear )
    {
    my $reo = $self->reo();
    my $clear_hint_handler = html_hover_layer( $reo, VALUE => 'Clear field' );

    # a datalist input clears its hidden key too
    my $clear_js = $datalist ? "set_value('$id', ''); reactor_datalist_change( q('$id'), 0 ); return false;" : "return set_value('$id', '')";

    if( $clear =~ /^[a-z_\-0-9\/]+\.(png|jpg|jpeg|gif|svg)$/ )
      {
      $clear_tag = html_element( 'img', undef, class => 'icon-clear', onClick => $clear_js, src => $clear, onmouseover => $clear_hint_handler );
      }
    else
      {
      my $s = $clear eq 1 ? '&times;' : $clear;
      $clear_tag = html_element( 'span', $s, class => 'icon-clear', onClick => $clear_js, onmouseover => $clear_hint_handler );
      }
    }

  my $text;

  my $form_id = $self->{ 'FORM_ID' };

  if( $datalist )
    {
    my $on_change = __submit_on_change_js( $opt{ 'SUBMIT_ON_CHANGE' } );

    my $name_hidden = $self->__ret_map_name( $name );

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
      my $l = $e->{ 'LABEL' }; # html-visible text label

      $k = $self->create_uniq_id() if $k eq '*';
      $k = $v                      if $k eq ''; # the value is visible, still mapped so mixed entries work

      $self->__ret_map_data( $name, $k => $v );

      ( $datalist_key, $datalist_label ) = ( $k, $l ) if $v eq $datalist_sv;
      $datalist_text .= html_element( 'option', undef, name => $l, value => $l, 'data-key' => $k );
      }

    $datalist_text = html_element( 'datalist', $datalist_text, id => $datalist_id );

    $text .= html_element( 'input', undef, id => $input_id, type => 'hidden', name => $name_hidden, value => $datalist_key, form => $form_id );
    $text .= html_element( 'input', undef, %options, class => $class, value => $datalist_label, form => $form_id, list => $datalist_id, 'data-input-id' => $input_id, 'data-empty-key' => $empty_key // '', onChange => "reactor_datalist_change( this, 0 ); $on_change; return", __attrs( \%opt, qw( value list data-input-id data-empty-key onchange ) ) ) . $clear_tag;
    $text .= $datalist_text;
    }
  else
    {
#    $text .= "<input class='$class' name='$name' value='$value' $options form='$form_id' $args>$clear_tag";
    $text .= html_element( 'input', undef, %options, class => $class, name => $name, value => $value, form => $form_id, __attrs( \%opt, qw( value ) ) ) . $clear_tag;
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

die "error: Form.pm: EXTRA used but it is removed, content is [$opt{ 'EXTRA' }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'EXTRA' };
die "error: Form.pm: ARGS used but it is removed, content is [$opt{ 'ARGS'   }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'ARGS'   };

  __check_name( $name );
  __check_ident( $id );

  my %options;

  $options{ 'multiple' } = 'multiple' if $opt{ 'MULTI' };
  $options{ 'id'       } = $id        if $id ne '';

  my $text;

  my $form_id = $self->{ 'FORM_ID' };

  $text .= html_element( 'input', undef, %options, class => $class, name => $name, type => 'file', form => $form_id, __attrs( \%opt, qw( type ) ) );

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
  my $value   =    $opt{ 'VALUE'   } // ''; # never undef, html_element() would make a self-closed <button/>
  my $confirm =    $opt{ 'CONFIRM' };
  my $hint    =    $opt{ 'HINT'    }; # hover layer text, see html_hover_layer()

die "error: Form.pm: EXTRA used but it is removed, content is [$opt{ 'EXTRA' }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'EXTRA' };
die "error: Form.pm: ARGS used but it is removed, content is [$opt{ 'ARGS'   }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'ARGS'   };

  __check_name( $name );
  __check_ident( $id );

  my %options;

  if( $opt{ 'DISABLED' } )
    {
    $options{ 'disabled' } = 'disabled';
    $class   .= " disabled-button";
    }

  $options{ 'id'      } = $id                       if $id ne '';
  $options{ 'onClick' } = __confirm_js( $confirm ) if $confirm;
  # a disabled button has no hint, as html_alink()
  $options{ 'onmouseover' } = html_hover_layer( $self->reo(), VALUE => $hint, DELAY => 1000 ) if $hint and ! $opt{ 'DISABLED' };

  my $text;

  $name =~ s/^button://i;

  my $form_id = $self->{ 'FORM_ID' };
#  $text .= "<input class='$class' id='$id' type='submit' name='button:$name' value='$value' onDblClick='return false;' form='$form_id' $options $args>";
  #$text .= "<button class='$class' id='$id' type='submit' name='button:$name' value='1' onDblClick='return false;' form='$form_id' $options $args>$value</button>";

  $text .= html_element( 'button', $value, %options, form => $form_id, class => $class, name => "button:$name", onDblClick => 'return false;', __attrs( \%opt ) );

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

die "error: Form.pm: EXTRA used but it is removed, content is [$opt{ 'EXTRA' }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'EXTRA' };
die "error: Form.pm: ARGS used but it is removed, content is [$opt{ 'ARGS'   }]\n" . Exception::Sink::get_stack_trace() if $opt{ 'ARGS'   };

  __check_name( $name );
  __check_ident( $id );

  my %options;

  # FIXME: make this for all entries! common func?
  for my $o ( qw( HEIGHT WIDTH ONMOUSEOVER ) )
    {
    my $e = $opt{ $o };
    $options{ $o }  = $e if $e ne '';
    }

  $options{ 'id'      } = $id                       if $id ne '';
  $options{ 'onClick' } = __confirm_js( $confirm ) if $confirm;
  # HINT replaces ONMOUSEOVER (same key), a disabled button has no hint, as html_alink()
  $options{ 'ONMOUSEOVER' } = html_hover_layer( $self->reo(), VALUE => $hint, DELAY => 1000 ) if $hint and ! $opt{ 'DISABLED' };

  my $text;

  my $form_id = $self->{ 'FORM_ID' };
  $name =~ s/^button://i;

  ### $text .= "<input class='$class' id='$id' type='image' name='button:$name' src='$src' border=0 $options onDblClick='return false;'>";
  $text .= html_element( 'input', undef, %options, type => 'image', form => $form_id, class => $class, name => "button:$name", src => $src, onDblClick => 'return false;', __attrs( \%opt, qw( type ) ) );

  $text .= "\n";
  return $text;
}

sub image_button_default
{
  my $self = shift;

  my %opt = @_;

  my $user_agent = $self->reo()->get_user_session_agent();

  # msie and the real safari only, chrome, edge and opera also claim "Safari"
  my $default_class = 'hidden';
  $default_class = 'hidden2' if $user_agent =~ /MSIE|Trident/ or ( $user_agent =~ /Safari/ and $user_agent !~ /Chrome|Chromium|CriOS|Edg|OPR/ );

  $opt{ 'HEIGHT' } = 0;
  $opt{ 'WIDTH'  } = 0;
  $opt{ 'CLASS'  } = $opt{ 'CLASS' } || $default_class;

  return $self->image_button( %opt );
}

sub get_id
{
  my $self = shift;

  return $self->{ 'FORM_ID'   };
}

=pod

  my $form = $reo->new_form();

  $text .= $form->begin( NAME => 'try1', DEFAULT_BUTTON => 'def_but' );

  $text .= $form->input( NAME => 'line_one', VALUE => ( $I{ 'LINE_ONE' } || 'ne se chete' ) );

  $text .= 'cb1' . $form->checkbox( NAME => 'cb1', VALUE => 1 );
  $text .= 'cb2' . $form->checkbox( NAME => 'cb2', VALUE => 0 );
  $text .= 'cb3' . $form->checkbox_3state( NAME => 'cb3', VALUE => 0 );
  $text .= "<p>";

  $text .= "<hr noshade>";
  $text .= 'r1' . $form->radio( NAME => 'r1', KEY => 1 );
  $text .= 'r2' . $form->radio( NAME => 'r1', KEY => 2 );
  $text .= 'r3' . $form->radio( NAME => 'r1', KEY => 3, ON => 1 );
  $text .= "<hr noshade>";
  $text .= 'r1' . $form->radio( NAME => 'r2', RET => 'asd', ON => 1 );
  $text .= 'r2' . $form->radio( NAME => 'r2', RET => 'qwe' );
  $text .= 'r3' . $form->radio( NAME => 'r2', RET => 'zxc' );
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
