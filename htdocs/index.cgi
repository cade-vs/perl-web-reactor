#!/usr/bin/perl
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
##  CGI start script example: the PSGI application run by Plack's CGI handler,
##  see the SYNOPSIS in Web::Reactor for the PSGI (recommended) start
##
##############################################################################
use strict;
use lib '/opt/perl/reactor/lib'; # if Web::Reactor is not installed system-wide
use Web::Reactor;
use Plack::Handler::CGI;

my $ROOT = "/opt/reactor";

my %cfg = (
          'APP_NAME'      => 'demo',
          'APP_ROOT'      => "$ROOT/demo/",
          'LIB_DIRS'      => [ "$ROOT/demo/lib/" ],
          'HTML_DIRS'     => [ "$ROOT/demo/html/" ],
          'SESS_VAR_DIR'  => "$ROOT/demo/var/sess/",
          'REO_ACT_CLASS' => 'Web::Reactor::Actions::Packages', # actions from LIB_DIRS packages
          'LANG'          => 'bg',
          'DEBUG'         => 4,
          );

my $app = sub { return Web::Reactor->new( shift(), \%cfg )->run() };

Plack::Handler::CGI->new()->run( $app );

###EOF########################################################################
