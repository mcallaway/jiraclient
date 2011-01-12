%define destdir /share/scripts

Name: dsg-user-scripts
Summary: Scripts for creation and removal of users.
Version: 1.7
Release: 1
License: GPL
Vendor:  The Genome Center at Washington University
Packager:  Matthew Callaway <mcallawa@genome.wustl.edu>
BuildArch: noarch
Group: System/Administration
Source0:   %{name}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}2-%{version}-%{release}-build
Requires: coreutils

%description
This is a set of scripts for managing DSG users.

%prep
%setup

# build

%install
[ ${RPM_BUILD_ROOT} != "/" ] && rm -rf ${RPM_BUILD_ROOT}
make \
 DESTDIR=%{buildroot} \
 INSTALLDIR=%{destdir} \
 install

%clean
[ ${RPM_BUILD_ROOT} != "/" ] && rm -rf ${RPM_BUILD_ROOT}

%files
%defattr(-,root,root)
%dir %{destdir}
%attr(0555,root,root) %{destdir}/*

%changelog
* Wed Jan 12 2011 Matthew Callaway <mcallawa@genome.wustl.edu>
  [ 1.7-1 ]
- Fix wrong path to dsg-userAD in dsg-useradd.

* Mon Dec 13 2010 Matthew Callaway <mcallawa@genome.wustl.edu>
  [ 1.6-1 ]
- Replace corrupted dsg-homearchive.sh with a version recovered from /gsc/share/scripts.
- dsg-userdel: removed samba bits, fixed path to dsg-userAD (jhonold).

* Mon Sep 13 2010 Matthew Callaway <mcallawa@genome.wustl.edu>
  [ 1.5-1 ]
- Built a template spec file

