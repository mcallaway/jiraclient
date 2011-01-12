Name: gpfs-tools
Summary: Scripts for managing GPFS disks
Version: 0.3.2
Release: 1
License: GPL
Vendor:  The Genome Center at Washington University
Packager:  Matthew Callaway <mcallawa@genome.wustl.edu>
BuildArch: noarch
Group: System/Administration
Source0:   %{name}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-build
Requires: coreutils, bash

%description
This is a set of scripts for managing GPFS disks.

%prep
%setup

%install
[ ${RPM_BUILD_ROOT} != "/" ] && rm -rf ${RPM_BUILD_ROOT}
make \
 DESTDIR=%{buildroot} \
 install

%clean
[ ${RPM_BUILD_ROOT} != "/" ] && rm -rf ${RPM_BUILD_ROOT}

%files
%defattr(-,root,root)
%attr(0555,root,root) /usr/sbin/*

%changelog
* Wed Jan 12 2011 Matthew Callaway <mcallawa@genome.wustl.edu>
  [ 0.3.2-1 ]
- Add rpm packaging.
- Fix order of head and awk.
