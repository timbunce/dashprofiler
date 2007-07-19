package DashProfiler;

use strict;
use warnings;

our $VERSION = "1.04";

=head1 NAME

DashProfiler - collect call count and timing data aggregated by context

=head1 SYNOPSIS

 A work-in-progress

=head1 DESCRIPTION

Profile = store of profile info
Profiler = wrapper with key1 set
Sample = object from Profiler

Via DashProfiler::Import cost per call = 50,000/second, 0.000020s on modern box
(not accurate to realworld situations because of L2 caching, but the general
message that "it's fast" is)

=head1 APACHE CONFIGURATION

    <Perl>
    BEGIN {
        use DashProfiler;
        # create profile early so other code executed during startup
        # can see the named profile
        DashProfiler->add_profile('subsys', {
            disabled => 0,
            granularity => 30,
            flush_interval => 60,
            add_exclusive_sample => 'other',
            spool_directory => '/tmp', # needs write permission for 'nobody'
        });
    }
    </Perl>

    PerlChildInitHandler DashProfiler::reset_all_profiles
    PerlPostReadRequestHandler DashProfiler::start_sample_period_all_profiles
    PerlCleanupHandler DashProfiler::end_sample_period_all_profiles
    PerlChildExitHandler DashProfiler::flush_all_profiles

=cut

use Carp;
use Data::Dumper;

use DashProfiler::Core;


# PerlChildInitHandler - clear data in all profiles
# PerlChildExitHandler - save_to_disk all profiles
# PerlPostReadRequestHandler - store hi-res timestamp in a pnote
# PerlLogHandler - add sample for 'other' as time since start of request - duration_accumulated
#   save_to_disk() if not saved within last N seconds

my %profiles;

=head2 add_profile

  DashProfiler->add_profile( 'my_profile_name' );
  DashProfiler->add_profile( my_profile_name => { ... } );
  $stash = DashProfiler->add_stash( my_profile_name => { ... } );

Calls DashProfiler::Core->new to create a new stash and then caches it, using
the name as the key, so it can be refered to by name.

See L<DashProfiler::Core> for details of the arguments.

=cut

sub add_profile {
    my $class = shift;
    croak "A profile called '$_[0]' already exists" if $profiles{$_[0]};
    my $self = DashProfiler::Core->new(@_);
    $profiles{ $self->{profile_name} } = $self;
    return $self;
}

=head2 prepare

    $sampler = DashProfiler->prepare($profile_name, ...);

Calls prepare(...) on the profile named by $profile_name.

If no profile with that name exists then it will warn, but only once per name.

=cut

sub prepare {
    my $class = shift;
    my $profile_name = shift;
    my $profile_ref = $profiles{$profile_name};
    unless ($profile_ref) { # to catch spelling mistakes
        carp "No $class profiler called '$profile_name' exists"
            unless defined $profile_ref;
        $profiles{$profile_name} = 0; # only warn once
        return;
    };
    return $profile_ref->prepare(@_);
}

sub get_profile {
    my ($self, $profile_name) = @_;
    return $profiles{$profile_name};
}

sub profile_as_text {
    my $self = shift;
    my $profile_name = shift;
    my $profile_ref = $self->get_profile($profile_name) or return;
    return $profile_ref->profile_as_text(@_);
}

# --- static methods on all profiles ---
#
sub all_profiles_as_text {
    return map { $profiles{$_}->profile_as_text() } sort keys %profiles;
}

sub dump_all_profiles {
    my @text = all_profiles_as_text();
    warn @text if @text;
}

sub reset_all_profiles {    # eg PerlChildInitHandler
    $_->reset_profile_data for values %profiles;
    start_sample_period_all_profiles();
}

sub flush_all_profiles {    # eg PerlChildExitHandler
    $_->flush for values %profiles;
}

sub start_sample_period_all_profiles { # eg PerlPostReadRequestHandler
    $_->start_sample_period for values %profiles;
}

sub end_sample_period_all_profiles { # eg PerlCleanupHandler
    $_->end_sample_period for values %profiles;
    $_->flush_if_due      for values %profiles;
}


1;
