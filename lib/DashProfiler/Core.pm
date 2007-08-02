package DashProfiler::Core;

=head1 NAME

DashProfiler::Core - Accumulator of profile samples and sampler factory

=head1 SYNOPSIS

This is currently viewed as an internal class. The interface may change.

=cut

use strict;

our $VERSION = sprintf("1.%06d", q$Revision$ =~ /(\d+)/o);

use DBI 1.57 qw(dbi_time dbi_profile_merge);
use DBI::Profile;
use DBI::ProfileDumper;
use Carp;


BEGIN {
    # use env var to control debugging at compile-time
    my $debug = $ENV{DASHPROFILER_CORE_DEBUG} || $ENV{DASHPROFILER_DEBUG} || 0;
    eval "sub DEBUG () { $debug }; 1;" or die; ## no critic
}


BEGIN {
    # load Hash::Util for lock_keys()
    # if Hash::Util isn't available then install a stub for lock_keys()
    eval {
        require Hash::Util;
        Hash::Util->import('lock_keys');
    };
    die @$ if $@ && $@ !~ /^Can't locate Hash\/Util/;
    *lock_keys = sub { } if not defined &lock_keys;
}


# check for weaken support, used by ChildHandles
my $HAS_WEAKEN = eval {
    require Scalar::Util;
    # this will croak() if this Scalar::Util doesn't have a working weaken().
    Scalar::Util::weaken( my $test = [] );
    1;
};
*weaken = sub { croak "Can't weaken without Scalar::Util::weaken" }
    unless $HAS_WEAKEN;


my $sample_overhead_time = 0;
if (0) {    # calculate approximate (minimum) sample overhead time
    my $profile = __PACKAGE__->new('overhead',{ dbi_profile_class => 'DashProfiler::DumpNowhere' });
    my $sampler = $profile->prepare('c1');
    my $count = 100;
    my ($i, $sum) = ($count, 0);
    while ($i--) {
        my $t1 = dbi_time();
        my $ps1 = $sampler->("c2");
        undef $ps1;
        $sum += dbi_time() - $t1;
    }
    # overhead is average of time spent calling sampler & DESTROY:
    $sample_overhead_time = $sum / $count; # ~0.000017 on 2GHz MacBook Pro
    # ... minus the time accumulated by the samples:
    $sample_overhead_time -= ($profile->get_dbi_profile->{Data}{c1}{c2}[1] / $count);
    warn sprintf "sample_overhead_time=%.6fs\n", $sample_overhead_time if DEBUG();
    $profile->reset_profile_data;
}



sub new {
    my ($class, $profile_name, $args_ref) = @_;
    $args_ref ||= {};
    croak "No profile_name given" unless $profile_name && not ref $profile_name;
    croak "$class->new($profile_name, $args_ref) args must be a hash reference"
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

        flush_interval       => $args_ref->{flush_interval}  || 60,
        flush_due_at_time    => undef,
        flush_hook           => $args_ref->{flush_hook} || undef,
        spool_directory      => $args_ref->{spool_directory} || '/tmp',
        granularity          => $args_ref->{granularity}     || 0,

        # for start_period
        period_count         => 0,
        period_start_time    => $time,
        period_accumulated   => 0,
        period_exclusive     => $args_ref->{period_exclusive} || undef,
        exclusive_sampler    => undef,
    } => $class;
    $self->{flush_due_at_time} = $time + $self->{flush_interval};

    lock_keys(%$self);

    _load_class($self->{sample_class});

    if (my $exclusive_name = $self->{period_exclusive}) {
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
        weaken($handles->{$name}) if $weakly;
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
    my %args = %{ shift || {} };
    my $dbi_profile = $self->get_dbi_profile($name) or return;
    $args{path}   ||= [ $self->{profile_name} ];
    $args{format} ||= '%1$s: dur=%11$f count=%10$d (max=%14$f avg=%2$f)'."\n";
    $args{separator} ||= ">";
    return $dbi_profile->as_text(\%args);
}


sub reset_profile_data {
    for (values %{shift->{dbi_handles_all}}) {
        next unless $_ && $_->{Profile};
        $_->{Profile}->empty;
    }
    return;
}


sub _visit_nodes {  # depth first with lexical ordering
    my ($self, $node, $path, $sub) = @_;
    croak "No sub ref given" unless ref $sub eq 'CODE';
    croak "No node ref given" unless ref $node;
    $path ||= [];
    if (ref $node eq 'HASH') {    # recurse
        $path = [ @$path, undef ];
        return map {
            $path->[-1] = $_;
            ($node->{$_}) ? $self->_visit_nodes($node->{$_}, $path, $sub) : ()
        } sort keys %$node;
    }
    return $sub->($node, $path);
}   


sub visit_profile_nodes {
    my ($self, $name, $sub) = @_;
    my $dbi_profile = $self->get_dbi_profile($name);
    return $self->_visit_nodes($dbi_profile->{Data}, undef, $sub);
}


sub propagate_period_count {
    my $self = shift;
    # force count of all nodes to be count of periods instead of samples
    my $count = $self->{period_count} || 1;
    warn "propagate_period_count $self->{profile_name} count $count" if DEBUG();
    # force count of all nodes to be count of periods
    $self->visit_profile_nodes('main', sub { return unless ref $_[0] eq 'ARRAY'; $_[0]->[0] = $count });
    return $count;
}


sub flush {
    my $self = shift;
    $self->propagate_period_count;
    if (my $flush_hook = $self->{flush_hook}) {
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
    $self->{period_count}++;
    $self->{period_accumulated} = 0;
    $self->{period_start_time}  = dbi_time();
    return;
}


sub end_sample_period {
    my $self = shift;
    if (my $profiler = $self->{exclusive_sampler}) {
        # add a sample with the start time forced to be period_start_time
        # shifted forward by the accumulated sample durations + sampling overheads.
        # This accounts for all the time between start_sample_period and
        # end_sample_period that hasn't been accounted for by normal samples.
        dbi_profile_merge(my $total=[], $self->get_dbi_profile->{Data});
        my $overhead = $sample_overhead_time * $total->[0];
        warn "$self->{name} period end: overhead ${overhead}s ($total->[0] * $sample_overhead_time)"
            if DEBUG() && DEBUG() >= 3;
        $profiler->(undef, $self->{period_start_time} + $self->{period_accumulated} + $overhead);
        # gets destroyed, and so counted, immediately.
    }
    # disconnect period_summary dbi profile from receiving any more samples
    # return it to caller
    return delete $self->{dbi_handles_active}{period_summary};
}


sub prepare {
    my ($self, $context1, $context2, %meta) = @_;
    # return undef if profile exists but is disabled
    return undef if $self->{disabled}; ## no critic

    # return a light wrapper around the profile, containing the context1
    my $sample_class = $self->{sample_class};
    # use %meta to carry context info into sample object factory
    $meta{_dash_profile} = $self;
    $meta{_context1}     = $context1;
    $meta{_context2}     = $context2;
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


=head2 DEBUG
    
The DEBUG subroutine is a constant that returns whatever the value of

    $ENV{DASHPROFILER_CORE_DEBUG} || $ENV{DASHPROFILER_DEBUG} || 0;

was when the modle was loaded.
        
=cut



# --- DBI::ProfileDumper subclass that doesn't flush_to_disk
#     Used by period_sample
{
    package DashProfiler::DumpNowhere;
    use strict;
    use base qw(DBI::ProfileDumper);
    sub flush_to_disk { return }
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
