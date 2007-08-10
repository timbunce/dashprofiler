package DashProfiler::Auto;

use strict;
use warnings;

use DashProfiler::Import;

use base qw(Exporter);

our @EXPORT = qw(auto_profiler); # re-export what we import from DashProfiler::Import below

our $VERSION = "1.04";

=head1 NAME

DashProfiler::Auto - Creates and imports a predeclared DashProfiler sampler

=head1 SYNOPSIS

  perl -MDashProfiler::Auto -e '$a = auto_profiler("foo"); sleep 1'

=head1 DESCRIPTION

The DashProfiler::Auto is for quick temporary use of DashProfiler.
It avoids the need to create a profile by creating one for you with a typical
configuration.

=cut

my $auto = DashProfiler->add_profile( auto => {
    period_exclusive => 'other',
    flush_hook => sub {
        my ($self, $dbi_profile_name) = @_;
        warn $_ for $self->profile_as_text($dbi_profile_name);
        return $self->reset_profile_data($dbi_profile_name);
    },
});

DashProfiler::Import->import( auto_profiler => [ "auto" ] );

$auto->start_sample_period();

END {
    $auto->end_sample_period();
    $auto->flush;
}


1;
