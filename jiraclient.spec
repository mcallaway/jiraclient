
Name: jiraclient
Summary: A command line client for Jira.
BuildArch: noarch
Version: 1.6.8
Release: 1
License: GPL
Vendor:  The Genome Center at Washington University
Packager: %packager
Group: System/Utilities
Source0:   %{name}-%version.tar.gz
BuildRoot: %{_tmppath}/%{name}2-%{version}-%{release}-build
Requires: python, python-fpconst, python-soappy, python-yaml

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
/bin/jiraclient

%changelog
* Fri Dec  3 2010 Matthew Callaway <mcallawa@genome.wustl.edu>
  [ 1.6.8-1 ]
- ISSOFT-12: Support text names for components and fixVersions

* Mon Nov 15 2010 Matthew Callaway <mcallawa@genome.wustl.edu>
  [ 1.6.7-1 ]
- Added Debian packaging.

* Fri Oct  8 2010 Matthew Callaway <mcallawa@genome.wustl.edu>
  [ 1.5.6-1 ]
- Added RPM packaging.

