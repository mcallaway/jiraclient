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
    my @targets = (
        'libgpfsmapper-perl_0v0.1.0-1_i386.build',
        'libgpfsmapper-perl_0v0.1-1_all.deb',
        'libgpfsmapper-perl_0v0.1-1.dsc',
        'libgpfsmapper-perl_0v0.1-1_i386.build',
        'libgpfsmapper-perl_0v0.1-1_i386.changes',
        'libgpfsmapper-perl_0v0.1-1_source.build',
        'libgpfsmapper-perl_0v0.1-1_source.changes',
        'libgpfsmapper-perl_0v0.1-1.tar.gz'
        );
    foreach my $file (@targets) {
      rename "../$file", "./dist/$file";
    }
}
SUBCLASS

my $build = $class->new
(
 module_name => 'gpfsmapper',
 license  => 'perl',
 scripts => ['scripts/gpfsmapper'],
 add_to_cleanup => [
 'dist',
 'debian/files',
 'debian/libgpfsmapper-perl.debhelper.log',
 'debian/libgpfsmapper-perl.substvars',
 'debian/libgpfsmapper-perl',
 ],
 requires => {
 'Exception::Class' => '0',
 'Getopt::Std' => '0',
 'Pod::Find' => '0',
 'Pod::Usage' => '0',
 'Data::Dumper' => '0',
 },
 );
$build->create_build_script;
