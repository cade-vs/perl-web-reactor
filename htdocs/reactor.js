/****************************************************************************
##
##  Web::Reactor application machinery
##  2014-2022 (c) Vladi Belperchinov-Shabanski "Cade"
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
  if( elem.style.visibility = "visible" )
    {
    html_element_show( elem );
    }
  else
    {
    html_element_hide( elem );
    }
}

function html_element_show_id( elem_id )
{
  var elem = document.getElementById( elem_id );
  html_element_show( elem );
}

function html_element_hide_id( elem_id )
{
  var elem = document.getElementById( elem_id );
  html_element_hide( elem );
}

function html_element_toggle_id( elem_id )
{
  var elem = document.getElementById( elem_id );
  html_element_toggle( elem );
}

/*-------------------------------------------------------------------------*/

function html_block_show( block )
{
  var ds = "block"; // display style

  if( block.tagName == "TR" && ! is_msie )
    ds = "table-row";

  block.style.display = ds;
}

function html_block_hide( block )
{
  block.style.display = "none";
}

function html_block_toggle( block )
{
  if( block.style.display == "none" )
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
  var block = document.getElementById( block_id );
  html_block_show( block );
}

function html_block_hide_id( block_id )
{
  var block = document.getElementById( block_id );
  html_block_hide( block );
}

function html_block_toggle_id( block_id )
{
  var block = document.getElementById( block_id );
  html_block_toggle( block );
}

/***************************************************************************/

function ftree_click( ftree_id, branch_id )
{
  var root_table = document.getElementById( ftree_id );
  var branch_tr  = document.getElementById( branch_id );

  branch_tr.open = ! branch_tr.open;

  var elems = root_table.getElementsByTagName( 'TR' )
  var bia = branch_id.split( "." );

  for( var i = 0; i < elems.length; i++ )
    {
    var el = elems[i];
    var el_id = elems[i].id;

    var eia = el_id.split( "." );

    if( el_id.substr( 0, branch_id.length ) == branch_id )
      {
      if( branch_tr.open )
        {
        if( eia.length == bia.length + 1 )
          {
          html_block_show( el );
          }
        }
      else
        {
        if( eia.length > bia.length )
          {
          html_block_hide( el );
          el.open = false;
          }
        }
      }
    }
}

/***************************************************************************/

function current_date( fmt )
  {
  var now = new Date();
  var d = now.getDate();
  var m = now.getMonth() + 1;
  var y = now.getYear();
  if( y < 1000 ) y += 1900; // stupid msie shit
  if( d < 10 ) d = '0' + d;
  if( m < 10 ) m = '0' + m;
  
  fmt = fmt.substr( 0, 3 );
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
  var now = new Date();
  return current_date( fmt ) + ' ' + current_time();
  }

/* used for input html elements with onClick=js:etc... */
function set_value( id_name, val )
  {
  var e = document.getElementById( id_name );
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

// TABs support with browser localStorage persistence

function reactor_tab_activate_id( tab_id )
  {
  if( ! tab_id ) return;

  var tab = document.getElementById( tab_id );

  return reactor_tab_activate( tab );
  }

function reactor_tab_activate( tab )
  {
  var tab_ctrl = document.getElementById( tab.dataset.controllerId );

  var tabs = tab_ctrl.dataset.tabsList.split( "," );
  var con  = tab_ctrl.dataset.classOn;
  var coff = tab_ctrl.dataset.classOff;
  var pkey = tab_ctrl.id; // persistent-key
  var z;

  for( z = 0; z < tabs.length; z++ )
    {
    var t = document.getElementById( tabs[z] );
    t.style.display = "none";
    document.getElementById( t.dataset.handleId ).className = coff;
    }

  document.getElementById( tab.dataset.handleId ).className = con;
  if( pkey )
    {
    sessionStorage.setItem( 'TABSET_ACTIVE_' + pkey, tab.id );
    }
  if( tab.tagName == 'TR' )
    tab.style.display = "table-row";
  else
    tab.style.display = "block";

  return false;
  }

/***************************************************************************/

function reactor_form_checkbox_set( el, value )
{
   var ch_id  = el.dataset.checkboxInputId;
   var cb     = document.getElementById( ch_id );
   cb.value   = value ? 1 : 0;
   el.checked = value;

   var onchange = cb.getAttribute( 'ONCHANGE' );
   if( onchange )
     {
     if( is_msie )
       onchange();
     else
       eval( onchange );
     }
}

function reactor_form_checkbox_toggle( el )
{
   reactor_form_checkbox_set( el, el.checked );
}

function reactor_form_checkbox_set_all( form_id, value )
{
  var arr = document.getElementById( form_id ).elements;
  for( z = 0; z < arr.length; z++ )
    {
    var ch_id = arr[z].dataset.checkboxInputId;
    if( ! ch_id ) continue;
    if( value == -1 )
      reactor_form_checkbox_toggle( arr[z] );
    else  
      reactor_form_checkbox_set( arr[z], value );
    }
}

/*** multi-state checkboxes ************************************************/

function reactor_form_multi_checkbox_setup_id( el_id )
{
   var el     = document.getElementById( el_id );
   var cb_id  = el.dataset.checkboxInputId;
   var cb     = document.getElementById( cb_id );

   reactor_form_multi_checkbox_set( el, cb, cb.value );
}

function reactor_form_multi_checkbox_toggle( el )
{
   var cb_id  = el.dataset.checkboxInputId;
   var cb     = document.getElementById( cb_id );

   reactor_form_multi_checkbox_set( el, cb, (+cb.value) + 1 );
}

function reactor_form_multi_checkbox_set( el, cb, new_value )
{
   var stages = el.dataset.stages;
   var value = cb.value;
   if( new_value >= stages ) 
     cb.value = 0;
   else
     cb.value = new_value;  

   var new_label = el.dataset[ "valueLabel-" + cb.value ];
   var new_class = el.dataset[ "valueClass-" + cb.value ];

   el.className = new_class;
   el.innerHTML = new_label;

   if( new_value != value )
     {
     var onchange = cb.getAttribute( 'ONCHANGE' );
     if( onchange )
       {
       if( is_msie )
         onchange();
       else
         eval( onchange );
       }
     }  
}


/*** hover layers *******************************************************/

var reactor_hover_layer;
var reactor_hover_layer_timeout_id;

function reactor_hover_show( el, hl_name )
  {
  reactor_hover_show_delay( el, hl_name, 0 );
  }

function reactor_hover_show_delay( el, hl_name, delay, event )
  {
  if( reactor_hover_layer_timeout_id ) 
    clearTimeout( reactor_hover_layer_timeout_id );

  reactor_hover_layer = document.getElementById( hl_name );
  reactor_hover_layer_timeout_id = setTimeout( "reactor_hover_activate()", delay );
  reactor_hover_reposition( event );
  el.onmousemove = is_msie ? reactor_hover_reposition_ie : reactor_hover_reposition;
  el.onmouseout  = reactor_hover_hide;
  }

function reactor_hover_activate()
  {
  clearTimeout( reactor_hover_layer_timeout_id );
  reactor_hover_layer.style.display  = "block";
  reactor_hover_layer.style.position = "absolute";
  }

function reactor_hover_hide()
  {
  reactor_hover_layer.style.display = "none";
  clearTimeout( reactor_hover_layer_timeout_id );
  }

function reactor_hover_reposition( event )
  {
  reactor_reposition_div_to_xy( reactor_hover_layer, event.clientX, event.clientY );
  }

function reactor_hover_reposition_ie()
  {
  return reactor_hover_reposition( event );
  }

/*** popup layers **********************************************************/

function reactor_get_popup_layer( el )
{
  return document.getElementById( el.dataset.popupLayerId );
}

function reactor_popup_mouse_toggle( el, opt )
{
  var popup_layer = reactor_get_popup_layer( el );
  if( popup_layer.style.display == 'block' )
    reactor_popup_hide( el );
  else
    reactor_popup_show( el );

  return false;
};

/*-------------------------------------------------------------------*/

function reactor_popup_mouse_over( el, opt )
{
  if( ! opt ) opt = {};

  var timeout = opt.timeout > 0 ? opt.timeout : 200;
  
  var popup_layer = reactor_get_popup_layer( el );
  if( popup_layer.style.display == 'block' )
    {
    //console.log( "there is open popup, remove all running timeouts" );
    reactor_popup_clear_tos( el );
    return false;
    }  
  else
    {
    //console.log( "there is no open popup, set timeout for open" );
    if( opt.click_open )
      reactor_popup_show( el );
    else
      el.open_to = setTimeout( function() { reactor_popup_show( el ) }, timeout );
    el.onmouseout = function()
                    {
                    //console.log( "mouse out from main element, cancel open timeout, set close timeout" );
                    if( el.open_to )
                      clearTimeout( el.open_to );
                    el.onmouseout = null;
                    el.close_to   = setTimeout( function() 
                                                { 
                                                //console.log( "close timeout up, hide popup" );
                                                reactor_popup_hide( el ) 
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
                                              el.close_to = setTimeout( function() { reactor_popup_hide( el ) }, timeout );
                                              };
                    };
    }  

  return false;
};

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
    el.className = class_on;

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
    el.className = class_off;

  var popup_layer = reactor_get_popup_layer( el );
  popup_layer.style.display = "none";
  
  reactor_popup_clear_tos( el );
}

/*-------------------------------------------------------------------*/

function reactor_reposition_div_next_to( div, el )
{
  var abs_pos = element_absolute_position( el );

  var doc  = document.documentElement;
  var body = document.body;

  const vw = Math.max( doc && doc.clientWidth  || 0, window.innerWidth  || 0 )
  const vh = Math.max( doc && doc.clientHeight || 0, window.innerHeight || 0 )

  var dw = div.offsetWidth;
  var dh = div.offsetHeight;

  var ex = abs_pos.x;
  var ey = abs_pos.y;
  var ew = abs_pos.w;
  var eh = abs_pos.h;

  var scrollLeft = (doc && doc.scrollLeft || body && body.scrollLeft || 0);
  var scrollTop  = (doc && doc.scrollTop  || body && body.scrollTop  || 0);

  const pw = vw + scrollLeft;
  const ph = vh + scrollTop;

  var left = (ex + 16 + dw) > pw ? pw - dw - 16 : ex;
  var top  = (ey + 16 + dh) > ph ? ph - dh - 16 : ey;

  top += eh;

  div.style.left = left + 'px';
  div.style.top  = top  + 'px';
}

function reactor_reposition_div_to_xy( div, x, y )
{
  var doc  = document.documentElement;
  var body = document.body;

  const vw = Math.max( doc && doc.clientWidth  || 0, window.innerWidth  || 0 )
  const vh = Math.max( doc && doc.clientHeight || 0, window.innerHeight || 0 )

  var dw = div.offsetWidth;
  var dh = div.offsetHeight;

  var scrollLeft = (doc && doc.scrollLeft || body && body.scrollLeft || 0);
  var scrollTop  = (doc && doc.scrollTop  || body && body.scrollTop  || 0);

  const pw = vw + scrollLeft;
  const ph = vh + scrollTop;

  const nx = x + scrollLeft;
  const ny = y + scrollTop;
  
  const left = nx + ( ( nx + 16 + dw ) > pw ? -( 16 + dw ) : 16 );
  const top  = ny + ( ( ny + 16 + dh ) > ph ? -( 16 + dh ) : 16 );

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
  el.className = coff;
  el.disabled_to = setTimeout( function() { el.is_disabled = 0; el.className = con; }, timeout * 1000 );
  return true;
}

/*-------------------------------------------------------------------*/

function reactor_datalist_change( el, resubmit )
{
  var input = document.getElementById( el.dataset.inputId );

  var option = el.list.options.namedItem( el.value );
  if( option )
    {
    var datalist_key = option.dataset.key;
    input.value = datalist_key;
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
    if( img.src != img.dataset[ "src-" + i ] ) continue;
    var ni = img.dataset[ "src-" + ++i ];
    if( ni ) 
      img.src = ni;
    else  
      img.src = img.dataset[ "src-0" ];
    }
}

/***EOF*********************************************************************/
