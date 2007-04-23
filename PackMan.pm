package PackMan;

# Copyright (c) 2003-2004 The Trustees of Indiana University.
# Copyright (c) 2006      Erich Focht <efocht@hpce.nec.com>
#                         All rights reserved.
# $Id$

use strict;
use warnings;

use Carp;
use File::Spec;

use Data::Dumper;

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

my $installed_dir;

# Preloaded methods go here.
BEGIN {
    $installed_dir = "OSCAR";	# ugly hack

# change to qw(RPM DEB) when Deb gets written
# If, by hook or crook, you are on a system where both RPM and DEB (and
# whatever other package managers) will claim usability for a given
# filesystem, rank them in @preference. Recognition as the default package
# manager is on a first-come, first-served basis out of @preference. If no
# default package manager can be determined, all available package managers
# will be consulted in an indeterminant order in a final attempt to find one
# that's usable.
# !!GV!! Because Debian supports both rpm and deb and since rpm based distris
# do not support deb (at least for what i know), i changed the order
    @preference = qw(DEB RPM);

    my $packman_dir = File::Spec->catdir ($installed_dir,
					  split ("::", __PACKAGE__));
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
	croak "Couldn't access concrete " . __PACKAGE__ . " implementations: $!";

    foreach my $pm (readdir (PACKMANDIR)) {
	# only process .pm files
	if ($pm =~ m/\.pm$/) {
	    require File::Spec->catfile ($packman_dir, $pm);
	    $pm =~ s/\.pm$//;
	    my $module = $packman_dir;
	    # Calling isa requires that the installed directory be stripped.
	    $module =~ s:^$installed_dir/::;
	    $module = join ("::", File::Spec->splitdir ($module)) . "::" . $pm;
	    # if it's actually a PackMan module, remember it
	    if ("$module"->isa (__PACKAGE__)) {
		$concrete{$pm} = $module;
	    }
	}
    }
    closedir (PACKMANDIR);

    scalar %concrete or
    croak "No concrete " . __PACKAGE__ . " implementations could be found!";

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
    ref (shift) and
	croak __PACKAGE__ . " constructor is a class method.";

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
	if (defined ($chroot) && (($chroot =~ m/\s+/) || ! ($chroot =~ m/^\//))) {
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
	$self->{Repos} = \@repos;
	return (scalar(@repos));
    } else {
	return 0;
    }
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

# bit of boilerplate for completely handling the #chroot and guaranteeing
# certain properties of the #args tags in *_command_line returned strings.
# Also breaks off the command name for separate handling.
sub command_helper {
    ref (my $self = shift) or croak "command_helper is an instance method";
    my $command_line_helper = shift;

    my ($aggregatable, $cl, $success) = $self->$command_line_helper;
    my @command_line = split /\s+/, $cl;
    my $command = shift @command_line;
    $cl = join (" ", @command_line);
    my $chroot_arg;

    # repositories replacement
    if (defined ($self->{Repos})) {
	# substitute value of $Repos into implementation's repo_arg_command_line
	$self->can ('repo_arg_command_line') or
	    croak "Concrete " . __PACKAGE__ . " module doesn't implement method " .
	    "repo_arg_command_line";

	# do we need to add repository at all?
	if ($cl =~ m,#repos,) {
	    my @repos_args;
	    for my $r (@{$self->{Repos}}) {
		my $tmp = $self->repo_arg_command_line;
		$tmp =~ s/#repo/$r/g;
		push @repos_args, $tmp;
	    }
	    my $repos = join(" ",@repos_args);
	    $cl =~ s/#repos/$repos/g;
	}
    }

    # chroot replacement
    if (defined ($self->{ChRoot})) {
	# substitute value of $ChRoot into implementation's chroot_arg_command_line
	$self->can ('chroot_arg_command_line') or
	    croak "Concrete " . __PACKAGE__ . " module doesn't implement method " .
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
    if (! ($cl =~ m/#args/)) {
	$cl = $cl . " #args";
    }
    return ($aggregatable, $command, $cl, $success);
}

# template for install, upgrade, and remove command operations
sub do_simple_command {
    my $self = shift;
    my $command_name = shift;
    local *SYSTEM;

    ref ($self) or croak $command_name . " is an instance method";
    $self->can ($command_name . '_command_line') or
	croak "Concrete " . __PACKAGE__ . " module implements neither method " .
	$command_name . "install nor " . $command_name . "_command_line";

    my @lov = @_;	# list of victims
    my ($aggregatable, $command, $cl) =
	$self->command_helper ($command_name . '_command_line');
    my @captured_output;
    my $retval = 0;
    my ($callback, $cbargs, $line);

    $callback = $self->{Callback} if (defined($self->{Callback}));
    $cbargs = $self->{Callback_Args} if (defined($self->{Callback_Args}));


    # This is a hack to let the child behave as if it runs in a tty
    # Without it yum doesn't show progress information.
    my $pty = "/usr/bin/ptty_try";
    if (-x $pty) {
	$command = "$pty $command";
    }

    my $rr = 0;
    if ($aggregatable) {
	@captured_output = undef;
	my $all_args = join " ", @lov;
	$cl =~ s/#args/$all_args/g;

	my $pid = open(SYSTEM, "-|");
	defined ($pid) or die "can't fork: $!";

	if ($pid) {
	    #
	    # parent
	    #
	    while ($line = <SYSTEM>) {
	    	chomp $line;
	    	push @captured_output, $line;
		$rr = $self->progress_handler($line);
		$retval = 1 if ($rr);
	    	if ($callback) {
	    	    &{$callback}($line, @{$cbargs});
	    	}
	    }
	    close SYSTEM;
	    my $err = $?;
	    if ($retval == 0) {
		$retval = $err;
	    }
	} else {
	    #
	    # child
	    #

	    exec ("$command $cl") or die "can't exec program: $!";
	}
    } else {
	foreach my $package (@lov) {
	    @captured_output = undef;
	    my $pid = open (SYSTEM, "-|");
	    defined ($pid) or die "cannot fork: $!";
	    select SYSTEM; $| = 1;  # try to make unbuffered
	    if ($pid) {
		while ($line = <SYSTEM>) {
		    chomp $line;
		    push @captured_output, $line;
		    $rr = $self->progress_handler($line);
		    $retval = 1 if ($rr);
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
		my $line = $cl;
		$line =~ s/#args/$package/g;
		exec ($command, split /\s+/, $line) or die "can't exec program: $!";
	    }
	}
    }
    return (($retval?0:1), @captured_output);
}

# Command the underlying package manager to install each of the package files
# in the argument list. Returns a failure value if any of the operations
# fails. In non-aggregated mode, all packages which can be installed are
# guaranteed to be installed. In aggregated mode, such guarantee depends on
# the operation of the underlying package manager.
#
# [Erich Focht]: this command is deprecated. Use smart_install instead.

sub install {
    ref (my $self = shift) or croak "install is an instance method";
    if ((scalar @_) == 0) {
	return (0);
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
sub update {
    ref (my $self = shift) or croak "update is an instance method";
    return ($self->do_simple_command ('update', @_));
}

# Command the underlying package manager to remove each of the packages in the
# argument list. Returns a failure value if any of the operations fails. In
# non-aggregated mode, all packages which can be removed are guaranteed to be
# removed. In aggregated mode, such guarantee depends on the operation of the
# underlying package manager.
#
# [Erich Focht]: this command is deprecated. Use smart_install instead.
sub remove {
    ref (my $self = shift) or croak "remove is an instance method";
    if ((scalar @_) == 0) {
	return (0);
    }
    return ($self->do_simple_command ('remove', @_));
}

# Query the underlying package manager to report the list of which of the
# packages in the argument list are presently installed and which are
# uninstalled.
#
# [Erich Focht]: this command will probably become obsolete
sub query_installed {
    my @installed;
    my @not_installed;
    ref (my $self = shift) or croak "query_installed is an instance method";

    # save existing callback
    my ($save_cb, $save_cba);
    if ($self->{Callback}) {
	$save_cb = $self->{Callback};
	$save_cba = $self->{Callback_Args};
    }

    # filter routine to be used as temporary callback
    sub filter_installed {
	my ($line, $installed, $not_installed) = @_;
	if ($line =~ m/^\w+\s+(\S+)\s/) {
	    # horrible kludge alert!
	    # assumes second whitespace delimited field is our argument name
	    push @{$not_installed}, $1;
	} else {
	    push @{$installed}, $line;
	}
    }

    # register temporary callback
    $self->output_callback(\&filter_installed,\@installed,\@not_installed);

    # execute command and temporary callback for each output line
    $self->do_simple_command ('query_installed', @_);
    if ($save_cb) {
	$self->output_callback($save_cb, @{$save_cba});
    } else {
	delete $self->{Callback};
	delete $self->{Callback_Args};
    }
    return (\@installed, \@not_installed);
}


# Query the underlying package manager to report the versions of each of the
# packages listed in the arguments. Order of report/return value corresponds
# to the order of the argument list. undef value means corresponding package
# was not installed.
#
# [Erich Focht]: this command will probably become obsolete
sub query_version {
    my @versions;
    ref (my $self = shift) or croak "query_version is an instance method";

    # save existing callback
    my ($save_cb, $save_cba);
    if ($self->{Callback}) {
	$save_cb = $self->{Callback};
	$save_cba = $self->{Callback_Args};
    }

    # filter routine to be used as temporary callback
    sub filter_version {
	my ($line, $versions) = @_;
	if ($line =~ m/[ \t]+/) {
	    # horrible kludge alert!
	    # assumes any whitespace is an indication of failure
	    push @{$versions}, undef;
	} else {
	    push @{$versions}, $line;
	}
    }

    # register temporary callback
    $self->output_callback(\&filter_version,\@versions);

    # execute command and temporary callback for each output line
    $self->do_simple_command ('query_version', @_);

    # restore old callback
    if ($save_cb) {
	$self->output_callback($save_cb, @{$save_cba});
    } else {
	delete $self->{Callback};
	delete $self->{Callback_Args};
    }
    return (@versions);
}

# Command the smart package manager to install each of the package files
# in the argument list and resolve dependencies automatically.
# Returns a pair of values: ($err, $out_ref)
# $err contains a failure value if any of the operations fails.
# $out_ref is a reference to an array containing the output of the command.
# Smart installs should allways run in aggregated mode.
sub smart_install {
    ref (my $self = shift) or croak "smart_install is an instance method";
    if ((scalar @_) == 0) {
	return (0);
    }
    my ($err, @out) = $self->do_simple_command('smart_install', @_);

    #my ($inst, $notinst) = $self->query_installed(@_);
    #if (scalar(@{$notinst})) {
    #	print "WARNING: Some packages were not installed!\n";
    #	print "    ".join(" ",@{$notinst})."\n";
    #	$err = 0;
    #}
    return ($err,@out);
}

# Command the smart package manager to remove each of the package files
# in the argument list. It also removes all packages depending on these ones!
# Returns a pair of values: ($err, $out_ref)
# $err contains a failure value if any of the operations fails.
# $out_ref is a reference to an array containing the output of the command.
sub smart_remove {
    ref (my $self = shift) or croak "smart_remove is an instance method";
    if ((scalar @_) == 0) {
	return (0);
    }
    return ($self->do_simple_command ('smart_remove', @_));
}

# Command the smart package manager to update each of the package files
# in the argument list by using the repositories and taking the newest
# package versions from there.
# Returns a pair of values: ($err, $out_ref)
# $err contains a failure value if any of the operations fails.
# $out_ref is a reference to an array containing the output of the command.
sub smart_update {
    ref (my $self = shift) or croak "smart_update is an instance method";
    return ($self->do_simple_command ('smart_update', @_));
}

# Clean all smart package manager caches
sub clean {
    ref (my $self = shift) or croak "clean is an instance method";
    return ($self->do_clean);
}

# Generate repository caches for local repositories
sub gencache {
    ref (my $self = shift) or croak "gencache is an instance method";
    return ($self->do_simple_command ('gencache', @_));
}

# ###
# Functiones for exporting repositories via HTTPD
# These were taken from "yume" such that other package managers
# can also make use of them. [Erich Focht, 2006]
# Most of these are not "methods" but "functions", because yume uses
# them without creating packman instances.
# ###

# export repositories belonging to the current packman instance
# through httpd
sub repo_export {
    ref (my $self = shift) or croak "repo_export is an instance method";
    return add_httpd_conf(@{$self->{Repos}});
}

# unexport repositories belonging to the current packman instance
# through httpd
sub repo_unexport {
    ref (my $self = shift) or croak "repo_unexport is an instance method";
    return del_httpd_conf(@{$self->{Repos}});
}

# locate httpd configuration directory
# this is somewhat hardwired and might need to be extended
sub find_httpdir {
    my $httpdir;
    for my $d ("httpd", "apache", "apache2") {
	if (-d "/etc/$d/conf.d") {
	    $httpdir = "/etc/$d/conf.d";
	    last;
	}
    }
    if ($verbose) {
	print "Found httpdir = $httpdir\n";
    }
    return $httpdir;
}

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
		    print "Could not find directory $repo. Skipping.\n";
		    $err++;
		    next;
		}
		my $pname = "repo$repo";
		my $rname = $pname;
		$rname =~ s:/:_:g;
		my $cname = "$httpdir/$rname.conf";
		if (-f $cname) {
		    print "Config file $cname already existing. Skipping.\n";
		    next;
		}
		print "Exporting $repo through httpd, http://$hostname/$pname\n";
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
		print "Repository URL is not a local absolute path!\n";
		print "Skipping $repo\n";
		$err++;
		next;
	    }
	}
    } else {
	print "Could not find directory $httpdir!\n";
	print "Cannot setup httpd configuration for repositories.\n";
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
		    print "Deleting config file $cname\n";
		    if (unlink($cname)) {
			print "WARNING: Could not delete $cname : $!\n";
			$err++;
		    } else {
			++$changed;
		    }
		}
	    } else {
		print "Repository URL is not a local absolute path!\n";
		print "Skipping $repo\n";
		$err++;
		next;
	    }
	}
    } else {
	print "Could not find directory $httpdir!\n";
	print "Cannot delete httpd configuration for repositories.\n";
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
	    print "URL $alias : Repository --repo $rdir\n";
	}
    }
}

sub restart_httpd {
    for my $httpd ("httpd", "httpd2", "apache", "apache2") {
	if (-x "/etc/init.d/$httpd") {
	    print "Restarting $httpd\n";
	    system("/etc/init.d/$httpd restart");
	    last;
	}
    }
}


1;
__END__

=head1 NAME

PackMan - Perl extension for Package Manager abstraction

=head1 SYNOPSIS

  Constructors

  use PackMan;
  $pm = PackMan->new;

  Concrete package managers will always be available directly as:

  use PackMan::<conc>;
  $pm = <conc>->new;

  use PackMan;
  $pm = PackMan-><conc>;

  use PackMan;
  $pm = PackMan::<conc>->new;

  Currently, the only valid value for <conc> is RPM.


  Methods

  $new_pm = $pm->clone;

  $pm->chroot ("/mnt/other_root");

  $pm->chroot ("/");	# wrong, will cause chroot argument substitute anyway
  $pm->chroot (undef);	# right, no chroot argument will be used

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

  PackMan->new->chroot ("/mnt/other_root")->install qw(list of files);

  If you create a PackMan object with an alternative root and want to
  remember that chrooted PackMan:

  $pm = PackMan->new ("/mnt/my_root");
  $chrooted_pm = $pm->clone;

  You can now change $pm back to "/":

  $pm->chroot ("/");	# or $pm->chroot (undef);

  And $chrooted_pm remains pointing at the other directory:

  $chrooted_pm->chroot	# returns "/mnt/my_root"

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
  version of packages that aren't actually installed as undef.

  For suggestions for expansions upon or alterations to this API,
  don't hesitate to e-mail the author. Use "Subject: PackMan: ...".

=head2 EXPORT

  None by default.

=head1 SEE ALSO

  DepMan

=head1 AUTHOR

  Jeff Squyres, E<lt>jsquyres@lam-mpi.orgE<gt>
  Matt Garrett, E<lt>magarret@OSL.IU.eduE<gt>
  Erich Focht,  E<lt>efocht@hpce.nec.comE<gt>

=head1 COPYRIGHT AND LICENSE

  Copyright (c) 2003-2004 The Trustees of Indiana University.
                          All rights reserved.
  Copyright (c) 2005-2006 Erich Focht
                          All rights reserved.

=cut
