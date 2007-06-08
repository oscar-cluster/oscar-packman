package PackMan::DEB;

#   $Id$
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#   Copyright (c) 2003-2004 The Trustees of Indiana University.
#                      All rights reserved.
#   Copyright (c) 2006 Erich Focht <efocht at hpce.nec.com>
#                      All rights reserved.
#

use 5.008;
use strict;
use warnings;
use File::Basename;

use Carp;

our $VERSION;
$VERSION = "r" . q$Rev$ =~ /(\d+)/;

# Must use this form due to compile-time checks by PackMan.
use base qw(PackMan);

# Preloaded methods go here.
# boilerplate constructor because PackMan's is "abstract"
sub new {
  ref (my $class = shift) and croak ("constructor called on instance");
  my $new  = { ChRoot => shift };
  bless ($new, $class);
  return ($new);
}

# convenient constructor alias
sub DEB { 
  return (new (@_)) 
}

# Called by PackMan->new to determine which installed concrete PackMan handler
# claims to be able to manage packages on the target system. Args are the
# root directory being passed to the PackMan constructor.
sub usable {

    ref (shift) and croak ("usable is a class method");
    my $chroot = shift;
    my $rc;

    my $chrootcmd = "";
    if (defined $chroot) {
	if (! ($chroot =~ '^/')) {
	    croak("chroot argument must be an absolute path.");
	}
	$chrootcmd = "chroot $chroot";
    }

    # is dpkg installed an in the path?
    my $dpkg = system("$chrootcmd dpkg --help >/dev/null 2>&1");

    # is apt-get installed an in the path?
    my $aget = system("$chrootcmd apt-get --help >/dev/null 2>&1");

    # is rapt installed an in the path?
    my $rapt = system("$chrootcmd rapt --help >/dev/null 2>&1");

    if ($dpkg) {
        print "Packman: dpkg does not work!\n";
    } elsif ($aget) {
        print "Packman: apt-get does not work!\n";
    } elsif ($rapt) {
        print "Packman: rapt does not work!\n";
    }

    if (!$dpkg && !$aget && !$rapt) {
	return 1;
    }
    return 0;
}

# has smart package manager
sub is_smart {
    return 1;
}

# default handler for progress-meter
sub progress_handler {
    my $self = shift;
    my ($line) = @_;
    if ($line =~ /^Error:/ || $line =~ /^ERROR:/ || $line =~ /^failure:/) {
	return 1;
    }
    return 0 if (!exists($self->{Progress}));
    my $value = $self->{progress_value};
    # check out the corresponding fuction for RPM when implementing this
}



# How to install .deb packages (aggregatable)
sub install_command_line {
  1, 'apt-get install #args --allow-unauthenticated -y'
}

# How to upgrade installed packages (aggregatable)
sub update_command_line {
  1, 'dpkg -i #args'
}

# How to remove installed packages (aggregatable)
sub remove_command_line {
  1, 'dpkg -r --purge #args'
}

# How to query installed packages (not aggregatable)
sub query_installed_command_line {
  0, 'dpkg-query -p #args'
}

# How to query installed package versions (not aggregatable)
sub query_version_command_line {
  0, 'dpkg-query --queryformat %{VERSION}\n #args'
}

# How dpkg changes root
sub chroot_arg_command_line {
  '--root=#chroot'
}

# How rapt changes root
sub smart_chroot_arg_command_line {
    '--installroot #chroot'
}

# How rapt handles one repository
sub repo_arg_command_line {
    '--repo #repo'
}

# How rapt installs packages
sub smart_install_command_line {
    1,'rapt #repos #chroot install #args --allow-unauthenticated -y'
}

# How rapt removes packages
sub smart_remove_command_line {
    1,'rapt #repos -y #chroot remove #args'
}

# Generate repository caches
sub gencache_command_line {
    1,'rapt #repos --prepare'
}


1;
__END__
=head1 NAME

PackMan::DEB - Perl extension for Package Manager abstraction for DEBs

=head1 SYNOPSIS

  Constructors

  # in environment where DEB is the default package manager:
  use PackMan;
  $pm = PackMan->new;

  use PackMan::DEB;
  $pm = DEB->new;	or DEB->DEB;

  use PackMan;
  $pm = PackMan->DEB;

  use PackMan;
  $pm = PackMan::DEB->new;	or PackMan::DEB->DEB;

  For more, see PackMan.

=head1 ABSTRACT

  Specific Package Manager module for PackMan use. Relies on PackMan methods
  inheritted from PackMan, supplying just the specific command-line
  invocations for dpkg(8).

=head1 DESCRIPTION

  Uses PackMan methods suffixed with _command_line to specify the actual
  command-line strings the built-in PackMan methods should use. The first
  return value from the _command_line methods is the boolean indicating
  whether or not the command is aggregatable. Aggregatable describes a command
  where the underlying package manager is capable of outputting the
  per-argument response on a single line, and thus all arguments can be
  aggregated into a single command-line invocation. If an operation is not
  aggregatable, PackMan will iterate over the argument list and invoke the
  package manager separately for each, collecting output and final success or
  failure return value.

  The second return value is the string representing the command as it would
  be invoked on the command-line. ote that no shell processing will be done on
  these, so variable dereferencing and quoting and the like won't work. The
  third return value is a reference to a list of return values from the
  command that indicate success. If the third return value is omitted, zero
  (0) will be assumed.

  At least one of each method: update, install, remove, query_installed,
  query_version, must be defined as either themselves, overriding the PackMan
  built-in, or in its _command_line form, relying on the PackMan built-in. If
  defined as itself, the _command_line form is never used by PackMan in any
  way.

  In the _command_line string, the special tokens #args and #chroot may be
  used to indicate where the arguments to the method call should be grafted
  in, and for chrooted PackMan's, where the chroot_args_command_line syntax
  should be grafted in. The method call arguments will replace #args
  everywhere it appears in the _comand_line form (multiple instances are
  possible). In the case of aggregatable invocations, the entire method
  argument list is substituted. For non-aggregatable invocations, the
  individual file/package is substituted on an iteration by iteration basis.

  The syntax specified to replace the #chroot token is put in
  chroot_args_command_line. It is just a fragment of command-line syntax and
  is not meant to be a command-line to invoke by itself, so it doesn't take an
  aggregatable flag. The #chroot token in chroot_args_command_line is
  fundamentally different from the #chroot token in the other _command_line
  forms. The #chroot token within chroot_args_command_line is replaced by the
  actual value passed to the chroot method. The #chroot token in the invokable
  _command_line forms is only replaced by the syntax from
  chroot_args_command_line if the PackMan object has had a chroot defined for
  it, otherwise, all #chroot tags in those _command_line forms are deleted
  before each invocation.

  Each token, #args and #chroot, has a default location if it is omitted.
  #args goes at the end of the invocation argument list, and #chroot goes
  immediately before the first #args token. In chroot_args_command_line,
  #chroot goes on the end, like #args for the other _command_line forms. As
  such, in this example of a specific PackMan module, all instances of #args
  and #chroot tokens could be removed and it would operate in exactly the same
  way. If these default token locations are not suitable for some other
  specific package manager, the tokens can be placed anywhere after the first
  whitespace character (after the package manager's name).

  I used the long format arguments in this example. A package manager
  abstraction module author is, of course, free to implement his abstraction
  any way he wishes. So long as it inherits from PackMan and is located under
  the PackMan directory, PackMan will be able to find it and use it.

  For suggestions for expansions upon or alterations to the PackMan API, don't
  hesitate to e-mail the author. Use "Subject: PackMan: ...". For questions
  about this module, use "Subject: PackMan::RPM: ...". For questions about
  creating a new PackMan specific module (ex. Debian, Slackware, Stampede, et
  al.), use "Subject: PackMan::specific: ..."

=head2 EXPORT

  None by default.

=head1 SEE ALSO

  PackMan
  rpm(8)

=head1 AUTHOR

  Matt Garrett, E<lt>magarret@OSL.IU.eduE<gt>

=head1 COPYRIGHT AND LICENSE

  Copyright (c) 2003 The Trustees of Indiana University.
                    All rights reserved.

  This file is part of the OSCAR software package.  For license
  information, see the COPYING file in the top level directory of the
  OSCAR source distribution.
 
=cut
