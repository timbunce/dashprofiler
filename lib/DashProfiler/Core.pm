package DashProfiler::Core;

=head1 NAME

DashProfiler::Core - Accumulator of profile samples and sampler factory

=head1 SYNOPSIS

This is currently viewed as an internal class. The interface may change.

=cut

use strict;

our $VERSION = sprintf("1.%06d", q$Revision$ =~ /(\d+)/o);

use DBI 1.57 qw(dbi_time);
use DBI::Profile;
use Carp;

use Hash::Util qw(lock_keys);
use Scalar::Util qw(weaken);

sub new {
    my ($class, $profile_name, $args_ref) = @_;
    $args_ref ||= {};
    croak "add_profile($class, $args_ref) args must be a hash reference"
        if ref $args_ref ne 'HASH';

    my $time = dbi_time();
    my $self = bless {
        profile_name         => $profile_name,
        in_use               => 0,
        in_use_warning_given => 0,
        disabled             => $args_ref->{disabled},
        sample_class         => $args_ref->{sample_class} || 'DashProfiler::Sample',
        dbi_profile_class    => $args_ref->{dbi_profile_class} || 'DBI::Profile',
        dbi_handles_all      => {},
        dbi_handles_active   => {},
        exclusive_sampler    => undef,

        flush_interval       => $args_ref->{flush_interval}  || 60,
        flush_due_at_time    => undef,
        flush_hook           => $args_ref->{flush_hook} || undef,
        spool_directory      => $args_ref->{spool_directory} || '/tmp',
        granularity          => $args_ref->{granularity}     || 30,

        # for start_period
        period_start_time    => $time,
        period_accumulated   => 0,
    } => $class;
    $self->{flush_due_at_time} = $time + $self->{flush_interval};

    lock_keys(%$self);

    _load_class($self->{sample_class});

    if (my $exclusive_name = $args_ref->{period_exclusive}) {
        $self->{exclusive_sampler} = $self->prepare($exclusive_name, $exclusive_name);
    }

    my $dbi_profile = $self->_mk_dbi_profile($self->{dbi_profile_class}, $self->{granularity});
    $self->attach_dbi_profile( $dbi_profile, "main", 0 );

    if (my $period_summary = $args_ref->{period_summary}) {
        my $dbi_profile = $self->_mk_dbi_profile("DashProfiler::DumpNowhere", 0);
        my $dbh = $self->attach_dbi_profile( $dbi_profile, "period_summary", 0 );
        $self->{dbi_handles_all}{period_summary} = $dbh;
        $self->{dbi_handles_active}{period_summary} = $dbh;
    }

    return $self;
}


sub attach_dbi_profile {
    my ($self, $dbi_profile, $name, $weakly) = @_;
    # wrap DBI::Profile object/spec with a DBI handle
    my $dbh = DBI->connect("dbi:DashProfiler:", "", "", {
        Profile => $dbi_profile,
        RaiseError => 1, PrintError => 1, TraceLevel => 0,
    });
    $dbh = tied %$dbh; # switch to inner handle
    $dbh->{Profile}->empty; # discard FETCH&STOREs etc due to connect()
    for my $handles ($self->{dbi_handles_all}, $self->{dbi_handles_active}) {
        # clean out any dead weakrefs
        defined $handles->{$_} or delete $handles->{$_} for keys %$handles;
        $handles->{$name} = $dbh;
        weaken $handles->{$name} if $weakly;
    }
    return $dbh;
}


sub attach_new_temporary_plain_profile {
    my ($self, $name) = @_;
    # create new DBI profile (with no time key) that doesn't flush anywhere
    my $dbi_profile = $self->_mk_dbi_profile("DashProfiler::DumpNowhere", 0);
    # attach to the profile, but only weakly
    $self->attach_dbi_profile( $dbi_profile, $name, 1 );
    # return ref so caller can store till ready to discard
    return $dbi_profile;
}


sub _mk_dbi_profile {
    my ($self, $class, $granularity) = @_;

    _load_class($class);
    my $Path = $granularity ? [ "!Time~$granularity", "!Statement", "!MethodName" ]
                            : [                       "!Statement", "!MethodName" ];
    my $dbi_profile = $class->new(
        Path  => $Path,
        Quiet => 1,
        Trace => 0,
        File  => "dashprofile.$self->{profile_name}",
        Dir   => $self->{spool_directory},
    );

    return $dbi_profile;
};

sub get_dbi_profile {
    my ($self, $name) = @_;
    my $dbi_handles = $self->{dbi_handles_all} or return;
    # we take care to avoid auto-viv here
    my $dbh = $dbi_handles->{ $name || 'main' } or return;
    return $dbh->{Profile};
}

sub profile_as_text {
    my $self = shift;
    my $name = shift;
    my $dbi_profile = $self->get_dbi_profile($name) or return;
    my $tag = ref($self)." $self->{profile_name}";
    return $dbi_profile->as_text({
        path => [ $tag ],
        separator => ">",
        format => '%1$s: dur=%11$fs count=%10$d (max=%14$f avg=%2$f)'."\n",
    });
}


sub reset_profile_data {
    for (values %{shift->{dbi_handles_all}}) {
        next unless $_ && $_->{Profile};
        $_->{Profile}->empty;
    }
    return;
}

sub flush {
    my $self = shift;
    if (my $flush_hook = $_->{flush_hook}) {
        # if flush_hook returns true then don't call flush_to_disk
        return if $flush_hook->($self);
    }
    for (values %{ $self->{dbi_handles_all} }) {
        next unless $_ && $_->{Profile};
        $_->{Profile}->flush_to_disk;
    }
    return;
}

sub flush_if_due {
    my $self = shift;
    return 0 if time() < $self->{flush_due_at_time};
    $self->{flush_due_at_time} = time() + $self->{flush_interval};
    return $self->flush;
}


sub start_sample_period {
    my $self = shift;
    # marks the start of a series of related samples, e.g, within one http request
    # see end_sample_period()
    if (my $period_summary_h = $self->{dbi_handles_all}{period_summary}) {
        # ensure period_summary_h dbi profile will receive samples
        $self->{dbi_handles_active}{period_summary} = $period_summary_h;
        $period_summary_h->{Profile}->empty; # start period empty
    }
    $self->{period_accumulated} = 0;
    $self->{period_start_time}  = dbi_time();
    return;
}

sub end_sample_period {
    my $self = shift;
    if (my $profiler = $self->{exclusive_sampler}) {
        # create a sample with the start time forced to be period_start_time
        # shifted forward by the accumulated sample durations. This effectively
        # accounts for all the time between start_sample_period and end_sample_period
        # that hasn't been accounted for by normal samples
        $profiler->(undef, $self->{period_start_time} + $self->{period_accumulated});
        # gets destroyed, and so counted, immediately.
    }
    # disconnect period_summary dbi profile from receiving any more samples
    delete $self->{dbi_handles_active}{period_summary};
    return;
}


sub prepare {
    my ($self, $context1, $context2, %meta) = @_;
    # return undef if profile exists but is disabled
    return undef if $self->{disabled}; ## no critic

    # return a light wrapper around the profile, containing the context1
    my $sample_class = $self->{sample_class};
    # use %meta to carry context info into sample object factory
    $meta{_profile_ref} = $self;
    $meta{_context1}    = $context1;
    $meta{_context2}    = $context2;
    # skip method lookup
    my $coderef = $sample_class->can("new") || "new";
    return sub {
        # takes closure over $sample_class, %meta and $coderef
        $sample_class->$coderef(\%meta, @_)
    };
}


sub _load_class {
    my ($class) = @_;
    ## no critic
    no strict 'refs';
    return 1 if keys %{"$class\::"}; # already loaded
    (my $file = $class) =~ s/::/\//g;
    require "$file.pm";
}




# --- ultra small 'null' driver for DBI ---
#     This is really just for the custom dbh DESTROY method below

{
    package DBD::DashProfiler;
    our $drh;       # holds driver handle once initialised
    sub driver{
        return $drh if $drh;
        my ($class, $attr) = @_;
        return DBI::_new_drh($class."::dr", {
            Name => 'DashProfiler', Version => $DashProfiler::Core::VERSION,
        });
    }
    sub CLONE { undef $drh }
}
{   package DBD::DashProfiler::dr;
    our $imp_data_size = 0;
    sub DESTROY { undef }
}
{   package DBD::DashProfiler::db;
    our $imp_data_size = 0;
    use strict;
    sub STORE {
        my ($dbh, $attrib, $value) = @_;
        $value = ($value) ? -901 : -900 if $attrib eq 'AutoCommit';
        return $dbh->SUPER::STORE($attrib, $value);
    }
    sub DESTROY {
        my $dbh = shift;
        $dbh->{Profile} = undef; # don't profile the DESTROY
        return $dbh->SUPER::DESTROY;
    }
}
{   package DBD::DashProfiler::st;
    our $imp_data_size = 0;
}
# fake the %INC entry so DBI install_driver won't try to load it
BEGIN { $INC{"DBD/DashProfiler.pm"} = __FILE__ }



1;
