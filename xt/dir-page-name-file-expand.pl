#!/usr/bin/perl
use strict;

my $pn = 'users/admin/prefs';

my $dirs = [ '/usr/local/html', '/home/apps/remy', '/shared/misc/' ];

my $lang = 'gr';
my @lang = ( 'default' );
unshift @lang, $lang if $lang;

my @pn = grep { $_ } split /\/+/, $pn;

my @dirx; # expanded with pn/pn/pn etc...

for my $ln ( @lang )
  {
  my @dx;
  my $pp;
  for my $p ( undef, @pn )
    {
    $pp .= $p . '/';
    for my $dir ( reverse @$dirs )
      {
      push @dx, "$dir/$ln/$pp";
      }
    }
  push @dirx, reverse @dx;
  }

print "$_\n" for @dirx;
