%define binpref /usr/lib/perl5/site_perl/OSCAR
%define manpref /usr/share/man/man3
%define bintarget $RPM_BUILD_ROOT%{binpref}
%define mantarget $RPM_BUILD_ROOT%{manpref}

Summary:		A package and dependency manager abstraction layer.
Name:      		packman-depman
Version:   		2.6
Release:   		1
Vendor:			Open Cluster Group <http://OSCAR.OpenClusterGroup.org/>
Distribution:		OSCAR
Packager:		Erich Focht <efocht@hpce.nec.com>
License: 		GPL
Group:     		Development/Libraries
Source:			%{name}.tar.gz
BuildRoot: 		%{_localstatedir}/tmp/%{name}-root
BuildArch:		noarch


%package rpms
Summary:		A package and dependency manager abstraction layer, rpm part
Vendor:			Open Cluster Group <http://OSCAR.OpenClusterGroup.org/>
Distribution:		OSCAR
Packager:		Erich Focht <efocht@hpce.nec.com>
License: 		GPL
Group:     		Development/Libraries
BuildArch:		noarch


%description
A collection of Perl object modules for use in the OSCAR framework (among
other places) to facilitate the transparent utilization of the native
underlying package manader and dependency manager infrastructure across a wide
range of Linux/UNIX Operating System distributions through a standardized
interface.

%description rpms
A collection of Perl object modules for use in the OSCAR framework (among
other places) to facilitate the transparent utilization of the native
underlying package manader and dependency manager infrastructure across a wide
range of Linux/UNIX Operating System distributions through a standardized
interface. RPMs part.

%prep
%setup -n %{name}

%build
/usr/bin/pod2man --section=3 PackMan.pm		  | gzip > PackMan.3.gz
/usr/bin/pod2man --section=3 DepMan.pm 		  | gzip > DepMan.3.gz
/usr/bin/pod2man --section=3 PackMan/RPM.pm	  | gzip > PackMan-RPM.3.gz
/usr/bin/pod2man --section=3 DepMan/UpdateRPMs.pm | gzip > DepMan-UpdateRPMs.3.gz


%install
%__rm -rf $RPM_BUILD_ROOT

%__install -m 755 -d %{bintarget}/PackMan
%__install -m 755 -d %{bintarget}/DepMan
%__install -m 755 PackMan.pm %{bintarget}
%__install -m 755 DepMan.pm %{bintarget}
%__install -m 755 PackMan/RPM.pm %{bintarget}/PackMan
%__install -m 755 DepMan/UpdateRPMs.pm %{bintarget}/DepMan
%__install -m 755 -d		 %{mantarget}
%__install -m 644 PackMan.3.gz	 %{mantarget}
%__install -m 644 DepMan.3.gz	 %{mantarget}
%__install -m 644 PackMan-RPM.3.gz	 %{mantarget}
%__install -m 644 DepMan-UpdateRPMs.3.gz %{mantarget}


%clean rpms
%__rm -rf $RPM_BUILD_ROOT

%files 
%defattr(-,root,root)
%{binpref}/PackMan.pm
%{binpref}/DepMan.pm
%{manpref}/PackMan.3.*
%{manpref}/DepMan.3.*

%files rpms
%defattr(-,root,root)
%{binpref}/PackMan/RPM.pm
%{binpref}/DepMan/UpdateRPMs.pm
%{manpref}/PackMan-RPM.3.*
%{manpref}/DepMan-UpdateRPMs.3.*


%changelog
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
