%define binpref /usr/bin
%define manpref /usr/share/man/man3
%define bintarget $RPM_BUILD_ROOT%{binpref}
%define libtarget $RPM_BUILD_ROOT%{libpref}
%define mantarget $RPM_BUILD_ROOT%{manpref}

%define _use_internal_dependency_generator 0

Summary:		A package and dependency manager abstraction layer.
Name:      		packman
Version:   		3.1.9
Release:   		1
Vendor:			Open Cluster Group <http://OSCAR.OpenClusterGroup.org/>
Distribution:		OSCAR
Packager:		Erich Focht <efocht@hpce.nec.com>
License: 		GPL
Group:     		Development/Libraries
Source:			%{name}.tar.gz
BuildRoot: 		%{_localstatedir}/%{name}-root
BuildArch:		noarch
Requires:       	oscar-base-lib, yume >= 2.8.2
AutoReq :       	yes
Provides:       	perl(OSCAR::PackManDefs)
AutoReqProv: 		no

%description
A collection of Perl object modules for use in the OSCAR framework (among
other places) to facilitate the transparent utilization of the native
underlying package manager and dependency manager infrastructure across a wide
range of Linux/UNIX Operating System distributions through a standardized
interface.

%prep
%setup -n %{name}
# We need to override the RPM dependency auto-detection which screw up
# dependencies to Perl modules.
%define __perl_provides %{_builddir}/%{name}-root

%build
make

%install
%__rm -rf $RPM_BUILD_ROOT
make install DESTDIR=$RPM_BUILD_ROOT

%clean rpms
%__rm -rf $RPM_BUILD_ROOT

%files 
%defattr(-,root,root)
/usr/*


%changelog
* Tue Apr 07 2009 Geoffroy Vallee <valleegr@ornl.gov> 3.1.9-1
- new upstream version (see Changelog for more details).
* Tue Mar 17 2009 Geoffroy Vallee <valleegr@ornl.gov> 3.1.8-1
- new upstream version (see Changelog for more details).
* Fri Mar 13 2009 Geoffroy Vallee <valleegr@ornl.gov> 3.1.7-1
- new upstream version (see Changelog for more details).
* Mon Feb 09 2009 Geoffroy Vallee <valleegr@ornl.gov> 3.1.6-1
- new upstream version (see Changelog for more details).
* Tue Jan 20 2009 Geoffroy Vallee <valleegr@ornl.gov> 3.1.5-1
- new upstream version (see Changelog for more details).
* Thu Jan 15 2009 Geoffroy Vallee <valleegr@ornl.gov> 3.1.4-1
- new upstream version (see Changelog for more details).
* Thu Dec 04 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.1.2-5
- Move the libraries into a noarch directory.
* Fri Nov 28 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.1.2-4
- Disable automatic dependencies.
* Fri Nov 28 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.1.2-3
- Update the dependency to oscar-base-libs to oscar-base-lib.
* Wed Nov 05 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.1.2-2
- change the yum dependency to a yume >= 2.8.1 dependency.
* Wed Nov 05 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.1.2-1
- new upstream version (see Changelog for more details).
* Fri Sep 26 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.1.1-1
- new upstream version (see Changelog for more details).
* Mon Sep 22 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.1.0-1
- new upstream version (see Changelog for more details).
* Thu Aug 21 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.0.5-1
- new upstream version (see Changelog for more details).
* Thu Aug 07 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.0.5-1
- new upstream version (see Changelog for more details).
* Mon Aug 04 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.0.4-1
- new upstream version (see Changelog for more details).
* Mon Jul 28 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.0.3-1
- new upstream version (see Changelog for more details). 
* Wed Jul 23 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.0.2-1
- new upstream version (see ChangeLog for more details).
* Sun Jun 29 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.0.1-1
- new upstream version (see ChangeLog for more details).
* Wed Jun 25 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.0.0-3
- overwrite automatic dependencies to Perl modules, otherwise nothing works.
* Wed Jun 25 2008 Geoffroy Vallee <valleegr@ornl.gov> 3.0.0-2
- add a dependency with oscar-libs.
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
