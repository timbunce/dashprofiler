package DashProfiler;

use strict;
use warnings;

our $VERSION = "1.08"; # $Revision$

=head1 NAME

DashProfiler - collect call count and timing data aggregated by context

=head1 SYNOPSIS

The DashProfiler modules enable you to efficiently collect performance data
by adding just a line of code to the functions or objects you want to monitor.

Data is aggregated by context and optionally also by a granular time axis.

See L<DashProfiler::UserGuide> for a general introduction.

=head1 DESCRIPTION

=head2 Performance

DashProfiler is fast, very fast. Especially given the functionality and flexibility it offers.

When you build DashProfiler, the test suite shows the performance on your
system when you run "make test". On my system, for example it reports:

    t/02.sample....... you're using perl 5.008006 on darwin-thread-multi-2level
      Average 'hot' sample overhead is  0.000029s (max 0.000240s, min 0.000028s)
      Average 'cold' sample overhead is 0.000034s (max 0.000094s, min 0.000030s)

=head2 Apache mod_perl

DashProfiler was designed to work well with Apache mod_perl in high volume production environments.

Refer to L<DashProfiler::Apache> for details.

=cut

use Carp;
use Data::Dumper;

use DashProfiler::Core;

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

Typically called from mod_perl PerlChildInitHandler.

=cut

sub reset_all_profiles {    # eg PerlChildInitHandler
    $_->reset_profile_data for values %profiles;
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

=head1 AUTHOR

DashProfiler by Tim Bunce, L<http://www.tim.bunce.name>

=head1 COPYRIGHT

The DBI module is Copyright (c) 2007-2008 Tim Bunce. Ireland.
All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=cut

1;
