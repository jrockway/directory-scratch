#!/usr/bin/perl
# invalid_directory.t 
# Copyright (c) 2006 Jonathan Rockway <jrockway@cpan.org>

use Test::More tests => 3;
use Directory::Scratch;
use strict;
use warnings;

my $tmp = Directory::Scratch->new;

ok($tmp->touch('foo'), 'create a file called foo');

eval {
    $tmp->mkdir('foo');
};
ok($@, "can't create a directory with the same name as a file");

eval {
    # make mkdir not work
    no warnings 'redefine';
    *Path::Class::Dir::mkpath = sub { return };
    $tmp->mkdir('bar');
};
ok($@, "can't create a directory when mkdir doesn't work");
