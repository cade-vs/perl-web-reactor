#!/usr/bin/perl
##############################################################################
##
##  Web::Reactor application machinery
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
##
##  tests for htdocs/reactor.js, run with JavaScript::QuickJS against a small
##  fake DOM (elements with style, dataset, classList, children, events, a
##  session storage and a manual timer queue), skipped without the engine
##
##  usage:
##
##    cd t && perl test_reactor_js.pl    -- run, TAP output on stdout
##    perl t/test_reactor_js.pl          -- same, from the distribution root
##
##  the assertions are written in javascript and call back into Test::More
##  through t_ok( cond, name ) and t_is( got, expected, name )
##
##############################################################################
use strict;
use Test::More;
use File::Basename qw( dirname );

eval { require JavaScript::QuickJS; 1 } or plan skip_all => 'JavaScript::QuickJS is not installed';

my $js_file = dirname( __FILE__ ) . '/../htdocs/reactor.js';
open( my $fh, '<', $js_file ) or die "cannot read [$js_file]: $!\n";
my $reactor_js = do { local $/; <$fh> };
close( $fh );

my $js = JavaScript::QuickJS->new();
$js->set_globals(
                t_ok => sub { ok( $_[0], $_[1] ); () },
                t_is => sub { is( $_[0], $_[1], $_[2] ); () },
                );

##############################################################################
##
##  the fake DOM
##

my $FAKE_DOM = <<'JS';

// timers run only when the test asks, in delay order
var __timers = [];
var __timer_id = 0;
function setTimeout( fn, ms ) { __timers.push( { id: ++__timer_id, fn: fn, ms: ms } ); return __timer_id; }
function clearTimeout( id )   { __timers = __timers.filter( function( t ) { return t.id != id; } ); }
function run_timers()
{
  var t = __timers;
  __timers = [];
  t.sort( function( a, b ) { return a.ms - b.ms; } );
  for( var i = 0; i < t.length; i++ ) t[i].fn();
  return t.length;
}
function pending_timers() { return __timers.length; }

var navigator = { userAgent: "FakeBrowser/1.0" };

// session storage, can be made to throw as a browser does when it is blocked
var __storage = {};
var __storage_blocked = false;
var sessionStorage = {
                     getItem: function( k )    { if( __storage_blocked ) throw new Error( "SecurityError" ); return k in __storage ? __storage[k] : null; },
                     setItem: function( k, v ) { if( __storage_blocked ) throw new Error( "SecurityError" ); __storage[k] = String( v ); },
                     };

function Event( type, init ) { this.type = type; this.bubbles = !!( init && init.bubbles ); this.target = null; }

var __ids = {};

function El( tag, id )
{
  var self = this;
  this.tagName    = tag.toUpperCase();
  this.id         = id || "";
  this.style      = {};
  this.dataset    = {};
  this.attrs      = {};
  this.computed   = {};   // what a stylesheet would give, see getComputedStyle
  this.children   = [];
  this.parentNode = null;
  this.listeners  = {};
  this.offsetLeft = 0;
  this.offsetTop  = 0;
  this.offsetParent = null;
  this.__w = 0;           // size when shown, a hidden element has none
  this.__h = 0;
  this.checked = false;
  this.value   = "";
  this.name    = "";
  this.__classes = [];
  this.classList = {
                   add:      function( c ) { if( self.__classes.indexOf( c ) < 0 ) self.__classes.push( c ); },
                   remove:   function( c ) { var i = self.__classes.indexOf( c ); if( i >= 0 ) self.__classes.splice( i, 1 ); },
                   contains: function( c ) { return self.__classes.indexOf( c ) >= 0; },
                   };
  Object.defineProperty( this, 'className',    { get: function() { return self.__classes.join( " " ); }, set: function( v ) { self.__classes = v ? v.split( /\s+/ ) : []; } } );
  Object.defineProperty( this, 'offsetWidth',  { get: function() { return self.style.display == "none" ? 0 : self.__w; } } );
  Object.defineProperty( this, 'offsetHeight', { get: function() { return self.style.display == "none" ? 0 : self.__h; } } );
  Object.defineProperty( this, 'src',          { get: function() { return self.attrs.src; }, set: function( v ) { self.attrs.src = v; } } );
  if( this.id ) __ids[ this.id ] = this;
}

El.prototype.appendChild = function( c ) { c.parentNode = this; this.children.push( c ); return c; };
El.prototype.getAttribute = function( n ) { return n in this.attrs ? this.attrs[n] : null; };
El.prototype.setAttribute = function( n, v ) { this.attrs[n] = String( v ); };
El.prototype.closest = function( tag )
{
  var e = this;
  while( e ) { if( e.tagName == tag.toUpperCase() ) return e; e = e.parentNode; }
  return null;
};
El.prototype.getElementsByTagName = function( tag )
{
  var out = [];
  var walk = function( e ) { for( var i = 0; i < e.children.length; i++ ) { if( e.children[i].tagName == tag.toUpperCase() ) out.push( e.children[i] ); walk( e.children[i] ); } };
  walk( this );
  return out;
};
El.prototype.addEventListener = function( type, fn ) { ( this.listeners[type] = this.listeners[type] || [] ).push( fn ); };
El.prototype.dispatchEvent = function( ev )
{
  ev.target = this;
  var e = this;
  while( e )
    {
    if( e[ 'on' + ev.type ] ) e[ 'on' + ev.type ].call( e, ev );
    var ls = e.listeners[ ev.type ] || [];
    for( var i = 0; i < ls.length; i++ ) ls[i].call( e, ev );
    if( ! ev.bubbles ) break;
    e = e.parentNode;
    }
  return true;
};

var document = {
                getElementById:  function( id ) { return __ids[id] || null; },
                documentElement: { clientWidth: 1000, clientHeight: 800, scrollLeft: 0, scrollTop: 0 },
                body:            { scrollLeft: 0, scrollTop: 0 },
                };

var window = {
              innerWidth:  1000,
              innerHeight: 800,
              getComputedStyle: function( el )
                {
                return {
                       display:    el.style.display    || el.computed.display    || "block",
                       visibility: el.style.visibility || el.computed.visibility || "visible",
                       };
                },
              };

// helpers for the tests
function mk( tag, id, dataset, classes )
{
  var e = new El( tag, id );
  if( dataset ) for( var k in dataset ) e.dataset[k] = dataset[k];
  if( classes ) e.className = classes;
  return e;
}
JS

##############################################################################
##
##  the tests
##

my $TESTS = <<'JS';

/*** show/hide helpers *****************************************************/
{
  var td = mk( 'TD', 'sh_td' );
  html_block_show( td );
  t_is( td.style.display, "table-cell", 'html_block_show() gives a TD table-cell' );
  var tr = mk( 'TR', 'sh_tr' );
  html_block_show( tr );
  t_is( tr.style.display, "table-row", 'html_block_show() gives a TR table-row' );
  var dv = mk( 'DIV', 'sh_dv' );
  dv.computed.display = "none"; // hidden by a stylesheet only
  html_block_toggle( dv );
  t_is( dv.style.display, "block", 'html_block_toggle() shows an element hidden by css only' );
  html_block_toggle( dv );
  t_is( dv.style.display, "none", 'html_block_toggle() hides it again' );
  var ve = mk( 'SPAN', 'sh_ve' );
  ve.computed.visibility = "hidden";
  html_element_toggle( ve );
  t_is( ve.style.visibility, "visible", 'html_element_toggle() shows an element hidden by css only' );
  html_element_toggle_id( 'sh_ve' );
  t_is( ve.style.visibility, "hidden", 'html_element_toggle_id() hides it again' );
}

/*** class swap ************************************************************/
{
  var e = mk( 'SPAN', 'cs', { classKeep: 'keep' }, 'keep off other' );
  reactor_class_swap( e, 'off', 'on' );
  t_ok( e.classList.contains( 'on' ) && ! e.classList.contains( 'off' ), 'reactor_class_swap() swaps the classes' );
  t_ok( e.classList.contains( 'other' ), 'reactor_class_swap() keeps unrelated classes' );
  reactor_class_swap( e, 'keep on', 'off' );
  t_ok( e.classList.contains( 'keep' ), 'reactor_class_swap() re-adds the data-class-keep classes' );
  t_is( e.className, "other off keep", 'reactor_class_swap() class order' );
  reactor_class_swap( null, 'a', 'b' );
  t_ok( true, 'reactor_class_swap() ignores a missing element' );
}

/*** tabs ******************************************************************/
{
  var ctrl = mk( 'DIV', 'C', { tabsList: 'T1,T2,T3,T4', classOn: 'on', classOff: 'off' } );
  var t1 = mk( 'DIV', 'T1', { controllerId: 'C', handleId: 'H1' } );
  var t2 = mk( 'DIV', 'T2', { controllerId: 'C', handleId: 'H2' } );
  var t3 = mk( 'TR',  'T3', { controllerId: 'C', handleId: 'H3' } );
  var t4 = mk( 'TD',  'T4', { controllerId: 'C', handleId: 'H4' } );
  var h1 = mk( 'SPAN', 'H1', {}, 'off' );
  var h2 = mk( 'SPAN', 'H2', { classKeep: 'keep' }, 'keep off' );
  var h3 = mk( 'SPAN', 'H3', {}, 'off' );
  var h4 = mk( 'SPAN', 'H4', {}, 'off' );

  t_is( reactor_tab_restore( 'C', 'T1' ), false, 'reactor_tab_restore() returns false (for onclick)' );
  t_is( t1.style.display, "block", 'reactor_tab_restore() shows the default tab' );
  t_is( t2.style.display, "none",  'reactor_tab_restore() hides the other tabs' );
  t_ok( h1.classList.contains( 'on' ) && ! h1.classList.contains( 'off' ), 'the default tab handle gets the on class' );
  t_is( sessionStorage.getItem( 'TABSET_ACTIVE_C' ), "T1", 'the active tab is remembered in the session storage' );

  reactor_tab_activate_id( 'T2' );
  t_is( t1.style.display, "none",  'reactor_tab_activate_id() hides the previous tab' );
  t_is( t2.style.display, "block", 'reactor_tab_activate_id() shows the tab' );
  t_ok( h1.classList.contains( 'off' ) && h2.classList.contains( 'on' ), 'the handles swap their classes' );
  t_ok( h2.classList.contains( 'keep' ), 'the handle keeps its data-class-keep class' );
  t_is( sessionStorage.getItem( 'TABSET_ACTIVE_C' ), "T2", 'the new active tab is remembered' );

  reactor_tab_activate_id( 'T3' );
  t_is( t3.style.display, "table-row",  'a TR tab shows as table-row' );
  reactor_tab_activate_id( 'T4' );
  t_is( t4.style.display, "table-cell", 'a TD tab shows as table-cell' );

  sessionStorage.setItem( 'TABSET_ACTIVE_C', 'T2' );
  reactor_tab_restore( 'C', 'T1' );
  t_is( t2.style.display, "block", 'reactor_tab_restore() restores the remembered tab' );
  sessionStorage.setItem( 'TABSET_ACTIVE_C', 'NOPE' );
  reactor_tab_restore( 'C', 'T1' );
  t_is( t1.style.display, "block", 'a stale remembered tab id falls back to the default' );
  t_is( reactor_tab_activate_id( 'NOPE' ), false, 'reactor_tab_activate_id() with an unknown id does nothing' );

  __storage_blocked = true;
  var threw = false;
  try { reactor_tab_activate_id( 'T2' ); reactor_tab_restore( 'C', 'T1' ); } catch( e ) { threw = true; }
  __storage_blocked = false;
  t_ok( ! threw, 'blocked session storage does not break the tabs' );
  t_is( t1.style.display, "block", 'with blocked storage the default tab shows' );

  var lone = mk( 'DIV', 'LONE', { controllerId: 'NOCTRL', handleId: 'H1' } );
  t_is( reactor_tab_activate( lone ), false, 'a tab without a controller in the page does nothing' );
}

/*** checkboxes ************************************************************/
{
  var form = mk( 'FORM', 'F' );
  var changes = 0;
  form.addEventListener( 'change', function( ev ) { changes++; } );
  var h1 = form.appendChild( mk( 'INPUT', 'h1' ) ); h1.value = "0";
  var h2 = form.appendChild( mk( 'INPUT', 'h2' ) ); h2.value = "0";
  var c1 = form.appendChild( mk( 'INPUT', 'c1', { checkboxInputId: 'h1' } ) );
  var c2 = form.appendChild( mk( 'INPUT', 'c2', { checkboxInputId: 'h2' } ) );
  var plain = form.appendChild( mk( 'INPUT', 'plain' ) );
  form.elements = [ h1, h2, c1, c2, plain ];
  var own = 0;
  var own_ctx;
  h1.onchange = function( ev ) { own++; own_ctx = ( this === h1 && ev.type == 'change' ); };

  reactor_form_checkbox_set( c1, true );
  t_ok( own_ctx, 'the hidden input onchange runs with this and the event' );
  t_is( h1.value, 1, 'reactor_form_checkbox_set() sets the hidden input' );
  t_is( c1.checked, true, 'reactor_form_checkbox_set() sets the checkbox' );
  t_is( own, 1, 'the change event reaches the hidden input' );
  t_is( changes, 1, 'the change event bubbles to the form' );

  c1.checked = false; // the browser flipped it on click
  reactor_form_checkbox_toggle_by_id( 'c1' );
  t_is( h1.value, 0, 'reactor_form_checkbox_toggle() copies the checkbox state' );

  reactor_form_checkbox_set_all( 'F', 1 );
  t_ok( c1.checked && c2.checked && h1.value == 1 && h2.value == 1, 'reactor_form_checkbox_set_all( 1 ) checks all' );
  c1.checked = false; h1.value = 0;
  reactor_form_checkbox_set_all( 'F', -1 );
  t_ok( c1.checked && ! c2.checked && h1.value == 1 && h2.value == 0, 'reactor_form_checkbox_set_all( -1 ) inverts all' );
  reactor_form_checkbox_set_all( 'F', 0 );
  t_ok( ! c1.checked && ! c2.checked && h1.value == 0 && h2.value == 0, 'reactor_form_checkbox_set_all( 0 ) clears all' );
}

/*** multi-state checkboxes ************************************************/
{
  var mh = mk( 'INPUT', 'mh' ); mh.value = "5";
  var fired = 0;
  mh.onchange = function() { fired++; };
  var m = mk( 'SPAN', 'M', { checkboxInputId: 'mh', stages: "10" } );
  for( var i = 0; i < 10; i++ ) m.appendChild( mk( 'SPAN', 'M' + i ) );

  reactor_form_multi_checkbox_setup_id( 'M' );
  t_is( String( mh.value ), "5", 'setup keeps a value below 10 stages (numbers, not text compare)' );
  t_is( fired, 0, 'setup fires no change when the value stays' );
  t_is( m.children[5].style.display, "inline", 'the current stage is shown' );
  t_is( m.children[4].style.display, "none",   'the other stages are hidden' );

  reactor_form_multi_checkbox_toggle_by_id( 'M' );
  t_is( String( mh.value ), "6", 'toggle moves to the next stage' );
  t_is( fired, 1, 'toggle fires a change' );

  mh.value = "9";
  reactor_form_multi_checkbox_toggle( m );
  t_is( String( mh.value ), "0", 'toggle wraps to 0 after the last stage' );
  t_is( fired, 2, 'the wrap fires a change' );

  reactor_form_multi_checkbox_set( m, mh, 0 );
  t_is( fired, 2, 'setting the same value fires no change' );

  var sh = mk( 'INPUT', 'sh' ); sh.value = "1"; sh.name = "ord";
  var s  = mk( 'SPAN', 'S', { checkboxInputId: 'sh', stages: "3" } );
  var ic = mk( 'INPUT', 'IC' ); ic.value = "";
  reactor_form_sort_toggle( s, 'IC' );
  t_is( ic.value, "ord 2;", 'reactor_form_sort_toggle() records the column and its new state' );
}

/*** hover layers **********************************************************/
{
  var hl = mk( 'DIV', 'HL' ); hl.style.display = "none"; hl.__w = 100; hl.__h = 50;
  var el = mk( 'SPAN', 'HE' );
  reactor_hover_show_delay( el, 'HL', 250, { clientX: 990, clientY: 100 } );
  t_is( hl.style.display, "none", 'the hover layer waits for the delay' );
  t_is( pending_timers(), 1, 'a show timer is pending' );
  t_ok( typeof el.onmousemove == "function" && typeof el.onmouseout == "function", 'the element gets move and out handlers' );
  run_timers();
  t_is( hl.style.display,  "block", 'the hover layer shows after the delay' );
  t_is( hl.style.position, "absolute", 'the hover layer is positioned absolutely' );
  t_is( hl.style.left, "874px", 'the layer is placed left of the mouse at the right edge (sized only once shown)' );
  t_is( hl.style.top,  "116px", 'the layer is placed below the mouse' );
  el.onmousemove( { clientX: 10, clientY: 790 } );
  t_is( hl.style.left, "26px",  'a mouse move re-places the layer' );
  t_is( hl.style.top,  "724px", 'the layer goes above the mouse at the bottom edge' );
  el.onmouseout();
  t_is( hl.style.display, "none", 'the layer hides on mouse out' );
  reactor_hover_show( el, 'HL', { clientX: 10, clientY: 10 } );
  run_timers();
  t_is( hl.style.display, "block", 'reactor_hover_show() shows with a zero delay' );
  el.onmouseout();
}

/*** popup layers **********************************************************/
{
  var pa = mk( 'DIV', 'PA' ); pa.style.display = "none"; pa.__w = 200; pa.__h = 150;
  var pb = mk( 'DIV', 'PB' ); pb.style.display = "none"; pb.__w = 200; pb.__h = 150;
  var ea = mk( 'SPAN', 'EA', { popupLayerId: 'PA', popupClassOn: 'open', popupClassOff: 'closed' }, 'closed' );
  var eb = mk( 'SPAN', 'EB', { popupLayerId: 'PB' } );
  ea.offsetLeft = 100; ea.offsetTop = 600; ea.__w = 50; ea.__h = 30;
  ea.offsetParent = { offsetLeft: 50, offsetTop: 100, offsetParent: null }; // the usual nested element
  eb.offsetLeft = 10;  eb.offsetTop = 10;  eb.__w = 50; eb.__h = 30;

  reactor_popup_mouse_over( ea, { click_open: 1, timeout: 300, single: 1 } );
  t_is( pa.style.display, "block", 'a click popup opens at once' );
  t_ok( ea.classList.contains( 'open' ) && ! ea.classList.contains( 'closed' ), 'the element gets the popup on class' );
  t_is( pa.style.left, "150px", 'the popup is placed under the element, parent offsets included' );
  t_is( pa.style.top,  "634px", 'the popup is pulled up at the bottom edge, element height included' );

  reactor_popup_mouse_over( eb, { click_open: 1, single: 1 } );
  t_is( pa.style.display, "none",  'a SINGLE popup closes the open SINGLE one' );
  t_is( pb.style.display, "block", 'and opens itself' );
  t_ok( ea.classList.contains( 'closed' ), 'the closed element gets the off class back' );
  t_is( pb.style.top, "40px", 'the popup is placed below its element' );

  // the mouse leaves B, A opens within the timeout, B's close timer must not forget A
  eb.onmouseout();
  reactor_popup_mouse_over( ea, { click_open: 1, single: 1 } );
  t_is( pb.style.display, "none", 'opening A closes B' );
  run_timers();
  reactor_popup_mouse_over( eb, { click_open: 1, single: 1 } );
  t_is( pa.style.display, "none", 'the SINGLE tracker survives the close timer of the previous popup' );
  reactor_popup_mouse_over( eb, { click_open: 1, single: 1 } );
  t_is( pb.style.display, "none", 'a click on the element of an open popup closes it' );

  // context (timed) open honours SINGLE too
  reactor_popup_mouse_over( ea, { click_open: 1, single: 1 } );
  reactor_popup_mouse_over( eb, { timeout: 100, single: 1 } );
  t_is( pb.style.display, "none", 'a timed popup waits for its timeout' );
  run_timers();
  t_is( pb.style.display, "block", 'a timed popup opens after the timeout' );
  t_is( pa.style.display, "none",  'a timed SINGLE popup closes the open SINGLE one' );
  reactor_popup_hide_by_id( 'EB' );
  t_is( pb.style.display, "none", 'reactor_popup_hide_by_id() hides' );
  reactor_popup_mouse_toggle( eb );
  t_is( pb.style.display, "block", 'reactor_popup_mouse_toggle() shows' );
  reactor_popup_mouse_toggle( eb );
  t_is( pb.style.display, "none", 'reactor_popup_mouse_toggle() hides' );

  // the mouse moves from the element into the popup and out of it
  reactor_popup_mouse_over( eb, { click_open: 1, timeout: 100 } );
  eb.onmouseout();
  t_is( pending_timers(), 1, 'leaving the element starts the close timer' );
  pb.onmouseover();
  t_is( pending_timers(), 0, 'entering the popup cancels the close timer' );
  t_is( pb.style.display, "block", 'the popup stays open while the mouse is in it' );
  pb.onmouseout();
  t_is( pending_timers(), 1, 'leaving the popup starts the close timer again' );
  run_timers();
  t_is( pb.style.display, "none", 'the popup closes after the timeout' );
}

/*** disable on click ******************************************************/
{
  var b = mk( 'A', 'DB', { classOn: 'btn', classOff: 'btn-off' }, 'btn' );
  t_is( reactor_element_disable_on_click( b, 3 ), true, 'the first click goes through' );
  t_ok( b.classList.contains( 'btn-off' ) && ! b.classList.contains( 'btn' ), 'the element gets the off class' );
  t_is( reactor_element_disable_on_click( b, 3 ), false, 'a second click while disabled is dropped' );
  run_timers();
  t_ok( b.classList.contains( 'btn' ) && ! b.classList.contains( 'btn-off' ), 'the element is enabled again after the timeout' );
  t_is( b.is_disabled, 0, 'the disabled mark is cleared' );
}

/*** ftree *****************************************************************/
{
  var ft = mk( 'TABLE', 'FT' );
  var r1  = ft.appendChild( mk( 'TR', 'FT.1.' ) );
  var r12 = ft.appendChild( mk( 'TR', 'FT.1.2.' ) );   r12.style.display = "none";
  var r13 = ft.appendChild( mk( 'TR', 'FT.1.3.' ) );   r13.style.display = "none";
  var r134 = ft.appendChild( mk( 'TR', 'FT.1.3.4.' ) ); r134.style.display = "none";
  var r5  = ft.appendChild( mk( 'TR', 'FT.5.' ) );

  ftree_click( 'FT', 'FT.1.' );
  t_is( r12.style.display,  "table-row", 'opening a branch shows its rows' );
  t_is( r13.style.display,  "table-row", 'all of its rows' );
  t_is( r134.style.display, "none",      'but not the rows of a closed sub-branch' );
  t_ok( ! r5.style.display,              'other branches are untouched' );
  ftree_click( 'FT', 'FT.1.3.' );
  t_is( r134.style.display, "table-row", 'opening the sub-branch shows its rows' );
  ftree_click( 'FT', 'FT.1.' );
  t_is( r12.style.display,  "none", 'closing the branch hides its rows' );
  t_is( r134.style.display, "none", 'and the rows of the open sub-branch' );
  t_is( r13.open, false, 'a hidden sub-branch is marked closed' );
  ftree_click( 'FT', 'FT.1.' );
  t_is( r134.style.display, "none", 'reopening the branch leaves the sub-branch closed' );
  ftree_click( 'FT', 'FT.1.3.' );
  t_is( r134.style.display, "table-row", 'one click opens the sub-branch again' );
}

/*** collapsible table *****************************************************/
{
  var ct = mk( 'TABLE', 'CT' );
  var c1   = ct.appendChild( mk( 'TR', 'c1',   { cid: '1' } ) );
  var c12  = ct.appendChild( mk( 'TR', 'c12',  { cid: '1.2' } ) );   c12.style.display = "none";
  var c123 = ct.appendChild( mk( 'TR', 'c123', { cid: '1.2.3' } ) ); c123.style.display = "none";
  var c14  = ct.appendChild( mk( 'TR', 'c14',  { cid: '1.4' } ) );   c14.style.display = "none";
  var c10  = ct.appendChild( mk( 'TR', 'c10',  { cid: '10' } ) );    c10.style.display = "none";
  var plain = ct.appendChild( mk( 'TR', 'cp' ) );
  var td = c1.appendChild( mk( 'TD', 'c1td' ) );

  ctable_row_click( td );
  t_is( c12.style.display, "table-row", 'a click on the first cell shows the direct children' );
  t_is( c14.style.display, "table-row", 'all direct children' );
  t_is( c123.style.display, "none",     'deeper rows stay hidden' );
  t_is( c10.style.display,  "none",     'a row whose cid only starts with the same digits is not a child' );
  ctable_row_click( c1 );
  t_is( c12.style.display, "none", 'a second click hides the children' );
}

/*** image click loop ******************************************************/
{
  var img = mk( 'IMG', 'IM', { 'src-0': 'a.png', 'src-1': 'b.png', 'src-2': 'c.png' } );
  img.setAttribute( 'src', 'a.png' );
  reactor_image_click_loop( img );
  t_is( img.getAttribute( 'src' ), 'b.png', 'reactor_image_click_loop() goes to the next image' );
  reactor_image_click_loop( img );
  reactor_image_click_loop( img );
  t_is( img.getAttribute( 'src' ), 'a.png', 'reactor_image_click_loop() wraps to the first image' );
}

/*** datalist, set_value ***************************************************/
{
  var inp = mk( 'INPUT', 'DI' );
  var dl = mk( 'INPUT', 'DL', { inputId: 'DI', emptyKey: '0' } );
  var opts = { 'Two': { value: 'Two', dataset: { key: '2' } } };
  dl.list = { options: { namedItem: function( v ) { return opts[v] || null; } } };
  var submitted = 0;
  dl.form = { submit: function() { submitted++; } };
  dl.value = 'Two';
  reactor_datalist_change( dl, 0 );
  t_is( inp.value, '2', 'reactor_datalist_change() stores the key of the chosen option' );
  dl.value = 'nope';
  reactor_datalist_change( dl, 1 );
  t_is( inp.value, '0', 'reactor_datalist_change() stores the empty key for an unknown value' );
  t_is( dl.value, '',   'and clears the input' );
  t_is( submitted, 1,   'reactor_datalist_change() resubmits the form when asked' );
  set_value( 'DI', 'x' );
  t_is( inp.value, 'x', 'set_value() sets by id' );
}

/*** dates *****************************************************************/
{
  t_is( date_is_leap_year( 1900 ), 0, '1900 is not a leap year' );
  t_is( date_is_leap_year( 2000 ), 1, '2000 is a leap year' );
  t_is( date_is_leap_year( 2024 ), 1, '2024 is a leap year' );
  t_is( date_is_leap_year( 2026 ), 0, '2026 is not a leap year' );
  t_is( date_days_in_month( 2024, 1 ), 29, 'February 2024 has 29 days' );
  t_is( date_days_in_month( 2026, 1 ), 28, 'February 2026 has 28 days' );
  t_ok( /^\d\d\.\d\d\.\d{4}$/.test( current_date() ),      'current_date() is DD.MM.YYYY by default' );
  t_ok( /^\d{4}\.\d\d\.\d\d$/.test( current_date( 'YMD' ) ), 'current_date( YMD )' );
  t_ok( /^\d\d\.\d\d\.\d{4}$/.test( current_date( 'MDY' ) ), 'current_date( MDY )' );
  t_ok( /^\d\d:\d\d:\d\d$/.test( current_time() ),          'current_time() is HH:MM:SS' );
  t_ok( /^\d\d\.\d\d\.\d{4} \d\d:\d\d:\d\d$/.test( current_utime() ), 'current_utime() is date and time' );
}

JS

$js->eval( $FAKE_DOM );
$js->eval( $reactor_js );
$js->eval( $TESTS );

done_testing();

###EOF########################################################################
