#!/usr/bin/perl
# touch.t 
# Copyright (c) 2006 Jonathan Rockway <jrockway@cpan.org>

use Test::More tests => 8;
use Directory::Scratch;
use strict;
use warnings;
use File::Slurp qw(read_file);

my $tmp = Directory::Scratch->new;
ok($tmp, 'created $tmp');
ok($tmp->touch('foo', qw(foo bar baz)), 'created foo');
ok($tmp->exists('foo'), 'foo exists');
my @lines = read_file($tmp->exists('foo')->stringify);
is(chomp @lines, 3, 'right number of lines');
is_deeply(\@lines, [qw(foo bar baz)], 'foo has correct contents');
ok($tmp->touch('bar'), 'created bar');
ok($tmp->exists('bar'), 'bar exists');
ok(!read_file($tmp->exists('bar')->stringify), 'bar has no content');
