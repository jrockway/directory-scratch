#!/usr/bin/perl
# Makefile.PL
# Copyright (c) 2006 Jonathan Rockway <jrockway@cpan.org>

use strict;
use warnings;
use inc::Module::Install;

name('Directory-Scratch');
author('Jonathan Rockway <jrockway@cpan.org');
version_from('lib/Directory/Scratch.pm');
abstract_from('lib/Directory/Scratch.pm');
license('Perl');
include('ExtUtils::AutoInstall');

requires(
	 'File::Temp'  => 0,
	 'File::Path'  => 0,
	 'File::Slurp' => 0,
	 'Path::Class' => 0,
	 'File::Copy'  => 0,
	 'Carp'        => 0,
	);
build_requires(
	 'Test::More' => 0
	);
features(
	 'String::Random for random files' => 
	    ['String::Random' => 0]
	);

tests('t/*/*.t');
auto_install();
WriteAll();
