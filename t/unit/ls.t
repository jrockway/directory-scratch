#!/usr/bin/perl
# ls.t 
# Copyright (c) 2006 Jonathan Rockway <jrockway@cpan.org>

use Test::More tests => 11;
use Directory::Scratch;
use strict;
use warnings;

my $tmp = Directory::Scratch->new;
ok($tmp, 'created $tmp');

ok($tmp->touch('foo'), 'foo');
ok($tmp->mkdir('bar/baz'), 'bar/baz');
ok($tmp->touch('bar/quux'), 'bar/quux');
ok($tmp->touch('bar/baz/quux'), 'bar/baz/quux');

my @files = sort $tmp->ls;
is(scalar @files, 5, 'got 5 files under /');
is_deeply(\@files, [qw(bar bar/baz bar/baz/quux bar/quux foo)]);

@files = sort $tmp->ls('this filename is fake');
is(scalar @files, 0, 'no fake files [scalar]');
{ no warnings;
ok(@files == (), 'no fake files [list]');
}
@files = sort $tmp->ls('foo');
is_deeply(\@files, [qw(foo)], 'single file = list');

@files = sort $tmp->ls('bar/baz');
is_deeply(\@files, [qw(bar/baz/quux)], 'got bar/baz/quux in bar/baz');
