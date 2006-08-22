#!/usr/bin/perl
# 09-new_on_object.t 
# Copyright (c) 2006 Al Tobey <tobeya@cpan.org>
use Directory::Scratch;
use Test::More tests=>11;
use File::Spec;
use strict;
use warnings;

my $t = Directory::Scratch->new;

can_ok( $t, 'new' );

ok( my $sub_t = $t->new, "Call new on a parent Directory::Scratch object." );

my @parent = File::Spec->splitdir( $t->base );
my @child  = File::Spec->splitdir( $sub_t->base );

ok( @child > @parent, "Child should have more nodes than the parent." );
my $subdir = pop @child;

ok( @child == @parent, "Child with last element popped should == parent." );

#diag( "chdir into the parent directory" );
chdir($t->base);

ok( -d $subdir, "child subdirectory basename exists under parent" );

ok( my $sub_sub_t = $sub_t->new, "create a grandchild" );

my $subsub_dir = $sub_sub_t->base;
ok( -d $subsub_dir, "grandchild directory exists" );

ok( $sub_t->cleanup, "call cleanup() on the child" );

ok( !-d $subsub_dir, "grandchild no longer exists after cleanup()" );
ok( !-d $subdir, "child no longer exists after cleanup()" );
ok( -d $t->base, "parent still exists after cleanup()" );

