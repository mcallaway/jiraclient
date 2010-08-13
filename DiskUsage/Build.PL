use Module::Build;

my $build = Module::Build->new
(
    module_name         => 'DiskUsage',
    license             => 'perl',
    dist_author         => 'Matthew Callaway <mcallawa@genome.wustl.edu>',
    add_to_cleanup => [
    'dist',
    'debian/files',
    'debian/libdiskusage-perl.debhelper.log',
    'debian/libdiskusage-perl.substvars',
    'debian/libdiskusage-perl',
    ],
    requires => {
    'Cwd' => '0',
    'Data::Dumper' => '0',
    'Date::Manip' => '0',
    'DBI' => '0',
    'Exception::Class' => '0',
    'File::Basename' => '0',
    'File::Find::Rule' => '0',
    'Getopt::Std' => '0',
    'Net::SNMP' => '0',
    'Pod::Find' => '0',
    'Pod::Usage' => '0',
    'POSIX' => '0',
    'Time::HiRes' => '0',
    },
    scripts => ['bin/disk_usage.pl'],
);

$build->create_build_script();
