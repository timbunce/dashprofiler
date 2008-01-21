package DashProfiler::Apache;

use strict;
use warnings;
use Carp;

use DashProfiler;

our $VERSION = sprintf("1.%06d", q$Revision$ =~ /(\d+)/o);

=head1 NAME

DashProfiler::Apache - Hook DashProfiler into Apache mod_perl (v1 or v2)

=head1 SYNOPSIS

XXX NOT IMPLEMENTED YET - SEE BELOW

To hook DashProfiler into Apache you can just add this line to httpd.conf:

    PerlModule DashProfiler::Apache;

you'll need to also define at least one profile. An easy way of doing that
is to use DashProfiler::Auto to get a predefined profile called 'auto':

    PerlModule DashProfiler::Apache;
    PerlModule DashProfiler::Auto;

Or you can define your own, like this:

    PerlModule DashProfiler::Apache;
    <Perl>
	DashProfile->add_profile( foo => { ... } );
    </Perl>

=head1 DESCRIPTION

=head2 Example Apache mod_perl Configuration

    <Perl>
    BEGIN {
        # create profile early so other code can use DashProfiler::Import
        use DashProfiler;
        # files will be written to $spool_directory/dashprofiler.subsys.ppid.pid
        DashProfiler->add_profile('subsys', {
            granularity => 30,
            flush_interval => 60,
            add_exclusive_sample => 'other',
            spool_directory => '/tmp', # needs write permission for apache user
        });
    }
    </Perl>

    # hook DashProfiler into appropriate mod_perl handlers
    PerlChildInitHandler DashProfiler::reset_all_profiles
    PerlPostReadRequestHandler DashProfiler::start_sample_period_all_profiles
    PerlCleanupHandler DashProfiler::end_sample_period_all_profiles
    PerlChildExitHandler DashProfiler::flush_all_profiles


XXX NOT IMPLEMENTED YET

For now you can use DashProfiler with Apache by adding these lines
into your httpd.conf:

    PerlModule DashProfiler
    PerlChildInitHandler       DashProfiler::reset_all_profiles
    PerlPostReadRequestHandler DashProfiler::start_sample_period_all_profiles
    PerlCleanupHandler         DashProfiler::end_sample_period_all_profiles
    PerlChildExitHandler       DashProfiler::flush_all_profiles

Simple!

The aim of the module is to a) simplify it even further, and b) do some magic to
force start_sample_period_all_profiles to be the first PerlPostReadRequestHandler
called, and end_sample_period_all_profiles to be the last PerlCleanupHandler called.

=cut

sub start_sample_period_all_profiles {
    my $r = shift;

}


1;
