package OSCAR::PackMan;

# Copyright (c) 2003-2004 The Trustees of Indiana University.
# Copyright (c) 2006      Erich Focht <efocht@hpce.nec.com>
#                         All rights reserved.
# Copyright (C) 2008      Oak Ridge National Laboratory
#                         Geoffroy Vallee <valleegr@ornl.gov>
#                         All rights reserved.
# $Id$

use strict;
use warnings "all";

use Carp;
use File::Spec;
use Data::Dumper;
use POSIX;
use File::Path;

use OSCAR::PackManDefs;
use OSCAR::OCA::OS_Detect;
use OSCAR::OCA::OS_Settings;
use OSCAR::SystemServices;
use OSCAR::SystemServicesDefs;
use OSCAR::Utils;
use OSCAR::Env;
use OSCAR::Logger;
use OSCAR::LoggerDefs;
use v5.10.1; # Given/When
# Avoid smartmatch warnings when using given
no if $] >= 5.017011, warnings => 'experimental::smartmatch';

our $VERSION;
$VERSION = "r" . q$Rev$ =~ /(\d+)/;

# concrete package manager order of preference, for breaking ties on systems
# where multiple package manager modules might claim usability.
# see below
my @preference;

my $verbose = $ENV{PACKMAN_VERBOSE};

# populated by BEGIN block with keys usable in @preference and values of
# where each PackMan module is located
my %concrete;

my $format;


# Preloaded methods go here.
BEGIN {

# change to qw(RPM DEB) when Deb gets written
# If, by hook or crook, you are on a system where both RPM and DEB (and
# whatever other package managers) will claim usability for a given
# filesystem, rank them in @preference. Recognition as the default package
# manager is on a first-come, first-served basis out of @preference. If no
# default package manager can be determined, all available package managers
# will be consulted in an indeterminant order in a final attempt to find one
# that's usable.
    @preference = qw(DEB RPM);

    my $packman_dir = File::Spec->catdir (split ("::", __PACKAGE__));
    my $full_dir;

    foreach my $inc (@INC) {
        $full_dir = File::Spec->catdir ($inc, $packman_dir);
        if (-d $full_dir) {
            last;
        } else {
            undef ($full_dir);
        }
    }

    defined ($full_dir) or
        croak "No directory of concrete " . __PACKAGE__ .
              " implementations could be found!";

    opendir (PACKMANDIR, $full_dir) or
        croak "Couldn't access concrete " . __PACKAGE__ . 
              " implementations: $!";

    foreach my $pm (readdir (PACKMANDIR)) {
        # only process .pm files
        if ($pm =~ m/\.pm$/) {
            require File::Spec->catfile ($packman_dir, $pm);
            $pm =~ s/\.pm$//;
            my $module = $packman_dir;
            $module = join ("::", File::Spec->splitdir ($module)) . "::" . $pm;
            # if it's actually a PackMan module, remember it
            if ("$module"->isa (__PACKAGE__)) {
                $concrete{$pm} = $module;
            }
        }
    }
    closedir (PACKMANDIR);

    scalar %concrete 
        or croak "No concrete " . __PACKAGE__ . 
                 " implementations could be found!";

    @preference = grep { defined $concrete{$_} } @preference;
}

# AUTOLOAD named constructors for the concrete modules
# Makes PackMan->RPM (<root dir>) do the same as PackMan::RPM->new (<root dir>)
sub AUTOLOAD {
    no strict 'refs';
    our $AUTOLOAD;

    if ($AUTOLOAD =~ m/::(\w+)$/ and grep $1 eq $_, keys %concrete) {
        my $module = $concrete{$1}; # uninitialized hash element error otherwise
        *{$1} = sub {
            ref (shift) and croak $1 . " constructor is a class method";
            return ("$module"->new (@_))
            };
        die $@ if $@;
        goto &$1;
    } else {
        die "$_[0] does not understand $AUTOLOAD\n";
    }
}

# Primary constructor
# doesn't actually create/bless any new objects itself (hence its class is
# abstract).
sub new {
    # require clauses are not necessary here, since each module's been
    # require'd in the BEGIN block to determine if it's actually a PackMan
    # object.
    my $invocant = shift;
    ref ($invocant)
        and croak __PACKAGE__ . " constructor is a class method.";

    foreach my $pm (@preference) {
        if ("$concrete{$pm}"->usable (@_)) {
            # first come, first served
            return ("$concrete{$pm}"->new (@_));
        }
    }
    # Wasn't found among the preferences, second chance, all of %concrete
    # Can this be made more efficient by filtering out all values belonging to
    # modules in @preferences? Perhaps.
    foreach my $pm (values %concrete) {
        if ("$pm"->usable (@_)) {
            return ("$pm"->new (@_));
        }
    }
    # Here, we're solidly S.O.L.
    croak "No usable concrete " . __PACKAGE__ . " module was found.";
}

# "instance constructor", creates a copy of an existing object with instance
# variable values.
sub clone {
    ref (my $self = shift) or croak "clone is an instance method";
    my $new  = { ChRoot => $self->{ChRoot} };
    bless ($new, ref ($self));
    return ($new);
}

# destructor, essentialy to quell some annoying warning messages.
sub DESTROY {
    ref (my $self = shift) or croak "DESTROY is an instance method";
    delete $self->{ChRoot};
}

# Set the ChRoot instance variable for this object. A value of undef is
# treated as a directive to quash all chrooted tags, ostensibly operating on
# the real root filesystem.
sub chroot {
    ref (my $self = shift) or croak "chroot is an instance method";
    if (@_) {
        my $chroot = shift;
        if (defined ($chroot) && (($chroot =~ m/\s+/) 
            || ! ($chroot =~ m/^\//))) {
            croak "Root value invalid " .
                  "(contains whitespace or doesn't start with /)";
        } else {
            $self->{ChRoot} = $chroot;
        }
        return ($self);
    } else {
        return ($self->{ChRoot});
    }
}

# Set the Repo instance variable for this object. Multiple repositories
# are possible and normal.
sub repo {
    ref (my $self = shift) or croak "repo is an instance method";
    if (@_) {
        my @repos = @_;
        my @r;
        # We do not want to add empty local repositories.
        require OSCAR::PackagePath;
        foreach my $repo (@repos) {
            if (OSCAR::PackagePath::repo_local ($repo) == 0
                || (OSCAR::PackagePath::repo_local ($repo) == 1
                    && OSCAR::PackagePath::repo_empty ($repo) == 0)) {
                unshift (@r, $repo);
            }
        }
        $self->{Repos} = \@r;
        return (scalar(@r));
    } else {
        return 0;
    }
}

# Assign a distro id to a PackMan object. The distro id follows the OS_Detect
# syntax (i.e., debian-4-x86_64). Based on the distro id it is trivial to find
# the list of repos, and all needed information for package management or even
# image creation.
# 
# Return: 1 if success, 0 else.
sub distro {
    ref (my $self = shift) or croak "distro is an instance method";
    if (@_) {
        my $distro = shift;
        require OSCAR::PackagePath;
        require OSCAR::Utils;
        $self->{Distro} = $distro;
        my ($dist, $ver, $arch)
            = OSCAR::PackagePath::decompose_distro_id ($distro);
        my $os = OSCAR::OCA::OS_Detect::open (fake=>{distro=>$dist,
                                                     distro_version=>$ver,
                                                     arch=>$arch});
        if (!defined $os) {
            carp "ERROR: Cannot recognized the OS ($distro)";
            return 0;
        }
        my $drepo_str = OSCAR::PackagePath::distro_repo_url(os=>$os);
        my $orepo_str = OSCAR::PackagePath::oscar_repo_url(os=>$os);
        my (@drepo, @orepo);
        if (OSCAR::Utils::is_a_valid_string ($drepo_str)) {
            @drepo = split (",", $drepo_str);
        }
        if (OSCAR::Utils::is_a_valid_string ($orepo_str)) {
            @orepo = split (",", $orepo_str);
        }
        my (@repos, @drepos, @orepos);
        foreach my $r (@drepo) {
            unshift (@repos, $r) if (OSCAR::Utils::is_a_valid_string ($r));
        }
        foreach my $r (@orepo) {
            unshift (@repos, $r) if (OSCAR::Utils::is_a_valid_string ($r));
        }
        $self->{Repos} = \@repos;
        return 1;
    } else {
        return 0;
    }
}

sub status {
    ref (my $self = shift) or croak "status is an instance method";
    my $str = "Packman status:\n";
    $str .= "\tFormat: ".$self->{Format}."\n";
    $str .= "\tAssociated distro: " . $self->{Distro} . "\n"
        if (defined ($self->{Distro}));
    $str .= "\tChRoot: " . $self->{ChRoot} . "\n" if defined $self->{ChRoot};
    my $repo_ref = $self->{Repos};
    $str .= "\tNumber of repos: " . scalar (@$repo_ref) . "\n" 
        if defined $repo_ref;
    $str .= "\tList of repos: ". join(", ", @$repo_ref) . "\n"
        if (defined $repo_ref && scalar (@$repo_ref) > 0);
    return $str;
}

# Set the Progress instance variable for this object.
# Non-zero argument enables builtin progress output.
# No argument disables progress output.
sub progress {
    ref (my $self = shift) or croak "progress is an instance method";
    if (@_) {
        $self->{Progress} = 1;
        $self->{progress_value} = 0;
    } else {
        undef $self->{Progress};
    }
}

# Register an output filter callback. This routine will be called for
# every output line captured during do_simple_command.
# Usage:
# $self->output_callback(\&function, $arg1, ...)
sub output_callback {
    ref (my $self = shift) or croak "output_callback is an instance method";
    my $callback = shift;
    if (ref($callback) ne "CODE") {
        croak("callback should be a reference to a function!");
    }
    $self->{Callback} = $callback;
    if (@_) {
        my @callback_args = @_;
        $self->{Callback_Args} = \@callback_args;
    }
}

# Bit of boilerplate for completely handling the #chroot and guaranteeing
# certain properties of the #args tags in *_command_line returned strings.
# Also breaks off the command name for separate handling.
#
# Return: aggregatable, ??
#         command, the command that actually needs to be executed,
#         cl, ???
#         success, the error code.
sub command_helper {
    ref (my $self = shift) or croak "command_helper is an instance method";
    my $command_line_helper = shift;

    my ($aggregatable, $cl, $success) = $self->$command_line_helper;
    my @command_line = split /\s+/, $cl;
    my $command = shift @command_line;
    $cl = join (" ", @command_line);
    my $chroot_arg;

    oscar_log(5, INFO, "No repositories available with this PackMan object") 
        if (!defined ($self->{Repos}));
    # repositories replacement
    if (defined ($self->{Repos})) {
        # substitute value of $Repos into implementation's repo_arg_command_line
        $self->can ('repo_arg_command_line') or
            croak "Concrete " . __PACKAGE__ 
                  . " module doesn't implement method "
                  . "repo_arg_command_line";

        # do we need to add repository at all?
        if ($cl =~ m/#repos/) {
            my @repos_args;
            for my $r (@{$self->{Repos}}) {
                my $tmp = $self->repo_arg_command_line;
                $tmp =~ s/#repo/$r/g;
                push @repos_args, $tmp;
            }
            my $repos = join(" ",@repos_args);
            $cl =~ s/#repos/$repos/g;
        }
    } else {
        # if no repo is specified, we just remove the #repos string from
        # the command
        $cl =~ s/#repos//g;
    }

    if (defined ($self->{Distro})) {
        # substitute value of $Distro into implementation's
        # repo_arg_command_line
        $self->can ('distro_arg_command_line') or
            croak "Concrete " . __PACKAGE__ 
                  . " module doesn't implement method "
                  . "distro_arg_command_line";

        if ($cl =~ m/#distro/) {
            my $tmp = $self->distro_arg_command_line;
            my $d = $self->{Distro};
            $tmp =~ s/#distro/$d/g;
            $cl =~ s/#distro/$tmp/g;
            $cl =~ s/#distro//g;
        }
    } else {
        # if no distro is specified, we just remove the #distro string from
        # the command
        $cl =~ s/#distro//g;
    }

    # chroot replacement
    if (defined ($self->{ChRoot})) {
        # substitute value of $ChRoot into implementation's
        # chroot_arg_command_line
        $self->can ('chroot_arg_command_line') or
            croak "Concrete " . __PACKAGE__ . 
                  " module doesn't implement method " .
                  "chroot_arg_command_line";

        if ($command_line_helper =~ m/^smart_/) {
            $chroot_arg = $self->smart_chroot_arg_command_line;
        } else {
            $chroot_arg = $self->chroot_arg_command_line;
        }

        if ($chroot_arg =~ m/#chroot/) {
            # put everywhere #chroot tag is
            $chroot_arg =~ s/#chroot/$self->{ChRoot}/g;
        } else {
            # put on end
            $chroot_arg = $chroot_arg . " " . $self->{ChRoot};
        }

        # substitute value of $chroot_arg into implementations
        if ($cl =~ m/#chroot/) {
            # put everywhere #chroot tag is
            $cl =~ s/#chroot/$chroot_arg/g;
        } elsif ($cl =~ m/#args/) {
            # put in front of first #args tag
            $cl =~ s/#args/$chroot_arg #args/;
        } else {
            # put on end
            $cl = $cl . " " . $chroot_arg;
        }
    } else {
        # just clear $cl of any #chroot tags
        $cl =~ s/#chroot//g;
    }

    # guarantee that there's a #args tag somewhere
    if (! ($cl =~ m/#args/) ) {
        $cl = $cl . " #args";
    }
    return ($aggregatable, $command, $cl, $success);
}

################################################################################
# Template for command operations.
#
# Return: PM_SUCCESS if success, PM_ERROR else.
################################################################################
sub do_simple_command {
    my $self = shift;
    my $command_name = shift;
    local *SYSTEM;

    ref ($self) 
        or return (PM_ERROR, $command_name . " is an instance method");
    $self->can ($command_name . '_command_line') 
        or return (PM_ERROR, "Concrete " . __PACKAGE__ . " module implements ".
                          "neither method " . $command_name . "install nor " .
                          $command_name . "_command_line");

    my @lov = @_;    # list of victims
    my ($aggregatable, $command, $cl) =
        $self->command_helper ($command_name . '_command_line');
    my @captured_output;
    my $retval = 0;
    my $errors = 0;
    my ($callback, $cbargs, $line);

    $callback = $self->{Callback} if (defined($self->{Callback}));
    $cbargs = $self->{Callback_Args} if (defined($self->{Callback_Args}));


    # This is a hack to let the child behave as if it runs in a tty
    # Without it yum doesn't show progress information.
#     my $pty = "/usr/bin/ptty_try";
#     if (-x $pty && ($command =~ /^yum/ || $command =~ /^\/usr\/sbin\/yum/)) {
#         $command = "$pty $command";
#     }

    my $rr = 0;
    if ($aggregatable) {
        splice(@captured_output);
        # need to put all packages into quotes (support for perl(Pod::Man)).
        @lov = map { "'$_'" } @lov;
        my $all_args = join " ", @lov;
        $cl =~ s/#args/$all_args/g;

        oscar_log(5, INFO, "Command to execute: $command $cl");

        my $pid = open(SYSTEM, "-|");
        defined ($pid) 
            or return (PM_ERROR, "can't fork: $!");

        if ($pid) {
            #
            # parent
            #
            while ($line = <SYSTEM>) {
                chomp $line;
                push @captured_output, $line;
                if ($line =~ /^ERROR/ || $line =~ /^E:/) {
                    # error detecting during the execution of the child
                    $errors ++;
                }
                $rr = $self->progress_handler($line);
                $retval = 1 if ($rr);
                if ($callback) {
                   &{$callback}($line, @{$cbargs});
                }
            }
            close (SYSTEM) || oscar_log(1, ERROR, "Error during execution $?");
            my $err = $?;
            if ($retval == 0) {
                $retval = $err;
            }
        } else {
            #
            # child
            #
            exec ("$command $cl")
                or return (PM_ERROR, "can't exec program ($command $cl): $!");
        }
    } else {
        foreach my $package (@lov) {
            splice(@captured_output);
            my $pid = open (SYSTEM, "-|");
            defined ($pid) 
                or return (PM_ERROR, "cannot fork: $!");
            select SYSTEM; $| = 1;  # try to make unbuffered
            if ($pid) {
                #
                # parent
                #
                while ($line = <SYSTEM>) {
                    chomp $line;
                    if ($line =~ /^ERROR/ || $line =~ /^E:/) {
                        # error detecting during the execution of the child
                        $errors ++;
                    }
                    push @captured_output, $line;
                    $rr = $self->progress_handler($line);
                    $retval = PM_ERROR if ($rr);
                    if ($callback) {
                        &{$callback}($line, @{$cbargs});
                    }
                }
                close (SYSTEM);
                my $err = $?;
                if ($retval == 0) {
                    $retval = $err;
                }
            } else {
                #
                # child
                #
                my $line = $cl;
                $line =~ s/#args/$package/g;
                exec ("$command $line") 
                    or return (PM_ERROR, "can't exec program ($command $cl): $!");
            }
        }
    }

    if ($retval == 0 && $errors > 0) {
        $retval = $errors;
    }
    return ($retval, @captured_output);
}

# Command the underlying package manager to install each of the package files
# in the argument list. Returns a failure value if any of the operations
# fails. In non-aggregated mode, all packages which can be installed are
# guaranteed to be installed. In aggregated mode, such guarantee depends on
# the operation of the underlying package manager.
#
# [Erich Focht]: this command is deprecated. Use smart_install instead.

sub install ($@) {
    ref (my $self = shift) 
        or return (PM_ERROR, "install is an instance method");
    if ((scalar @_) == 0) {
        return (PM_SUCCESS);
    }
    return ($self->do_simple_command ('install', @_));
}

# Command the underlying package manager to update/upgrade each of the
# packages in the argument list. Returns a failure value if any of the
# operations fails. In non-aggregated mode, all packages which can be updated
# are guaranteed to be updated. In aggregated mode, such guarantee depends on
# the operation of the underlying package manager.
#
# [Erich Focht]: this command is deprecated. Use smart_install instead.
sub update ($@) {
    ref (my $self = shift) 
        or return (PM_ERROR, "update is an instance method");
    return ($self->do_simple_command ('update', @_));
}

# Command the smart package manager to bootstrap the image dir if we are
# in a chrooted environment (otherwize, do nothing).
# Smart bootstrap should allways run in aggregated mode.
#
# Input: $self
#        $phase : ("bootstrap" or "cleanup")
# Return: (PM_SUCCESS or PM_ERROR, "error message")
sub smart_image_bootstrap($$) {
    ref (my $self = shift)
        or (oscar_log(1, ERROR, "smart_image_bootstrap is an instance method"),
            return (PM_ERROR, "smart_image_bootstrap is an instance method"));

    my $phase = shift; # "bootstrap" or "cleanup"
    if (($phase ne "bootstrap") and ($phase ne "cleanup")) {
        oscar_log(1, ERROR, "smart_image_bootstrap API Error: wrong phase: $phase");
        return (PM_ERROR, "smart_image_bootstrap API Error: wrong phase: $phase");
    }

    my ($err, @output, $line, $cmd);

    # No bootstrapping if not a chrooted environment (not an image directory)
    # Also do nothing if already already bootstrapped.
    return (PM_SUCCESS)
        if((! defined($self->{ChRoot})) ||
           ($self->{ChRoot} eq "/") ||
           ($self->{Bootstrap} eq $phase) ||
           ( -f $self->{ChRoot}/etc/bootstrap_infos.txt));
    
    # Create the image directory if it doesn't exists (and at image bootstrap phase).
    File::Path::mkpath ($self->{ChRoot}) if((! -d $self->{ChRoot}) && ($phase eq "bootstrap"));

    # Get the bootstrapping phase specific instructions for this distro.
    my $bootstrap_instructions = $self->get_distro_sample_file("img_bootstrap", $phase);

    if(! defined($bootstrap_instructions)) {
        oscar_log(1, ERROR, "Image bootstrap: no support for this distro.");
        return(PM_ERROR, "Image bootstrap: no support for this distro.");
    }

    my @bind   = (); # List of mount point to mount -o bind in image
    my @del    = (); # List of files to delete.
    my @mkdir  = (); # List of Paths to create.
    my @pkgs   = (); # List of packages to install.
    my @post   = (); # List of post bootstrap script to execute.
    my @pre    = (); # List of pre bootstrap scripts to execute.
    my @unbind = (); # List of mountpoints to unmount from image.

    my $line_nb=0;


    open(BOOTSTRAP, $bootstrap_instructions)
        || (oscar_log(1, ERROR, "Could not open file $bootstrap_instructions"),
            return(PM_ERROR,"Could not open file $bootstrap_instructions"));
    while ($line = <BOOTSTRAP>) {
        $line_nb++;
        next if (!OSCAR::Utils::is_a_valid_string ($line));
        $line =~ s/\s*#.*$//; # remove comments
        $line = OSCAR::Utils::trim ($line);
        next if ($line eq "");

        # Now parse the line.
        my @arguments = split(/\s+/, $line);
        my $command = shift(@arguments);

        given ($command) {
            when ("bind") { # Mount a filesystem from host in the image
                if (! -d $arguments[0]) {
                    oscar_log(1, ERROR, "Can't mount $arguments[0] into image: No such directory.");
                    close (BOOTSTRAP);
                    return(PM_ERROR, "Failed to bootstrap image: $self->{ChRoot}");
                }
                my $mnt_point = $arguments[0];
                push (@mkdir, $mnt_point)
                    if (! -d $self->{ChRoot}.$arguments[0]); # Will need to create this mountpoint in image.
                push (@bind, $mnt_point);
            }
            when ("del") { # Remove files from image.
                push (@del, @arguments);
            }
            when ("path") { # Supports multiple path to create at once.
                push (@mkdir, @arguments);
            }
            when ("pkgs") {
                push (@pkgs, @arguments);
            }
            when ("post") {
                push (@post, @arguments);
            }
            when ("pre") {
                push (@pre, @arguments);
            }
            when ("unbind") { # Unmount a filesystem relative to the image path.
                if (! -d $self->{ChRoot}.$arguments[0]) {
                    oscar_log(1, ERROR, "Can't unmount $arguments[0] from image: No such directory.");
                    close (BOOTSTRAP);
                    return(PM_ERROR, "Failed to bootstrap image: $self->{ChRoot}");
                }
                push (@unbind, $arguments[0]);
            }
            default {
                oscar_log(1, ERROR, "Unknown instruction'$command' in $bootstrap_instructions line: $line_nb");
                close (BOOTSTRAP);
                return(PM_ERROR, "Failed to bootstrap image: $self->{ChRoot}");
            }
        }
    }
    close (BOOTSTRAP);

    # Parsing finished, now, it's time for action.

    # Scripts dir (if no absolute PATH)
    my $scripts_path;
    if (defined $ENV{OSCAR_HOME}) {
        $scripts_path = "$ENV{OSCAR_HOME}/oscarsamples/img_bootstrap/";
    } else {
        $scripts_path = "/usr/share/oscar/oscarsamples/img_bootstrap/";
    }

    # 1: pre
    for my $script (@pre) {
        $script = $scripts_path.$script if ($script =~ /^\//);
        if(oscar_system($script)) {
            oscar_log(1, ERROR, "Failed to run pre($script)");
            return(PM_ERROR, "Failed to bootstrap image: $self->{ChRoot}");
        }
    }

    # 2: mkpath
    my @dirs = map { $self->{ChRoot}.$_ } @mkdir;
    File::Path::make_path(@dirs, { verbose => 1, error => \my $mkperr }); # FIXME: do not hardcode verbose.
    if (@$mkperr) {
        for my $diag (@$mkperr) {
             my ($delfile, $delmessage) = %$diag;
             if ($delfile eq '') {
                  oscar_log(1, ERROR, "Failed to create path: $delmessage");
                  return(PM_ERROR, "Failed to bootstrap image: $self->{ChRoot}");
             } else {
                  oscar_log(1, ERROR, "Failed to create path: $delfile: $delmessage");
                  return(PM_ERROR, "Failed to bootstrap image: $self->{ChRoot}");
             }
        }
    }

    # 3: del
    if (@del) {
        $cmd = "rm -rf ".join(" ",map { $self->{ChRoot}.$_ } @del);
        oscar_log(5, INFO, "Deleting ".join(" ",@del)." from imagedir $self->{ChRoot}");
        if(oscar_system($cmd)) {
            oscar_log(1, ERROR, "Failed to delete ".join(" ",@del)." from image $self->{ChRoot}");
            return(PM_ERROR, "Failed to bootstrap image: $self->{ChRoot}");
        }
    }

    # 4: Mount bind
    for my $mpt (@bind) {
        $cmd = "mount -o bind ".$mpt." ".$self->{ChRoot}.$mpt;
        oscar_log(5, INFO, "Mounting $mpt into image $self->{ChRoot}");
        if(oscar_system($cmd)) {
            oscar_log(1, ERROR, "Failed to mount $mpt into imagedir $self->{ChRoot}");
            return(PM_ERROR, "Failed to bootstrap image: $self->{ChRoot}");
        }
    }

    # 5: unbind
    for my $umpt (@unbind) {
        $cmd = "umount ".$self->{ChRoot}.$umpt;
        oscar_log(5, INFO, "Unmounting $umpt from imagedir $self->{ChRoot}");
        if(oscar_system($cmd)) {
            oscar_log(1, ERROR, "Failed to unmount $umpt from image $self->{ChRoot}");
            return(PM_ERROR, "Failed to bootstrap image: $self->{ChRoot}");
        }
    }

    # 6: pkgs (install)
    if (@pkgs) {
        ($err, @output) = $self->do_simple_command ('smart_install', @pkgs);
        if($err) {
            oscar_log(1, ERROR, "Failed to install the following pkgs into image $self->{ChRoot}:\n".join(" ",@pkgs));
            return(PM_ERROR, "Failed to bootstrap image: $self->{ChRoot}");
        }
    }

    # 7: post
    for my $script (@post) {
        $script = $scripts_path.$script if ($script =~ /^\//);
        if(oscar_system($script)) {
            oscar_log(1, ERROR, "Failed to run post($script)");
            return(PM_ERROR, "Failed to bootstrap image: $self->{ChRoot}");
        }
    }

    $self->{Bootstrap} = $phase;

    # If cleanup successfull, put a stamp in the image.
    if ($phase == "cleanup") {
        open BS_INFOS, ">$self->{ChRoot}/etc/bootstrap_infos.txt"
            || oscar_log(1, WARNING, "Could not create $self->{ChRoot}/etc/bootstrap_infos.txt");
        print BS_INFO <<EOF;
This image has been successfully bootstrapped for the following OS:
$self->{Distro}.
EOF
        close BS_INFO;
    }
    return(PM_SUCCESS);
}

# Command the underlying package manager to remove each of the packages in the
# argument list. Returns a failure value if any of the operations fails. In
# non-aggregated mode, all packages which can be removed are guaranteed to be
# removed. In aggregated mode, such guarantee depends on the operation of the
# underlying package manager.
#
# [Erich Focht]: this command is deprecated. Use smart_install instead.
# sub remove {
#     ref (my $self = shift) 
#         or return (PM_ERROR, "remove is an instance method");
#     if ((scalar @_) == 0) {
#         return (PM_SUCCESS);
#     }
#     return ($self->do_simple_command ('remove', @_));
# }
# 

# Function to get the full pathname of an oscarsample file given its category and file extension
# category is the name of oscarsample sub directory to search into. e.g.: pkgfiles
# 1st try to return the "distro" file, and if not found, the compat-distro file.
# get_distro_sample_file should allways run in aggregated mode.
sub get_distro_sample_file($$$) {
    ref (my $self = shift) 
        or (oscar_log(1, ERROR, "get_distro_sample_file is an instance method"), return undef);
    my ($category, $extension) = @_;

    if (! defined($self->{Distro})) {
        oscar_log(1, ERROR, "Distro not defined. Can't find appropriate config file");
        return undef;
    }

    my $file;
    if (defined $ENV{OSCAR_HOME}) {
        $file = "$ENV{OSCAR_HOME}/oscarsamples/$category";
    } else {
        $file = "/usr/share/oscar/oscarsamples/$category";
    }

    # 1st: check if distro file exists.
    if (-f "$file/$self->{Distro}.$extension") {
        oscar_log(5, INFO, "Selected config file: $file/$self->{Distro}.$extension");
        return ("$file/$self->{Distro}.$extension");
    }

    #2nd: distro file not found, we try to check for distro-compat file.
    my ($dist, $ver, $arch) = OSCAR::PackagePath::decompose_distro_id ($self->{Distro});
    my $os = OSCAR::OCA::OS_Detect::open (fake=>{ distro=>$dist,
                                                  distro_version=>$ver,
                                                  arch=>$arch});
    if (!defined ($os)) {
        oscar_log(1, ERROR, "Impossible to detect the distro ($self->{Distro})");
        return undef;
    }

    my $compat_distro = "$os->{compat_distro}-$os->{compat_distrover}-$arch";
    if ( -f "$file/$compat_distro.$extension" ) {
        $file .= "/$compat_distro.$extension";
    } else {
        oscar_log(1, ERROR, "Impossible to open the file $self->{Distro}.$extension or $compat_distro.$extension");
        return undef;
    }
    oscar_log(5, INFO, "Selected config file: $file");

    return($file);
}

# Command the smart package manager to install each of the package files
# in the argument list and resolve dependencies automatically.
# Smart installs should allways run in aggregated mode.
#
# Return: a pair of values: ($err, $out_ref)
#         - $err contains a failure value if any of the operations fails.
#         - $out_ref is a reference to an array containing the output of the
#           command.
sub smart_install ($@) {
    ref (my $self = shift) 
        or return (PM_ERROR, "ERROR: smart_install is an instance method");
    my @pkgs = @_;
    if ((scalar @pkgs) == 0) {
        return (PM_SUCCESS, "smart_install successful");
    }
    my ($err, @output, $msg);

    # 1st, we need to bootstrap the image.
    ($err, $msg) = $self->smart_image_bootstrap("bootstrap");

    # If bootstrapping of the image fails, no need to continue.
    if (defined ($err) && $err) {
        return ($err, $msg);
    }


#    my ($err, @output, $line);
#    # If the image does not exist for a given RPM based image, we need to
#    # bootstrap the image. For Debian system, RAPT deals with it.
#    if ($self->{Format} eq "RPM" && defined ($self->{ChRoot}) 
#                                 && (! -d $self->{ChRoot})) {
#        oscar_log(1, INFO, "Bootstrapping the image...");
#        
#        # If this is an RPM based image, we need the following directory to
#        # avoid error messages everytime we try to install a package.
#        File::Path::mkpath ($self->{ChRoot}."/var/lib/yum");
#        my $filerpmlist = $self->get_distro_sample_file("pkglists", "pkglist");
#
#        open(DAT, $filerpmlist)
#            || (return(PM_ERROR, "Could not open file $filerpmlist"));
#        while ($line = <DAT>) {
#            next if (!OSCAR::Utils::is_a_valid_string ($line));
#            $line = OSCAR::Utils::trim ($line);
#            next if ($line =~ /^#/);
#            ($err, @output) = $self->do_simple_command ('smart_install',
#                              $line);
#            if ($err == PM_ERROR) {
#                oscar_log(1, ERROR, "Unable to install $line");
#            }
#        }
#        close (DAT);
#    }
#


    # 2nd, Now that the image is bootstrapped, we can actually install the packages.
    ($err, @output) = $self->do_simple_command ('smart_install', @pkgs);

    if (defined ($err) && $err) {
        # If we failed in installing packages, we still need to cleanup at least binded mountpoints.
        ($err, $msg) = $self->smart_image_bootstrap("cleanup"); # Don't care for success here (already in failed state)
        if (scalar (@output) == 0) {
            return (PM_ERROR, "No error message");
        } else {
            return (PM_ERROR, join("\n", @output));
        }
    }

    # 3rd, we need to cleanup the image. (unmount some binded filesystems, remove some garbage, ...)
    ($err, $msg) = $self->smart_image_bootstrap("cleanup");
    if (defined ($err) && $err) {
        return (PM_ERROR, $err);
    }

    # 4th, Finished, we return SUCCESS.
    return (PM_SUCCESS, "Install succeeded.");
}

# Command the smart package manager to remove each of the package files
# in the argument list. It also removes all packages depending on these ones!
#
# Return: a pair of values: ($err, $out_ref)
#         - $err contains a failure value if any of the operations fails.
#         - $out_ref is a reference to an array containing the output of the
#           command.
sub smart_remove ($@) {
    ref (my $self = shift) 
        or return (PM_ERROR, "smart_remove is an instance method");
    my @pkgs = @_;
    if ((scalar @pkgs) == 0) {
        return (PM_SUCCESS, "");
    }
    return ($self->do_simple_command ('smart_remove', @pkgs));
}

# Command the smart package manager to update each of the package files
# in the argument list by using the repositories and taking the newest
# package versions from there.
# Returns a pair of values: ($err, $out_ref)
# $err contains a failure value if any of the operations fails.
# $out_ref is a reference to an array containing the output of the command.
sub smart_update {
    ref (my $self = shift) 
        or return (PM_ERROR, "smart_update is an instance method");
    return ($self->do_simple_command ('smart_update', @_));
}

# Clean all smart package manager caches
sub clean {
    ref (my $self = shift) 
        or return (PM_ERROR, "clean is an instance method");
    return ($self->do_clean);
}

# Generate repository caches for local repositories
sub gencache {
    ref (my $self = shift) 
        or return (PM_ERROR, "gencache is an instance method");
    my $a = $self->{Repos};
    if (scalar (@$a) == 0) {
        return (PM_SUCCESS, "No repository are defined");
    }
    return ($self->do_simple_command ('gencache', @_));
}

# sub query_opkgs ($@) {
#     my $self = shift;
#     my @opkgs = @_
# 
#     # If the user does not specify any particular OPKG, we assume we want to 
#     # get data about all available OPKGs.
#     if (!defined @opkgs) {
#         push (@opkgs, "*");
#     }
# 
#     return ($self->do_simple_command ('query_opkgs', @opkgs);
# }

sub query_list_installed_pkgs {
    ref (my $self = shift)
        or return (PM_ERROR, "query_list_installed_pkgs is an instance method");
    my @installed;

    # save existing callback
    my ($save_cb, $save_cba);
    if ($self->{Callback}) {
        $save_cb = $self->{Callback};
        $save_cba = $self->{Callback_Args};
    }

    # filter routine to be used as temporary callback
    sub filter1 {
        my ($line, $installed) = @_;
        push (@$installed, $line);
    }

    # register temporary callback
    $self->output_callback(\&filter1, \@installed);

    # execute command and temporary callback for each output line
    $self->do_simple_command('query_list_installed_pkgs', @_);
    if ($save_cb) {
        $self->output_callback($save_cb, @{$save_cba});
    } else {
        delete $self->{Callback};
        delete $self->{Callback_Args};
    }
#    vprint("PM:query_list_installed_pkgs: returns:\n".
#        OSCAR::Utils::print_array(@installed)."\n");
    return @installed;     
}

# Query the underlying package manager to report the list of which of the
# packages in the argument list are presently installed and which are
# uninstalled.
#
# Argument: list of packages to be queried
#
# Returns: reference to a hash containing as primary keys the really installed
#          package names. Each hash entry is a reference to an array of hash
#          references of the form:
#          {
#            version => "1.2.3-1",
#            arch => "i386"
#          }
#
sub query_installed {
    ref (my $self = shift) 
        or return (PM_ERROR, "query_installed is an instance method");
    my %installed;

    # save existing callback
    my ($save_cb, $save_cba);
    if ($self->{Callback}) {
        $save_cb = $self->{Callback};
        $save_cba = $self->{Callback_Args};
    }

    # filter routine to be used as temporary callback
    sub filter_installed {
        my ($line, $installed) = @_;
        if ($line =~ m/^found: (\S+) (\S+) (\S+)$/) {
            my $name = $1;
            my $version = $2;
            my $arch = $3;
            if (exists($installed->{$name})) {
                push (@{$installed->{$name}},
                     { version => $version, arch => $arch });
            } else {
                $installed->{$name}
                    = [ { version => $version, arch => $arch } ];
            }
            oscar_log(5, INFO, "PM:filter_installed: $line");
        }
    }
    # register temporary callback
    $self->output_callback(\&filter_installed, \%installed);

    # execute command and temporary callback for each output line
    $self->do_simple_command('query_installed', @_);
    if ($save_cb) {
        $self->output_callback($save_cb, @{$save_cba});
    } else {
        delete $self->{Callback};
        delete $self->{Callback_Args};
    }
    oscar_log(5, INFO, "PM:query_installed: returns:\n".Dumper(\%installed));
    return \%installed;
}

#
# Check whether a list of packages was installed or not.
# Usage:
#    @list = $pm->check_installed(@pkgs);
#
# @list is the list of packages which are not installed
#
sub check_installed {
    ref (my $self = shift) 
        or return (PM_ERROR, "check_installed is an instance method");
    my (@pkgs) = @_;

    my $installed = $self->query_installed(@pkgs);
    my @match;
    for (keys(%{$installed})) {
        push @match, "\Q$_";
        for my $p (@{$installed->{$_}}) {
            push @match, "\Q$_".".".$p->{arch};
        }
    }
    my $match = join("|", @match);
    my @failed;
    # match targetted packages with installed package names
    for my $p (@pkgs) {
        if ($p !~ m/^($match)$/) {
            push @failed, $p;
        }
    }
    my @really_failed;
    # check if failed packages are capabilities
    for (@failed) {
        if ($self->whatprovides($_) eq "") {
            push @really_failed, $_;
        }
    }
    return @really_failed;
}

################################################################################
# This function parses the result of the search command from rapt. Except some #
# cleanup up (some lines are empty), this is fairly simple.                    #
#                                                                              #
# Input: opkgs, array with OPKGs name and some stuff to clean up, the actual   #
#               result of the rapt command.                                    #
# Output: an array of OPKGs names.                                             #
################################################################################
sub parse_deb_search_result ($@) {
    ref (my $self = shift)
        or return (PM_ERROR, "parse_deb_search_result is an instance method");
    my @opkgs = @_;

    for (my $i=0; $i<scalar(@opkgs); $i++) {
        # We do some cleaning
        if (!defined $opkgs[$i]) {
            splice (@opkgs, $i, 1);
            # if we remove an element, we have to keep the same index in the 
            # array
            $i--;
            next;
        }
        chomp $opkgs[$i];
        $opkgs[$i] = OSCAR::Utils::trim($opkgs[$i]);
        if ($opkgs[$i] eq "") {
            splice (@opkgs, $i, 1);
            # if we remove an element, we have to keep the same index in the 
            # array
            $i--;
        }
    }
    return @opkgs;
}

################################################################################
# This functions parses the result of the yume command to search for packages  #
# and extract OPKGs' names. The typical output is:                             #
#     opkg-linux-ha-server-0:2.0.8-2.noarch                                    #
# and we only want to get "opkg-linux-ha-server".                              #
#                                                                              #
# Input: output, an array, result of the yume command, with the yume's output; #
#                each line is in a separate element of the array.              #
# Result: an array of OPKGs names.                                             #
################################################################################
sub parse_rpm_search_result ($@) {
    ref (my $self = shift)
        or return (PM_ERROR, "parse_deb_search_result is an instance method");
    my @output = @_;
    my @opkgs;

    for (my $i=0; $i<scalar(@output); $i++) {
    if (OSCAR::Utils::is_a_valid_string($output[$i])
            && ($output[$i] =~ /^(.*)-[0-9]:(.*)$/)) {
            push (@opkgs, $1);
        }
    }
    return @opkgs;
}

################################################################################
# Search repository for packages matching the passed pattern.                  #
#                                                                              #
# Usage:                                                                       #
#    ($err, @list) = $pm->search_repo("pattern");                              #
# Input: pattern, the pattern to look for.                                     #
# Result: err, the error return code.                                          #
#         list, array with the name of OPKGs.                                  #
################################################################################
sub search_repo ($$) {
    ref (my $self = shift)
        or return (PM_ERROR, "search_repo is an instance method");
    my $pattern = shift;
    my ($rc, @output);
    my @opkgs;
    if ($self->{Format} eq "DEB") {
        ($rc, @output) = $self->do_simple_command ('search_repo', $pattern);
        @opkgs = $self->parse_deb_search_result (@output);
    } elsif ($self->{Format} eq "RPM") {
        ($rc, @output) = $self->do_simple_command ('search_repo_update', $pattern);
        @opkgs = $self->parse_rpm_search_result (@output);
    } else {
        return (PM_ERROR, "**search_repo** unknown format (".$self->{Format}.")");
    }
    return ($rc, @opkgs);
}

################################################################################
# Function that helps at parsing the output of the yume command that gets      #
# details about a given package and create accordingly a hash with all package #
# data. This function typically find the position of the next package          #
# description.                                                                 #
#                                                                              #
# Input: pos, position of the current package description.                     #
#        output, yume command output that describes OPKG(s).                   #
# Output: position of the next package description, -1 is no other package     #
#         description.                                                         #
################################################################################
sub find_next_rpm_pkg ($$@) {
    ref (my $self = shift) 
        or return (PM_ERROR, "show_repo is an instance method");
    my ($pos, @output) = @_;

    for (my $i = $pos; $i < scalar (@output); $i++) {
        return ($i-1) if ($output[$i] =~ /^Matched from:/);
    }
    return -1;
}

################################################################################
# This function takes the output of the yume command to get package details,   #
# parses it and format it into a hash PackMan and everything on top of PackMan #
# will understand (format independent to the underlying binary package format  #
# tool).                                                                       #
#                                                                              #
# Input: output, the output of the Yume command: one line per array element.   #
# Return: a hash that fits the OSCAR description of a package.                 #
################################################################################
sub rpm_pkg_data_to_hash ($@) {
    ref (my $self = shift) 
        or return (PM_ERROR, "rpm_pkg_data_to_hash is an instance method");
    my @output = @_;
    my ($ver, $rel, $summary, $packager, $desc, $class, $name, $group,
        $conflicts, $isdesc, $dist);
    my %o;

    OSCAR::Utils::print_array (@output) if $verbose;
    my @tokens;

    for (my $i=0; $i < scalar (@output); $i++) {
        if (OSCAR::Utils::is_a_valid_string($output[$i]) == 1) {
            @tokens = split (/:/, $output[$i], 2);
#            print STDERR "Token ID: ". $tokens[0].".\n";
            if (OSCAR::Utils::trim ($tokens[0]) eq "Name") {
                $name = OSCAR::Utils::trim ($tokens[1]);
            } 
            if (OSCAR::Utils::trim ($tokens[0]) eq "Version") {
                $ver = OSCAR::Utils::trim ($tokens[1]);
            } 
            if (OSCAR::Utils::trim ($tokens[0]) eq "Release") {
                $ver .= OSCAR::Utils::trim ($tokens[1]);
            } 
            if (OSCAR::Utils::trim ($tokens[0]) eq "Summary") {
                $summary = OSCAR::Utils::trim ($tokens[1]);
            }
            if (OSCAR::Utils::trim ($tokens[0]) eq "Description") {
                $desc = OSCAR::Utils::trim ($tokens[1]);
            }
            if (OSCAR::Utils::trim ($tokens[0]) eq "") {
                $desc .= OSCAR::Utils::trim ($tokens[1]);
            }
            $i++ if scalar(@tokens) == 1;
        }
        if ($name) {
            $o{$name} = {
                package => $name,
                version => $ver,
                summary => $summary,
                packager => $packager,
                description => $desc,
                class => $class,
                group => $group,
                distro => $self->{Distro},
                conflicts => $conflicts,
            };
        }
    }
    return %o;
}

################################################################################
# This function takes the output of the rapt show command, parses it and       #
# format it into a hash PackMan and everything on top of PackMan will          #
# understand (format independent to the underlying binary package format       #
# tool).                                                                       #
#                                                                              #
# Input: output, the output of the RAPT command: one line per array element.   #
# Return: a hash that fits the OSCAR description of a package.                 #
################################################################################
sub deb_pkg_data_to_hash ($@) {
    my ($self, @output) = @_;
    my ($ver, $rel, $summary, $packager, $desc, $class, $name, $group,
        $conflicts, $isdesc, $dist);
    my %o;

    foreach my $line (@output) {
        next if (!defined $line);
        chomp $line;
        if ($line =~ /^Package: (.*)$/) {
            $name = $1;
            $isdesc = 0;
            $ver = $rel = $summary = $packager = $desc = $class = "";
            $conflicts = "";
        } elsif ($line =~ /^Version: (.*)$/) {
            $ver = $1;
        } elsif ($line =~ /^Section: (.*)$/) {
            $group = $1;
            $class = "";
            if ($group =~ m/^([^:]*):([^:]*)/) {
                $group = $1;
                $class = $2;
            }
        } elsif ($line =~ /^Maintainer: (.*)$/) {
            $packager = $1;
        } elsif ($line =~ /^Conflicts: (.*)$/) {
            $conflicts = $1;
        } elsif ($line =~ /^Description: (.*)$/) {
            $isdesc = 1;
            $summary = $1;
        } elsif ($line =~ /^Bugs:/) {
            $isdesc = 0;
        } else {
            if ($isdesc) {
                if ($line =~ m/^ (.*)$/) {
                    $desc .= "$1\n";
                }
            }
        }
         if ($name) {
            $o{$name} = {
                package => $name,
                version => $ver,
                summary => $summary,
                packager => $packager,
                description => $desc,
                class => $class,
                group => $group,
                distro => $dist,
                conflicts => $conflicts,
            };
         }
    }
    return %o;
}


#
# Show packages details that matches the passed pattern for a given repository
#
# Usage:
#    ($err, %hash) = $pm->show_repo("list of packages");
sub show_repo {
    ref (my $self = shift) 
        or return (PM_ERROR, "show_repo is an instance method");
    my $opkgs = shift;
    my ($ret, @o) = $self->do_simple_command ('show_repo', $opkgs);
    my %data;
    if ($self->{Format} eq "DEB") {
        %data = $self->deb_pkg_data_to_hash (@o);
    } elsif ($self->{Format} eq "RPM") {
        %data = $self->rpm_pkg_data_to_hash (@o);
    } else {
        return undef;
    }
    return ($ret, %data);
}

# ###
# Functions for exporting repositories via HTTPD
# These were taken from "yume" such that other package managers
# can also make use of them. [Erich Focht, 2006]
# Most of these are not "methods" but "functions", because yume uses
# them without creating packman instances.
# ###

# export repositories belonging to the current packman instance
# through httpd
sub repo_export {
    ref (my $self = shift) 
        or return (PM_ERROR, "repo_export is an instance method");
    return add_httpd_conf(@{$self->{Repos}});
}

# unexport repositories belonging to the current packman instance
# through httpd
sub repo_unexport {
    ref (my $self = shift) 
        or return (PM_ERROR, "repo_unexport is an instance method");
    return del_httpd_conf(@{$self->{Repos}});
}

# locate httpd configuration directory
sub find_httpdir {
    my $httpdir = OSCAR::OCA::OS_Settings::getitem(HTTP()."_configdir");
#    for my $d ("httpd", "apache", "apache2") {
#        if (-d "/etc/$d/conf.d") {
#            $httpdir = "/etc/$d/conf.d";
#            last;
#        }
#    }
    oscar_log(5, INFO, "Using httpdir = $httpdir");
    return $httpdir;
}

# Return: 0 if success, else the number of errors that occured.
sub add_httpd_conf {
    my (@repos) = @_;
    my $httpdir = find_httpdir();
    my $changed = 0;
    my $err = 0;
    chomp(my $hostname = `hostname`);
    if ($httpdir) {
        for my $repo (@repos) {
            if ($repo =~ /^(file:\/|\/)/) {
                $repo =~ s|^file:||;
                if (!-d $repo) {
                    oscar_log(1, WARNING, "Could not find directory $repo. Skipping.");
                    $err++;
                    next;
                }
                my $pname = "repo$repo";
                my $rname = $pname;
                $rname =~ s:/:_:g;
                my $cname = "$httpdir/$rname.conf";
                if (-f $cname) {
                    oscar_log(1, WARNING, "Config file $cname already existing. Skipping.");
                    next;
                }
                oscar_log(1, INFO, "Exporting $repo through httpd, ".
                      "http://$hostname/$pname");
                open COUT, ">$cname" or die "Could not open $cname : $!";
                print COUT "Alias /$pname $repo\n";
                print COUT "<Directory $repo/>\n";
                print COUT "  Options Indexes\n";
                print COUT "  order allow,deny\n";
                print COUT "  allow from all\n";
                print COUT "</Directory>\n";
                close COUT;
                ++$changed;
            } else {
                oscar_log(1, WARNING, "Repository URL is not a local absolute path!");
                oscar_log(1, INFO, "Skipping $repo");
                $err++;
                next;
            }
        }
    } else {
        oscar_log(1, ERROR, "Could not find directory $httpdir!");
        oscar_log(1, ERROR, "Cannot setup httpd configuration for repositories.");
        $err++;
    }
    restart_httpd() if ($changed);
    return $err;
}

sub del_httpd_conf {
    my (@repos) = @_;
    my $httpdir = find_httpdir();
    my $changed = 0;
    my $err = 0;
    if ($httpdir) {
    for my $repo (@repos) {
        if ($repo =~ /^(file:\/|\/)/) {
            $repo =~ s|^file:||;
            my $pname = "repo$repo";
            my $rname = $pname;
            $rname =~ s:/:_:g;
            my $cname = "$httpdir/$rname.conf";
            if (-f $cname) {
                oscar_log(1, INFO, "Deleting config file $cname");
                if (unlink($cname)) {
                oscar_log(1, WARNING, "Could not delete $cname : $!");
                $err++;
                } else {
                ++$changed;
                }
            }
        } else {
            oscar_log(1, WARNING, "Repository URL is not a local absolute path!");
            oscar_log(1, INFO, "Skipping $repo");
            $err++;
            next;
        }
    }
    } else {
        oscar_log(1, ERROR, "Could not find directory $httpdir!");
        oscar_log(1, ERROR, "Cannot delete httpd configuration for repositories.");
        $err++;
    }
    restart_httpd() if ($changed);
    return $err;
}

sub list_exported {
    my $httpdir = find_httpdir();
    if ($httpdir) {
        for my $repoconf (glob("$httpdir/repo_*.conf")) {
            my $rname = basename($repoconf,".conf");
            my ($dummy, $alias,$rdir) = split(" ",`grep "^Alias" $repoconf`);
            chomp $rdir;
            oscar_log(1, INFO, "URL $alias : Repository --repo $rdir");
        }
    }
}

sub restart_httpd {
    !system_service(HTTP(),RESTART())
        or ( oscar_log(1, ERROR, "Couldn't restart http service."), return -1);
}

1;
__END__

=head1 NAME

OSCAR::PackMan - Perl extension for Package Manager abstraction

=head1 SYNOPSIS

  Constructors

  use OSCAR::PackMan;
  $pm = OSCAR::PackMan->new;

  Concrete package managers will always be available directly as:

  use OSCAR::PackMan::<conc>;
  $pm = <conc>->new;

  use OSCAR::PackMan;
  $pm = OSCAR::PackMan-><conc>;

  use OSCAR::PackMan;
  $pm = OSCAR::PackMan::<conc>->new;

  Currently, the only valid value for <conc> is RPM.


  Methods

  $new_pm = $pm->clone;

  $pm->chroot ("/mnt/other_root");

  $pm->chroot ("/");    # wrong, will cause chroot argument substitute anyway
  $pm->chroot (undef);    # right, no chroot argument will be used

  my $pm_chroot = $pm->chroot;

  $pm->repo("/tftpboot/rpm");
  $pm->repo("http://master/repo_rpm","http://master/repo_oscar");

  $pm->gencache;

  ($err,$outref) = $pm->smart_install("pkg1",...);

  ($err,$outref) = $pm->smart_remove("pkg1",...);

  ($err,$outref) = $pm->smart_update("pkg1",...);

  $pm->output_callback(\&function,\$arg1,...);

  $err = $pm->repo_export;

  $err = $pm->repo_unexport;

  $pm->list_exported;

  Following methods will probably become obsolete:

  if ($pm->install [<file> ...]) {
    # everything installed fine
  } else {
    # one or more failed to install
  }

  if ($pm->update [<file> ...]) {
    # everything updated fine
  } else {
    # one or more failed to update
  }

  if ($pm->remove [<package> ...]) {
    # everything was removed fine
  } else {
    # one or more failed to get removed
  }

  my ($installed, $not_installed) = $pm->query_installed [<package> ...];
  # $installed and $not_installed are array refs

  my @versions = $pm->query_versions [<package> ...];
  # undef (as a member within the list) means no version of that package was
  # installed

=head1 ABSTRACT

  PackMan is essentially an abstract class, even though Perl doesn't
  have them. It's expected there will be additional modules under
  PackMan:: to handle concrete package managers while PackMan itself
  acts as the front-door API.

=head1 DESCRIPTION

  All constructors take an optional argument of the root directory
  upon which to operate (if different from '/');

  Methods

  The current root can be changed at any time with the chroot()
  method.

  $pm->chroot ("/mnt/other_root");

  When setting root, another method call may be chained off of it for
  quick, one-off commands:

  OSCAR::PackMan->new->chroot ("/mnt/other_root")->install qw(list of files);

  If you create a PackMan object with an alternative root and want to
  remember that chrooted PackMan:

  $pm = OSCAR::PackMan->new ("/mnt/my_root");
  $chrooted_pm = $pm->clone;

  You can now change $pm back to "/":

  $pm->chroot ("/");    # or $pm->chroot (undef);

  And $chrooted_pm remains pointing at the other directory:

  $chrooted_pm->chroot    # returns "/mnt/my_root"

  All arguments to the chroot method must be absolute paths (begin
  with "/"), and contain no spaces.

  There are five basic methods on PackMan objects. Three are
  procedures that perform an action and return a boolean success
  condition and two are queries.

  The procedures are install, update, and remove. install and update,
  take a list of files as arguments. remove takes a list of packages
  as its argument.

  Both queries also take a list of packages as their arguments.

  install, update, and remove will install, update, and remove
  packages from the system, as expected. query_installed returns two
  lists, the first one is the list of all packages, from the argument
  list, that are installed, the second, the ones that
  aren't. query_versions returns a list of the currently installed
  versions all all packages from the argument list, listing the
  version of packages that aren't actually installed as undef. Status
  gives the status of the current packman object.

  For suggestions for expansions upon or alterations to this API,
  don't hesitate to e-mail the author. Use "Subject: PackMan: ...".

=head2 EXPORT

  None by default.

=head1 Implementation Details

The execution of commands for the actual management of binary packages
(installation, removal and so on), using for instance yume or RAPT, is done
using a child process. This allows PackMan to monitor the progress and 
sub-command. For instance, if the installation of a binary package leads to the
creation of a new image, PackMan monitors the progress for the image creation.

=head1 Error Management

Because tools used by PackMan for the management of binary packages are executed
in a separate process, it is difficult to catch return codes, the process tree
is quickly complex (especially when ptty_try is used). However, since Packman
already monitor commands output, we monitor those message in order to catch any
error messages. Typically, all messages starting by "ERROR" are concidered as
error messages and handled as an exception by PackMan.

=head1 AUTHOR

  Jeff Squyres    <jsquyres@lam-mpi.org>
  Matt Garrett    <magarret@OSL.IU.edu>
  Erich Focht     <efocht@hpce.nec.com>
  Geoffroy Vallee <valleegr@ornl.gov>

=head1 COPYRIGHT AND LICENSE

  Copyright (c) 2003-2004 The Trustees of Indiana University.
                          All rights reserved.
  Copyright (c) 2005-2006 Erich Focht
                          All rights reserved.
  Copyright (c) 2008      Geoffroy Vallee
                          Oak Ridge National Laboratory
                          All rights reserved.

=cut
