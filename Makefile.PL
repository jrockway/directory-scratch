use strict;
use warnings;
use inc::Module::Install;

name 'Directory-Scratch';
all_from 'lib/Directory/Scratch.pm';

requires 
  'File::Temp'  => 0,
  'File::Path'  => 0,
  'File::Slurp' => '9999.12',
  'Path::Class' => 0,
  'File::Copy'  => 0,
  'File::Spec'  => 0,
  'File::stat'  => 0, # core
  'Carp'        => 0;

build_requires
  'Test::More' => 0;

features 
  'String::Random for random files' => 
  ['String::Random' => 0];

par_base 'JROCKWAY';

tests 't/*/*.t';
WriteAll;
