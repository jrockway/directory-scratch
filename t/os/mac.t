#!/usr/bin/perl
# mac.t 
# Copyright (c) 2006 Jonathan Rockway <jrockway@cpan.org>

use Test::More tests => 3;
use Directory::Scratch qw(Mac);
use Path::Class;

my $tmp = Directory::Scratch->new;
ok($tmp, 'created $tmp');
my $file = $tmp->touch("foo:bar:baz");
ok(-e $file, "$file (foo:bar:baz) exists");
my @files = sort $tmp->ls;
is_deeply(\@files, [sort (dir('foo'), dir(qw'foo bar'), dir(qw'foo bar baz'))]);

