%define destdir /dsg/share/scripts

Name: dsg-user-scripts
Summary: Scripts for creation and removal of users.
Version: 1.5
Release: 1
License: GPL
Vendor:  The Genome Center at Washington University
Packager:  %{packager}
BuildArch: noarch
Group: System/Administration
Source0:   %{name}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}2-%{version}-%{release}-build
Requires: coreutils

%description
This is a set of scripts for managing DSG users.

%prep
%setup

%build

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
* Mon Sep 13 2010 Matthew Callaway <mcallawa@genome.wustl.edu>
  [ 1.5-1 ]
- Built a template spec file

