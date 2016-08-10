#!/usr/bin/perl
#
# SYNOPSIS:
#   make_dist.pl [OPTS] 
#
# DESCRIPTION:
#   Create a BioNetGen distribution from the repository. By default, attempts
#   to extract version number and codename from VERSION file in BNG root.
#
# OPTIONS:
#   --bngpath PATH  : path to BioNetGen repository (default: script directory)
#   --outdir  PATH  : output path (default: current directory)
#   --bindir  PATH  : path to pre-compiled binaries (default: undef)
#   --version VERS  : version number (overrides VERSION file)
#   --codename NAME : distribution codename (overrides VERSION file)
#   --archive       : create distribution archive file
#   --build         : compile and install binaries 
#   --validate      : validate installation 
#   --overwrite     : overwrite any existing distribution
#   --help          : display help

use strict;
use warnings;

# Perl Core Modules
use FindBin;
use File::Spec;
use Getopt::Long;
use Cwd ("getcwd");
use Config;
use File::Path qw(remove_tree);

### PARAMETERS ###
# BNG root directory
my $bngpath = $FindBin::RealBin;
# output directory
my $outdir = File::Spec->curdir();
# binary subdirectory (default=undef)
my $bindir;
 # if true, creates a tar.gz compressed archive
my $archive = 0;
# if true, compiles and installs the binaries
my $build = 0;
# if true, validates installation
my $validate = 0;
# if true, overwrites existing distribution (default 0)
my $overwrite = 0;
# distribution version (default undefined)
my $version = '';
# distribution codename (default="stable")
my $codename = 'stable';
# regex for excluding files (exclude make_dist.pl itself and all files beginning with "." or "_" or ending in "~")
my $exclude_files = '(^\.|^_|~$|\.old$|^make_dist\.pl$)';

#same regex exclude but includes files beginning with "_"
my $python_exclude_files = '(^\.|~$|\.old$|^make_dist\.pl$)';

# file extensions that should get executable flag
my $executable_suffix = '(pl|py|dll|exe)';
# subdirectories to include in distribution
my @include_subdirectories = qw/ Perl2 Models2 Network3 PhiBPlot Validate /;
#python subdiretories to include (main difference is that they are associated with python_exclude_files instead)
#my @include_python_subdirectories = qw/  SBMLparser /;

# directory containing library archives
my $libarc_subdir = "libsource";
# include libraries
my @include_libraries = ("cvode-2.6.0.tar.gz","muparser_v2_2_4.tar.gz");
# run_network binary
my $run_network = "run_network";

### System specific commands and flags ###
# copy
my $sys_copy = "cp";
my @copybin_flags = (); #("-d");
# chmod
my $sys_chmod = "chmod";
my $chmod_flags = "+x";
# system shell 
my $sys_shell = "sh";
# autoreconf
my $build_subdir = "Network3";
my $sys_autoconf = "autoreconf";
my @autoconf_flags = ("--no-recursive","--install");
# configure
my $sys_configure = "configure";
my @configure_flags = ("--disable-shared");
# make
my $sys_make = "make";
my @make_flags = ();
# tarzip
my $sys_tarzip = "tar";
my @tarzip_flags = ("--force-local", "-zxf");
# perl
my $sys_perl = "perl";
# validation
my $validate_subdir = "Validate";
my $validate_script = "validate_examples.pl";
my @validate_flags  = ();

###                                                          ###
###  BEGIN MAIN SCRIPT, no user options beyond this point!!  ###
###                                                          ###

# Greet the User
print "\n>>> BioNetGen Distribution Tool\n";

# parse command line arguments
GetOptions( 'help|h'        => sub { display_help(); exit(0); },
            'bngpath=s'     => \$bngpath,
            'outdir=s'      => \$outdir,
            'bindir=s'      => \$bindir,
            'version=s'     => \$version,
            'codename=s'    => \$codename,
            'archive'       => \$archive,
            'build'         => \$build,
            'validate'      => \$validate,
            'overwrite'     => \$overwrite
          )
or die "Error in command line arguments (try: make_dist.pl --help)";

if (@ARGV)
{
    printf "make_dist.pl warning:\nignoring unrecognized arguments (%s).\n", join(" ", @ARGV);
}

if ($version ne '')
{   # check for proper version format
    unless ($version =~ /^\d+\.\d+\.\d+$/)
    {   # invalid format
        print "make_dist.pl error:\ninvalid version '$version'.\n";
        exit -1;
    }
}
else
{   # try to read version file
    print "..attempting to extract version info from VERSION file.\n";
    my $version_file = File::Spec->catfile( $bngpath, "VERSION" );
    my $vfh;
    unless (open $vfh, '<', $version_file)
    {   # some problem opening version file
        print "make_dist.pl error:\ncannot open VERSION file'.\n";
        exit -1;
    }
    # get version line
    my $vline = <$vfh>;
    close $vfh;
    # strip leading space
    $vline =~ s/^\s+//;

    # extract version
    if ( $vline =~ s/^(\d+\.\d+\.\d+)\s*// )
    {   $version = $1;   }
    else
    {   # some problem reading version information
        print "make_dist.pl error:\nversion information has unrecognized format.\n";
        exit -1;
    }

    # extract codename, if any
    if ( $vline =~ s/^(\w+)// )
    {   $codename = $1;   }

    print "version: $version  codename: $codename\n";
}


# define distribution name, directory and archive file
my $dist_name    = "BioNetGen-${version}" . (($codename eq '') ? '' : "-${codename}");
my $dist_dir     = File::Spec->catdir( $outdir, $dist_name );
my $abs_dist_dir = File::Spec->rel2abs( $dist_dir );
my $dist_bindir  = File::Spec->catdir( $dist_dir, "bin" );
my $build_dir    = File::Spec->catdir( $dist_dir, $build_subdir );
my $archive_file = File::Spec->catfile( $outdir, "${dist_name}.tar.gz" );



# begin creating distribution
print  "Creating distribution version ${version} codename ${codename}\n";
printf "  bngpath: %s\n", $bngpath;
printf "  distdir: %s\n", $dist_dir;
if ($archive)
{
    printf "  archive: %s\n", $archive_file;
}
print "\n";


# check if output directory exists..
unless (-d $outdir)
{
    # try to make output directory
    unless ( mkdir $outdir )
    {
        print "make_dist.pl error:\ncannot make output directory ($!).\n";
        exit -1;
    }
}


if ($archive)
{   # check if archive file already exists..
    if (-e $archive_file)
    {
        if ($overwrite)
        {   # warn using about overwrite
            print "make_dist.pl warning:\noverwriting archive file '${archive_file}'\n";
        }
        else
        {   # overwrite not allowed! exit with error.
            print "make_dist.pl error:\narchive '${archive_file}' already exists.\n";
            exit -1;
        }
    }
}


# check if distribution directory already exists..
if (-d $dist_dir)
{
    if ($overwrite)
    {   # warn user about overwrite
        print "make_dist.pl warning:\noverwriting distribution directory '${dist_dir}'\n";
        unless ( remove_tree($dist_dir) ){
        		print "make_dist.pl error:\ncannot delete existing distribution directory '${dist_dir}' ($!).\n";
        		exit -1;
        }
    }
    else
    {   # overwrite not allowed! exit with error.
        print "make_dist.pl error:\ntarget distribution directory '${dist_dir}' already exists.\n"; 
        exit -1;
    }
}



# Include root..
my $recursive = 0;
my $err = copy_dir( $bngpath, $dist_dir, $recursive, $exclude_files);
if ($err)
{
    print "make_dist.pl error:\n$err\n";
    exit -1;
}

# Include subdirectories..
foreach my $dir ( @include_subdirectories )
{   
    my $source_dir = File::Spec->catdir( $bngpath,  $dir );
    my $dest_dir   = File::Spec->catdir( $dist_dir, $dir );

    my $recursive = 1;    
    my $err = copy_dir( $source_dir, $dest_dir, $recursive, $exclude_files );
    if ($err)
    {
        print "make_dist.pl error:\n$err\n";
        exit -1;
    }
}

# Create VERSION file for the distribution
my $vh;
my $vstring = "$version" . (($codename) eq "" ? "" : " ${codename}" );
unless( open($vh, ">", File::Spec->catfile($dist_dir, "VERSION")) )
{
    print "make_dist.pl error:\ncould not create VERSION file ($!).\n"; 
    exit -1;
}
print $vh $vstring;
close $vh;


# get pre-compiled binaries
if (defined $bindir)
{
    print "fetching pre-compiled binaries from $bindir . . .\n";

    unless (-d $bindir)
    {   # bindir doesn't exist!
        print "make_dist.pl error:\nbindir '$bindir' does not exist.\n";
        exit -1;
    }

    # create subdirectory for binaries
    unless (-d $dist_bindir)
    {
        # try to make output directory
        unless ( mkdir $dist_bindir )
        {
            print "make_dist.pl error:\ncannot make bin directory ($!).\n";
            exit -1;
        }
    }

    # copy all files in bindir to distbindir
    my $recursive = 0;
    my $err = copy_dir( $bindir, $dist_bindir, $recursive, $exclude_files, @copybin_flags );
    if ($err)
    {
        print "make_dist.pl error:\n$err\n";
        exit -1;
    }
}


# gather libraries, build configure scripts, and (optionally) compile/install
{
    unless (-d $build_dir)
    {   # build_dir doesn't exist!
        print "make_dist.pl error:\nbuild directory '${build_dir}' does not exist.\n";
        exit -1;
    }

    # get current directory
    my $cwd = getcwd();

    # change to build_dir
    unless( chdir $build_dir )
    {   print "make_dist.pl error:\nunable to chdir to build directory '${build_dir}'.\n";
        exit -1;
    }
    
    print "preparing libaries . . .\n";
    foreach my $libfile (@include_libraries)
    {
        # get absolute path of libfile
        my $abs_libfile = File::Spec->catfile( ($bngpath, $libarc_subdir), $libfile );
        # check if libfile is readable
        unless (-r $abs_libfile)
        {   print "make_dist.pl error:\ncan't access library archive '${libfile}'.\n";
            exit -1;
        }

        # get directory where libdir will be extracted
        (my $extract_libdir = $libfile) =~ s/\.tar\.gz$//;

        my $new_install = 1;
        #if (-d $extract_libdir)
        #{   # check if libfile is newer than 
        #    my $modtime_libfile = (stat $abs_libfile)[9];
        #    my $modtime_libdir  = (stat $extract_libdir)[9];
        #    $new_install = ($modtime_libdir > $modtime_libdir) ? 1 : 0;
        #}

        if ($new_install)
        {
            print "extracting ${libfile} . . .\n";
            my @args = ($sys_tarzip, @tarzip_flags, $abs_libfile);
            unless( system(@args)==0 )
            {  print "make_dist.pl error:\ncannot extract library archive file ($?)";  exit -1;  }
        }
    }

    # run autoconf
    #print "generating $build_subdir configuration scripts . . .\n";
    #my @args = ($sys_autoconf, @autoconf_flags);

    my @args = ($sys_copy, "Makefile.cmake", "Makefile");
    print "command: ", join(" ", @args), "\n";
    unless( system(@args)==0 )
    {  print "make_dist.pl error:\nsome problem running autoconf ($?)";  exit -1; }

    if ($build)
    {
        # {
        #     print "configuring $build_subdir . . .\n";
        #     my @args = ($sys_shell, $sys_configure, @configure_flags, "--prefix=${abs_dist_dir}");
        #     print "command: ", join(" ", @args), "\n";
        #     unless( system(@args)==0 )
        #     {  print "make_dist.pl error:\nsome problem configuring ${build_subdir} ($?)";  exit -1; }
        # }

        {
            print "making $build_subdir . . .\n";
            my @args = ($sys_make, @make_flags);
            print "command: ", join(" ", @args), "\n";
            unless( system(@args)==0 )
            {  print "make_dist.pl error:\nsome problem making ${build_subdir} ($?)";  exit -1; }
        }

        # {
        #     print "installing $build_subdir . . .\n";
        #     my @args = ($sys_make, "install" );
        #     print "command: ", join(" ", @args), "\n";
        #     unless( system(@args)==0 )
        #     {  print "make_dist.pl error:\nsome problem installing ${build_subdir} ($?)";  exit -1;  }
        # }

        {
            #print "appending arch/OS signature to ${run_network} binary . . .\n";
            my $arch = $Config{myarchname};
            my $abs_run_network = File::Spec->catfile(($abs_dist_dir, "bin"), $run_network);
            
            unless (-e $abs_run_network)
            {  print "make_dist.pl error:\ncan't find built run_network ($?)";  exit -1;  }

            # append architecture name
            #my $abs_run_network_arch = $abs_run_network . "_${arch}";
            # rename as architecture specific
            #unless ( rename $abs_run_network, $abs_run_network_arch )
            #{  print "make_dist.pl error:\ncan't find built run_network ($?)";  exit -1;  }

        }

        # go back to original directory
        unless( chdir $cwd ){   
            print "make_dist.pl error:\nunable to chdir back to original directory '$cwd'.\n";
            exit -1;
        }
        
    }

    # go back to original directory
    unless( chdir $cwd ){   
    		print "make_dist.pl error:\nunable to chdir back to original directory '$cwd'.\n";
    		exit -1;
    }

    if ($validate)
    {
        #  validate workdir
        my $validate_workdir = File::Spec->catfile( $abs_dist_dir, $validate_subdir ); #"validate_${dist_name}";

#        # check if output directory exists..
#        unless (-d $validate_workdir)
#        {
#            # try to make output directory
#            unless ( mkdir $validate_workdir )
#            {
#                print "make_dist.pl error:\ncannot make validation working directory ($!).\n";
#                exit -1;
#            }
#        }

        # change to validate workdir
        unless( chdir $validate_workdir ){
        		print "make_dist.pl error:\nunable to chdir to validation working directory '${validate_workdir}'.\n";
            exit -1;
        }

        # run validation script
#        my $abs_validate_script = File::Spec->catfile( ($abs_dist_dir, $validate_subdir), $validate_script );
        my $abs_validate_script = File::Spec->catfile( $validate_workdir, $validate_script );
        print "validating ${dist_name} . . .\n";
        my @args = ($sys_perl, $abs_validate_script, @validate_flags );
        print "command: ", join(" ", @args), "\n";
        unless( system(@args)==0 )
        {  
            print "make_dist.pl error:\nsome problem validating ${dist_name} ($?)\n";  
            exit -1;
        }

        unless( chdir $cwd ){   
       		print "make_dist.pl error:\nunable to chdir back to original directory '$cwd'.\n";
       		exit -1;
       }

    }
}


if ($archive)
{
    # create tar-archive
    print "\nCreating distribution archive:\n";
    print "tar cvzf ${archive_file} ${dist_dir}\n";
    `tar cvzf ${archive_file} ${dist_dir}`;
}


# all done
print "\nFinished creating distribution.\n";
exit 0;


##-------------##
## Subroutines ##
##-------------##


# copy directories (optionally recursive) with exclude filter
sub copy_dir
{
    my $source_dir = shift @_;
    my $dest_dir   = shift @_;
    my $recursive  = @_ ? shift @_ : 1;
    my $exclude_files = @_ ? shift @_ : '';
    my @copy_flags = @_;

    my @files;

    if ( -d $source_dir )
    {   # read files in source_dir
        my $dh;
        unless( opendir $dh, $source_dir )
        {
            return "copy_dir: cannot read directory '$source_dir'.";
        }
        @files = grep {$_ !~ m/$exclude_files/} readdir($dh);
        closedir $dh;
    }
    else
    {   # return error
        return "copy_dir: source '$source_dir' is not a directory.";
    }

    # create directory, unless it exists
    unless ( -d $dest_dir )
    {   
        unless ( mkdir $dest_dir )
        {   # return error
            return "copy_dir: cannot create directory '$dest_dir' ($!)";
        }
    }

    print "including $source_dir . . .\n";
    foreach my $file (@files)
    {

        # TODO: using catfile is questionable, since file may be a subdirectory
        my $source_file = File::Spec->catfile( $source_dir, $file );
        my $dest_file   = File::Spec->catfile( $dest_dir,   $file );

        if ( -d $source_file )
        {   
            if ($recursive)
            {   # copy subdirectory
                my $err = copy_dir( $source_file, $dest_file, $recursive, $exclude_files, @copy_flags );
                if (defined $err) {  return $err;  }
            }
        }   
        else
        {   # copy file
            #print "  $file\n";
            my @args = ( $sys_copy, @copy_flags, $source_file, $dest_file );
            unless( system(@args)==0 )
            {  return "copy_dir: cannot copy file ($?)";  }

            if ($dest_file =~ /\.${executable_suffix}$/)
            {   # try to set executable flag
                my @args = ( $sys_chmod, $chmod_flags, $dest_file );
                unless( system(@args)==0 )
                {  return "copy_dir: cannot set executable flag ($?)";  }
            }
        }
    }

    return undef;
}



# display help menu
sub display_help
{
print <<END_HELP

make_dist.pl

SYNOPSIS:
   make_dist.pl [OPTS] 

DESCRIPTION:
   Create a BioNetGen distribution from the repository. By default, attempts
   to extract version number and codename from VERSION file in BNG root.

OPTIONS:
   --bngpath PATH  : path to BioNetGen repository (default: script directory)
   --outdir  PATH  : output path (default: current directory)
   --bindir  PATH  : path to pre-compiled binaries (default: undef)
   --version VERS  : version number (overrides VERSION file)
   --codename NAME : distribution codename (overrides VERSION file)
   --archive       : create distribution archive file
   --build         : compile and install binaries 
   --validate      : validate installation 
   --overwrite     : overwrite any existing distribution
   --help          : display help

END_HELP

}
