package DashProfiler::Sample;

=head1 NAME

DashProfiler::Sample - encapsulates the acquisition of a single sample

=head1 DESCRIPTION

Firstly, read L<DashProfiler::UserGuide> for a general introduction.

A DashProfiler::Sample object is returned from the prepare() method of DashProfiler::Core,
or from the functions imported by DashProfiler::Import.

The object, and this class, are rarely used directly.

=head1 METHODS

=cut

use strict;

our $VERSION = sprintf("1.%06d", q$Revision$ =~ /(\d+)/o);

use DBI::Profile qw(dbi_profile dbi_time);
use Carp;

BEGIN {
    # use env var to control debugging at compile-time
    # see pod for DEBUG at end
    my $debug = $ENV{DASHPROFILER_SAMPLE_DEBUG} || $ENV{DASHPROFILER_DEBUG} || 0;
    eval "sub DEBUG () { $debug }; 1;" or die; ## no critic
}


=head2 new

This method is normally only called by the code reference returned from the
DashProfiler::Core prepare() method, and not directly.

    $sample = DashProfiler::Sample->new($meta, $context2);
    $sample = DashProfiler::Sample->new($meta, $context2, $start_time, $allow_overlap);

The returned object encapsulates the time of its creation and the supplied arguments.

The $meta parameter must be a hash reference containing at least a
'C<_dash_profile>' element which must be a reference to a DashProfiler::Core
object. The new() method marks the profile as 'in use'.

If the $context2 is false then $meta->{_context2} is used instead.

If $start_time false, which it normally is, then the value returned by dbi_time() is used instead.

If $allow_overlap is false, which it normally is, then if the DashProfiler
refered to by the 'C<_dash_profile>' element of %$meta is marked as 'in use'
then a warning is given (just once) and C<new> returns undef, so no sample is
taken.

If $allow_overlap is true, then overlaping samples can be taken. However, if
samples do overlap then C<period_exclusive> is disabled for that DashProfiler.

=cut

sub new {
    my ($class, $meta, $context2, $start_time, $allow_overlaping_use) = @_;
    my $profile_ref = $meta->{_dash_profile};
    return if $profile_ref->{disabled};
    if ($profile_ref->{in_use}++) {
        if ($allow_overlaping_use) {
            # can't use exclusive timer with nested samples
            undef $profile_ref->{exclusive_sampler};
        }
        else {
            Carp::cluck("$class $profile_ref->{profile_name} already active in outer scope")
                unless $profile_ref->{in_use_warning_given}++; # warn once
            return; # don't double count
        }
    }
    # to help debug nested profile samples you can uncomment this
    # and remove the ++ from the if() above and tweak the cluck message
    #$profile_ref->{in_use} = Carp::longmess("");
    return bless [
        $meta,
        $context2   || $meta->{_context2},
        $start_time || dbi_time(), # do this as late as practical
    ] => $class;
}


=head2 DESTROY

When the DashProiler::Sample object is destroyed it:

 - calls dbi_time() to get the time of the end of the sample

 - marks the profile as no longer 'in use'

 - adds the timespan of the sample to the 'period_accumulated' of the DashProiler

 - extracts context2 from the DashProiler::Sample object

 - if $meta (passed to new()) contained a 'C<context2edit>' code reference
   then it's called and passed context2 and $meta. The return value is used
   and context2. This is very useful where the value of context2 can't be determined
   at the time the sample is started.

 - calls DBI::Profile::dbi_profile(handle, context1, context2, start time, end time)
   for each DBI profile currently attached to the DashProiler.

=cut

sub DESTROY {
    my $end_time = dbi_time(); # get timestamp as early as practical

    # Any fatal errors won't be reported because we're in a DESTROY.
    # This can make debugging hard. If you suspect a problem then uncomment this:
    local $SIG{__DIE__} = sub { warn @_ } if DEBUG(); ## no critic

    my ($meta, $context2, $start_time) = @{+shift};

    my $profile_ref = $meta->{_dash_profile};
    undef $profile_ref->{in_use};
    $profile_ref->{period_accumulated} += $end_time - $start_time;

    my $context2edit = $meta->{context2edit} || (ref $context2 eq 'CODE' ? $context2 : undef);
    $context2 = $context2edit->($context2, $meta) if $context2edit;

    carp(sprintf "%s: %s %s: %f - %f = %f",
        $profile_ref->{profile_name}, $meta->{_context1}, $context2, $start_time, $end_time, $end_time-$start_time
    ) if DEBUG() and DEBUG() >= 4;

    # if you get an sv_dump ("SV = RV(0x181aa80) at 0x1889a80 ...") to stderr
    # it probably means %$dbi_handles_active contains a plain hash ref not a dbh
    for (values %{$profile_ref->{dbi_handles_active}}) {
        next unless defined; # skip any dead weakrefs
        dbi_profile($_, $meta->{_context1}, $context2, $start_time, $end_time);
    }

    return;
}


=head2 DEBUG

The DEBUG subroutine is a constant that returns whatever the value of

    $ENV{DASHPROFILER_SAMPLE_DEBUG} || $ENV{DASHPROFILER_DEBUG} || 0;

was when the modle was loaded.

=cut

1;
