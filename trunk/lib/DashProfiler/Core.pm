package DashProfiler::Core;

=head1 NAME

DashProfiler::Core - DashProfiler core object and sampler factory

=head1 SYNOPSIS

See L<DashProfiler::UserGuide> for a general introduction.

DashProfiler::Core is currently viewed as an internal class. The interface may change.
The DashProfiler and DashProfiler::Import modules are the usual interfaces.

=head1 DESCRIPTION

A DashProfiler::Core objects are the core of the DashProfiler, naturally.
They sit between the 'samplers' that feed data into a core, and the DBI::Profile
objects that aggregate those samples. A core may have multiple samplers and
multiple profiles.

=cut

use strict;

our $VERSION = sprintf("1.%06d", q$Revision$ =~ /(\d+)/o);

use DBI 1.57 qw(dbi_time dbi_profile_merge);
use DBI::Profile;
use DBI::ProfileDumper;
use Carp;

our $ENDING = 0;

BEGIN {
    # use env var to control debugging at compile-time
    my $debug = $ENV{DASHPROFILER_CORE_DEBUG} || $ENV{DASHPROFILER_DEBUG} || 0;
    eval "sub DEBUG () { $debug }; 1;" or die; ## no critic
}
END {
    $ENDING = 1;
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


my $sample_overhead_time = 0.000020; # on my 2GHz laptop (must not be zero)
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


=head2 new

  $obj = DashProfiler::Core->new( 'foo' );

  $obj = DashProfiler::Core->new( 'bar', { ...options... } );

  $obj = DashProfiler::Core->new( extsys => {
      granularity => 10,
      flush_interval => 300,
  } );

Creates DashProfiler::Core objects. These should normally created very early in
the life of the program, especially when using DashProfiler::Import.

=head3 Options

=over 4

=item disabled

Set to a true value to prevent samples being added to this core.
Especially relevant for DashProfiler::Import where disabling
.
Default false.

=item dbi_profile_class

Specifies the class to use for creating DBI::Profile objects.
The default is C<DBI::Profile>. Alternatives include C<DBI::ProfileDumper>
and C<DBI::ProfileDumper::Apache>.

=item dbi_profile_args

Specifies extra arguments to pass the new() method of the C<dbi_profile_class>
(e.g., C<DBI::Profile>). The default is C<{ }>.

=item flush_interval

How frequently the DBI:Profiles associated with this core should be written out
and the data reset. Default is 0 - no regular flushing.

=item flush_hook

If set, this code reference is called when flush() is called and can influence
its behaviour. For example, this is the flush_hook used by L<DashProfiler::Auto>:

    flush_hook => sub {
        my ($self, $dbi_profile_name) = @_;
        warn $_ for $self->profile_as_text($dbi_profile_name);
        return $self->reset_profile_data($dbi_profile_name);
    },

See L</flush> for more details.

=item granularity

The default C<Path> for the DBI::Profile objects doesn't include time.
The granularity option adds 'C<!Time~$granularity>' to the front of the Path.
So as time passes the samples are aggregated into new sub-trees.

=item sample_class

The sample_class option specifies which class should be used to take profile samples.
The default is C<DashProfiler::Sample>.
See the L</prepare> method for more information.

=item period_exclusive

When using periods, via the start_sample_period() and end_sample_period() methods,
DashProfiler can add an additional sample representing the time between the
start_sample_period() and end_sample_period() method calls that wasn't accounted for by the samples.

The period_exclusive option enables this extra sample. The value of the option
is used as the value for key1 and key2 in the Path.

=item period_summary

Specifies the name of the extra DBI Profile object to attach to the core.
This extra 'period summary' profile is enabled and reset by the start_sample_period()
method and disabled by the end_sample_period() method.

The mechanism enables a single profile to be used to capture both long-running
sampling (for example in a web application, often with C<granularity> set)
and single-period.

=item profile_as_text_args

A reference to a hash containing default formatting arguments for the profile_as_text() method.

=back


=cut

sub new {
    my ($class, $profile_name, $opt_params) = @_;
    $opt_params ||= {};
    croak "No profile_name given" unless $profile_name && not ref $profile_name;
    croak "$class->new($profile_name, $opt_params) options must be a hash reference"
        if ref $opt_params ne 'HASH';

    our $opt_defaults ||= {
        disabled => 0,
        sample_class => 'DashProfiler::Sample',
        dbi_profile_class => 'DBI::Profile',
        dbi_profile_args => {},
        flush_interval => 0,
        flush_hook => undef,
        granularity => 0,
        period_exclusive => undef,
        period_summary => undef,
        profile_as_text_args => undef,
    };
    croak "Invalid options: ".join(', ', grep { !$opt_defaults->{$_} } keys %$opt_params)
        if keys %{ { %$opt_defaults, %$opt_params } } > keys %$opt_defaults;

    my $time = dbi_time();
    my $self = bless {
        profile_name         => $profile_name,
        in_use               => 0,
        in_use_warning_given => 0,
        dbi_handles_all      => {},
        dbi_handles_active   => {},
        flush_due_at_time    => undef,
        # for start_period
        period_count         => 0,
        period_start_time    => 0,
        period_accumulated   => 0,
        exclusive_sampler    => undef,
        %$opt_defaults,
        %$opt_params,
    } => $class;
    $self->{flush_due_at_time} = $time + $self->{flush_interval};

    lock_keys(%$self);

    _load_class($self->{sample_class});

    if (my $exclusive_name = $self->{period_exclusive}) {
        $self->{exclusive_sampler} = $self->prepare($exclusive_name, $exclusive_name);
    }
    my $dbi_profile = $self->_mk_dbi_profile($self->{dbi_profile_class}, $self->{granularity});
    $self->attach_dbi_profile( $dbi_profile, "main", 0 );

    if (my $period_summary = $self->{period_summary}) {
        my $dbi_profile = $self->_mk_dbi_profile("DashProfiler::DumpNowhere", 0);
        my $dbh = $self->attach_dbi_profile( $dbi_profile, "period_summary", 0 );
        $self->{dbi_handles_all}{period_summary} = $dbh;
        $self->{dbi_handles_active}{period_summary} = $dbh;
    }

    return $self;
}


=head2 attach_dbi_profile

  $core->attach_dbi_profile( $dbi_profile, $name );

Attaches a DBI Profile to a DashProfiler::Core object using the $name given.
Any later samples are also aggregated into this DBI Profile.

Not normally called directly. The new() method calls attach_dbi_profile() to
attach the "main" profile and the C<period_summary> profile, if enabled.

The $dbi_profile argument can be either a DBI::Profile object or a string
containing a DBI::Profile specification.

The get_dbi_profile($name) method can be used to retrieve the profile.

=cut

sub attach_dbi_profile {
    my ($self, $dbi_profile, $dbi_profile_name, $weakly) = @_;
    # wrap DBI::Profile object/spec with a DBI handle
    croak "No dbi_profile_name specified" unless defined $dbi_profile_name;
    local $ENV{DBI_AUTOPROXY};
    my $dbh = DBI->connect("dbi:DashProfiler:", "", "", {
        Profile => $dbi_profile,
        RaiseError => 1, PrintError => 1, TraceLevel => 0,
    });
    $dbh = tied %$dbh; # switch to inner handle
    $dbh->{Profile}->empty; # discard FETCH&STOREs etc due to connect()
    for my $handles ($self->{dbi_handles_all}, $self->{dbi_handles_active}) {
        # clean out any dead weakrefs
        defined $handles->{$_} or delete $handles->{$_} for keys %$handles;
        $handles->{$dbi_profile_name} = $dbh;
#       weaken($handles->{$dbi_profile_name}) if $weakly;   # not currently documented or used
    }
    return $dbh;
}


sub _attach_new_temporary_plain_profile {   # not currently documented or used
    my ($self, $dbi_profile_name) = @_;
    # create new DBI profile (with no time key) that doesn't flush anywhere
    my $dbi_profile = $self->_mk_dbi_profile("DashProfiler::DumpNowhere", 0);
    # attach to the profile, but only weakly
    $self->attach_dbi_profile( $dbi_profile, $dbi_profile_name, 1 );
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
        %{ $self->{dbi_profile_args} },
    );

    return $dbi_profile;
};


=head2 get_dbi_profile

  $dbi_profile  = $core->get_dbi_profile( $dbi_profile_name );
  @dbi_profiles = $core->get_dbi_profile( '*' );

Returns a reference to the DBI Profile object that attached to the $core with the given name.
If $dbi_profile_name is undef then it defaults to "main".
Returns undef if there's no profile with that name atached.
If $dbi_profile_name is 'C<*>' then it returns all attached profiles.
See L</attach_dbi_profile>.

=cut

sub get_dbi_profile {
    my ($self, $name) = @_;
    my $dbi_handles = $self->{dbi_handles_all}
        or return;
    # we take care to avoid auto-viv here
    my $dbh = $dbi_handles->{ $name || 'main' };
    return $dbh->{Profile} if $dbh;
    return unless $name && $name eq '*';
    croak "get_dbi_profile('*') called in scalar context" unless wantarray;
    return map {
        ($_->{Profile}) ? ($_->{Profile}) : ()
    } values %$dbi_handles;
}


=head2 profile_as_text

  $core->profile_as_text();
  $core->profile_as_text( $dbi_profile_name );
  $core->profile_as_text( $dbi_profile_name, {
      path      => [ $self->{profile_name} ],
      format    => '%1$s: dur=%11$f count=%10$d (max=%14$f avg=%2$f)'."\n",
      separator => ">",
  } );

Returns the aggregated data from the specified DBI Profile (default "main") formatted as a string.
Calls L</get_dbi_profile> to get the DBI Profile, then calls the C<as_text> method on the profile.
See L<DBI::Profile> for more details of the parameters.

In list context it returns one item per profile leaf node, in scalar context
they're concatenated into a single string. Returns undef if the named DBI
Profile doesn't exist.

=cut

sub profile_as_text {
    my $self = shift;
    my $name = shift;
    my $default_args = $self->{profile_as_text_args} || {};
    my %args = (%$default_args, %{ shift || {} });

    $args{path}   ||= [ $self->{profile_name} ];
    $args{format} ||= '%1$s: dur=%11$f count=%10$d (max=%14$f avg=%2$f)'."\n";
    $args{separator} ||= ">";

    my $dbi_profile = $self->get_dbi_profile($name) or return;
    return $dbi_profile->as_text(\%args);
}


=head2 reset_profile_data

  $core->reset_profile_data( $dbi_profile_name );

Resets (discards) DBI Profile data and resets the period count to 0.
If $dbi_profile_name is false then it defaults to "main".
If $dbi_profile_name is false "*" then all attached profiles are reset.
Returns a list of the affected DBI::Profile objects.

=cut

sub reset_profile_data {
    my ($self, $dbi_profile_name) = @_;
    my @dbi_profiles = $self->get_dbi_profile($dbi_profile_name);
    $_->empty for @dbi_profiles;
    $self->{period_count} = 0;
    return @dbi_profiles;
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


=head2 visit_profile_nodes

  $core->visit_profile_nodes( $dbi_profile_name, sub { ... } )

Calls the given subroutine for each leaf node in the named DBI Profile.
The name defaults to "main". If $dbi_profile_name is "*" then the leafs nodes
in all the attached profiles are visited.

=cut

sub visit_profile_nodes {
    my ($self, $dbi_profile_name, $sub) = @_;
    my @dbi_profiles = $self->get_dbi_profile($dbi_profile_name);
    for my $dbi_profile (@dbi_profiles) {
        my $data = $dbi_profile->{Data}
            or next;
        $self->_visit_nodes($data, undef, $sub)
    }
    return;
}


=head2 propagate_period_count {

  $core->propagate_period_count( $dbi_profile_name )

Sets the count field of all the leaf-nodes in the named DBI Profile to the
number of times start_sample_period() has been called since the last flush() or
reset_profile_data().

If $dbi_profile_name is "*" then counts in all attached profiles are set.

Resets the period count to zero and returns the previous count.

Does nothing but return 0 if the the period count is zero.

This method is especially useful where the number of sample I<periods> are much
more relevant than the number of samples. This is typically the case where
sample periods correspond to major units of work, such as web requests.
Using propagate_period_count() lets you calculate averages based on the count
of periods instead of samples.

Imagine, for example, that you're instrumenting a web application and you have
a function that sends a request to some network service and another reads each
line of the response.  You'd add DashProfiler sampler calls to each function.
The number of samples recorded in the leaf node will depends on the number of
lines in the response from the network service. You're much more likely to want
to know "average total time spent handling the network service per http request"
than "average time spent in a network service related function".

This method is typically called just before a flush(), often via C<flush_hook>.

=cut

sub propagate_period_count {
    my ($self, $dbi_profile_name) = @_;
    # force count of all nodes to be count of periods instead of samples
    my $count = $self->{period_count}
        or return 0;
    warn "propagate_period_count $self->{profile_name} count $count" if DEBUG();
    # force count of all nodes to be count of periods
    $self->visit_profile_nodes($dbi_profile_name, sub { return unless ref $_[0] eq 'ARRAY'; $_[0]->[0] = $count });
    $self->{period_count} = 0;
    return $count;
}


=head2 flush

  $core->flush()
  $core->flush( $dbi_profile_name )

Calls the C<flush_hook> code reference, if set, passing it $core and the
$dbi_profile_name augument (which is typically undef).  If the C<flush_hook>
code returns a non-empty list then flush() does nothing more except return that
list.

If C<flush_hook> wasn't set, or it returned an empty list, then the flush_to_disk()
method is called for the named DBI Profile (defaults to "main", use "*" for all).
In this case flush() returns a list of the DBI::Profile objects flushed.

=cut


sub flush {
    my ($self, $dbi_profile_name) = @_;
    if (my $flush_hook = $self->{flush_hook}) {
        # if flush_hook returns true then don't call flush_to_disk
        my @ret = $flush_hook->($self, $dbi_profile_name);
        return @ret if @ret;
        # else fall through
    }
    my @dbi_profiles = $self->get_dbi_profile($dbi_profile_name);
    $_->flush_to_disk for (@dbi_profiles);
    return @dbi_profiles;
}


=head2 flush_if_due

  $core->flush_if_due()

Returns nothing if C<flush_interval> was not set.
Returns nothing if C<flush_interval> was set but insufficient time has passed since
the last call to flush_if_due().
Otherwise notes the time the next flush will be due, and calls C<return flush();>.

=cut

sub flush_if_due {
    my ($self) = @_;
    return unless $self->{flush_interval};
    return if time() < $self->{flush_due_at_time};
    $self->{flush_due_at_time} = time() + $self->{flush_interval};
    return $self->flush();
}


=head2 has_profile_data

    $bool = $core->has_profile_data
    $bool = $core->has_profile_data( $dbi_profile_name )

Returns true if the named DBI Profile (default "main") contains any profile data.

=cut

sub has_profile_data {
    my ($self, $dbi_profile_name) = @_;
    my @dbi_profiles = $self->get_dbi_profile($dbi_profile_name)
        or return undef; ## no critic
    keys %{$_->{Data}||{}} && return 1 for (@dbi_profiles);
    return 0;
}


=head2 start_sample_period

  $core->start_sample_period

Marks the start of a series of related samples, e.g, within one http request.

Increments the C<period_count> attribute.
Resets the C<period_accumulated> attribute to zero.
Sets C<period_start_time> to the current dbi_time().
If C<period_summary> is enabled then the period_summary DBI Profile is enabled and reset.

See also L</end_sample_period>, C<period_summary> and L</propagate_period_count>.

=cut

sub start_sample_period {
    my $self = shift;
    # marks the start of a series of related samples, e.g, within one http request
    # see end_sample_period()
    if ($self->{period_start_time}) {
        carp "start_sample_period() called for $self->{profile_name} without preceeding end_sample_period()";
        $self->end_sample_period();
    }
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


=head2 end_sample_period

  $core->end_sample_period

Marks the end of a series of related samples, e.g, within one http request.

If start_sample_period() was not called for this core then end_sample_period()
just returns undef.

If C<period_exclusive> is enabled then a sample is added with a duration
caclulated to be the time since start_sample_period() was called to now, minus
the time accumulated by samples since start_sample_period() was called.

Resets the C<period_start_time> attribute to 0.  If C<period_summary> is
enabled then the C<period_summary> DBI Profile is disabled and returned, else
undef is returned.

See also L</start_sample_period>, C<period_summary> and L</propagate_period_count>.

=cut

sub end_sample_period {
    my $self = shift;
    if (not $self->{period_start_time}) {
        carp "end_sample_period() ignored for $self->{profile_name} without preceeding start_sample_period()" if DEBUG();
        return undef;
    }
    if (my $profiler = $self->{exclusive_sampler} and
        my $dbi_profile = $self->get_dbi_profile
    ) {
        # add a sample with the start time forced to be period_start_time
        # shifted forward by the accumulated sample durations + sampling overheads.
        # This accounts for all the time between start_sample_period and
        # end_sample_period that hasn't been accounted for by normal samples.
        dbi_profile_merge(my $total=[], $dbi_profile->{Data});
        my $overhead = $sample_overhead_time * $total->[0];
        warn "$self->{name} period end: overhead ${overhead}s ($total->[0] * $sample_overhead_time)"
            if DEBUG() && DEBUG() >= 3;
        $profiler->(undef, $self->{period_start_time} + $self->{period_accumulated} + $overhead)
            if $overhead; # don't add 'other' if there have been no actual samples
        # gets destroyed, and so counted, immediately.
    }
    $self->{period_start_time} = 0;
    # disconnect period_summary dbi profile from receiving any more samples
    # return it to caller
    my $period_summary_dbh = delete $self->{dbi_handles_active}{period_summary};
    return ($period_summary_dbh) ? $period_summary_dbh->{Profile} : undef;
}


=head2 prepare

  $sampler_code_ref = $core->prepare( $context1 )
  $sampler_code_ref = $core->prepare( $context1, $context2 )
  $sampler_code_ref = $core->prepare( $context1, $context2, %meta )

  $sampler_code_ref->( $context2 )
  $sampler_code_ref->( $context2, $start_time )

Returns a reference to a subroutine that will create sampler objects.
In effect the prepare() method creates a 'factory'.

The sampler objects created by the returned code reference are pre-set to use
$context1, and optionally $context2, as their context values.

If the appropriate value for C<context2> won't be available until the end of
the sample you can set $context2 to a code reference. The reference will be
executed at the end of the sample. See L<DashProfiler::Sample>.

XXX needs more info about %meta - see the code for now, it's not very complex.

See L<DashProfiler::Sample> for more information.

=cut

sub prepare {
    my ($self, $context1, $context2, %meta) = @_;
    # return undef if profile exists but is disabled
    return undef if $self->{disabled}; ## no critic

    # return a light wrapper around the profile, containing the context1
    my $sample_class = $meta{sample_class} || $self->{sample_class};
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


sub DESTROY {
    my $self = shift;
    # global destruction shouldn't be relied upon because often the
    # dbi profile data will have been already destroyed
    $self->end_sample_period() if $self->{period_start_time};
    $self->flush if $self->has_profile_data("*");
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
