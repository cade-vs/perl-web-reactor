##############################################################################
##
##  Web::Reactor application machinery
##  2014-2021 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@noxrun.com> <cade@bis.bg> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
##############################################################################
package Web::Reactor::HTML::Form;
use strict;
use Exporter;
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

  return $self->get_reo()->create_uniq_id( shift() );
}

sub __check_ident
{
  for( @_ )
    {
    /^([a-zA-Z_0-9_:.]+|)$/ or boom "invalid or empty IDENTIFIER [$_]";
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
  my $default_button =    $opt{ 'DEFAULT_BUTTON' };

  $self->{ 'CLASS_MAP' } = $opt{ 'CLASS_MAP' } || {};

  $method =~ /^(POST|GET)$/  or boom "METHOD can be either POST or GET";

  my $reo = $self->get_reo();

  $name ||= $reo->create_uniq_id();
  $id   ||= $name . '.' . $reo->create_uniq_id();
  __check_ident( $name, $id );

  if( $reo->is_debug() )
    {
    $name = "FORM_$name";
    $id   = "FORM_ID_$id";
    }

  $self->{ 'FORM_NAME'  } = $name;
  $self->{ 'FORM_ID'    } = $id;
  $self->{ 'RADIO'      } = {};
  $self->{ 'RET_MAP'    } = {}; # return data mapping (combo, checkbox, etc.)
  
  my %at;
  
  $at{ 'autocomplete' } = 'off' if $opt{ 'NO_AUTOCOMPLETE' };

  my $text;

  # FIXME: TODO: debug info inside html text, begin formname end etc.
  
  $self->state( 'FORM_NAME'  => $name  ); # TODO: replace with _FRO
  $self->state( 'FORM_ID'    => $id    ); # TODO: replace with _FRI
  $self->state( ':ARGS_TYPE' => 'HERE' );

  my $ps = $reo->get_page_session();
  $ps->{ ':FORM_DEF' }{ $name } = {};

  
  $text .= html_element( 'FORM', '', name => $name, id => $id, action => $action, method => $method, enctype => 'multipart/form-data', %at );
  
#### REMOVE ###  $text .= "<form name='$form_name' id='$form_id' action='$action' method='$method' enctype='multipart/form-data' $options></form>";
#### REMOVE ###  ### $text .= "<input style='display: none;' name='__avoidiebug__' form='$form_id'>"; # stupid IE bugs
  if( $default_button )
    {
    $text .= html_element( 'INPUT', undef, form => $id, type => 'image', name => "BUTTON:$default_button", src => 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQI12NgYGBgAAAABQABXvMqOgAAAABJRU5ErkJggg==', border => 0, height => 0, width => 0, style => 'display: none;', onDblClick => 'return false;' );
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

  $text .= $self->end_radios();
  # $text .= "</form>";

# FIXME: TODO: debug info inside html text, begin formname end etc.

  my $reo = $self->get_reo();
  my $page_session = $reo->get_page_session();

  my $form_name = $self->{ 'FORM_NAME' };
  my $form_id   = $self->{ 'FORM_ID'   };

  my $link_shr = $reo->get_link_session();
  $link_shr->{ 'FORM_RET_MAP' }{ $form_id } = $self->{ 'RET_MAP' };

  my $state_keeper = $reo->args_type( $self->{ 'FORM_STATE'  }{ ':ARGS_TYPE' }, %{ $self->{ 'FORM_STATE'  } } );

##### REMOVE #####  #$text .= "<input type=hidden name='_' value='$state_keeper' form='$form_id'>";
  $text .= html_element( 'INPUT', undef, form => $form_id, type => 'hidden', name => '_', value => $state_keeper );

  $text .= "\n";
  return $text;
}


sub __ret_map_name
{
  my $self = shift;
  my $name = shift; # input element name to be hidden

  my $key = uc $self->create_uniq_id( 1 ); # upper case
  $self->{ 'RET_MAP' }{ 'NAME' }{ $key } = $name;
  return $key;
}

# $self->__ret_map_set( $input_element_name, visible_key1 => return_value1, visible_key2 => return_value2, ... );
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

  my $name  = $opt{ 'NAME'  };
  my $class = $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'CHECKBOX' } || 'checkbox';
  my $value = $opt{ 'VALUE' } ? 1 : 0;
  my $args  = $opt{ 'ARGS'  };

  __check_ident( $name );

  my $options;
  $options .= $value ? " checked " : undef;

  my $text;

  my $ch_id = $self->create_uniq_id(); # checkbox data holder

  my $form_id = $self->{ 'FORM_ID' };
  #print STDERR "ccccccccccccccccccccc CHECKBOX [$name] [$value]\n";
  #$text .= "<input type='checkbox' name='$name' value='1' $options>";
  $text .= "\n";
  $text .= "<input type='hidden' name='$name' id='$ch_id' value='$value' form='$form_id' $args>";
  # --> $text .= html_element( "input", undef, type => 'hidden', name => $name, id => $ch_id, value => $value, form => $form_id, extra => $args );
#  $text .= qq[ <input type='checkbox' $options checkbox_data_input_id="$ch_id" onclick='document.getElementById( "$ch_id" ).value = this.checked ? 1 : 0'> ];
  $text .= qq[ <input type='checkbox' $options data-checkbox-input-id="$ch_id" form='$form_id' onclick='reactor_form_checkbox_toggle(this)' class='$class'> ];
  # --> $text .= html_element( "input", undef, type => 'checkbox', 'data-checkbox-input-id' => $ch_id, form => $form_id, onclick='reactor_form_checkbox_toggle(this)', class => $class, extra => $options );
  $text .= "\n";

  return $text;
}

##############################################################################
# multi-stages css-styled checkbox

sub checkbox_multi
{
  my $self = shift;

  my %opt = @_;

  my $name   = $opt{ 'NAME'   };
  my $class  = $opt{ 'CLASS'  } || $self->{ 'CLASS_MAP' }{ 'CHECKBOX' } || 'checkbox';
  my $value  = $opt{ 'VALUE'  };
  my $args   = $opt{ 'ARGS'   };
  my $stages = $opt{ 'STAGES' } || 2;
  my $labels = $opt{ 'LABELS' } || [ 'x', '&radic;' ];
  my $hint   = $opt{ 'HINT'   };

  __check_ident( $name );

  $value = abs( int( $value ) );
  $value = 0 if $value >= $stages;

  my $text;

  my $labels_spans;
  for my $s ( 0 .. $stages - 1 )
    {
    my $display = $value == $s ? 'inline' : 'none';
    $labels_spans .= html_element( 'span', $labels->[$s], style => "display: $display" );
    }

  my $reo = $self->get_reo();
  my $hint_handler = $hint ? html_hover_layer( $reo, VALUE => $hint ) : undef;

  my $cb_id = $self->create_uniq_id(); # checkbox id
  my $el_id = $opt{ 'ID' } || $self->create_uniq_id(); # checkbox label element id

  my $form_id = $self->{ 'FORM_ID' };
  $text .= html_element( "input", undef, type => 'hidden', name => $name, id => $cb_id, value => $value, form => $form_id, extra => $args );
  $text .= html_element( "span", $labels_spans, id => $el_id, 'data-stages' => $stages, 'data-checkbox-input-id' => $cb_id, onclick => 'reactor_form_multi_checkbox_toggle(this)', extra => $hint_handler );
#  $text .= html_element( "script", "reactor_form_multi_checkbox_setup_id( '$el_id' )" );
  $text .= "\n";

print STDERR $text;

  return $text;
}

##############################################################################

sub checkbox_3state
{
  my $self = shift;

  my %args = @_; # to fix uneven args
  return $self->checkbox_multi( %args, STAGES => 3, LABELS => [ '?', '&radic;', 'x' ] );
}

##############################################################################

sub radio
{
  my $self = shift;

  my %opt = @_;

  my $name  = $opt{ 'NAME'  }; # FIXME:escape or check?
  my $class = $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'RADIO' } || 'radio';
  my $on    = $opt{ 'ON'    }; # active?
  my $ret   = $opt{ 'RET'   }; # map return value!
  my $key   = $opt{ 'KEY'   }; 
  my $extra = $opt{ 'EXTRA' };

  __check_ident( $name );

  my $text;

  my $val = defined $ret ? $self->create_uniq_id() : $key;

  my $form_id = $self->{ 'FORM_ID' };
  my $checked = $on ? 'checked' : undef;
  $text .= "<input type='radio' $checked name='$name' value='$val' form='$form_id' $extra>";

  $self->__ret_map_data( $name, $val => $ret ) if defined $ret;

  $text .= "\n";
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
         KEY   => string      # visible html key
         VALUE => string      # return value, safely stored or encrypted
         LABEL => string      # visible text for this key/value
         ORDER => \d+
         },
       ];

$data = {
         KEY => {
                VALUE => string      # return value, safely stored or encrypted
                LABEL => string      # visible text for this key/value
                ORDER => \d+
                },
         KEY => label_string,
        };

if VALUE is missing, KEY will be returned

=cut

sub select
{
  my $self = shift;

  my %opt = @_;

  my $name  = $opt{ 'NAME'  };
  my $id    = $opt{ 'ID'    };
  my $class = $opt{ 'CLASS' } || $self->{ 'CLASS_MAP' }{ 'SELECT' } || 'select';
  my $rows  = $opt{ 'SIZE'  } || $opt{ 'ROWS'  } || 1;
  my $attrs = $opt{ 'ATTRS' };

  __check_ident( $name, $id );

  my $data     = $opt{ 'DATA'     }; # array reference or hash reference, inside hashesh are the same
  my $selected = $opt{ 'SELECTED' }; # hashref with selected keys (values are true's)
  my $sel_data;

  my %at;
  
  $at{ 'form' } = $self->{ 'FORM_ID' };

  $at{ 'name' } = $self->__ret_map_name( $name );
  for( qw( id class rows ) )
    {
    $at{ $_ } = $opt{ uc $_ } if $opt{ uc $_ };
    }

  if( ref($data) eq 'HASH' )
    {
    $sel_data = [];
    my %res;
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

  # TODO: FIXME: FIXME: FIXME: FIXME: FIXME: cleanup this mess!
  $at{ 'onChange' } = 'this.form.submit()'       if $opt{ 'SUBMIT_ON_CHANGE' } and $opt{ 'SUBMIT_ON_CHANGE' }  > 0;
  $at{ 'onChange' } = $opt{ 'SUBMIT_ON_CHANGE' } if $opt{ 'SUBMIT_ON_CHANGE' } and $opt{ 'SUBMIT_ON_CHANGE' } == 0;

=pod
  if( $opt{ 'RADIO' } )
    {
    for my $hr ( @$sel_data )
      {
      my $sel   = $hr->{ 'SELECTED' } ? 'selected' : ''; # is selected?
      my $key   = $hr->{ 'KEY'      };
      my $ret   = $hr->{ 'RET'      };
      my $value = $hr->{ 'VALUE'    };

      $sel = 'selected' if ( ref( $selected ) and $selected->{ $key } ) or ( $selected eq $key );
#print STDERR "sssssssssssssssssssssssss RADIO [$name] [$value] [$key] $sel -- {$extra}\n";
      $text .= $self->radio( NAME => $name, RET => $ret, KEY => $key, ON => $sel, EXTRA => $extra, DISABLED => $disabled ) . " $value";
      $text .= "<br>" if $opt{ 'RADIO' } != 2;
      }
    # FIXME: kakvo stava ako nqma dadeno selected pri submit na formata?
    }
  else
=cut
    {
    $at{ 'multiple' } = 'multiple' if $opt{ 'MULTIPLE' };

    my $opt_text;
    my $pad = '&nbsp;' x 3;
    for my $hr ( @$sel_data )
      {
      my $key    = $hr->{ 'KEY'   };
      my $value  = $hr->{ 'VALUE' };
      my $label  = $hr->{ 'LABEL' } || '';

      my %at_opt;
      $at_opt{ 'selected' } = 'selected' if $hr->{ 'SELECTED' } or ( ref( $selected ) ? $selected->{ $value } : $selected eq $value );

      $key = $self->create_uniq_id() if $key eq '*';

      if( $key ne '' )
        {
        $key ||= $self->create_uniq_id();
        $self->__ret_map_data( $name, $key => $value );
        }
      else
        {
        $key = $value;
        }  

      $at_opt{ 'value' } = $key;
#print STDERR "sssssssssssssssssssssssss COMBO [$name] [$value] [$key] $sel\n";
      #$opt_text .= "<option value='$val_id' $sel>$value$pad</option>\n";
      $opt_text .= html_element( 'OPTION', $label, %at_opt );
      }

#    $text .= "</select>";
#    $text .= 
#    $text .= "<select class='$class' id='$id' name='$name' size='$rows' $multiple form='$form_id' $args $extra $options>";
    $text .= html_element( 'SELECT', $opt_text, %at, %$attrs );
    }
# print STDERR "FOOOOOOOOOOOOOOOOOOOOOORM[$text](@$sel){@$order}";

  $text .= "\n";
  return $text;
}

sub combo
{
  my $self = shift;

  my %opt = @_;
  $opt{ 'ROWS'  } ||= 1;
  return $self->select( %opt );
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
  my $cols  =    $opt{ 'COLS'  } ||  5;
  my $maxl  =    $opt{ 'MAXLEN'  } || $opt{ 'MAX' };
  my $geo   =    $opt{ 'GEOMETRY' }  || $opt{ 'GEO' };
  my $args  =    $opt{ 'ARGS'    };

  __check_ident( $name, $id );

  ( $cols, $rows ) = ( $1, $2 ) if $geo =~ /(\d+)[\*\/\\](\d+)/i;


  my $options;

  $options .= "disabled='disabled' " if $opt{ 'DISABLED' };
  $options .= "maxlength='$maxl' "   if $maxl > 0;
  $options .= "id='$id' "            if $id ne '';
  $options .= "readonly='readonly' " if $opt{ 'READONLY' } || $opt{ 'RO' };
  $options .= "required='required' " if $opt{ 'REQUIRED' } || $opt{ 'REQ' };
  $options .= "onFocus=\"this.value=''\" " if $opt{ 'FOCUS_AUTO_CLEAR' };

  my $extra = $opt{ 'EXTRA' };
  $options .= " $extra ";

  $data = str_html_escape( $data );

  my $text;
  my $form_id = $self->{ 'FORM_ID' };

  $text .= "<textarea class='$class' name='$name' rows='$rows' cols='$cols' $options form='$form_id' $args>$data</textarea>";

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
  my $value =    $opt{ 'VALUE'   } || "";
  # FIXME: default data?
  my $size  =    $opt{ 'SIZE'    } || $opt{ 'LEN' } || $opt{ 'WIDTH' };
  my $maxl  =    $opt{ 'MAXLEN'  } || $opt{ 'MAX' };

  my $len   =    $opt{ 'LEN'     };
  my $args  =    $opt{ 'ARGS'    };
  my $hid   =    $opt{ 'HIDDEN'  };
  my $ret   =    $opt{ 'RET'     } || $opt{ 'RETURN'  }; # if return value should be mapped, works only with HIDDEN
  
  my $phi   =    $opt{ 'PH' } || $opt{ 'PHI' };

  my $clear =    $opt{ 'DISABLED' } ? undef : $opt{ 'CLEAR'   };
  
  my $datalist    = $opt{ 'DATALIST'              }; # array ref with 'key', 'value' and 'label' hash
  my $datalist_sk = $opt{ 'DATALIST_SELECTED_KEY' }; # key of the selected item

  __check_ident( $name, $id );

  $size = $maxl = $len if $len > 0;

  my %options;

  $options{ 'type'     } = $opt{ 'TYPE' };
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

  my $extra = $opt{ 'EXTRA' };
  $options{ 'extra' } = $extra if $extra;

  if( $hid and defined $ret )
    {
    # if input is hidden and return value mapping requested, VALUE is not used!
    $value = $self->create_uniq_id();
    $self->__ret_map_data( $name, $value => $ret );
    }

  my $name_hidden = $self->__ret_map_name( $name );  # FIXME: TODO: check if works?


  my $clear_tag;
  if( $clear )
    {
    my $reo = $self->get_reo();
    my $clear_hint_handler = html_hover_layer( $reo, VALUE => 'Clear field' );

    if( $clear =~ /^[a-z_\-0-9\/]+\.(png|jpg|jpeg|gif|svg)$/ )
      {
      $clear_tag = html_element( 'img', undef, class => 'icon-clear',  border => '0', onClick => "return set_value('$id', '')", src => $clear, extra => $clear_hint_handler );
      }
    else
      {
      my $s = $clear eq 1 ? '&times;' : $clear;
      $clear_tag = html_element( 'span', $s, class => 'icon-clear',  border => '0', onClick => "return set_value('$id', '')", extra => $clear_hint_handler );
      }
    }

  my $text;

  my $form_id = $self->{ 'FORM_ID' };
  
  if( $datalist )
    {
    my $on_change;
    # TODO: FIXME: FIXME: FIXME: FIXME: FIXME: cleanup this mess!
    $on_change = 'this.form.submit()'       if $opt{ 'SUBMIT_ON_CHANGE' } and $opt{ 'SUBMIT_ON_CHANGE' }  > 0;
    $on_change = $opt{ 'SUBMIT_ON_CHANGE' } if $opt{ 'SUBMIT_ON_CHANGE' } and $opt{ 'SUBMIT_ON_CHANGE' } == 0;
    
    my $empty_key   = $opt{ 'EMPTY_KEY' };
    my $input_id    = $self->create_uniq_id();
    my $datalist_id = $self->create_uniq_id();
    $class .= " search_list";

#    $text  .= "\n\n\n\n\n<input           id=$input_id     type=hidden    name='$name' value='$key'          form='$form_id'      >";
#    $text  .= "\n<input                             class='$class' value='$value' list=$datalist_id $options form='$form_id' $args data-input-id=$input_id data-empty-key='$empty_key' onchange='return reactor_datalist_change( this, $resub )'>$clear_tag";
#    $text  .= "\n<datalist id=$datalist_id>";

    my $datalist_key;
    my $datalist_label;

    my $datalist_text;
    for my $e ( @$datalist )
      {
      my $k = $e->{ 'KEY'   }; # html-visible key, which is returned
      my $v = $e->{ 'VALUE' }; # actual value, if key is given or generated, return map is used key => value
      my $l = $e->{ 'LABEL' }; # html-visible text label

      $k = $self->create_uniq_id() if $k eq '*';

      if( $k ne '' )
        {
        $self->__ret_map_data( $name, $k => $v );
        }
      else
        {
        $k = $v;
        }  

      ( $datalist_key, $datalist_label ) = ( $k, $l ) if $v eq $datalist_sk;
      $datalist_text .= html_element( 'option', undef, name => $l, value => $l, 'data-key' => $k );
      }
    
    $datalist_text = html_element( 'datalist', $datalist_text, id => $datalist_id );
    
    $text .= html_element( 'input', undef,           id => $input_id, type => 'hidden', class => $class, name => $name_hidden, value => $datalist_key,   form => $form_id );
    $text .= html_element( 'input', undef, %options, id => $input_id,                   class => $class,                       value => $datalist_label, form => $form_id, list => $datalist_id, 'data-input-id' => $input_id, 'data-empty-key' => $empty_key, onChange => "reactor_datalist_change( this, 0 ); $on_change; return" ) . $clear_tag;
    $text .= $datalist_text;
    }
  else
    {  
#    $text .= "<input class='$class' name='$name' value='$value' $options form='$form_id' $args>$clear_tag";
    $text .= html_element( 'input', undef, %options, class => $class, name => $name, value => $value, form => $form_id ) . $clear_tag;
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
  my $args  =    $opt{ 'ARGS'    };

  __check_ident( $name, $id );

  my $options;

  $options .= "multiple " if $opt{ 'MULTI' };
  $options .= "id='$id' " if $id ne '';

  my $text;

  my $form_id = $self->{ 'FORM_ID' };

  $text .= "<input class='$class' name='$name' type=file $options form='$form_id' $args>";

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
  my $class   =    $opt{ 'CLASS'   } || 'button';
  my $value   =    $opt{ 'VALUE'   };
  my $confirm =    $opt{ 'CONFIRM' };
  my $args    =    $opt{ 'ARGS'    };

  __check_ident( $name, $id );

  my $options;
  
  if( $opt{ 'DISABLED' } )
    {
    $options .= "disabled='disabled' " ;
    $class   .= " disabled-button";
    }

  my $text;

  $name =~ s/^button://i;

  my $form_id = $self->{ 'FORM_ID' };
#  $text .= "<input class='$class' id='$id' type='submit' name='button:$name' value='$value' onDblClick='return false;' form='$form_id' $options $args>";
  #$text .= "<button class='$class' id='$id' type='submit' name='button:$name' value='1' onDblClick='return false;' form='$form_id' $options $args>$value</button>";

  if( $confirm )
    {
    $confirm = "[~Are you sure?]" if $confirm == 1;
    $confirm = qq[return confirm("$confirm");];
    }
  
  $text .= html_element( 'button', $value, form => $form_id, class => $class, id => $id, name => "button:$name", onDblClick => 'return false;', onClick => $confirm, extra => "$options $args" );

  $text .= "\n";
  return $text;
}

sub image_button
{
  my $self = shift;

  my %opt = @_;

  my $name  = uc $opt{ 'NAME'  };
  my $id    =    $opt{ 'ID'    };
  my $class =    $opt{ 'CLASS' } || 'image_button';
  my $src   =    $opt{ 'SRC'   } || $opt{ 'IMG'  };
  my $args  =    $opt{ 'ARGS'  };
  my $extra =    $opt{ 'EXTRA' };

  my $options;

  # FIXME: make this for all entries! common func?
  for my $o ( qw( HEIGHT WIDTH ONMOUSEOVER ) )
    {
    my $e = $opt{ $o };
    # FIXME: escape? $e
    $options .= "$o='$e' " if $e ne '';
    }

  __check_ident( $name, $id );

  my $text;

  my $form_id = $self->{ 'FORM_ID' };
  $name =~ s/^button://i;
  $text .= "<input class='$class' id='$id' type='image' name='button:$name' src='$src' border=0 $options onDblClick='return false;' $args form='$form_id' $extra>";

  $text .= "\n";
  return $text;
}

sub image_button_default
{
  my $self = shift;

  my %opt = @_;

  my $user_agent = $self->get_reo()->get_user_session_agent();

  my $default_class = 'hidden';
  $default_class = 'hidden2' if $user_agent =~ /MSIE|Safari/;

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
