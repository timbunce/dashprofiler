package DashProfiler::Sample;

=head1 NAME

DashProfiler::Sample - encapsulates the acquisition of a single sample

=head1 DESCRIPTION

A DashProfiler::Sample object is returned from the prepare() method of DashProfiler::Core,
or from the functions imported by DashProfiler::Import.

The object, and this class, are rarely used directly.

=head1 METHODS

=cut

use strict;

our $VERSION = sprintf("1.%06d", q$Revision$ =~ /(\d+)/o);

use DBI::Profile qw(dbi_profile dbi_time);
use Carp;



=head2 new

    $sample = DashProfiler::Sample->new($meta, $context2);
    $sample = DashProfiler::Sample->new($meta, $context2, $start_time);

The returned object encapsulates the time of its creation and some related meta data, such as the C<context2>.

=cut

sub new {
    my ($class, $meta, $context2, $start_time) = @_;
    my $profile_ref = $meta->{_profile_ref};
    return if $profile_ref->{disabled};
    if ($profile_ref->{in_use}++) {
        Carp::cluck("$class $profile_ref->{profile_name} already active in outer scope")
            unless $profile_ref->{in_use_warning_given}++; # warn once
        return; # don't double count
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


=head2 DESTROY

When the object is destroyed it:

 - calls dbi_time() to get the time of the end of the sample
 - marks the profile as no longer 'in use'
 - adds the timespan of the sample to the 'period_accumulated' of the stash
 - determines the value of C<context2>
 - calls DBI::Profile::dbi_profile() for each profile attached to the stash

=cut

sub DESTROY {
    # Any fatal errors won't be reported because we're in a DESTROY.
    # This can make debugging hard. If you suspect a problem then uncomment this:
    local $SIG{__DIE__} = sub { warn @_ };

    my $end_time = dbi_time();
    my ($meta, $start_time, $context2) = @{+shift};

    my $profile_ref = $meta->{_profile_ref};
    $profile_ref->{in_use} = undef;
    $profile_ref->{period_accumulated} += $end_time - $start_time;

    my $context2edit = $meta->{context2edit} || (ref $context2 eq 'CODE' ? $context2 : undef);
    $context2 = $context2edit->($context2) if $context2edit;

    carp(sprintf "%s: %s %s: %f - %f = %f",
        $profile_ref->{profile_name}, $meta->{_context1}, $context2, $start_time, $end_time, $end_time-$start_time
    ) if 0; # enable if needed for debugging

    # if you get an sv_dump ("SV = RV(0x181aa80) at 0x1889a80 ...") to stderr
    # it probably means %$dbi_handles_active contains a plain hash ref not a dbh
    for (values %{$profile_ref->{dbi_handles_active}}) {
        next unless defined; # skip any dead weakrefs
        dbi_profile($_, $meta->{_context1}, $context2, $start_time, $end_time);
    }

    return;
}

1;
