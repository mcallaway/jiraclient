
use strict;
use warnings;
use Module::Build;

use FindBin qw($Bin);
use lib ("$Bin/../lib");

my $builder = Module::Build->new(
    module_name         => 'LSFSpool',
    license             => 'perl',
    dist_author         => 'Matthew Callaway <mcallawa@genome.wustl.edu>',
    build_requires => {
        'Test::More' => '0.10',
    },
);

$builder->create_build_script();
