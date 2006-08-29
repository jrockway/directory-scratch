package Directory::Scratch;

# see POD after __END__.

use warnings;
use strict;

use Carp;
use File::Temp;
use File::Spec;
use File::Copy;
use File::Path;
use Scalar::Util qw(blessed);

use overload '""' => \&base,
  fallback => "yes, fallback";

our $VERSION = '0.07_03';

sub new {
    my $class = shift;
    my $self  ={};
    my %args;

    eval {
	%args = @_;
    };
    if($@){
        croak "Invalid number of arguments to Directory::Scratch->new().";
    }
    
    # explicitly default CLEANUP to 1
    if(!exists $args{CLEANUP}){
	$args{CLEANUP} = 1;
    }
    
    # args to new() are passed on to File::Temp::tempdir
    # TEMPLATE is a special case, since it's positional in File::Temp
    my @file_temp_args;
    foreach my $arg ( keys %args ) {
        if ( $arg eq 'TEMPLATE' ) {
            unshift @file_temp_args, $args{TEMPLATE};
        }
        elsif ( $arg eq 'CLEANUP' || $arg eq 'DIR' ) {
            push @file_temp_args, $arg, $args{$arg};
        }
        else {
            croak qq{Invalid argument "$arg" to Directory::Scratch->new(): }.
		   q{only CLEANUP, DIR, and TEMPLATE are allowed.};
        }
    }

    # fix TEMPLATE to DWIM
    if(exists $args{TEMPLATE} && !exists $args{DIR}){
	push @file_temp_args, (TMPDIR => 1);
    }

    $self->{_parent_args} = \%args;

    my $base = File::Temp::tempdir( @file_temp_args );

    croak "Couldn't create a tempdir: $!" unless -d $base;
    $self->{base} = $base;

    return bless $self, $class;    
}

sub child {
    my $this = shift;
    my $self;
    my %args;

    if ( blessed $this && $this->isa( __PACKAGE__ ) ) {
        # copy args from parent object
        if ( exists $this->{_parent_args} && ref $this->{_parent_args} eq 'HASH' ) {
            %args = %{ $this->{_parent_args} };
        }

        # force the directory end up as a child of the parent, though
        $args{DIR} = $this->base;
	
	$self = Directory::Scratch->new(%args);
    }
    else {
	croak "Invalid reference passed to Directory::Scratch->clone";
    }
    
    return $self;
}

sub base {
    my $self = shift;
    return $self->{base};
}

sub exists {
    my $self = shift;
    my $file = shift;
    my $base = $self->base;
    my $path = File::Spec->catfile($base, $file);
    return $path if -e $path;
    return; # undef otherwise
}

sub mkdir {
    my $self = shift;
    my $dir  = shift;
    my $base = $self->base;

    my @directories = File::Spec->splitdir($dir);
    foreach my $directory (@directories){
	$base = File::Spec->catdir($base, $directory);
	mkdir $base;
	croak "Failed to create $base: $!" if !-d $base;
    }
    
    return $base;
}

sub link {
    my $self = shift;
    my $from = shift;
    my $to   = shift;
    my $base = $self->base;
    
    $from = File::Spec->catfile($base, $from);
    $to   = File::Spec->catfile($base, $to);

    symlink($from, $to) 
      or croak "Couldn't link $from to $to: $!";

    return $to;
}


sub read {
    my $self = shift;
    my $file = shift;
    my $base = $self->base;
    
    $file = File::Spec->catfile($base, $file);
    
    if(wantarray){
	my @lines = read_file($file);
	chomp @lines;
	return @lines;
    }
    else {
	my $scalar = read_file($file);
	chomp $scalar;
	return $scalar;
    }
}

sub write {
    my $self   = shift;
    my $file   = shift;
    my $base   = $self->base;
    
    my $_file; 
    if(!($_file = $self->exists($file))){
	$file = $self->touch($file); # creates parent directories
    }
    else {
	$file = $_file;
    }
    
    my $args = {};

    my (undef, undef, undef, $method) = caller(1);
    
    if(defined $method && $method eq 'Directory::Scratch::append'){
	$args = {append => 1};
    }
    
    my @lines = map { $_ . $/ } @_;
    write_file($file, $args, @lines) or croak "Error writing file: $!";
}

sub append {
    return &write(@_); # magic!
}

sub prepend {
    my( $self, $file ) = splice @_, 0, 2;

    my @directories = (
        File::Spec->splitdir( $self->base ),
        File::Spec->splitdir($file)
    );
    my $basename = pop @directories;


    my $portable_path = File::Spec->catdir(@directories);
    my $portable_file = File::Spec->catdir(@directories, $basename);

    unless ( -d $portable_path ) {
        croak  q{prepend() cannot function without write access to}.
	      qq{"$file"'s directory ($portable_path).};#'
    }

    # create a temporary file in the same directory as the source file so
    # the efficient inode update version of mv/move can be taken advantage of
    my $tmp = File::Temp->new(
        DIR      => $portable_path,
        UNLINK   => 0 # manual unlink in case something goes awry
    );

    my @tmpfile_spec = File::Spec->splitdir( $tmp->filename );
    my $tmpfile      = File::Spec->catdir( @tmpfile_spec );

    File::Copy::move( $portable_file, $tmpfile )
        || croak "Could not temporarily relocate file '$file' to '$tmpfile': $!";

    # catch exceptions then throw another one with an additional message
    eval {
        write_file( $portable_file, {}, @_ );
    };
    if ( $@ ) {
        croak "$@\nThe original file is probably still available in '$tmpfile'";
    }

    # gonna do a size check after all the appending is complete
    my $original_size = -s $tmpfile;
    my $append_size   = -s $portable_file;

    # now copy one file into the other line-by-line
    open(my $input, '<', $tmpfile)
        or croak "Could not open '$tmpfile' (your original file) for reading: $!";
    open( my $output, '>>', $portable_file)
        or croak "Could not open '$portable_file' for appending data from '$tmpfile': $!";

    while ( <$input> ) {
        print $output $_;
    }
    close( $output );
    close( $input );

    # almost, but not quite, entirely portable size comparison
    my $result = undef;
    my $new_size = -s $portable_file;
    my $exp_size = $original_size + $append_size;
    if ( $new_size == $exp_size ) {
        $result = 1;
    }
    else {
        croak "The new file's size did not match the expected size ($exp_size).\n" .
              "  * original file (size: $original_size): $tmpfile\n" .
              "  * prepended file (size: $new_size): $portable_file";
    }

    unlink $tmpfile;
    return $result;
}

sub tempfile {
    my $self = shift;
    my $path = shift;
    if(!defined $path){
	$path = $self->base;
    }
    else {
	$path = File::Spec->catfile($self->base, $path);
    }
    
    return File::Temp::tempfile( DIR => $path );
}

sub touch {
    my $self = shift;
    my $file = shift;
    my $base = $self->base;
    
    # create parent dir
    my @directories = File::Spec->splitdir($file);
    pop @directories; # pop off filename

    my $parents = File::Spec->catdir(@directories);
    $self->mkdir($parents) if $parents;
    
    my $path = File::Spec->catfile($base, $file);

    open(my $fh, '>', $path)
        or croak "Failed to open $path: $!";

    # behave differently when called as openfile()
    my (undef, undef, undef, $method) = caller(1);
    if ( $method && $method eq 'Directory::Scratch::openfile' ) {
        return $fh;
    }

    # no need to copy @_, just use it directly for aliasing goodness
    if ( @_ > 0 ) {
        map {
            print {$fh} $_, $/ or croak "Write error: $!"
        } @_;
        close($fh) or croak "Failed to close $path: $!";
    }
    return $path;
}

sub openfile {
    return &touch(@_); # more trickery.
}

sub ls {
    my $self = shift;
    my $dir = shift;
    my $base = $self->base;
    my @result;

    $dir ||= ''; # silences a lot of warnings in File::Spec

    if(!$self->exists($dir)){
	return (); # doesn't exist, return the empty list
    }
    
    $base = File::Spec->catdir($base, $dir);
    
    # shoudln't be using this with files; but allow anyway
    if(!-d $self->exists($dir)){
	return ($dir);
    }
    
    opendir my $dh, $base or croak "Failed to open directory $base: $!";
    while(my $file = readdir $dh){
	next if $file eq '.';
	next if $file eq '..';
	
	my $full  = File::Spec->catfile($base, $file);
	my $short;
	if(!$dir || $dir eq '/'){
	    $short = $file;
	}
	else {
	    $short = File::Spec->catfile($dir, $file);
	}
	if(-d $full){
	    push @result, $self->ls($short);
	}
	push @result, $short;
    }
    closedir $dh;
    
    return @result;
}

sub delete {
    my $self = shift;
    my $path = shift;
    my $base = $self->base;

    $path = File::Spec->catdir($base, $path);
    
    croak "No such file or directory '$path'" if !-e $path;
    
    if(-d _){ # reuse stat() from -e test
	return (scalar rmdir $path or croak "Couldn't remove directory $path: $!");
    }
    else {
	return (scalar unlink $path or croak "Couldn't unlink $path: $!");
    }
    
}

sub cleanup {
    my $self = shift;
    my $base = $self->{base};

    # see File::Path
    my @errors;
    local $SIG{__WARN__} = sub {
        push @errors, [ @_ ];
    };

    File::Path::rmtree( $base );

    if ( @errors > 0 ) {
        croak "cleanup() method failed: $!\n@errors";
    }

    return 1;
}

# randfile() needs to remember if it has loaded String::Random
# and whether or not it succeeded between calls

sub randfile {
    my $self = shift;

    my( $min, $max ) = ( 1024, 131072 );
    if ( @_ == 2 ) {
        ($min, $max) = @_;
    }
    elsif ( @_ == 1 ) {
        $max = $_[0];
        $min = int(rand($max)) if ( $min > $max );
    }

    confess "Cannot request a maximum length < 128 with randfile()."
        if ( $max < 1 );

    my( $fh, $name ) = $self->tempfile;

    eval {
    # allow tests to control loading of String::Random so both
    # methods can be tested
	croak "skipping load of String::Random"
        if exists $self->{skip_string_random};
	require String::Random;
    };

    # string::random was required OK
    if ( !$@ ) {
        my $rand = String::Random->new();
        print {$fh} $rand->randregex( ".{$min,$max}" );
    }
    
    # apparently we don't have string::random
    else {
        # cheesy approach
        my $target_len = $max;
        if ( $min != $max ) {
            $target_len = rand($max);
            while ( $target_len < $min || $target_len > $max ) {
                $target_len = rand($max)
            }
        }
        my $length = 0;
        while ( $length < $target_len ) {
            my $str = rand() . $/;
            $length += length($str);

            if ( $length > $max ) {
                my $chop = $length - $max;
                substr $str, 0, $chop, '';
            }
            print {$fh} $str;
        }
    }
    close($fh);
    
    return $name;
}

# think of these as File::Slurp::Lite
# it happens to use Perl's buffered IO while IO::Slurp uses sys*
sub read_file {
    my $file = shift;
    my $args = shift;

    my $binmode = $args->{binmode};

    my( $buffer, @buffer );

    open my $fh, '<', $file
      or croak "Could not open '$file' for reading: $!";

    if($binmode){
	binmode $fh, $binmode 
	  or croak "Could not set binmode $binmode on '$file': $!";
    }

    if (wantarray) {
        @buffer = <$fh>;
    }
    else {
        $buffer = do { local $/; <$fh> };
    }
    close( $fh );

    return wantarray ? @buffer : $buffer;
}

sub write_file {
    my $file = shift;
    my $args = shift;
    
    my $fh;
    my $append  = $args->{append};
    my $binmode = $args->{binmode};
    
    if ($append) {
        open $fh, '>>', $file
	  or croak "Could not open '$file' for appending: $!";
    }
    else {
        open $fh, '>', $file
	  or croak "Could not open '$file' for writing: $!";
    }
    
    if ($binmode) {
        binmode $fh, $binmode
	  or croak "Could not set binmode $binmode on $file: $!";
    }
    
    my $list = \@_;

    if ( ref $_[0] eq 'ARRAY' ) {
        $list = $_[0];
    }

    if ($binmode) {
	# no output record separator
        print {$fh} @$list;
    }
    else {
        foreach ( @$list ) {
            chomp;
            print {$fh} "$_$/" or croak "write error: $!";
        }
    }
    close $fh;
}

# throw a warning if CLEANUP is off and cleanup hasn't been called
sub DESTROY {
    my $self = shift;
    if ( $self->{args} && exists $self->{args}{CLEANUP} ) {
        carp "Not cleaning up files in $self->{base}."
            unless ( $self->{args}{CLEANUP} || $self->{called_cleanup} );
    }
    
    unlink $self->base;
}

1;

__END__

=head1 NAME

Directory::Scratch - Easy-to-use self-cleaning scratch space.

=head1 VERSION

Version 0.07_03

=cut

=head1 SYNOPSIS

When writing test suites for modules that operate on files, it's often
inconvenient to correctly create a platform-independent temporary
storage space, manipulate files inside it, then clean it up when the
test exits.  The inconvenience usually results in tests that don't work
everwhere, or worse, no tests at all.

This module aims to eliminate that problem by making it easy to do
things right.

Example:

    use Directory::Scratch;

    my $temp = Directory::Scratch->new();
    my $dir  = $temp->mkdir('foo/bar');
    my @lines= qw(This is a file with lots of lines);
    my $file = $temp->touch('foo/bar/baz', @lines);

    my $fh = openfile($file);
    print {$fh} "Here is another line.\n";
    close $fh;

    $temp->delete('foo/bar/baz');

    undef $temp; # everything else is removed

    # Directory::Scratch objects stringify to base
    $temp->touch('foo');
    ok(-e "$temp/foo");  # /tmp/xYz837/foo should exist 

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

    my $temp = Directory::Scratch->new;
    my $another = $temp->new(); # will be under $temp

    # some File::Temp arguments get passed through (may be less portable)
    my $temp = Directory::Scratch->new(
        DIR      => '/var/tmp',       # be specific about where your files go
        CLEANUP  => 0,                # turn off automatic cleanup
        TEMPLATE => 'ScratchDirXXXX', # specify a template for the dirname
    );

If C<DIR>, C<CLEANUP>, or C<TEMPLATE> are omitted, reasonable defaults
are selected.  C<CLEANUP> is on by default, and C<DIR> is set to C<File::Spec->tmpdir>;

=head2 child

Creates a new C<Directory::Scratch> directory inside the current
C<base>, copying TEMPLATE and CLEANUP options from the current
instance.  Returns a C<Directory::Scratch> object.

=head2 base

Returns the full path of the temporary directory.

=head2 mkdir

Creates a directory (and its parents, if necessary) inside the
temporary directory and returns its name.  Any leading C</> on the
directory name is ignored; all directories are created inside the
C<base>.

The full path of this directory is returned if the operation is
successful, otherwise an exception is thrown.

=head2 tempfile([$path])

Returns an empty filehandle + filename in $path.  If $path is omitted,
the base directory is assumed.

See L<File::Temp::tempfile|File::Temp/FUNCTIONS/tempfile>.

    my($fh,$name) = $scratch->tempfile;

=head2 touch($filename, [@lines])

Creates a file named C<$filename>, optionally containing the elements
of C<@lines> separated by C<\n> characters.  

The full path of the new file is returned if the operation is
successful, an exception is thrown otherwise.

=head2 openfile($filename)

Just like touch(), only it doesn't take any data and returns a filehandle
instead of the file path.   It's up to you to take care of flushing/closing.

=head2 exists($file)

Returns the file's real (system) path if $file exists, undefined
otherwise.

=head2 read($file)

Returns the contents of $file.  In array context, returns a list of
chompped lines.  In scalar context, returns a chomped representation
of the entire file.

=head2 write($file, @lines)

Replaces the contents of file with @lines.  Each line will be ended
with a C<\n>.  The file will be created if necessary.

=head2 append($file, @lines)

Appends @lines to $file, as per C<write>.

=head2 prepend($file, @lines)

Backs up $file, writes the @lines to its original name, then appends
the original file to that.

=head2 randfile()

Generates a file with random string data in it.   If String::Random is
available, it will be used to generate the file's data.   If it's not, a very
simplistic builtin generator is used (calls rand() a lot of times).   Takes 0,
1, or 2 arguments - default size, max size, or size range.

A max size of 0 will cause an exception to be thrown.

    my $file = $temp->randfile(); # size is between 1024 and 131072
    my $file = $temp->randfile( 4192 ); # size is below 4129

    # big files are probably very slow
    my $file = $temp->randfile( 1000000, 4000000 ); # between 1000000 and 4000000

=head2 link($from, $to)

Symlinks a file in the temporary directory to another file in the
temporary directory.

=head2 ls([$path])

Returns a list (in no particular order) of all files below C<$path>.
If C<$path> is omitted, the root is assumed.

=head2 delete

Deletes the named file or directory.

If the path is removed successfully, the method returns true.
Otherwise, an exception is thrown.

(Note: delete means C<unlink> for a file and C<rmdir> for a directory.
C<delete>-ing an unempty directory is an error.)

=head2 cleanup

Forces an immediate cleanup of the current object's directory.   See File::Path's
rmtree().

=head2 read_file($path, \%args) [INTERNAL]

A tiny implementation similar to IO::Slurp's read_file, but lighter
and doesn't use sysread().  Accepts "binmode" as an argument, to set a
binmode on the file.

=head2 write_file [INTERNAL]

See above.

=head1 RATIONALE 

Why a module for this?  Before the module, my tests usually looked
like this:

    use Test::More tests => 42;
    use Foo::Bar;

    my $TESTDIR = "/tmp/test.$$";
    my $FILE    = "$TESTDIR/file";
    mkdir $TESTDIR;
    open(my $file, '>', $FILE) or die $!;
    print {$file} "test\n" or die $!;
    close($file) or die $!;

    ok(-e $FILE);

    # tests
 
    END { `rm -rf $TESTDIR` }

Nasty.  (What if rm doesn't work?  What if the test dies half way
through?  What if /tmp doesn't exist? What if C</> isn't the path
separator?  etc., etc.)

Now they look like this:

    use Foo::Bar;
    use Directory::Scratch;
    use Test::More tests => 42;

    my  $tmp = Directory::Scratch->new;
    my $FILE = $tmp->touch('file', "test");

    ok(-e $FILE)

    # tests

Portable.  Readable.  Clean.  

Much better.

=head2 TO THE NITPICKERS

Many people have complained that the above rationale section isn't
good enough.  I've never seen another module that even I<has> a
rationale section, but whatever.  

Here's how to do the same thing with File::Temp:

    use Foo::Bar;
    use File::Temp qw(tempdir);
    use File::Spec::Functions qw(catfile);
    use Test::More tests => 42;

    my $TMPDIR = tempdir(CLEANUP => 1, TMPDIR => 1);
    my $FILE   = catfile($TMPDIR, 'file');

    open my $fh, '>', $file or die $!;
    print {$fh} "test\n" or die $!;
    close $fh or die $!;

    ok(-e $FILE);

    # tests


I find Directory::Scratch easier to use, but this is Perl, so
TMTOWTDI.  Please use what you prefer.  CPAN isn't a popularity
contest.

=head1 PATCHES

Commentary, patches, etc. are most welcome.  If you send a patch,
try patching the subversion version available from:

L<svn://svn.jrock.us/cpan_modules/Directory-Scratch>

=head1 SEE ALSO

 L<File::Temp>
 L<File::Path>
 L<File::Spec>

=head1 BUGS

Please report any bugs or feature through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Directory-Scratch>.

=head1 ACKNOWLEDGEMENTS

Thanks to Al Tobey (TOBEYA) for some excellent patches, notably:

=over 4

=item C<child>

=item Random Files (C<randfile>)

=item C<tempfile>

=item C<openfile>

=item C<readfile>, C<writefile>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2006 Jonathan Rockway, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
