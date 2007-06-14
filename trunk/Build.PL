use strict;
use warnings;

use lib q(builder);
use MyBuild;

my $builder = MyBuild->new(
    module_name         => 'DashProfiler',
    license             => 'perl',
    dist_author         => 'Tim Bunce <Tim.Bunce@pobox.com>',
    dist_version_from   => 'lib/DashProfiler.pm',
    requires => {
        'Test::More' => 0,
        'version'    => 0,
        'Module::Build' => 0,
    },
    add_to_cleanup      => [ 'DashProfiler-*' ],
    create_makefile_pl  => 'passthrough',
);

$builder->create_build_script();

exit 0;
