/****************************************************************************
##
##  Web::Reactor application machinery
##  2013 (c) Vladi Belperchinov-Shabanski "Cade"
##  <cade@bis.bg> <cade@biscom.net> <cade@cpan.org>
##
##  LICENSE: GPLv2
##
****************************************************************************/

var user_agent = navigator.userAgent.toLowerCase();
var is_msie    = ( ( user_agent.indexOf( "msie"  ) != -1 ) && ( user_agent.indexOf("opera") == -1 ) );
var is_opera   =   ( user_agent.indexOf( "opera" ) != -1 );

/***************************************************************************/

function toggle_display( eid )
{
  var elem = document.getElementById( eid );
  if( elem.style.position == "absolute" )
    {
    elem.style.position   = "relative";
    elem.style.visibility = "visible";
    }
  else
    {
    elem.style.position   = "absolute";
    elem.style.visibility = "hidden";
    }
}

function toggle_display_block( eid )
{
  var elem = document.getElementById( eid );
  if( elem.style.display == "none" )
    {
    elem.style.display = "block";
    }
  else
    {
    elem.style.display = "none";
    }
}

function toggle_display_tr( eid )
{
  var elem = document.getElementById( eid );
  if( elem.style.display == "none" )
    {
    if( is_msie_shit )
      elem.style.display = "block";
    else
      elem.style.display = "table-row";
    }
  else
    {
    elem.style.display = "none";
    }
}

/***************************************************************************/

function ftree_click( ftree_id, branch_id )
{
  var root_table = document.getElementById( ftree_id );
  
  var elems = root_table.getElementsByTagName( 'TR' )

  for( var i = 0; i < elems.length; i++ )
    {
    var el = elems[i];
    var el_id = elems[i].id;
    
    if( el_id.substr( 0, branch_id.length ) == branch_id && el_id.length > branch_id.length )
      toggle_display_tr( el_id );
    }

}

/***EOF*********************************************************************/
