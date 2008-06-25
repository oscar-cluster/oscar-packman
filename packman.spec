%define binpref /usr/bin
%define libpref /usr/lib/perl5/site_perl/OSCAR
%define manpref /usr/share/man/man3
%define bintarget $RPM_BUILD_ROOT%{binpref}
%define libtarget $RPM_BUILD_ROOT%{libpref}
%define mantarget $RPM_BUILD_ROOT%{manpref}

Summary:		A package and dependency manager abstraction layer.
Name:      		packman
Version:   		3.0.0
Release:   		1
Vendor:			Open Cluster Group <http://OSCAR.OpenClusterGroup.org/>
Distribution:		OSCAR
Packager:		Erich Focht <efocht@hpce.nec.com>
License: 		GPL
Group:     		Development/Libraries
Source:			%{name}.tar.gz
BuildRoot: 		%{_localstatedir}/%{name}-root
BuildArch:		noarch

%description
A collection of Perl object modules for use in the OSCAR framework (among
other places) to facilitate the transparent utilization of the native
underlying package manager and dependency manager infrastructure across a wide
range of Linux/UNIX Operating System distributions through a standardized
interface.

%prep
%setup -n %{name}

%build
make

%install
%__rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT LIBDIR=/usr/lib/perl5/site_perl/OSCAR

%clean rpms
%__rm -rf $RPM_BUILD_ROOT

%files 
%defattr(-,root,root)
%{binpref}/packman
%{libpref}/PackMan.pm
%{manpref}/PackMan.3.*
%{libpref}/PackManDefs.pm
%{libpref}/PackMan/RPM.pm
%{libpref}/PackMan/DEB.pm
%{manpref}/PackMan-RPM.3.*
%{manpref}/PackMan-DEB.3.*


%changelog
* Wed Jun 25 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.0.0-1
- new upstream version (see ChangeLog for more details).
* Tue Jun 24 2008 Geoffroy Vallee <valleegr@ornl.gov> 2.9.2-1
- new upstream version (see ChangeLog for more details).
* Sun Jun 22 2008 Geoffroy Vallee <valleegr@ornl.gov> 2.9.1-1
- new upstream version (see ChangeLog for more details).
* Thu Nov 08 2007 Erich Focht -> 2.9.0-1
- fixed query_installed bugs
- added whatprovides method to RPM module, this is missing in Debian
- added check_installed method for checking if a list of packages is installed
- added search_repo method for searching a repository for packages matching a pattern
- added clean method implementation for apt caches
- limited clean method scope to the configured repositories
* Fri Dec 22 2006 Geoffroy Vallee <valleegr@ornl.gov>
- add debugging information for the Debian part of packman.
* Sun Jul 16 2006 Geoffroy Vallee <valleegr@ornl.gov>
- change the order of preferences for the backends. It is now (DEB, RPM).
* Tue May 08 2006 Erich Focht
- added DEB.pm
* Mon Apr 10 2006 Erich Focht
- added repo_export and repo_unexport methods.
- repository export/unexport routines come from yume and can now be shared
with debian routines, too.
* Tue Feb 21 2006 Erich Focht
- removed "--" from yume options, some versions don't like it
* Wed Feb 1 2006 Erich Focht
- added yume support and improved module recognition. Now
there is no need for checks for distro release files.
* Tue Nov 1 2005 Fernando Camargos <fernando@revolutionlinux.com>
- added Mandriva support (mandriva-release)
- changed extension of %files to * instead of gz so they can be rebuilded by Mandriva distros
* Mon Jul 18 2005 Erich Focht <efocht@hpce.nec.com>
- repackaged
- added ScientificLinux and Centos support
* Wed Apr 14 2004 Mat Garrett <agarret@OSL.IU.edu>
- release 4, bug fixes and moved to site_perl
* Mon Apr 12 2004 Mat Garrett <magarret@OSL.IU.edu>
- release 3, more bug fixes
* Wed Apr 06 2004 Mat Garrett <magarret@OSL.IU.edu>
- release 2, bug fixes
* Tue Mar 30 2004 Mat Garrett <magarret@OSL.IU.edu>
- v1.3, First spec file. (Thanks, Dave!)
