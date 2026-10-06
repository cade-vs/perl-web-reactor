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
##  demo script: prints an html_hbox() box with a format
##
##############################################################################
use strict;
use lib '../lib';
use lib 'lib';
use Web::Reactor;
use Data::Dumper;
use Web::Reactor::HTML::Layout;


print Dumper( [ html_hbox( "ctl:<,,>", 123, undef, 789 ) ] );
