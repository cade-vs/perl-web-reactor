#!/usr/bin/perl
##############################################################################
##
##  Web::Reactor README.md and README check
##  Copyright (c) 2013-2026 Vladi Belperchinov-Shabanski "Cade"
##        <cade@noxrun.com>
##  http://cade.noxrun.com
##
##  LICENSE: GPLv2
##  https://github.com/cade-vs/perl-web-reactor
##
##############################################################################
##
##  README.md and README are generated from the Web::Reactor POD by fix-md.sh
##  (pod2markdown and pod2text < lib/Web/Reactor.pm), this checks they are
##  not stale. skipped without Pod::Markdown.
##
##############################################################################
use strict;
use Test::More;
use File::Basename;

eval { require Pod::Markdown; 1 } or plan skip_all => 'Pod::Markdown is not installed';

my $dist = dirname( __FILE__ ) . '/..';

my $md;
my $parser = Pod::Markdown->new();
$parser->output_string( \$md );
$parser->parse_file( "$dist/lib/Web/Reactor.pm" );

open( my $fh, '<:raw', "$dist/README.md" ) or die "cannot read [$dist/README.md]: $!\n";
my $readme = do { local $/; <$fh> };
close( $fh );

ok( $readme eq $md, 'README.md matches the Web::Reactor POD, run fix-md.sh if not' );

require Pod::Text;
my $txt;
my $pt = Pod::Text->new();
$pt->output_string( \$txt );
$pt->parse_file( "$dist/lib/Web/Reactor.pm" );

open( $fh, '<:raw', "$dist/README" ) or die "cannot read [$dist/README]: $!\n";
my $readme_txt = do { local $/; <$fh> };
close( $fh );

ok( $readme_txt eq $txt, 'README matches the Web::Reactor POD, run fix-md.sh if not' );

done_testing();

###EOF########################################################################
