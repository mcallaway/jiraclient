use Module::Build;
my $build = Module::Build->new
(
 module_name => 'gpfsmapper',
 license  => 'perl',
 add_to_cleanup => [
   'Build','MYMETA.yml','_build'
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
