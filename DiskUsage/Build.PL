use Module::Build;
my $class = Module::Build->subclass
(
  class => "Module::Build::Custom",
  code => <<'SUBCLASS' );
  sub ACTION_deb {
    my $self = shift;
    $self->depends_on('test');
    $self->do_system(qw/debuild/,'--no-tgz-check');
    $self->do_system(qw/mkdir/,'-p','dist');
    my $name = lc($self->{properties}->{dist_name});
    my $version = "0". $self->{properties}->{dist_version} . "-1";
    $name = "lib" . $name . "-perl_" . $version;
    my @targets = (
     "${name}_all.deb",
     "${name}.dsc",
     "${name}_i386.build",
     "${name}_i386.changes",
     "${name}.tar.gz",
    );
    foreach my $file (@targets) {
      rename "../$file", "./dist/$file";
    }
  }
SUBCLASS

my $build = $class->new
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
    'Exception::Class::TryCatch' => '0',
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
