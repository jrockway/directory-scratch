use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Directory::Scratch',
    AUTHOR              => 'Jonathan Rockway <jrockway@cpan.org>',
    VERSION_FROM        => 'lib/Directory/Scratch.pm',
    ABSTRACT_FROM       => 'lib/Directory/Scratch.pm',
    PL_FILES            => {},
    PREREQ_PM => {
		  'Test::More'  => 0,
		  'File::Spec'  => 0,
		  'File::Temp'  => 0,
		  'File::Slurp' => 0,
		 },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Directory-Scratch-*' },
);
