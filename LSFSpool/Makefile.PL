#use 5.010000;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'LSFSpool',
    VERSION_FROM      => 'lib/LSFSpool.pm', # finds $VERSION
    PREREQ_PM         => { }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/LSFSpool.pm', # retrieve abstract from module
       AUTHOR         => 'Matt Callaway <mcallawa@apple.com>') : ()),
    EXE_FILES         => ['bin/lsf_spool.pl'],
);
