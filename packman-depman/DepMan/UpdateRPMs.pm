package DepMan::UpdateRPMs;

# Copyright (c) 2003-2004 The Trustees of Indiana University.
#                         All rights reserved.
#

use strict;
use warnings;

use Carp;

our $VERSION;
$VERSION = "r" . q$Rev: 19 $ =~ /(\d+)/;

# Must use this form due to compile-time checks by DepMan.
use base qw(DepMan);

# Preloaded methods go here.
# boilerplate constructor because DepMan's is "abstract"
sub new {

#  use OSCAR::oda;

  ref (my $class = shift) and croak ("constructor called on instance");
  my $new_obj_ref = { 'ChRoot' => shift, 'Cache' => shift };

  if ((! (defined ($new_obj_ref->{'Cache'}))) &&
      (system("which oda > /dev/null 2>&1") == 0) && 
      (system("oda list_tables > /dev/null 2>&1") == 0) && 
      (system("oda read_records oscar_file_server > /dev/null 2>&1") == 0)) {

# This means that ODA will never be used from here due to the flaky nature of
# the OSCAR prereq structure.

# Added to get actual Cache from ODA
#  my %oscar_file_server;
#  database_read_table_fields ("oscar_file_server" "oscar_httpd_server_url",
#			      null, \%oscar_file_server, 1) &&
#  $new_object{'Cache'} = $oscar_file_server{oscar_httpd_server_url};
#
# FIX THIS. It needs to access oda via the Perl interface, not by invoking the
# oda command line tool.
# -- MCG

#  my $oda_fh = open ('-|',
#    'oda read_records oscar_file_server oscar_httpd_server_url | head -1');
#  read ($oda_fh, $new_obj{'Cache'}, 80);
  $new_obj_ref->{'Cache'} = `oda read_records oscar_file_server oscar_httpd_server_url | head -1`;
  $new_obj_ref->{'Cache'} =~ s/\n$//g;
  $new_obj_ref->{'Cache'} =~ s/\r$//g;
#  close ($oda_fh);
  } else {
    # data shared with .../oscar/share/prereqs/00update-rpms/scripts/setup
    $new_obj_ref->{'Cache'} = "/var/cache/update-rpms";
  }

  bless ($new_obj_ref, $class);
  return ($new_obj_ref);
}

# convenient constructor alias
sub UpdateRPMs { 
  return (new (@_)) 
}

# Called by DepMan->new to determine which installed concrete DepMan handler
# claims to be able to manage package dependencies on the target system. Args
# are the root directory being passed to the PackMan constructor.
sub usable {
  my @DISTROFILES = qw( fedora-release
                        mandrake-release
                        mandrakelinux-release
			mandriva-release
                        redhat-release
                        redhat-release-as
                        aaa_version
                        aaa_base
                        sl-release
                        centos-release
                      );

  ref (shift) and croak ("usable is a class method");
  my $chroot = shift;
  my $rc;

  if (defined $chroot) {
    if (! ($chroot =~ '^/')) {
      croak ("chroot argument must be an absolute path.");
    }
  }

  foreach my $distro (@DISTROFILES) {
    if (defined $chroot) {
      $rc = system ("rpm --query --root=${chroot} ${distro} > /dev/null 2>&1");
    } else {
      $rc = system ("rpm --query ${distro} > /dev/null 2>&1");
    }
    if (($rc / 256) == 0) {
      return (1);
    }
  }

  return (0);
}

# How update-rpms(8) queries uninstalled package file dependencies
# (aggregatable)
sub query_required_by_command_line {
  #ARGH! Why is it outputting to stderr?
  1, 'update-rpms --check --quiet --cache=u #cache #args 2>&1';
}

# How update-rpms(8) queries installed package dependencies
# (aggregatable)
sub query_requires_command_line {
  0, 'update-rpms --check --remove --quiet #cache #args'
}

# How update-rpms(8) changes root
sub chroot_arg_command_line {
  '--root=#chroot'
}

# How update-rpms(8) specifies the location of its database cache
sub cache_arg_command_line {
  '--cachedir=#cache'
}

1;
__END__
=head1 NAME

DepMan::UpdateRPMs - Perl extension for Dependency Manager abstraction for RPMs

=head1 SYNOPSIS

  Constructors

  # in environment where RPM is the default package manager and the
  # update-rpms default database directory exists:
  use DepMan;
  $dm = DepMan->new;

  # otherwise
  use DepMan::UpdateRPMs;
  $dm = UpdateRPMs->new;		or UpdateRPMs->UpdateRPMs;

  use DepMan;
  $dm = DepMan->UpdateRPMs;

  use DepMan;
  $dm = DepMan::UpdateRPMs->new;	or DepMan::UpdateRPMs->UpdateRPMs;

  For more, see DepMan.

=head1 ABSTRACT

  Specific Dependency Manager module for DepMan use. Relies on DepMan methods
  inheritted from DepMan, supplying just the specific command-line
  invocations for update-rpms(8).

=head1 DESCRIPTION

  Uses DepMan methods suffixed with _command_line to specify the
  actual command-line strings the built-in DepMan methods should
  use. The first return value from the _command_line methods is the
  boolean indicating whether or not the command is
  aggregatable. Aggregatable describes a command where the underlying
  dependency manager is capable of outputting the per-argument
  responce on a single line, and thus all arguments can be aggregated
  into a single command-line invocation. If an operation is not
  aggregatable, DepMan will iterate over the argument list and invoke
  the dependency manager separately for each, collecting output and
  final success or failure return value.

  The second return value is the string representing the command as it
  would be invoked on the command-line. Note that no shell processing
  will be done on these, so variable dereferencing and quoting and the
  like won't work. The third return value is a reference to a list of
  return values from the command that indicate success. If the third
  return value is omitted, zero (0) will be assumed.

  At least one of each method: query_requires, query_required_by, must
  be defined as either themselves, overriding the DepMan built-in, or
  in its command_line form, relying on the DepMan built-in. If defined
  as itself, the command_line form is never used by DepMan in any way.

  In the _command_line string, the special tokens #args and #chroot
  may be used to indicate where the arguments to the method call
  should be grafted in, and for chrooted DepMan's, where the
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
  if the DepMan object has had a chroot defined for it, otherwise, all
  #chroot tags in those _command_line forms are deleted before each
  invocation.

  Each token, #args and #chroot, has a default location if it is
  omitted.  #args goes at the end of the invocation argument list, and
  #chroot goes immediately before the first #args token. In
  chroot_args_command_line, #chroot goes on the end, like #args for
  the other _command_line forms. As such, in this example of a
  specific DepMan module, all instances of #args and #chroot tokens
  could be removed and it would operate in exactly the same way. If
  these default token locations are not suitable for some other
  specific package manager, the tokens can be placed anywhere after
  the first whitespace character (after the dependency manager's
  name).

  I used the long format arguments in this example. A package manager
  abstraction module author is, of course, free to implement his
  abstraction any way he wishes. So long as it inherits from DepMan
  and is located under the DepMan directory, DepMan will be able to
  find it and use it.

  For suggestions for expansions upon or alterations to the DepMan
  API, don't hesitate to e-mail the author. Use "Subject: DepMan:
  ...". For quesitons about this module, use "Subject:
  DepMan::UpdateRPMs: ...". For questions about creating a new DepMan
  specific module (ex. Debian, Slackware, Stampede, et al.), use
  "Subject: DepMan::specific: ..."

=head2 EXPORT

  None by default.

=head1 SEE ALSO

  DepMan
  update-rpms(8)

=head1 AUTHOR

  Jeff Squyres, E<lt>jsquyres@lam-mpi.orgE<gt>
  Matt Garrett, E<lt>magarret@OSL.IU.eduE<gt>

=head1 COPYRIGHT AND LICENSE

  Copyright (c) 2003-2004 The Trustees of Indiana University.
                          All rights reserved.

=cut
