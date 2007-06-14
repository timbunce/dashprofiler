use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'DashProfiler',
    license             => 'perl',
    dist_author         => 'Tim Bunce <Tim.Bunce@pobox.com>',
    dist_version_from   => 'lib/DashProfiler.pm',
    requires => {
        'Test::More' => 0,
        'version'    => 0,
    },
    add_to_cleanup      => [ 'DashProfiler-*' ],
);

$builder->create_build_script();
