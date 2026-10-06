/****************************************************************************
##
##  Web::Reactor application machinery
##  2014-2026 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@noxrun.com> <cade@bis.bg> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
****************************************************************************/

var user_agent = navigator.userAgent.toLowerCase();
var is_msie    = ( ( user_agent.indexOf( "msie"  ) != -1 ) && ( user_agent.indexOf("opera") == -1 ) );
var is_opera   =   ( user_agent.indexOf( "opera" ) != -1 );

function get_utime()
{
  return Math.round((new Date()).getTime() / 1000);
}

function q( id )
{
  return document.getElementById( id );
}

/*** SHOW/HIDE elements ****************************************************/

function html_element_show( elem )
{
  elem.style.position   = "relative";
  elem.style.visibility = "visible";
}

function html_element_hide( elem )
{
  elem.style.position   = "absolute";
  elem.style.visibility = "hidden";
}

function html_element_toggle( elem )
{
  // the inline value, or the computed one when only css sets it
  var vis = elem.style.visibility || window.getComputedStyle( elem ).visibility;
  if( vis == "visible" )
    {
    html_element_hide( elem );
    }
  else
    {
    html_element_show( elem );
    }
}

function html_element_show_id( elem_id )
{
  var elem = q( elem_id );
  html_element_show( elem );
}

function html_element_hide_id( elem_id )
{
  var elem = q( elem_id );
  html_element_hide( elem );
}

function html_element_toggle_id( elem_id )
{
  var elem = q( elem_id );
  html_element_toggle( elem );
}

/*-------------------------------------------------------------------------*/

function html_block_show( block )
{
  var ds = "block"; // display style

  if( block.tagName == "TR" && ! is_msie )
    ds = "table-row";
  else if( block.tagName == "TD" && ! is_msie )
    ds = "table-cell";

  block.style.display = ds;
}

function html_block_hide( block )
{
  block.style.display = "none";
}

function html_block_toggle( block )
{
  // the inline value, or the computed one when only css hides it
  var ds = block.style.display || window.getComputedStyle( block ).display;
  if( ds == "none" )
    {
    html_block_show( block );
    }
  else
    {
    html_block_hide( block );
    }
}

function html_block_show_id( block_id )
{
  var block = q( block_id );
  html_block_show( block );
}

function html_block_hide_id( block_id )
{
  var block = q( block_id );
  html_block_hide( block );
}

function html_block_toggle_id( block_id )
{
  var block = q( block_id );
  html_block_toggle( block );
}

/***************************************************************************/

function ftree_click( ftree_id, branch_id )
{
  var root_table = q( ftree_id );
  var branch_tr  = q( branch_id );

  branch_tr.open = ! branch_tr.open;

  var elems = root_table.getElementsByTagName( 'TR' );
  var bia = branch_id.split( "." );

  for( var i = 0; i < elems.length; i++ )
    {
    var el    = elems[i];
    var el_id = elems[i].id;

    var eia = el_id.split( "." );

    if( el_id.substr( 0, branch_id.length ) == branch_id )
      {
      if( branch_tr.open )
        {
        if( eia.length == bia.length + 1 )
          {
          html_block_show( el );
          // el.open = true;
          }
        }
      else
        {
        if( eia.length > bia.length )
          {
          html_block_hide( el );
          el.open = false; // a hidden branch shows closed when its parent opens again
          }
        }
      }
    }
}

function ctable_row_click( branch_el )
{
  var table_el = branch_el.closest( "TABLE" );

  if( branch_el.tagName == 'TD' ) branch_el = branch_el.closest( "TR" );

//  branch_el.open = ! branch_el.open;

  var rows = table_el.getElementsByTagName( 'TR' );
  var branch_cid = branch_el.dataset.cid;
  var bia = branch_cid.split( "." );

  for( var i = 0; i < rows.length; i++ )
    {
    var row = rows[i];
    var row_cid = row.dataset.cid;
    if( ! row_cid ) continue;
    var ria = row_cid.split( "." );

    if( row_cid.substr( 0, branch_cid.length ) == branch_cid && row_cid.substr( branch_cid.length, 1 ) == "." )
      {
        if( ria.length == bia.length + 1 )
          {
          html_block_toggle( row );
          }
        if( ria.length > bia.length + 1 )
          {
          html_block_hide( row );
          }
        continue;  
/*
      if( branch_el.open )
        {
        if( ria.length == bia.length + 1 )
          {
          html_block_show( row );
          // row.open = true;
          }
        }
      else
        {
        if( ria.length > bia.length )
          {
          html_block_hide( row );
          // row.open = false;
          }
        }
*/        
      }
    }
}

/***************************************************************************/

function current_date( fmt )
  {
  var now = new Date();
  var d = now.getDate();
  var m = now.getMonth() + 1;
  var y = now.getFullYear();
  if( d < 10 ) d = '0' + d;
  if( m < 10 ) m = '0' + m;
  
  fmt = ( fmt || 'DMY' ).substr( 0, 3 );
  if( fmt == "MDY" )
    return m + '.' + d + '.' + y;
  if( fmt == "YMD" )
    return y + '.' + m + '.' + d;
  //default: if( fmt == "DMY" ) 
    return d + '.' + m + '.' + y;
  }

function current_time()
  {
  var now = new Date();
  var h = now.getHours();
  var m = now.getMinutes();
  var s = now.getSeconds();
  if( h < 10 ) h = '0' + h;
  if( m < 10 ) m = '0' + m;
  if( s < 10 ) s = '0' + s;
  return  h + ':' + m + ':' + s;
  }

function current_utime( fmt )
  {
  return current_date( fmt ) + ' ' + current_time();
  }

/* used for input html elements with onClick=js:etc... */
function set_value( id_name, val )
  {
  var e = q( id_name );
  e.value = val;
  return false;
  }

/***************************************************************************/

function element_absolute_position( el )
{
  var pa = el;

  var x = pa.offsetLeft;
  var y = pa.offsetTop;

  while( pa = pa.offsetParent )
    {
    x += pa.offsetLeft;
    y += pa.offsetTop;
    }

  var abs_pos = { x: x, y: y, w: el.offsetWidth, h: el.offsetHeight };
  return abs_pos;
}

/***************************************************************************/

// TABs support with browser sessionStorage persistence (per browser tab)

function reactor_tab_activate_id( tab_id )
  {
  if( ! tab_id ) return false;

  // the id may be a stale one restored from sessionStorage, i.e. the tab set
  // has fewer tabs now, then there is nothing to activate
  var tab = q( tab_id );
  if( ! tab ) return false;

  return reactor_tab_activate( tab );
  }

// removes the classes in "rm" and adds the ones in "add" (space separated),
// other classes of the element, and the ones in data-class-keep, are kept
function reactor_class_swap( el, rm, add )
  {
  if( ! el ) return;
  var r = ( rm  || "" ).split( /\s+/ );
  var a = ( add || "" ).split( /\s+/ );
  var z;
  var k = ( el.dataset && el.dataset.classKeep || "" ).split( /\s+/ ); // classes which always stay
  for( z = 0; z < r.length; z++ ) if( r[z] ) el.classList.remove( r[z] );
  for( z = 0; z < a.length; z++ ) if( a[z] ) el.classList.add( a[z] );
  for( z = 0; z < k.length; z++ ) if( k[z] ) el.classList.add( k[z] );
  }

function reactor_tab_activate( tab )
  {
  var tab_ctrl = q( tab.dataset.controllerId );
  if( ! tab_ctrl ) return false; // no tab controller in the page, see HTML::Tab finish()

  var tabs = tab_ctrl.dataset.tabsList.split( "," );
  var con  = tab_ctrl.dataset.classOn;
  var coff = tab_ctrl.dataset.classOff;
  var pkey = tab_ctrl.id; // persistent-key
  var z;

  for( z = 0; z < tabs.length; z++ )
    {
    var t = q( tabs[z] );
    if( ! t ) continue;
    t.style.display = "none";
    reactor_class_swap( q( t.dataset.handleId ), con, coff );
    }

  reactor_class_swap( q( tab.dataset.handleId ), coff, con );
  if( pkey )
    {
    try { sessionStorage.setItem( 'TABSET_ACTIVE_' + pkey, tab.id ); } catch( e ) {} // storage may be blocked
    }
  if( tab.tagName == 'TR' )
    tab.style.display = "table-row";
  else if( tab.tagName == 'TD' )
    tab.style.display = "table-cell";
  else
    tab.style.display = "block";

  return false;
  }

// called by the tab controller (HTML::Tab finish()) when the page loads: shows
// the tab remembered in the browser session, if it is still in the page, else
// default_tab_id (if given)
function reactor_tab_restore( ctrl_id, default_tab_id )
  {
  var tab_id;
  try { tab_id = sessionStorage.getItem( 'TABSET_ACTIVE_' + ctrl_id ); } catch( e ) {} // storage may be blocked
  if( ! tab_id || ! q( tab_id ) ) tab_id = default_tab_id;
  return reactor_tab_activate_id( tab_id );
  }

/***************************************************************************/

function reactor_form_checkbox_set( el, value )
{
   var ch_id  = el.dataset.checkboxInputId;
   var cb     = q( ch_id );
   cb.value   = value ? 1 : 0;
   el.checked = value;

   reactor_fire_change( cb );
}

// fires a change event on el, so its onchange handler (and listeners) run
// with this = el and the event, as on a real change
function reactor_fire_change( el )
{
  if( typeof Event == "function" )
    el.dispatchEvent( new Event( "change", { bubbles: true } ) ); // bubbles as a real change does
  else if( el.onchange ) // old msie, no Event constructor
    el.onchange();
}

function reactor_form_checkbox_toggle( el )
{
   reactor_form_checkbox_set( el, el.checked );
}

function reactor_form_checkbox_toggle_by_id( el_id )
{
   reactor_form_checkbox_toggle( q( el_id ) );
}

function reactor_form_checkbox_set_all( form_id, value )
{
  var arr = q( form_id ).elements;
  for( var z = 0; z < arr.length; z++ )
    {
    var ch_id = arr[z].dataset.checkboxInputId;
    if( ! ch_id ) continue;
    if( value == -1 )
      reactor_form_checkbox_set( arr[z], ! arr[z].checked );
    else  
      reactor_form_checkbox_set( arr[z], value );
    }
}

/*** multi-state checkboxes ************************************************/

function reactor_form_multi_checkbox_setup_id( el_id )
{
  var el     = q( el_id );
  var cb_id  = el.dataset.checkboxInputId;
  var cb     = q( cb_id );

  reactor_form_multi_checkbox_set( el, cb, cb.value );
}

function reactor_form_multi_checkbox_toggle( el )
{
  var cb_id  = el.dataset.checkboxInputId;
  var cb     = q( cb_id );

  reactor_form_multi_checkbox_set( el, cb, (+cb.value) + 1 );
}

function reactor_form_multi_checkbox_toggle_by_id( id )
{
  reactor_form_multi_checkbox_toggle( q( id ) );
}

function reactor_form_multi_checkbox_set( el, cb, new_value )
{
  var stages = +el.dataset.stages; // numbers, not text compare
  new_value  = +new_value;
  var value = cb.value;
  if( new_value >= stages ) 
    cb.value = 0;
  else
    cb.value = new_value;  

  var kids = el.children;
  for( var z = 0; z < kids.length; z++ )
    {
    kids[z].style.display = cb.value == z ? "inline" : "none";
    }
/*
   var new_label = el.dataset[ "valueLabel-" + cb.value ];
   var new_class = el.dataset[ "valueClass-" + cb.value ];

   el.className = new_class;
   el.innerHTML = new_label;
*/

  if( cb.value != value )
    {
    reactor_fire_change( cb );
    }  
}

/*------------------------------------*/

function reactor_form_sort_toggle( el, sort_ic_name )
{
  var cb_id  = el.dataset.checkboxInputId;
  var cb     = q( cb_id );
  var ic     = q( sort_ic_name );

  reactor_form_multi_checkbox_set( el, cb, (+cb.value) + 1 );
  
  ic.value = ic.value + cb.name + " " + cb.value + ";";
}

/*** hover layers *******************************************************/

var reactor_hover_layer;
var reactor_hover_layer_timeout_id;
var reactor_hover_layer_x; // last mouse position, the layer is placed again
var reactor_hover_layer_y; // when it shows, hidden it has no size for the edge check

function reactor_hover_show( el, hl_name, event )
  {
  reactor_hover_show_delay( el, hl_name, 0, event );
  }

function reactor_hover_show_delay( el, hl_name, delay, event )
  {
  if( reactor_hover_layer_timeout_id ) 
    clearTimeout( reactor_hover_layer_timeout_id );

  reactor_hover_layer = q( hl_name );
  reactor_hover_layer_timeout_id = setTimeout( reactor_hover_activate, delay );
  reactor_hover_reposition( event );
  el.onmousemove = is_msie ? reactor_hover_reposition_ie : reactor_hover_reposition;
  el.onmouseout  = reactor_hover_hide;
  }

function reactor_hover_activate()
  {
  clearTimeout( reactor_hover_layer_timeout_id );
  reactor_hover_layer.style.display  = "block";
  reactor_hover_layer.style.position = "absolute";
  reactor_reposition_div_to_xy( reactor_hover_layer, reactor_hover_layer_x, reactor_hover_layer_y );
  }

function reactor_hover_hide()
  {
  reactor_hover_layer.style.display = "none";
  clearTimeout( reactor_hover_layer_timeout_id );
  }

function reactor_hover_reposition( event )
  {
  reactor_hover_layer_x = event.clientX;
  reactor_hover_layer_y = event.clientY;
  reactor_reposition_div_to_xy( reactor_hover_layer, event.clientX, event.clientY );
  }

function reactor_hover_reposition_ie()
  {
  return reactor_hover_reposition( event );
  }

/*** popup layers **********************************************************/

function reactor_get_popup_layer( el )
{
  return q( el.dataset.popupLayerId );
}

function reactor_popup_mouse_toggle( el, opt )
{
  var popup_layer = reactor_get_popup_layer( el );
  if( popup_layer.style.display == 'block' )
    reactor_popup_hide( el );
  else
    reactor_popup_show( el );

  return false;
}

/*-------------------------------------------------------------------*/

var single_popup_layer;

function reactor_popup_mouse_over( el, opt )
{
  if( ! opt ) opt = {};

  var timeout = opt.timeout > 0 ? opt.timeout : 200;
  
  var popup_layer = reactor_get_popup_layer( el );
  if( popup_layer.style.display == 'block' )
    {
    //console.log( "there is open popup, remove all running timeouts and close it" );
    reactor_popup_clear_tos( el );
    reactor_popup_hide( el );
    return false;
    }  
  else
    {
    //console.log( "there is no open popup, set timeout for open" );
    if( opt.click_open )
      {
      if( opt.single && single_popup_layer ) reactor_popup_hide( single_popup_layer );
      reactor_popup_show( el );
      if( opt.single ) single_popup_layer = el;
      }
    else
      el.open_to = setTimeout( function()
                               {
                               if( opt.single && single_popup_layer ) reactor_popup_hide( single_popup_layer );
                               reactor_popup_show( el );
                               if( opt.single ) single_popup_layer = el;
                               }, timeout );
    el.onmouseout = function()
                    {
                    //console.log( "mouse out from main element, cancel open timeout, set close timeout" );
                    if( el.open_to ) clearTimeout( el.open_to );
                    el.onmouseout = null;
                    el.close_to   = setTimeout( function() 
                                                { 
                                                //console.log( "close timeout up, hide popup" );
                                                reactor_popup_hide( el );
                                                if( opt.single && single_popup_layer === el ) single_popup_layer = null; // not another one opened meanwhile
                                                }, timeout );
                    
                    popup_layer.onmouseover = function() 
                                              { 
                                              //console.log( "mouse inside popup, cancel all timeouts" );
                                              reactor_popup_clear_tos( el );
                                              };

                    popup_layer.onmouseout  = function() 
                                              { 
                                              //console.log( "mouse leave popup, set close timeout" );
                                              reactor_popup_clear_tos( el );
                                              el.close_to = setTimeout( function() 
                                                                        { 
                                                                        reactor_popup_hide( el );
                                                                        if( opt.single && single_popup_layer === el ) single_popup_layer = null;
                                                                        }, timeout );
                                              };
                    };
    }  

  return false;
}

function reactor_popup_clear_tos( el )
{
  if( el.open_to )
    clearTimeout( el.open_to );
  if( el.close_to )
    clearTimeout( el.close_to );
}

/*-------------------------------------------------------------------*/

function reactor_popup_show( el )
{
  var class_on = el.dataset.popupClassOn;
  if( class_on )
    reactor_class_swap( el, el.dataset.popupClassOff, class_on );

  var popup_layer = reactor_get_popup_layer( el );
  popup_layer.style.display  = "block";
  popup_layer.style.position = "absolute";

  reactor_reposition_div_next_to( popup_layer, el );

  return false;
}

function reactor_popup_hide( el )
{
  var class_off = el.dataset.popupClassOff;
  if( class_off )
    reactor_class_swap( el, el.dataset.popupClassOn, class_off );

  var popup_layer = reactor_get_popup_layer( el );
  popup_layer.style.display = "none";
  
  reactor_popup_clear_tos( el );
}

function reactor_popup_show_by_id( id )
{
  reactor_popup_show( q( id ) );    
}

function reactor_popup_hide_by_id( id )
{
  reactor_popup_hide( q( id ) );    
}

/*-------------------------------------------------------------------*/

function reactor_reposition_div_next_to( div, el )
{
  var abs_pos = element_absolute_position( el );

  var doc  = document.documentElement;
  var body = document.body;

  var vw = Math.max( doc && doc.clientWidth  || 0, window.innerWidth  || 0 );
  var vh = Math.max( doc && doc.clientHeight || 0, window.innerHeight || 0 );

  var dw = div.offsetWidth;
  var dh = div.offsetHeight;

  var ex = abs_pos.x;
  var ey = abs_pos.y;
  var eh = abs_pos.h;

  var scrollLeft = (doc && doc.scrollLeft || body && body.scrollLeft || 0);
  var scrollTop  = (doc && doc.scrollTop  || body && body.scrollTop  || 0);

  var pw = vw + scrollLeft;
  var ph = vh + scrollTop;

  // the div goes under the element, so its height counts for the edge check
  var left = (ex + 16 + dw)      > pw ? pw - dw - 16 : ex;
  var top  = (ey + eh + 16 + dh) > ph ? ph - dh - 16 : ey + eh;

  div.style.left = left + 'px';
  div.style.top  = top  + 'px';
}

function reactor_reposition_div_to_xy( div, x, y )
{
  var doc  = document.documentElement;
  var body = document.body;

  var vw = Math.max( doc && doc.clientWidth  || 0, window.innerWidth  || 0 );
  var vh = Math.max( doc && doc.clientHeight || 0, window.innerHeight || 0 );

  var dw = div.offsetWidth;
  var dh = div.offsetHeight;

  var scrollLeft = (doc && doc.scrollLeft || body && body.scrollLeft || 0);
  var scrollTop  = (doc && doc.scrollTop  || body && body.scrollTop  || 0);

  var pw = vw + scrollLeft;
  var ph = vh + scrollTop;

  var nx = x + scrollLeft;
  var ny = y + scrollTop;
  
  var left = nx + ( ( nx + 16 + dw ) > pw ? -( 16 + dw ) : 16 );
  var top  = ny + ( ( ny + 16 + dh ) > ph ? -( 16 + dh ) : 16 );

  //console.log( "mouse x: " + nx + ", y: " + ny );
  //console.log( "div pos left: " + left + ", top: " + top );

  div.style.left = left + 'px';
  div.style.top  = top  + 'px';
}

/*-------------------------------------------------------------------*/

function reactor_element_disable_on_click( el, timeout )
{
  if( get_utime() < el.is_disabled ) return false;
  el.is_disabled = get_utime() + timeout;
  var con  = el.dataset.classOn;
  var coff = el.dataset.classOff;
  reactor_class_swap( el, con, coff );
  el.disabled_to = setTimeout( function() { el.is_disabled = 0; reactor_class_swap( el, coff, con ); }, timeout * 1000 );
  return true;
}

/*-------------------------------------------------------------------*/

function reactor_datalist_change( el, resubmit )
{
  var input = q( el.dataset.inputId );

  var option = el.list.options.namedItem( el.value );
  if( option )
    {
    input.value = option.dataset.key;
    el.value    = option.value;
    }
  else
    {
    input.value = el.dataset.emptyKey;
    el.value    = '';  
    }
    
  if( resubmit )  
    el.form.submit();
}

/*** image click loop ******************************************************/

function reactor_image_click_loop( img )
{
  for( var i = 0; i < 32; i++ )
    {
    // the src attribute as written, img.src would be the absolute url
    if( img.getAttribute( "src" ) != img.dataset[ "src-" + i ] ) continue;
    var ni = img.dataset[ "src-" + ++i ];
    if( ni ) 
      img.src = ni;
    else  
      img.src = img.dataset[ "src-0" ];
    break;
    }
}

/***************************************************************************/

function date_is_leap_year( year )
{
    if( year %   4 ) return 0;
    if( year % 100 ) return 1;
    if( year % 400 ) return 0;
    return 1;
}

var __days_in_month = [
                        [ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ],
                        [ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ]
                      ];

var __nz_months = [ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"  ];

function date_days_in_month( year, month )
{
  return __days_in_month[ date_is_leap_year( year ) ][ month ];
}

//alert( date_days_in_month( 1900, 2 ) );

function display_cal( dd )
{
  var text;

  var di = dd.id;

  var y  = dd.dataset.y;
  var m  = dd.dataset.m;
  var d  = dd.dataset.d;
  dd.dataset.d = 0;
  var wd = new Date( y, m, 1 ).getDay();
  if( wd == 0 ) wd = 7; // make it sensible, weeks start Monday :)
  wd--;


  var mm = (+m) + 1; // aaah stupid crappy js
  if( mm < 10 ) mm = "0" + mm;
  
  text = "<span class=nz-nav>" + 
         "<span onclick='__nz_py( this )' data-div-id='"+di+"'>&nbsp;&lArr;&nbsp;</span>" + 
         "<span onclick='__nz_pm( this )' data-div-id='"+di+"'>&nbsp;&nbsp;&larr;</span>" +
         "<span onclick='__nz_td( this )' data-div-id='"+di+"'>&nbsp;&nbsp;&nbsp;&darr;&nbsp;" +
         __nz_months[ m ] + " " + y + "&nbsp;&nbsp;</span> " +
         "<span onclick='__nz_nm( this )' data-div-id='"+di+"'>&rarr;&nbsp;&nbsp;</span>" +
         "<span onclick='__nz_ny( this )' data-div-id='"+di+"'>&nbsp;&rArr;&nbsp;</span>" + 
         "</span>\n";

  text += "<span class=nz-head> Mon Tue Wed Thu Fri Sat Sun</span>\n";

  for( var i = 0; i < wd; i++ )
    text += "    ";
    
  for( var i = 1; i <= date_days_in_month( y, m ); i++ )
    {
    var di2 = i < 10 ? "0" + i : i; // day, two digits like the month
    var ds = y + "." + mm + "." + di2;
    if( dd.dataset.fmt == 'DMY' ) ds = di2 + "." + mm + "." + y;
    if( dd.dataset.fmt == 'MDY' ) ds = mm + "." + di2 + "." + y;
    var tm = d > 0 && d == i ? "*" : " "; // today mark
    text += "<span class=nz-date onclick='__nz_set( this )' data-date='"+ds+"' data-div-id='"+di+"'> " + ( i < 10 ? " " : "" ) + tm + i + "</span>";
    if( ( wd + i ) % 7 == 0 ) text += "\n";
    }

  dd.innerHTML = "<pre class=nz-date-picker>" + text + "</pre>";
}

function __nz_set( el )
{
  var dd = q( el.dataset.divId );
  var te = q( dd.dataset.t );
  if( te.tagName == "INPUT" )
    te.value = el.dataset.date;
  else
    te.innerHTML = el.dataset.date;
  if( dd.set_callback ) dd.set_callback();
  te.focus();
}

function nz_setup_picker( div_id, target_id, dt, fmt, scb )
{
  var y  = dt.getFullYear();
  var m  = dt.getMonth();
  var d  = dt.getDate();

  var dd = q( div_id );
  dd.dataset.y   = y;
  dd.dataset.m   = m;
  dd.dataset.d   = d;
  dd.dataset.t   = target_id;
  dd.dataset.fmt = fmt;
  dd.set_callback = scb;
  
  display_cal( dd );
}

function __nz_td( el )
{
  var dd = q( el.dataset.divId );
  var dt = new Date( Date.now() );
  dd.dataset.y = dt.getFullYear();
  dd.dataset.m = dt.getMonth();
  dd.dataset.d = dt.getDate();
  display_cal( dd );
}

function __nz_pm( el )
{
  var dd = q( el.dataset.divId );
  if( --dd.dataset.m < 0 ) { dd.dataset.y--; dd.dataset.m = 11; }
  display_cal( dd );
}

function __nz_nm( el )
{
  var dd = q( el.dataset.divId );
  if( ++dd.dataset.m > 11 ) { dd.dataset.y++; dd.dataset.m = 0; }
  display_cal( dd );
}

function __nz_py( el )
{
  var dd = q( el.dataset.divId );
  --dd.dataset.y;
  display_cal( dd );
}

function __nz_ny( el )
{
  var dd = q( el.dataset.divId );
  ++dd.dataset.y;
  display_cal( dd );
}

/***EOF*********************************************************************/
