package Directory::Scratch;

# see POD after __END__.

use warnings;
use strict;
use File::Temp;
use File::Spec;
use Carp;

our $VERSION = '0.02';

sub new {
    my $class = shift;
    my $self  = {};
    
    my $dir = File::Temp::tempdir( CLEANUP => 1 );

    croak "Couldn't create a tempdir: $!"
      if !-e $dir || !-d _;
    $self->{base} = $dir;

    bless $self, $class;    
    return $self;
}

sub base {
    my $self = shift;
    return $self->{base};
}

sub mkdir {
    my $self = shift;
    my $dir  = shift;
    my $base = $self->base;

    my @directories = File::Spec->splitdir($dir);
    foreach my $directory (@directories){
	$base = File::Spec->catdir($base, $directory);
	mkdir $base;
	
	die "Failed to create $base: $!"
	  if !-d $base;
    }
    
    return $base;
}

sub touch {
    my $self = shift;
    my $path = shift;
    my $base = $self->base;
    my @lines;

    $path = File::Spec->catdir($base, $path);

    open(my $fh, '>', $path) or die "Failed to open $path: $!";
    map {print {$fh} "$_\n"  or die "Write error: $!"} @lines if @lines;
    close($fh)               or die "Failed to close $path: $!";
    
    return $path;
}

sub delete {
    my $self = shift;
    my $path = shift;
    my $base = $self->base;

    $path = File::Spec->catdir($base, $path);
    
    die "No such file or directory $path" if(!-e $path);
    if(-d _){
	rmdir $path or die "Couldn't remove directory $path: $!";
    }
    else {
	unlink $path or die "Couldn't unlink $path: $!";
    }
    
    return;
}

1;
__END__

=head1 NAME

Directory::Scratch - Easy-to-use self-cleaning scratch space.

=head1 VERSION

Version 0.02

=cut

=head1 SYNOPSIS

When writing test suites for modules that operate on files, it's often
inconvenient to correctly create a platform-independent temporary
storage space, manipulate files inside it, then clean it up when the
test exits.

This module aims to eliminate the problem by making it easy to do
things right.

Example:

    use Directory::Scratch;

    my $temp = Directory::Scratch->new();
    my $dir  = $temp->mkdir('foo/bar');
    my @lines= qw(This is a file with lots of lines);
    my $file = $temp->touch('foo/bar/baz', @lines);

    open(my $fh, '<', $file);
    print {$fh} "Here is another line.\n";
    close $fh;

    $temp->delete('foo/bar/baz');

    undef $temp; # everything else is removed

=head1 METHODS

The file arguments to these methods are always relative to the
temporary directory.  If you specify C<touch('/etc/passwd')>, then a
file called C</tmp/whatever/etc/passwd> will be created instead.

This means that the program's PWD is ignored (for these methods), and
that a leading C</> on the filename is meaningless.

=head2 new

Creates a new temporary directory (via File::Temp and its defaults).
When the object returned by this method goes out of scope, the
directory and its contents are removed.

=head2 base

Returns the full path of the temporary directory.

=head2 mkdir

Creates a directory (and its parents, if necessary) inside the
temporary directory and returns its name.  Any leading C</> on the
directory name is ignored; all directories are created inside the
C<base>.

The full path of this directory is returned if the operation is
successful, otherwise an exception is thrown.

=head2 touch($filename, [@lines])

Creates a file named C<$filename>, optionally containing the elements
of C<@lines> separated by C<\n> characters.  

The full path of the new file is returned if the operation is
successful, an exception is thrown otherwise.

=head2 delete

Deletes the named file or directory.

If the path is removed successfully, the method returns.  Otherwise,
an exception is thrown.

(Note: delete means C<unlink> for a file and C<rmdir> for a directory.
C<delete>-ing an unempty directory is an error.)

=head1 RATIONALE 

Why a module for this?  Before the module, my tests usually looked
like this:

     use Test::More tests => 42;
     use Foo::Bar;

     my $TESTDIR = "/tmp/test.$$";
     my $FILE    = "$TESTDIR/file";
     mkdir $TESTDIR;
     open(my $file, '>', $FILE);
     print {$file} "test\n";
     close($file);
     ok(-e $FILE);

     # tests

     END { `rm -rf $TESTDIR` }

Nasty.  (What if rm doesn't work?  What if the test dies half way
through?  What if /tmp doesn't exist? What if C</> isn't the path
separator?  etc., etc.)

Now they look like this:

     use Foo::Bar;
     use Directory::Scratch;
      
     my  $tmp = Directory::Scratch->new;
     my $FILE = $tmp->touch('file');
     ok(-e $FILE)

     # tests

Portable.  Readable.  Clean.  

Ahh, much better.

=head1 TODO

Methods like C<cat> and C<ls> might make sense.  If you need them,
I'll add them for you.  Just send me an e-mail or open a problem
ticket on CPAN's RT.  (Link below.)

=head1 PATCHES

Commentary, patches, etc. are of course welcome, as well.

=head1 BUGS

Please report any bugs or feature through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Directory-Scratch>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Directory::Scratch

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Directory-Scratch>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Directory-Scratch>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Directory-Scratch>

=item * CPAN Search

L<http://search.cpan.org/dist/Directory-Scratch>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2006 Jonathan Rockway, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
