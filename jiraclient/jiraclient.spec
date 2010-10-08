
Name: jiraclient
Summary: A command line client for Jira.
Version: 1.5.6
Release: 1
License: GPL
Vendor:  The Genome Center at Washington University
Packager: %packager
Group: System/Utilities
Source0:   %{name}-%version.tar.bz2
BuildRoot: %{_tmppath}/%{name}2-%{version}-%{release}-build
BuildRequires:
Requires: python

%description
Jiraclient is a command line utility for Atlassian's Jira Issue Tracker.
It leverages SOAP or XML-RPC, depending upon the API selected in the
configuration.  It allows command line access to a number of Jira tasks
like issue creation and creation of many issues via YAML templates.

%prep
%setup

%build

%install
install -D -m 0755 jiraclient.py %{buildroot}/bin/jiraclient

%clean
[ ${RPM_BUILD_ROOT} != "/" ] && rm -rf ${RPM_BUILD_ROOT}

%files
%defattr(-,root,root)
%{rootdir}/bin/jiraclient

%changelog
* Fri Oct  8 2010 Matthew Callaway <mcallawa@genome.wustl.edu> 
  [ 1.5.6-1 ]
- Added RPM packaging.

