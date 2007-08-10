package DashProfiler;

use strict;
use warnings;

our $VERSION = "1.05";

=head1 NAME

DashProfiler - collect call count and timing data aggregated by context

=head1 SYNOPSIS

The DashProfiler modules enable you to efficiently collect performance data
by adding just a line of code to the functions or objects you want to monitor.

Data is aggregated by context and optionally also by a granular time axis.

See L<DashProfiler::UserGuide> for a general introduction.

=head1 DESCRIPTION

Via DashProfiler::Import cost per call = 50,000/second, 0.000020s on modern box
(not accurate to realworld situations because of L2 caching, but the general
message that "it's fast" is)

=head1 USE IN APACHE

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
  $core = DashProfiler->add_core( my_profile_name => { ... } );

Calls DashProfiler::Core->new to create a new DashProfiler::Core object and
then caches it, using the name as the key, so it can be refered to by name.

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

Calls prepare(...) on the DashProfiler named by $profile_name.

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

=head2 get_profile

    $core = DashProfiler->get_profile( $profile_name );

Returns the DashProfiler::Core object associated with that name.

=cut

sub get_profile {
    my ($self, $profile_name) = @_;
    return $profiles{$profile_name};
}


=head2 profile_as_text

  $text = DashProfiler->profile_as_text( $profile_name )

Calls profile_as_text(...) on the DashProfiler named by $profile_name.
Returns undef if no profile with that name exists.

=cut

sub profile_as_text {
    my $self = shift;
    my $profile_name = shift;
    my $profile_ref = $self->get_profile($profile_name) or return;
    return $profile_ref->profile_as_text(@_);
}


# --- static methods on all profiles ---

=head2 all_profiles_as_text

  @text = DashProfiler->all_profiles_as_text

Calls profile_as_text() on all profiles, ordered by name.

=cut

sub all_profiles_as_text {
    return map { $profiles{$_}->profile_as_text() } sort keys %profiles;
}


=head2 dump_all_profiles

    dump_all_profiles()

Equivalent to

    warn $_ for DashProfiler->all_profiles_as_text();

=cut

sub dump_all_profiles {
    warn $_ for all_profiles_as_text();
}


=head2 reset_all_profiles

Calls C<reset_profile_data> for all profiles.
Then calls start_sample_period_all_profiles()

Typically called from mod_perl PerlChildInitHandler.

=cut

sub reset_all_profiles {    # eg PerlChildInitHandler
    $_->reset_profile_data for values %profiles;
    start_sample_period_all_profiles();
}


=head2 flush_all_profiles

  flush_all_profiles()

Calls flush() for all profiles.
Typically called from mod_perl PerlChildExitHandler

=cut

sub flush_all_profiles {    # eg PerlChildExitHandler
    $_->flush for values %profiles;
}


=head2 start_sample_period_all_profiles

  start_sample_period_all_profiles()

Calls start_sample_period() for all profiles.
Typically called from mod_perl PerlPostReadRequestHandler

=cut

sub start_sample_period_all_profiles { # eg PerlPostReadRequestHandler
    $_->start_sample_period for values %profiles;
}


=head2 end_sample_period_all_profiles

  end_sample_period_all_profiles()

Calls end_sample_period() for all profiles.
Then calls flush_if_due() for all profiles.
Typically called from mod_perl PerlCleanupHandler

=cut

sub end_sample_period_all_profiles { # eg PerlCleanupHandler
    $_->end_sample_period for values %profiles;
    $_->flush_if_due      for values %profiles;
}


1;
