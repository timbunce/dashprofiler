package DashProfiler::Sample;

# encapsulates the acquisition of a single sample, using the destruction of the
# object to mark the end of the sample period.

use strict;
use DBI::Profile qw(dbi_profile dbi_time);
use Carp;

sub new {
    my ($class, $meta, $context2, $start_time) = @_;
    my $profile_ref = $meta->{_profile_ref};
    return undef if $profile_ref->{disabled};
    if ($profile_ref->{in_use}++) {
        Carp::cluck("$class $profile_ref->{profile_name} already active in outer scope")
            unless $profile_ref->{in_use_warning_given}++; # warn once
        return undef; # don't double count
    }
    # to help debug nested profile samples you can uncomment this
    # and remove the ++ from the if() above and tweak the cluck message
    # $profile_ref->{in_use} = Carp::longmess("");
    return bless [
        $meta,
        $start_time || dbi_time(),
        $context2   || $meta->{_context2},
    ] => $class;
}

sub DESTROY {
    my $end_time = dbi_time();
    my ($meta, $start_time, $context2) = @{+shift};

    my $profile_ref = $meta->{_profile_ref};
    $profile_ref->{in_use} = undef;
    $profile_ref->{period_accumulated} += $end_time - $start_time;

    my $context2edit = $meta->{context2edit} || (ref $context2 eq 'CODE' ? $context2 : undef);
    $context2 = $context2edit->($context2) if $context2edit;

    carp(sprintf "%s: %s %s: %f - %f = %f",
        $profile_ref->{profile_name}, $meta->{_context1}, $context2, $start_time, $end_time, $end_time-$start_time)
        if 0;

    defined && dbi_profile($_, $meta->{_context1}, $context2, $start_time, $end_time)
        for values %{$profile_ref->{dbi_handles}};
    return;
}

1;
