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
		  'File::Path'  => 0,
		  'File::Copy'  => 0,
		  'Symbol'      => 0,
		  'Carp'        => 0,
		 },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Directory-Scratch-*' },
);

sub MY::postamble {

    return <<"EOP";
cover: all
\tcover -delete
\tHARNESS_PERL_SWITCHES=-MDevel::Cover \$(MAKE) test
\tcover
EOP

}
