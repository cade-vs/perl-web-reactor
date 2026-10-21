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
##
## HTML Utils
##
## All checks and escaping are done according to HTML Living standard from
## 5 September 2022, chapter notes are given in the comments
## https://html.spec.whatwg.org/multipage/
##
##############################################################################
package Web::Reactor::HTML::Utils;
use strict;
use Exporter;
our @ISA = qw( Exporter );
# cc20261017-reo-optional html_uniq_id added to the exports
our @EXPORT = qw(
                html_element
                html_attrs
                html_element_e

                html_ftree

                html_hover_layer
                html_popup_layer
                html_popup_layer_attrs

                html_alink

                html_tabs_table

                html_debug

                html_check_tag_name
                html_check_tag_name_boom

                html_check_attr_name
                html_check_attr_name_boom

                html_check_name
                html_check_name_boom

                html_check_ident
                html_check_ident_boom

                html_check_button_name
                html_check_button_name_boom

                html_js_str
                html_confirm_js
                html_submit_on_change_js

                html_attrs_filter
                html_args_hide
                html_args_style

                html_uniq_id

                );
use Exception::Sink;
use Data::Dumper;
use Data::Tools;
use Crypt::PRNG;
# Web::Reactor::HTML::Tab and ::Layout are loaded when needed, both use Utils # cc20261017-2

##############################################################################


=pod

html_element( $tag, $html, attr1 => value1, attr2 => value2, ... )

returns the html element $tag with the given attributes and content:

  print html_element( 'div', 'text', class => 'box', id => 'x1' );
  # <div class='box' id='x1'>text</div>
  print html_element( 'input', undef, type => 'checkbox', checked => undef );
  # <input checked type='checkbox'/>

  - $html is raw html, it is not escaped (see html_element_e())
  - void elements (input, img, br, hr, meta, link, ...) are written as
    <tag .../> and cannot have content, it booms if $html is not empty
  - all other elements are always closed, an undef $html gives <tag ...></tag>
  - the tag and the attribute names are lower-cased and checked, an
    invalid name booms
  - attribute values are escaped, an undef value gives a bare attribute
    (checked, disabled, ...)
  - attributes are written sorted by name, the same call gives the same
    html; a later attribute replaces an earlier one with the same name, also
    when they differ only in case (onClick, onclick)

=cut

# void elements have no content and no end tag, $13.1.2
my %HTML_VOID_ELEMENTS = map { $_ => 1 } qw( area base br col embed hr img input link meta source track wbr );

sub html_element
{
  my $tag = shift;
  my $txt = shift;

  boom "expected even number of attribute arguments for tag [$tag]" if @_ % 2;

  html_check_tag_name_boom( $tag );
  $tag = lc $tag;

  my $html;

  # the names are checked here too, so the message tells the tag # cc20261017-2
  for( my $i = 0; $i < @_; $i += 2 )
    {
    my $k = lc $_[ $i ];
    html_check_attr_name_boom( $k, "invalid attribute name [$k] for tag [$tag]" );
    }

  $html .= "<$tag" . html_attrs( @_ ); # cc20261017-1 one attribute writer

  if( $HTML_VOID_ELEMENTS{ $tag } )
    {
    boom "void element [$tag] cannot have content" if $txt ne '';
    $html .= "/>";
    }
  else
    {
    # a non-void element is always closed, browsers ignore "/>" on them and
    # the following markup would end up inside
    $html .= ">" . ( $txt // '' ) . "</$tag>";
    }

#use Data::Dumper;
#print STDERR Dumper( "\n"x10, \@_, $tag, $txt, $html, "\n"x100 );

  return $html;
}

=pod

html_attrs( attr1 => value1, attr2 => value2, ... )

returns the attributes as html text, " attr1='value1' attr2='value2'" (with a
leading space, empty for no attributes), for hand-written tags. the same
rules as html_element(): names lower-cased and checked, values escaped, an
undef value gives a bare attribute, sorted, a later attribute replaces an
earlier one with the same name.

  my $h = html_attrs( class => 'tab', onclick => $js );
  print "<span$h>tab</span>";

=cut

sub html_attrs # cc20261017-1
{
  boom "expected even number of attribute arguments" if @_ % 2;

  # names are lower-cased in argument order, so a later attribute replaces an
  # earlier one also when they differ only in case (onClick, onclick)
  my %attr;
  while( @_ )
    {
    my $k = lc shift;
    $attr{ $k } = shift;
    }

  my $text = '';
  for my $k ( sort keys %attr ) # sorted, the same call gives the same html
    {
    html_check_attr_name_boom( $k );
    my $v = $attr{ $k };
    $text .= " $k";
    $text .= "='" . str_html_escape_attr( $v ) . "'" if defined $v;
    }

  return $text;
}

=pod

html_element_e( $tag, $text, attr1 => value1, ... )

same as html_element() but $text is plain text, it is escaped:

  print html_element_e( 'b', '1 < 2' ); # <b>1 &#60; 2</b>

=cut

sub html_element_e
{
  my $tag = shift;
  my $txt = shift;

  $txt = str_html_escape_text( $txt ) if defined $txt; # element content needs only & < > escaped

  return html_element( $tag, $txt, @_ );
}

##############################################################################

=pod

html_ftree( $data, %opt )

flat tree, represented by single table with rows, a click on a branch row
shows or hides its sub rows (ftree_click() in js/reactor.js)

DEMO:

  my $tree = [
          'opa',
          'tralala',
          'heyo',
          'yoyo',
          'didi',
          {
          LABEL => 'opa',
          DATA  => [
                     'tralala',
                     'heyo',
                     {
                     LABEL => 'sesssil',
                     DATA  => [
                              'tralala',
                              'heyo',
                              'yoyo',
                              'didi',
                              ],
                     },
                     'yoyo',
                     'didi',
                     ],
          },
          'heyo',
          'yoyo',
          ];

  print html_ftree( $tree, 'ARGS' => 'cellpadding=10 width=100% border=0' );

options:

  ARGS     -- raw table attributes
  CLASS    -- table class, used when there are no ARGS
  ARGS_TR  -- raw attributes for the rows without their own ARGS or CLASS, a
              style in it gets display: none merged for nested rows
  ARGS_TD  -- raw attributes for the cells

a row is a label (scalar) or a hash ref:

  LABEL    -- row label
  DATA     -- array ref of sub rows, the row becomes a branch
  ARGS     -- raw row attributes, a style in it gets display: none merged
              for a nested row
  CLASS    -- row class, used when there are no ARGS

=cut

# ftree ids: the per-process scope of html_uniq_id() (no "." in it, the rows
# use "." for the tree levels) and a counter. independent of reactor objects
# on purpose # cc20261017-reo-optional
my $ftree_item_id;
sub html_ftree
{
  my $data = shift;
  my %opt  = @_;

  my $t_args = $opt{ 'ARGS' };
  $t_args ||= "class='" . str_html_escape_attr( $opt{ 'CLASS' } ) . "'" if $opt{ 'CLASS' };

  my $ftree_scope = __uniq_scope(); # cc20261017-reo-optional
  $ftree_item_id++;

  my $ftree_table_id = "FTREE_TABLE_${ftree_scope}_$ftree_item_id";

  my $html;

  $html .= "\n";
  $html .= "<table id='$ftree_table_id' $t_args>";

  $html .= __html_ftree_branch( $data, $ftree_table_id, $ftree_table_id . '.', 0, \%opt );

  $html .= "</table>";
  $html .= "\n";

  return $html;
}

sub __html_ftree_branch
{
  my $data           = shift;
  my $ftree_table_id = shift;
  my $branch_id      = shift;
  my $level          = shift;
  my $opt            = shift;

  require Web::Reactor::HTML::Layout; # cc20261017-2 Layout uses Utils, loaded once per branch, not per row

  my $html;

  $html .= "\n";

  for my $row ( @$data )
    {
    my $label;
    my $sub_data; # sub rows of a branch

    my $r_args; # row  args
    my $c_args = $opt->{ 'ARGS_TD' }; # cell args

    if( ref( $row ) eq 'HASH' )
      {
      $label    = $row->{ 'LABEL' };
      $sub_data = $row->{ 'DATA'  };

      $r_args   = $row->{ 'ARGS' };
      $r_args ||= "class='" . str_html_escape_attr( $row->{ 'CLASS' } ) . "'" if $row->{ 'CLASS' };
      }
    else
      {
      $label = $row;
      }

    $r_args ||= $opt->{ 'ARGS_TR' };

    $ftree_item_id++;

    my $row_id = $branch_id . $ftree_item_id . '.';

    # $label = "($row_id) $label"; # DEBUG

    # nested rows start hidden: into a style already in the row args (quoted
    # or not), so the row has only one style attribute
    $r_args = html_args_hide( $r_args ) if $level > 0;
    # the indent is a share of the row width: 6% per level, up to 61% (level
    # 10), deeper levels keep it, the label always has room and a width over
    # 100% cannot happen
    my $pad = $level * 6 + 1;
    $pad = 61 if $pad > 61;
    my $cell = Web::Reactor::HTML::Layout::html_layout_2lr( '&nbsp;', $label, "$pad=<" );

    if( ref( $sub_data ) eq 'ARRAY' )
      {
      my $open_code = qq{ onclick='ftree_click( "$ftree_table_id", "$row_id" )' };
      $html .= "<tr id='$row_id' $open_code $r_args><td $c_args>$cell</td></tr>";
      $html .= __html_ftree_branch( $sub_data, $ftree_table_id, $row_id, $level + 1, $opt );
      }
    else
      {
      $html .= "<tr id='$row_id' $r_args><td $c_args>$cell</td></tr>";
      }

    $html .= "\n";
    }

  return $html;
}

##############################################################################

=pod

html_uniq_id()

returns a new id, unique in all processes, without a reactor object:
"scope.N", the scope is the pid, the time of the first call in the process
and a random part (also against a pid reused within a second), N counts the
ids of the process. letters, digits, "_" and ".", so it is a valid
html_check_name() too. with a reactor object use its create_uniq_id().

=cut

my $UNIQ_PID; # cc20261017-reo-optional
my $UNIQ_SCOPE;
my $UNIQ_COUNTER;

# the per-process scope of html_uniq_id() and html_ftree(), a new one in a
# forked child
sub __uniq_scope
{
  if( ! $UNIQ_PID or $UNIQ_PID != $$ )
    {
    $UNIQ_PID     = $$;
    $UNIQ_SCOPE   = join '_', $$, time(), Crypt::PRNG::random_string_from( 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789', 8 );
    $UNIQ_COUNTER = 0;
    }
  return $UNIQ_SCOPE;
}

sub html_uniq_id
{
  my $scope = __uniq_scope();
  return $scope . '.' . ++$UNIQ_COUNTER;
}

##############################################################################

# booms unless $reo is a reactor object (a Web::Reactor:: class) which can $method
# args:
#       reo    -- the reactor object to check
#       func   -- caller name for the message
#       method -- method the caller needs
#       what   -- the needed object, for the message
sub __check_reo
{
  my ( $reo, $func, $method, $what ) = @_;

  boom "missing REO reactor object" if ref( $reo ) !~ /^Web::Reactor(::|\z)/;
  boom "$func() needs $what, got [" . ref( $reo ) . "]" unless $reo->can( $method );

  return 1;
}

##############################################################################

=pod

html_hover_layer( $reo, VALUE => $html, %opt ) or html_hover_layer( $reo, $html )

hover (tooltip) layer, shown next to the mouse after DELAY while it stays
over an element. returns the javascript for the onmouseover attribute of
the element (the handle); the layer itself goes into the KIT_HTML hold,
pages show it with <$$kit_html>. in list context returns ( handle, layer
html ) and nothing goes into the hold.

the handle is an attribute VALUE, not an attribute: it goes into
onmouseover='...' (it has double quotes only) or to html_element() as the
onmouseover value. html_popup_layer() returns whole attributes instead,
it needs two of them.

  my $h = html_hover_layer( $reo, VALUE => 'more info', DELAY => 500 );
  print "<span onmouseover='$h'>?</span>";
  print html_element( 'span', '?', onmouseover => $h );

options:

  VALUE  -- layer html (the only argument in the short form)
  CLASS  -- layer class (default "hover-layer")
  DELAY  -- milliseconds before the layer shows (default 250, 0 shows at once)

$reo must be a Web::Reactor::Reflex or Web::Reactor object.

=cut

# returns the value for html tag attribute "onmouseover" (the layer goes into
# the KIT_HTML hold), in list context ( handle, layer html ) without the hold
sub html_hover_layer
{
  my $reo = shift;
  my %opt = @_ == 1 ? ( VALUE => $_[0] ) : @_; # short form: the layer html only

  __check_reo( $reo, 'html_hover_layer', 'html_hold_kit_add', 'a Web::Reactor::Reflex or Web::Reactor object' );

  my $value = $opt{ 'VALUE' };
  my $class = $opt{ 'CLASS' } || 'hover-layer';
  my $delay = int( $opt{ 'DELAY' } // 250 ); # 0 shows the layer at once, a number for the javascript

  my $hover_layer_id = 'R_HOVER_LAYER_' . $reo->create_uniq_id();

  my $handle = qq{ reactor_hover_show_delay( this, "$hover_layer_id", $delay, event ) };
  my $html   = html_element( 'div', $value, class => $class, id => $hover_layer_id );

  return ( $handle, $html ) if wantarray; # list context does not use the KIT_HTML hold

  $reo->html_hold_kit_add( 'KIT_HTML', $html ); # pages show it with <$$kit_html>
  return $handle;
}

##############################################################################

=pod

html_popup_layer( $reo, VALUE => $html, %opt ) or html_popup_layer( $reo, $html )

popup layer, opened by a click or by the context menu on an element and
kept open while the mouse is over the element or the layer. returns the
attributes for the element (the handle: onClick or onContextMenu and
data-popup-layer-id); the layer itself goes into the KIT_HTML hold, pages
show it with <$$kit_html>. in list context returns ( handle, layer html )
and nothing goes into the hold.

the handle is whole attributes, put as they are inside a hand-written tag;
it cannot be given to html_element(). html_hover_layer() returns a single
attribute value instead.

  my $h = html_popup_layer( $reo, VALUE => $menu_html, SINGLE => 1 );
  print "<span $h>menu</span>";

html_popup_layer_attrs() takes the same arguments and returns the handle as
attribute name/value pairs for html_element() or the ATTRS option of
Web::Reactor::HTML::Form, the layer always goes into the KIT_HTML hold:

  my %pa = html_popup_layer_attrs( $reo, VALUE => $menu_html, TYPE => 'CONTEXT' );
  print html_element( 'span', 'menu', %pa );
  print $form->input( NAME => 'date', ATTRS => \%pa );

options:

  VALUE    -- layer html (the only argument in the short form)
  CLASS    -- layer class (default "popup-layer")
  TYPE     -- CLICK (default) opens on click, CONTEXT opens on the context
              menu after TIMEOUT
  TIMEOUT  -- milliseconds the layer stays open after the mouse leaves, and
              the open delay for CONTEXT (default 200)
  SINGLE   -- only one SINGLE layer is open at a time, opening another one
              closes it

$reo must be a Web::Reactor::Reflex or Web::Reactor object.

=cut

sub html_popup_layer
{
  my ( $reo, $event, $js, $layer_id, $html ) = __popup_layer( 'html_popup_layer', @_ );

  my $handle = qq( $event="$js" data-popup-layer-id="$layer_id" );

  return ( $handle, $html ) if wantarray; # list context does not use the KIT_HTML hold

  $reo->html_hold_kit_add( 'KIT_HTML', $html ); # pages show it with <$$kit_html>
  return $handle;
}

sub html_popup_layer_attrs
{
  my ( $reo, $event, $js, $layer_id, $html ) = __popup_layer( 'html_popup_layer_attrs', @_ );

  $reo->html_hold_kit_add( 'KIT_HTML', $html ); # pages show it with <$$kit_html>
  return ( $event => $js, 'data-popup-layer-id' => $layer_id );
}

# common part of html_popup_layer() and html_popup_layer_attrs()
# returns:
#       ( reo, event attribute name, its javascript, layer id, layer html )
sub __popup_layer
{
  my $func = shift;
  my $reo  = shift;
  my %opt  = @_ == 1 ? ( VALUE => $_[0] ) : @_; # short form: the layer html only

  __check_reo( $reo, $func, 'html_hold_kit_add', 'a Web::Reactor::Reflex or Web::Reactor object' );

  my $value   =    $opt{ 'VALUE'   };
  my $class   =    $opt{ 'CLASS'   } || 'popup-layer';
  my $timeout = int( $opt{ 'TIMEOUT' } ); # a number for the javascript
  my $type    = uc $opt{ 'TYPE'    } || 'CLICK';

  boom "invalid popup TYPE [$type], expected CLICK or CONTEXT" unless $type =~ /^(CLICK|CONTEXT)\z/;
  my $single  = $opt{ 'SINGLE'  } ? 1 : 0;

  $timeout = 200 unless $timeout > 0;

  my ( $event, $js );
  if( $type eq 'CONTEXT' )
    {
    ( $event, $js ) = ( 'onContextMenu', "return reactor_popup_mouse_over( this, { timeout: $timeout, single: $single } )" );
    }
  else # ( $type eq 'CLICK' )
    {
    ( $event, $js ) = ( 'onClick', "return reactor_popup_mouse_over( this, { click_open: 1, timeout: $timeout, single: $single } )" );
    }

  my $popup_layer_id = 'R_POPUP_LAYER_' . $reo->create_uniq_id();

  my $html = html_element( 'div', $value, class => $class, id => $popup_layer_id ); # escapes the class

  return ( $reo, $event, $js, $popup_layer_id, $html );
}

##############################################################################

=pod

html_alink( $reo, $type, $html, \%opt, @args )

<a> link to a reactor page or action. the href is made by args_type() of
the reactor: $type is one of new, new_fr, here, back, back_back or none, @args are the
link parameters (see Web::Reactor args*()). $html is the link content.

  print html_alink( $reo, 'new', 'users', { CLASS => 'btn' }, _PN => 'users' );

options (hash reference):

  ID                      -- element id
  CLASS                   -- element class
  HINT                    -- hover layer text, see html_hover_layer()
  CONFIRM                 -- confirm() question before the link is followed,
                             1 asks the default question, see html_confirm_js()
  DISABLED                -- the link does nothing: it has no href (no LINK
                             session entry is made, middle-click or "open in
                             new tab" have nothing to follow), gets class
                             "disabled-button" and no HINT or CONFIRM
  DISABLE_ON_CLICK        -- seconds the link is disabled after a click
  DISABLE_ON_CLICK_CLASS  -- class of the link while it is disabled, swapped
                             with CLASS

only one onclick is made: CONFIRM, else DISABLE_ON_CLICK, none if DISABLED.
$reo must be a Web::Reactor object (args_type()).

=cut

sub html_alink
{
  my $reo   =    shift;
  my $type  =    shift; # args_type() lower-cases it
  my $value =    shift;
  my $opts  =    shift; # hashref with alink options
  my @args  = @_;

  __check_reo( $reo, 'html_alink', 'args_type', 'a Web::Reactor object (args_type)' );

  my %attr; # html_element() escapes all attribute values

  my $tag_id = $opts->{ 'ID' };

  my $class = $opts->{ 'CLASS' };
  my $hint = $opts->{ 'HINT' };

  my $confirm = $opts->{ 'CONFIRM' };
  my $disable_on_click = int( $opts->{ 'DISABLE_ON_CLICK' } );

  if( $opts->{ 'DISABLED' } )
    {
    $class = join ' ', grep { $_ ne '' } ( $class, 'disabled-button' );
    $hint = undef; # remove button hints for disabled buttons
    }

  $attr{ 'id'    } = $tag_id if $tag_id ne '';
  $attr{ 'class' } = $class  if $class  ne '';
  $attr{ 'onmouseover' } = html_hover_layer( $reo, VALUE => $hint, DELAY => 1000 ) if $hint;

  # one onclick only: confirm, else disable on click. a disabled link has
  # none, it has no href, so there is nothing to stop
  if( ! $opts->{ 'DISABLED' } and $confirm )
    {
    $attr{ 'onclick' } = html_confirm_js( $confirm );
    }
  elsif( ! $opts->{ 'DISABLED' } and $disable_on_click > 0 )
    {
    $attr{ 'data-class-on'  } = $class;
    $attr{ 'data-class-off' } = $opts->{ 'DISABLE_ON_CLICK_CLASS' };
    $attr{ 'onclick'        } = "return reactor_element_disable_on_click( this, $disable_on_click );";
    }

  # a disabled link gets no href, so there is nothing to follow
  $attr{ 'href' } = '?_=' . $reo->args_type( $type, @args ) unless $opts->{ 'DISABLED' };

  return html_element( 'a', $value, %attr );
}

##############################################################################

=pod

html_tabs_table( $reo, \@tabs, %opt )

table with tabs, one tab is visible at a time, see Web::Reactor::HTML::Tab.

$reo may be undef: then the page must load js/reactor.js itself and the tab
controller is added to the end of the returned html (with a reactor it goes
into the KIT_HTML hold, see Web::Reactor::HTML::Tab).

@tabs is a list of hash refs with this content:

    LABEL          -- label text for this tab handle
    LABEL_TD_ARGS  -- further optional arguments for the label TD. a class
                      in it is kept when the tab is switched, an id in it
                      becomes the tab handle id (HTML::Tab HANDLE_ID, safe
                      characters only), an onclick in it booms (the label TD
                      onclick switches the tab)
    TEXT           -- text to show when tab handle clicked
    TEXT_TD_ARGS   -- TD element args, same as above
    ON             -- if true, this tab will be initially visible, only one
                      entry may be ON
    TAB_ID         -- html id for this tab

%opt has the following items:

    LABELS_TABLE_ARGS -- args for the table holding the labels, horizontal only

    LABEL_CLASS_ON    -- active TD class for tab handle labels
    LABEL_CLASS_OFF   -- inactive TD class for tab handle labels

    ARGS              -- args for containing TABLE element
    VERTICAL          -- if true, tabs will be vertical
    VERT_LABEL_TD_ARGS -- args for the TD holding the labels, vertical only
    VERT_TEXT_TD_ARGS  -- args for the TD holding the tabs, vertical only

    ACTIVE_TAB_FORM_FEEDBACK_ID -- html INPUT element to hold active tab id,
                                   passed to HTML::Tab, not implemented yet

example:

  my @tabs;

  for my $z ( 1 .. 5 )
    {
    push @tabs, {
                  LABEL         => "TAB $z",
                  TEXT          => "$z " x 128,
                  LABEL_TD_ARGS => "class=tab-label style='cursor: pointer;'",
                  TEXT_TD_ARGS  => "class=tab-text",
                };
    }

  $html = html_tabs_table( $reo, \@tabs, ARGS => "width=70% border=2", VERTICAL => 1 );

=cut

sub html_tabs_table
{
  my $reo = shift;
  my $ar  = shift;
  my %opt = @_;

  my $vert = $opt{ 'VERTICAL' };

  my @label_td;
  my @text_td;

  my $cnt = @$ar;

  my $class_on  = $opt{ 'LABEL_CLASS_ON' };
  my $class_off = $opt{ 'LABEL_CLASS_OFF' };

  require Web::Reactor::HTML::Tab; # not at load time, Tab uses Utils
  my $tab = Web::Reactor::HTML::Tab->new( $reo, # cc20261017-1
                                   CLASS_ON    => $class_on,
                                   CLASS_OFF   => $class_off,
                                   ACTIVE_TAB_FORM_FEEDBACK_ID => $opt{ 'ACTIVE_TAB_FORM_FEEDBACK_ID' },
                                 );

  for my $e ( @$ar )
    {
    my $label      = $e->{ 'LABEL'         };
    my $label_args = $e->{ 'LABEL_TD_ARGS' };
    my $text       = $e->{ 'TEXT'          };
    my $text_args  = $e->{ 'TEXT_TD_ARGS'  };
    my $on         = $e->{ 'ON'            };
    my $tab_id     = $e->{ 'TAB_ID'        };

    if( ! $vert and $label_args !~ /width=/i )
      {
      my $w = int( 100 / $cnt );
      $label_args .= " width=$w%";
      }

    # a class in LABEL_TD_ARGS goes to the handle classes, so the label TD gets
    # only one class attribute and the class is kept when the tab is switched
    my $handle_class;
    $handle_class = $2 if $label_args =~ s/(?<![\w-])class\s*=\s*(['"])(.*?)\1//i or $label_args =~ s/(?<![\w-])class\s*=\s*()([^\s>'"]+)//i;
    # the same for an id, it becomes the handle id (checked by HTML::Tab). the
    # handle has its own onclick, a second one would be dropped by the browser
    my $handle_id;
    $handle_id = $2 if $label_args =~ s/(?<![\w-])id\s*=\s*(['"])(.*?)\1//i or $label_args =~ s/(?<![\w-])id\s*=\s*()([^\s>'"]+)//i;
    boom "LABEL_TD_ARGS cannot have onclick, the label TD onclick switches the tab, got [$label_args]" if $label_args =~ /(?<![\w-])onclick\s*=/i;

    my ( $tab_handle, $tab_html ) = $tab->add( "<td $text_args>$text</td>", TYPE => 'TR', ON => $on, TAB_ID => $tab_id, HANDLE_CLASS => $handle_class, HANDLE_ID => $handle_id );

    push @label_td, "<td $label_args $tab_handle>$label</td>";
    push @text_td,  $tab_html;
    }
  # without a reactor finish() returns the tab controller, it goes after the table
  my $controller = $tab->finish();

  my $args  = $opt{ 'ARGS' };

  my $text;

  $text .= "<table $args>\n";
  if( $vert )
    {
    my $label_args  = $opt{ 'VERT_LABEL_TD_ARGS' };
    my $text_args   = $opt{ 'VERT_TEXT_TD_ARGS' };

    $label_args .= " width=50%" if $label_args !~ /width=/i;

    $text .= "<tr>";
    $text .= "<td $label_args><table width=100%>";
    $text .= "<tr>" . join( "</tr><tr>", @label_td ) . "</tr>";
    $text .= "</table></td>";

    $text .= "<td $text_args><table width=100%>";
    $text .= join( '', @text_td );
    $text .= "</table></td>";

    $text .= "</tr>";
    }
  else
    {
    my $labels_table_args = $opt{ 'LABELS_TABLE_ARGS' };
    $labels_table_args .= " width=100%" if $labels_table_args !~ /width=/i;
    $text .= "<tr><td><table $labels_table_args><tr>" . join( '', @label_td ) . "</tr></table></td></tr>";
    $text .= join( '', @text_td );
    }
  $text .= "</table>\n";
  $text .= $controller if defined $controller;


  return $text;
}

##############################################################################

=pod

html_debug( @data )

returns a Data::Dumper dump of @data as an html block (escaped, inside
<pre>), for debug output in pages:

  $text .= html_debug( $row_data, \%opt );

=cut

sub html_debug
{
  # TODO: pass colors for background, border...
  # escaped, dumped data cannot close the block and turn into live html
  return "<div style='text-align: left; border: dotted 1px #A00'><pre>" . str_html_escape_text( Dumper( @_ ) ) . "</pre></div>";
}

##############################################################################

=pod

html_check_tag_name( $name ), html_check_attr_name( $name )

return true if $name is a valid html tag or attribute name. tag names start
with a letter, followed by letters and digits, custom element names
(my-widget) have at least one "-" and may also have "." and "_". attribute
names are letters, digits, "_", ":" and "-" (stricter than the standard).

html_check_tag_name_boom( $name, $msg ), html_check_attr_name_boom( $name, $msg )

boom with $msg (or a default message) if $name is not valid.

=cut

sub html_check_tag_name
{
  # $13.1.2.1, starts with a letter; $4.13.3 custom elements have a "-"
  return $_[0] =~ /^[a-zA-Z](?:[a-zA-Z0-9]*|[a-zA-Z0-9._]*-[a-zA-Z0-9._-]*)\z/;
}

sub html_check_tag_name_boom
{
  boom( $_[1] || "invalid tag name [$_[0]]" ) unless html_check_tag_name( $_[0] );
}

sub html_check_attr_name
{
  return $_[0] =~ /^[a-zA-Z_0-9\:\-]+\z/; # $13.1.2.3 but extra strict
}

sub html_check_attr_name_boom
{
  boom( $_[1] || "invalid attribute name [$_[0]]" ) unless html_check_attr_name( $_[0] );
}

##############################################################################

=pod

html_check_name( $name ), html_check_ident( $ident )

return true if $name is a valid element (form input) name: letters, digits,
"_", ":" and ".", not empty; or $ident a valid identifier (html id, etc.):
the same and "-", optional, empty or undef is valid.

html_check_name_boom( $name, $msg ), html_check_ident_boom( $ident, $msg )

boom with $msg (or a default message) if the value is not valid.

=cut

sub html_check_name
{
  return $_[0] =~ /^[a-zA-Z0-9_:.]+\z/;
}

sub html_check_name_boom
{
  boom( $_[1] || "invalid or empty NAME [$_[0]]" ) unless html_check_name( $_[0] );
}

sub html_check_ident
{
  return $_[0] =~ /^[a-zA-Z0-9_:.\-]*\z/;
}

sub html_check_ident_boom
{
  boom( $_[1] || "invalid IDENTIFIER [$_[0]]" ) unless html_check_ident( $_[0] );
}

##############################################################################

=pod

html_check_button_name( $name ), html_check_button_name_boom( $name, $msg )

returns true if $name is a button name Web::Reactor can read back (see
Web::Reactor::Reflex get_user_input_button()): "NAME" or "NAME:ID", NAME is
letters, digits and "_", ID is letters, digits, "_", ":" and "." (a
create_uniq_id() id fits). it must not end with ".X" or ".Y", that is the
click position suffix of image buttons. the _boom variant booms with $msg
(or a default message) if $name is not valid.

=cut

sub html_check_button_name
{
  return $_[0] =~ /^[a-zA-Z0-9_]+(:[a-zA-Z0-9_:.]+)?\z/ && $_[0] !~ /\.[XY]\z/i;
}

sub html_check_button_name_boom
{
  boom( $_[1] || "invalid button NAME [$_[0]], expected NAME or NAME:ID" ) unless html_check_button_name( $_[0] );
}

##############################################################################

=pod

html_js_str( $text )

returns $text as a double-quoted javascript string literal for inline event
handlers: backslashes and quotes are escaped, any line ending (CR, LF, CRLF)
becomes \n. the handler still goes through html_element() (or another
attribute escape), which escapes it for the html attribute.

  html_element( 'span', 'x', onclick => 'alert(' . html_js_str( $msg ) . ')' );

html_confirm_js( $confirm )

returns the onclick handler for a CONFIRM option: "return confirm(...);",
undef if $confirm is false. 1 asks the default question "[~Are you sure?]".

html_submit_on_change_js( $submit_on_change )

returns the onchange handler for a SUBMIT_ON_CHANGE option: a positive
number submits the form, any other string is javascript code to run, false
gives undef (no handler).

=cut

sub html_js_str
{
  my $s = shift;

  $s =~ s/([\\"'])/\\$1/g;
  $s =~ s/\r\n?|\n/\\n/g; # any line ending, a raw one breaks the string

  return qq["$s"];
}

sub html_confirm_js
{
  my $confirm = shift;

  return undef unless $confirm;
  $confirm = "[~Are you sure?]" if $confirm eq '1';
  return "return confirm(" . html_js_str( $confirm ) . ");";
}

sub html_submit_on_change_js
{
  my $soc = shift;

  return undef unless $soc;
  return 'this.form.submit()' if $soc =~ /^\d+\z/;
  return $soc;
}

##############################################################################

=pod

html_attrs_filter( $attrs, @drop )

returns the attribute name/value pairs of the $attrs hash reference (an ATTRS
option, extra attributes for an element) with lower-cased names, without
the names in @drop (attributes the caller sets itself and which must not
be replaced). empty list for undef $attrs, booms if it is not a hash
reference. the values are escaped later by html_element():

  html_element( 'input', undef, type => 'file', name => $n,
                html_attrs_filter( $opt{ 'ATTRS' }, qw( type name ) ) );

=cut

sub html_attrs_filter
{
  my $attrs = shift;
  my @drop  = @_;

  return () unless $attrs;
  boom "ATTRS must be a HASH reference" unless ref( $attrs ) eq 'HASH';

  my %ah = %$attrs;
  hash_lc_ipl( \%ah );
  delete @ah{ map { lc } @drop };

  return %ah;
}

##############################################################################

=pod

html_args_style( $args, $css )

returns the raw html attributes string $args with the css declarations $css
(e.g. "width: 20%;") added: merged into a style already in $args (quoted or
not), so the element has only one style attribute (a browser keeps the first
and drops the rest), or appended as a new style attribute. $css must not
contain quotes, it booms.

html_args_hide( $args )

the same with "display: none;", for a hidden element.

  $args = html_args_hide( $args ) unless $visible;
  $html = "<tr $args>...</tr>";

=cut

sub html_args_style # cc20261017-2
{
  my $args = shift;
  my $css  = shift;

  boom "css for a raw style attribute cannot have quotes [$css]" if $css =~ /['"]/;
  $css =~ s/\s*;?\s*\z/;/; # one ";" at the end

  $args =~ s/(?<![\w-])style\s*=\s*(['"])/style=$1$css /i
    or $args =~ s/(?<![\w-])style\s*=\s*([^\s'">]+)/style='$css $1'/i
    or $args .= " style='$css'";

  return $args;
}

sub html_args_hide
{
  return html_args_style( shift(), 'display: none;' ); # cc20261017-2
}

##############################################################################
1;
##############################################################################
###EOF########################################################################
