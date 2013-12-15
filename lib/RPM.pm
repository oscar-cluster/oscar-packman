package OSCAR::PackMan::RPM;

# Copyright (c) 2003-2004 The Trustees of Indiana University.
#
# Copyright (c) 2006      Erich Focht <efocht@hpce.nec.com>
#                         All rights reserved.
#
# $Id$

use strict;
use warnings;

use Carp;

our $VERSION;
$VERSION = "r" . q$Rev$ =~ /(\d+)/;

# Must use this form due to compile-time checks by PackMan.
use base qw(OSCAR::PackMan);

# Preloaded methods go here.
# boilerplate constructor because PackMan's is "abstract"
sub new {
  ref (my $class = shift) and croak ("constructor called on instance");
  my $new  = { ChRoot => shift, Format => "RPM", Distro => undef };
  bless ($new, $class);
  return ($new);
}

# convenient constructor alias
sub RPM { 
  return (new (@_)) 
}

# Called by PackMan->new to determine which installed concrete PackMan handler
# claims to be able to manage packages on the target system.
# Passed argument: the root directory being passed to the PackMan constructor.
# If undef, the current "/" filesystem is probed.
sub usable {

    ref (shift) and croak ("usable is a class method");
    my $chroot = shift;

    my $chrootcmd = "";
    if (defined $chroot) {
	if (! ($chroot =~ '^/')) {
	    croak("chroot argument must be an absolute path.");
	}
	$chrootcmd = "chroot $chroot";
    }

    # is rpm installed an in the path?
    my $rpm = system("$chrootcmd rpm --help >/dev/null 2>&1");

    # is yume installed an in the path?
    my $yume = system("$chrootcmd yume --help >/dev/null 2>&1");

    if (!$rpm && !$yume) {
	return 1;
    }
    return 0;
}

# has smart package manager
sub is_smart {
    return 1;
}

# default handler for progress-meter
# - prints
# Return: 0 if success, 1 else.
sub progress_handler {
    my $self = shift;
    my ($line) = @_;
    if ($line =~ /^Error:/ || $line =~ /^ERROR:/ || $line =~ /^failure:/) {
	return 1;
    }
    return 0 if (!exists($self->{Progress}));
    my $value = $self->{progress_value};
    my ($lines_so_far, $totallines);
    if ($line =~ /Setting up/) {
	$value = 2;
    } elsif ($line =~ /Resolving Dependencies/) {
	$value = 6;
    } elsif ($line =~ /Dependencies Resolved/) {
	$value = 15;
    }
    if ($line =~ /done (\d+)\/(\d+)[^\d]/) {
	$lines_so_far = $1;
	$totallines = $2;
    } elsif ($line =~ /Installing:.*\[\s*(\d+)\s*\/\s*(\d+)\s*\]/) {
	$lines_so_far = $1;
	$totallines = $2;
    }
    if ($totallines) {
	#print "totallines,lines_so_far = $totallines,$lines_so_far\n";
	$value = 15 + (100 - 15) * $lines_so_far / $totallines;
	$value = 100 if $value > 100;
    }
    if ($value) {
	my $ovalue = $self->{progress_value};
	if ($ovalue != $value) {
	    $self->{progress_value} = $value;
	    printf "[progress: %d]\n", $value;
	}
    }
    return 0;
}

#
# Return package which provides a certain feature.
#
sub whatprovides {
    my $self = shift;
    my $capability = shift;

    my $p = `rpm -q --whatprovides "$capability"`;
    if ($?) {
	return "";
    }
    return chomp($p);
}

# How rpm(8) installs packages (aggregatable)
sub install_command_line {
  1, 'rpm --install -vh #args'
}

# How rpm(8) upgrades installed packages (aggregatable)
sub update_command_line {
  1, 'rpm --upgrade -vh #args'
}

# How rpm(8) removes installed packages (aggregatable)
sub remove_command_line {
  1, 'rpm --erase #args'
}

# How rpm(8) queries installed packages (not aggregatable)
sub query_installed_command_line {
  1, 'rpm --query --qf \'found: %{NAME} %{VERSION}-%{RELEASE} %{ARCH}\\n\' #args'
}

sub query_list_installed_pkgs_command_line {
  1, 'rpm -qa'
}

# How rpm(8) changes root
sub chroot_arg_command_line {
  '--root #chroot'
}

# How yume changes root
sub smart_chroot_arg_command_line {
    '--installroot #chroot'
}

# How yume handles one repository
sub repo_arg_command_line {
    '--repo #repo'
}

# How rapt handles the specification of a distro
sub distro_arg_command_line {
    '--distro #distro'
}

# How yume installs packages
sub smart_install_command_line {
    1,'yume #repos -y #chroot install #args'
}

# How yume removes packages
sub smart_remove_command_line {
    1,'yume #repos -y #chroot remove #args'
}

# How yume updates packages
sub smart_update_command_line {
    1,'yume #repos -y #chroot update #args'
}

# How to search packages in a repository
sub search_repo_update_command_line {
    1,'yume #repos #chroot --repoquery --nevra #args'
}

# Clear yum caches
sub do_clean {
    return system("yume #repos #chroot clean all");
}

# Generate repository caches
sub gencache_command_line {
    1,'yume #repos --prepare'
}

# How to search packages in a repository
sub search_repo_command_line {
    1,'yume #repos #chroot search #args'
}

# How to show packages details in a repository
sub show_repo_command_line {
    1, 'yume #repos #chroot info #args'
}

1;
__END__
=head1 NAME

OSCAR::PackMan::RPM - Perl extension for Package Manager abstraction for RPMs

=head1 SYNOPSIS

  Constructors

  # in environment where RPM is the default package manager:
  use OSCAR::PackMan;
  $pm = PackMan->new;

  use OSCAR::PackMan::RPM;
  $pm = RPM->new;	or RPM->RPM;

  use OSCAR::PackMan;
  $pm = PackMan->RPM;

  use OSCAR::PackMan;
  $pm = PackMan::RPM->new;	or PackMan::RPM->RPM;

  For more, see PackMan.

=head1 ABSTRACT

  Specific Package Manager module for PackMan use. Relies on PackMan
  methods inheritted from PackMan, supplying just the specific
  command-line invocations for rpm(8).

=head1 DESCRIPTION

  Uses PackMan methods suffixed with _command_line to specify the
  actual command-line strings the built-in PackMan methods should
  use. The first return value from the _command_line methods is the
  boolean indicating whether or not the command is
  aggregatable. Aggregatable describes a command where the underlying
  package manager is capable of outputting the per-argument response
  on a single line, and thus all arguments can be aggregated into a
  single command-line invocation. If an operation is not aggregatable,
  PackMan will iterate over the argument list and invoke the package
  manager separately for each, collecting output and final success or
  failure return value.

  The second return value is the string representing the command as it
  would be invoked on the command-line. ote that no shell processing
  will be done on these, so variable dereferencing and quoting and the
  like won't work. The third return value is a reference to a list of
  return values from the command that indicate success. If the third
  return value is omitted, zero (0) will be assumed.

  At least one of each method: update, install, remove,
  query_installed, query_version, must be defined as either
  themselves, overriding the PackMan built-in, or in its _command_line
  form, relying on the PackMan built-in. If defined as itself, the
  _command_line form is never used by PackMan in any way.

  In the _command_line string, the special tokens #args and #chroot
  may be used to indicate where the arguments to the method call
  should be grafted in, and for chrooted PackMan's, where the
  chroot_args_command_line syntax should be grafted in. The method
  call arguments will replace #args everywhere it appears in the
  _comand_line form (multiple instances are possible). In the case of
  aggregatable invocations, the entire method argument list is
  substituted. For non-aggregatable invocations, the individual
  file/package is substituted on an iteration by iteration basis.

  The syntax specified to replace the #chroot token is put in
  chroot_args_command_line. It is just a fragment of command-line
  syntax and is not meant to be a command-line to invoke by itself, so
  it doesn't take an aggregatable flag. The #chroot token in
  chroot_args_command_line is fundamentally different from the #chroot
  token in the other _command_line forms. The #chroot token within
  chroot_args_command_line is replaced by the actual value passed to
  the chroot method. The #chroot token in the invokable _command_line
  forms is only replaced by the syntax from chroot_args_command_line
  if the PackMan object has had a chroot defined for it, otherwise,
  all #chroot tags in those _command_line forms are deleted before
  each invocation.

  Each token, #args and #chroot, has a default location if it is
  omitted.  #args goes at the end of the invocation argument list, and
  #chroot goes immediately before the first #args token. In
  chroot_args_command_line, #chroot goes on the end, like #args for
  the other _command_line forms. As such, in this example of a
  specific PackMan module, all instances of #args and #chroot tokens
  could be removed and it would operate in exactly the same way. If
  these default token locations are not suitable for some other
  specific package manager, the tokens can be placed anywhere after
  the first whitespace character (after the package manager's name).

  Since the introduction of support for smart package managers like yum
  two additional tokens have been added: #repos and #repo. #repo will be
  replaced by the particular repository URL in the repo_arg_command_line
  string. The replaced string, possibly built out of multiple such
  replacements for multiple repositories, will replace the #repos token in
  the smart commands which require repository arguments.

  The long format arguments were used in this example. A package manager
  abstraction module author is, of course, free to implement his
  abstraction any way he wishes. So long as it inherits from PackMan
  and is located under the PackMan directory, PackMan will be able to
  find it and use it.

  For suggestions for expansions upon or alterations to the PackMan
  API, don't hesitate to e-mail the author. Use "Subject: PackMan:
  ...". For questions about this module, use "Subject: PackMan::RPM:
  ...". For questions about creating a new PackMan specific module
  (ex. Debian, Slackware, Stampede, et al.), use "Subject:
  PackMan::specific: ..."

=head2 EXPORT

  None by default.

=head1 SEE ALSO

  OSCAR::PackMan
  rpm(8)

=head1 AUTHOR

  Jeff Squyres, E<lt>jsquyres@lam-mpi.orgE<gt>
  Matt Garrett, E<lt>magarret@OSL.IU.eduE<gt>
  Erich Focht,  E<lt>efocht@hpce.nec.comE<gt>

=head1 COPYRIGHT AND LICENSE

  Copyright (c) 2003-2004 The Trustees of Indiana University.
                          All rights reserved.
  Copyright (c) 2006 Erich Focht

=cut
