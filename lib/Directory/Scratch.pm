package Directory::Scratch;

# see POD after __END__.

use warnings;
use strict;
use Carp;
use File::Temp;
use File::Copy;
use Path::Class qw(dir file);
use File::Slurp qw(read_file write_file);

my $platform = 'Unix';
use Scalar::Util qw(blessed);

use overload q{""} => \&base,
  fallback => "yes, fallback";


our $VERSION = '0.09';

# allow the user to specify which OS's semantics he wants to use
# if platform is undef, then we won't do any translation at all
sub import {
    my $class = shift;
    return unless @_;
    $platform = shift;
    eval("require File::Spec::$platform") if $platform;
    croak "Don't know how to deal with platform '$platform'" if $@;
    return $platform;
}

# create an instance
sub new {
    my $class = shift;
    my $self  ={};
    my %args;

    eval { %args = @_ };
    croak 'Invalid number of arguments to Directory::Scratch->new' if $@;
    
    # explicitly default CLEANUP to 1
    $args{CLEANUP} = 1 unless exists $args{CLEANUP};
    
    # TEMPLATE is a special case, since it's positional in File::Temp
    my @file_temp_args;

    # convert DIR from their format to a Path::Class
    $args{DIR} = Path::Class::foreign_dir($platform, $args{DIR}) if $args{DIR};
    
    # change our arg format to one that File::Temp::tempdir understands
    for(qw(CLEANUP DIR)){
	push @file_temp_args, ($_ => $args{$_}) if $args{$_};
    }
    
    # this is a positional argument, not a named argument
    unshift @file_temp_args, $args{TEMPLATE} if $args{TEMPLATE};
    
    # fix TEMPLATE to do what we mean; if TEMPLATE is set then TMPDIR
    # needs to be set also
    push @file_temp_args, (TMPDIR => 1) if($args{TEMPLATE} && !$args{DIR});
    
    # keep this around for C<child>
    $self->{args} = \%args;

    # create the directory!
    my $base = dir(File::Temp::tempdir(@file_temp_args));
    croak "Couldn't create a tempdir: $!" unless -d $base;
    $self->{base} = $base;

    bless $self, $class;    
    $self->platform($platform || $args{platform}); # set platform for this instance
    return $self;
}

sub child {
    my $self = shift;
    my %args;
    
    croak 'Invalid reference passed to Directory::Scratch->child'
      if !blessed $self || !$self->isa(__PACKAGE__);
    
    # copy args from parent object
    %args = %{$self->{_args}} if exists $self->{_args};
    
    # force the directory end up as a child of the parent, though
    $args{DIR} = $self->base->stringify;
    
    return Directory::Scratch->new(%args);
}

sub base {
    my $self = shift;
    return $self->{base};#->stringify;
}

sub platform {
    my $self = shift;
    my $desired = shift;

    if($desired){
	eval {
	    require "File/Spec/$desired.pm";
	};
	croak "Unknown platform '$desired'" if $@;
	$self->{platform} = $desired;
    }
    
    return $self->{platform};
}

# make Path::Class's foreign_* respect the instance's desired platform
sub _foreign_file {
    my $self = shift;
    my $platform = $self->platform;

    if($platform){
	return Path::Class::file(Path::Class::foreign_file($platform, @_));
    }
    else {
	return Path::Class::file(@_);
    }
}

sub _foreign_dir {
    my $self = shift;
    my $platform = $self->platform;

    if($platform){
	return Path::Class::dir(Path::Class::foreign_dir($platform, @_));
    }
    else {
	return Path::Class::dir(@_);
    }
}

sub exists {
    my $self = shift;
    my $file = shift;
    my $base = $self->base;
    my $path = $self->_foreign_file($base, $file);
    return dir($path) if -d $path;
    return $path if -e $path;
    return; # undef otherwise
}

sub mkdir {
    my $self = shift;
    my $dir  = shift;
    my $base = $self->base;
    $dir = $self->_foreign_dir($base, $dir);
    $dir->mkpath;
    return $dir if (-e $dir && -d $dir);
    croak "Error creating $dir: $!";
}

sub link {
    my $self = shift;
    my $from = shift;
    my $to   = shift;
    my $base = $self->base;

    croak "Symlinks are not supported on MSWin32" 
      if $^O eq 'MSWin32';

    $from = $self->_foreign_file($base, $from);
    $to   = $self->_foreign_file($base, $to);

    symlink($from, $to) 
      or croak "Couldn't link $from to $to: $!";
    
    return $to;
}


sub read {
    my $self = shift;
    my $file = shift;
    my $base = $self->base;
    
    $file = $self->_foreign_file($base, $file);
    
    if(wantarray){
	my @lines = read_file($file->stringify);
	chomp @lines;
	return @lines;
    }
    else {
	my $scalar = read_file($file->stringify);
	chomp $scalar;
	return $scalar;
    }
}

sub write {
    my $self = shift;
    my $file = shift;
    my $base = $self->base;
    
    my $path = $self->_foreign_file($base, $file);
    $path->parent->mkpath;
    croak "Couldn't create parent dir ". $path->parent. ": $!"
      unless -e $path->parent;
    
    # figure out if we're "write" or "append"
    my (undef, undef, undef, $method) = caller(1);

    my $args;
    if(defined $method && $method eq 'Directory::Scratch::append'){
	$args->{append} = 1;
	write_file($path->stringify, $args, map { $_. ($, || "\n") } @_) 
	  or croak "Error writing file: $!";
    }
    else { # (cut'n'paste)++
	write_file($path->stringify, map { $_. ($, || "\n") } @_) 
	  or croak "Error writing file: $!";
    }
    return 1;
}

sub append {
    return &write(@_); # magic!
}

sub tempfile {
    my $self = shift;
    my $path = shift;

    if(!defined $path){
	$path = $self->base;
    }
    else {
	$path = $self->_foreign_dir($self->base, $path);
    }
    
    my ($fh, $filename) =  File::Temp::tempfile( DIR => $path );
    $filename = file($filename); # "class"ify the file
    if(wantarray){
	return ($fh, $filename);
    }
    
    # XXX: I don't know why you would want to do this...
    return $fh;
}

sub openfile {
    my $self = shift;
    my $file = shift;
    my $base = $self->base;

    my $path = $self->_foreign_file($base, $file);
    $path->dir->mkpath;
    croak 'Parent directory '. $path->dir. 
      ' does not exist, and could not be created' 
	unless -d $path->dir;
    
    open(my $fh, '+>', $path) or croak "Failed to open $path: $!"; 
    return ($fh, $path) if(wantarray);
    return $fh;
}

sub touch {
    my $self = shift;
    my $file = shift;
    
    local $, = $, || "\n"; 
    my ($fh, $path) = $self->openfile($file);
    
    write_file($fh, map { $_. ($, || "\n") } @_) 
      or croak "Write error to $path: $!";
    return $path;
}


sub ls {
    my $self = shift;
    my $dir = shift;
    my $base = $self->base;

    my @result;
    my $path;
    
    if($dir){
	$dir = $self->_foreign_dir($dir); 
	$path = $self->exists($dir);    
	return () if !$path;
	return (file($dir)) if !-d $path;
	$path = dir($base, $dir);
    }
    else {
	$path = dir($base);
    }
    
    opendir my $dh, $path or croak "Failed to open directory $base: $!";
    while(my $file = readdir $dh){
	next if $file eq '.';
	next if $file eq '..';

	my $full;
	my $short;
	if($dir){
	    $short = file($dir, $file);
	    $full  = file($base, $dir, $file);
	}
	else {
	    $short = file($file);
	    $full  = file($base, $file);
	}
	
	$short = $file if(!$dir || $dir eq '/');

	#print {*STDERR} "[$base][$file: $short -> $full]\n";
	
	if(-d $full){ #push child elements on
	    #print {*STDERR} "RECURSE -->\n";
	    push @result, $self->ls($short);
	    #print {*STDERR} "<-- RECURSE\n";
	    push @result, dir($short); # push ourselves on 
	}
	else {
	    push @result, file($short);
	}
    }
    closedir $dh;
    return @result;
}

sub delete {
    my $self = shift;
    my $path = shift;
    my $base = $self->base;

    $path = $self->_foreign_file($base, $path);
    
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
    my $base = $self->base;
    
    # capture warnings
    my @errors;
    local $SIG{__WARN__} = sub {
        push @errors, @_;
    };
    
    File::Path::rmtree( $base->stringify );

    if ( @errors > 0 ) {
        croak "cleanup() method failed: $!\n@errors";
    }

    $self->{args}->{CLEANUP} = 1; # it happened, so update this
    return 1;
}

sub randfile {
    my $self = shift;

    # make sure we can do this
    eval {
	require String::Random;
    };
    croak 'randfile: String::Random is required' if $@;

    # setup some defaults
    my( $min, $max ) = ( 1024, 131072 );

    if ( @_ == 2 ) {
	($min, $max) = @_;
    }
    elsif ( @_ == 1 ) {
        $max = $_[0];
        $min = int(rand($max)) if ( $min > $max );
    }
    confess "randfile: Cannot request a maximum length < 1"
      if ( $max < 1 );
    
    my ($fh, $name) = $self->tempfile;
    croak "Could not open $name: $!" if !$fh;
    $name = file($name);
    
    my $rand = String::Random->new();
    write_file($fh, $rand->randregex(".{$min,$max}"));    
    
    return file($name);
}

# throw a warning if CLEANUP is off and cleanup hasn't been called
sub DESTROY {
    my $self = shift;
    carp "Warning: not cleaning up files in ". $self->base
      if !$self->{args}->{CLEANUP};
}

1;

__END__

=head1 NAME

Directory::Scratch - Easy-to-use self-cleaning scratch space.

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

=head1 EXPORT

The first argument to the module is optional, but if specified, it's
interperted as the name of the OS whose file naming semantics you want
to use with Directory::Scratch.  For example, if you choose "Unix",
then you can provide paths to Directory::Scratch in UNIX-form
('foo/bar/baz') on any platform.  Unix is the default if you don't
choose anything explicitly.

If you want to use the local platform's flavor (not recommended),
specify an empty import list:

    use Directory::Scratch ''; # use local path flavor

Recognized platforms (from L<File::Spec|File::Spec>):

=over 4

=item Mac

=item UNIX

=item Win32

=item VMS

=item OS2

=back

The names are case sensitive, since they simply specify which
C<File::Spec::> module to use when splitting the path.

=head2 EXAMPLE

    use Directory::Scratch 'Win32';
    my $tmp = Directory::Scratch->new();
    $tmp->touch('C:\foo\bar\baz'); # and so on

Note that C:\ is actually ignored, since you are trapped inside a
tmpdir somewhere.  Hence, you should stick to relative paths.

=head1 METHODS

The file arguments to these methods are always relative to the
temporary directory.  If you specify C<touch('/etc/passwd')>, then a
file called C</tmp/whatever/etc/passwd> will be created instead.

This means that the program's PWD is ignored (for these methods), and
that a leading C</> on the filename is meaningless.

Finally, whenever a filename or path is returned, it is a
L<Path::Class|Path::Class> object rather than a string containing the
filename.  Usually, this object will act just like the string, but to
be extra-safe, call C<< $path->stringify >> to ensure that you're
really getting a string.  (Some clever modules try to determine
whether a variable is a filename or a filehandle; these modules
usually guess wrong when confronted with a C<Path::Class> object.)

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

Returns the full path of the temporary directory, as a Path::Class
object.

=head2 platform([$platform])

Returns the name of the platform that the filenames are being
interperted as (i.e., "Win32" means that this module expects paths
like C<\foo\bar>, whereas "UNIX" means it expects C</foo/bar>).

If $platform is sepcified, the platform is changed to the passed
value.  (Overrides the platform specified at module C<use> time, for
I<this instance> only, not every C<Directory::Scratch> object.)

=head2 touch($filename, [@lines])

Creates a file named C<$filename>, optionally containing the elements
of C<@lines> separated by the output record separator C<$\>.

The Path::Class object representing the new file is returned if the
operation is successful, an exception is thrown otherwise.

=head2 openfile($filename)

Opens $filename for writing and reading (C<< +> >>), and returns the
filehandle.  If $filename already exists, it will be truncated.  It's
up to you to take care of flushing/closing.

In list context, returns both the filehandle and the filename C<($fh,
$path)>.

=head2 mkdir($directory)

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

=head2 exists($file)

Returns the file's real (system) path if $file exists, undefined
otherwise.

Example:

    my $path = $tmp->exists($file);
    if(defined $path){
       say "Looks like you have a file at $path!";
       open(my $fh, '>>', $path) or die $!;
       print {$fh} "add another line\n";
       close $fh or die $!;
    }
    else {
       say "No file called $file."
    }

=head2 read($file)

Returns the contents of $file.  In array context, returns a list of
chompped lines.  In scalar context, returns a chomped representation
of the entire file.

=head2 write($file, @lines)

Replaces the contents of file with @lines.  Each line will be ended
with a C<\n>, or C<$,> if it is defined.  The file will be created if
necessary.

=head2 append($file, @lines)

Appends @lines to $file, as per C<write>.

=head2 randfile()

Generates a file with random string data in it.   If String::Random is
available, it will be used to generate the file's data.  Takes 0,
1, or 2 arguments - default size, max size, or size range.

A max size of 0 will cause an exception to be thrown.

Examples:

    my $file = $temp->randfile(); # size is between 1024 and 131072
    my $file = $temp->randfile( 4192 ); # size is below 4129
    my $file = $temp->randfile( 1000000, 4000000 ); 

=head2 link($from, $to)

Symlinks a file in the temporary directory to another file in the
temporary directory.

Note: symlinks are not supported on Win32.  Portable code must not use
this method.  (The method will C<croak> if it won't work.)

=head2 ls([$path])

Returns a list (in no particular order) of all files below C<$path>.
If C<$path> is omitted, the root is assumed.

=head2 delete($path)

Deletes the named file or directory at $path.

If the path is removed successfully, the method returns true.
Otherwise, an exception is thrown.

(Note: delete means C<unlink> for a file and C<rmdir> for a directory.
C<delete>-ing an unempty directory is an error.)

=head2 cleanup

Forces an immediate cleanup of the current object's directory.  See
File::Path's rmtree().  It is not safe to use the object after this
method is called.

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
TMTOWTDI.

=head1 PATCHES

Commentary, patches, etc. are most welcome.  If you send a patch,
try patching the subversion version available from:

L<svn://svn.jrock.us/cpan_modules/Directory-Scratch>

=head1 SEE ALSO

 L<File::Temp>
 L<File::Path>
 L<File::Spec>
 L<Path::Class>

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

=back

=head1 COPYRIGHT & LICENSE

Copyright 2006 Jonathan Rockway, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
