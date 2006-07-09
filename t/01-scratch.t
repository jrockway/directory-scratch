#!/usr/bin/perl
# 01-scratch.t 
# Copyright (c) 2006 Jonathan Rockway <jrockway@cpan.org>

use Test::More tests => 11;
use Directory::Scratch;

my $temp = Directory::Scratch->new;
my $base = $temp->base;

# create (4)
ok($temp);
ok(-e $base, 'tempdir exists');
ok(-d _, 'tempdir is a directory');
ok(-w _, 'tempdir is writable');

# mkdir (3)
my $dir = $temp->mkdir('foo/bar/baz');
ok($dir =~ m{foo.bar.baz.?$}, 'dir has a reasonable name');
ok(-e $dir, 'dir exists');
ok(-d $dir, 'dir is a directory');

# touch (2)
my $file = $temp->touch('foo/bar/baz/bat', qw{Here are some lines});
ok(-e $file, 'file exists');
ok(-r $file, 'file readable');

# delete (2)
$temp->delete('foo/bar/baz/bat');
ok(!-e $file, 'file went away');
$temp->delete('foo/bar/baz');
ok(!-e $dir, 'dir went away');
