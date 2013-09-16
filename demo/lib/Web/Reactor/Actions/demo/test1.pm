package Web::Reactor::Actions::demo::test1;
use strict;
use Data::Dumper;
use Web::Reactor::HTML::FormEngine;

sub main
{
  my $reo = shift;

  my $text;


  if( $reo->get_input_form_name() eq 'PERSON_FORM' and $reo->get_input_button() eq 'PERSON_CANCEL' )
    {
    print STDERR "FOOOOOOOOOOOOOOOOOOOOOOOORM BACK HER---------------------\n";
    return $reo->forward_back( OPA => 'hehe' );
    }

  $text .= "<p>Reactor::Actions::demo::test here! <&expire_hint>\n";

  my $grid_href = $reo->args_new( _PN => 'grid', TABLE => 'testtable', );
  $text .= "<a href=?_=$grid_href>go to grid | $grid_href</a><p>";

  my $page_session_hr = $reo->get_page_session();
  my $fortune = $page_session_hr->{ 'FORTUNE' } ||= `/usr/games/fortune`;

  my $la = $reo->args_new( PROBA => 123, TEST => 'IS OK' );
  my $ba = $reo->args_back( TESTBACK => 'OOKIES' );

  $text .= "<p><a href=?_=$la>testing link args</a><p>";
  $text .= " | <a href=?_=$ba>back</a>";

  $text .= "<p><hr><p>$fortune<hr>";

  my $bc = $reo->args_here();

  $text .= "<form method=post>";
  $text .= "<input type=hidden name=_ value=$bc>";
  $text .= "input <input name=inp>";
  $text .= "<input type=submit name=button:testbutton>";
  $text .= "</form>";

  my $form = $reo->new_form();

  $text .= "<p><hr><p>";

  my @selarr;
  my $c = 1;

  push @selarr, { KEY => $c++, VALUE => rand(), SELECTED => 0, };
  push @selarr, { KEY => $c++, VALUE => rand(), SELECTED => 0, };
  push @selarr, { KEY => $c++, VALUE => rand(), SELECTED => 1, };
  push @selarr, { KEY => $c++, VALUE => rand(), SELECTED => 0, };
  push @selarr, { KEY => $c++, VALUE => rand(), SELECTED => 0, };

  $text .= $form->begin( NAME => 'TEST_FORM' );
  $text .= $form->input( NAME => 'in1' );
  $text .= $form->cb( NAME => 'cb1' );
  $text .= $form->select( NAME => 'sel1', DATA => \@selarr, ROWS => 7, MULTIPLE => 1 );
  $text .= $form->select( NAME => 'sel2', DATA => \@selarr, ROWS => 1 );
  $text .= $form->button( NAME => 'b1', VALUE => 'testing button' );
  $text .= $form->end();

  $text .= "<p><hr><p>";

  my $form_def = [
                  {
                    NAME  => 'PERSON_NAME',
                    TYPE  => 'CHAR',
                    LABEL => 'Person name',
                    RE    => '^[a-zA-Z ]+$',
                    RE_HELP => 'Needed alphabetical user name',
                  },
                  {
                    NAME  => 'PERSON_SEX',
                    TYPE  => 'SELECT',
                    LABEL => 'Sex',
                    VALUE => [
                             { KEY => '0', VALUE => '- not selected -' },
                             { KEY => '1', VALUE => 'male' },
                             { KEY => '2', VALUE => 'female' },
                             ],
                    SAFE  => 1,
                  },
                  {
                    NAME  => 'PERSON_FILE',
                    TYPE  => 'FILE',
                    LABEL => 'File upload test',
                  },
                  {
                    NAME  => 'PERSON_ACTIVE',
                    TYPE  => 'CHECKBOX',
                    LABEL => 'Active',
                  },
                  {
                    NAME  => 'PERSON_OK',
                    TYPE  => 'BUTTON',
                    LABEL => 'OK',
                    VALUE => 'OK',
                  },
                  {
                    NAME  => 'PERSON_CANCEL',
                    TYPE  => 'BUTTON',
                    LABEL => 'CANCEL',
                    VALUE => 'CANCEL',
                  },

                  ];

  my ( $form_data, $form_errors );
  if( $reo->get_input_button() )
    {
    ( $form_data, $form_errors ) = html_form_engine_import_input( $reo, $form_def, NAME => 'PERSON_FORM' );
    }
  else
    {
    $form_data = $page_session_hr->{ 'FORM_INPUT_DATA' }{ 'PERSON_FORM' };
    }  
  my $form_text = html_form_engine_display( $reo, $form_def, NAME => 'PERSON_FORM', INPUT_DATA => $form_data, INPUT_ERRORS => $form_errors );

  $text .= $form_text;

  if( $reo->get_input_form_name() eq 'PERSON_FORM' and $reo->get_input_button() eq 'PERSON_OK' )
    {
    my $in = $reo->get_user_input();
    my $file_name   = $in->{ 'PERSON_FILE' };
    my $file_handle = $in->{ 'PERSON_FILE' };
    my $file_info   = $in->{ 'PERSON_FILE:UPLOAD_INFO' };
    local $/ = undef;
    my $file_body = <$file_handle>;
    $text .= "<p> file length is: " . length( $file_body ) . "<p>";
    $text .= "<p> file length is: " . Dumper( $file_name, $file_info ) . "<p>";
    }

  my $gi = $reo->args_new( _AN => 'getimg' );
  $text .= "<p><a href=?_=$gi>getting an image</a><p>";

#----------debug-start--------------------------------------------------------

  $text .= "<hr><h1>DEBUG</h1><pre>";
  local $Data::Dumper::sortkeys = 1;
  $text .= Dumper( {
                   'INPUT CGI' => $reo->get_user_input(),
                   'SAFE CGI'  => $reo->get_safe_input(),
                   'REQ HTTP'  => $reo->get_headers(),
                   'PAGE SESS' => $reo->get_page_session(),
                   },
                   "$page_session_hr"
                 );
  $text .= "</pre><hr><p>";
  
#----------debug-end----------------------------------------------------------
  

  return $text;
}

1;
