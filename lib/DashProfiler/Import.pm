package DashProfiler::Import;

use strict;

our $VERSION = sprintf("1.%06d", q$Revision$ =~ /(\d+)/o);

use base qw(Exporter);

use Carp;

use DashProfiler;

=head1 NAME

DashProfiler::Import - Import curried DashProfiler sampler function at compile-time

=head1 SYNOPSIS

  use DashProfiler::Import foo_profiler => [ "bar" ];

  ...
  my $sample = foo_profiler("baz");

=head1 DESCRIPTION

The example above imports a function called foo_profiler() that is a sample
factory for the stash called "foo", pre-configured ("curried") to use the value
"bar" for context1.

It also imports a function called foo_profiler_enabled() that's a constant,
returning false if the stash was disabled at the time. This is useful when
profiling very time-senstive code and you want the profiling to have zero
overhead when not in use. For example:

    $sample = foo_profiler("baz") if foo_profiler_enabled();

Because the C<*_profiler_enabled> function is a constant, the perl compiler
will completely remove the code if the corresponding stash is disabled.

=cut

sub import {
    my $class = shift;
    my $pkg = caller;

    while (@_) {
        local $_ = shift;
        m/^((\w+)_profiler)$/
            or croak "$class name '$_' must end with _profiler";
        my ($var_name, $profile_name) = ($1, $2);

        my $profile = DashProfiler->get_profile($profile_name)
            or croak "No profile called '$profile_name' has been defined";

        my $args = shift;
        croak "$var_name => ... requires an array ref containing at least one element"
            unless ref $args eq 'ARRAY' and @$args >= 1;
        my $profiler = $profile->prepare(@$args);

        #warn "$pkg $var_name ($profile_name) => $context1 $profiler";
        {
            no strict 'refs'; ## no critic
            # if profile has been disabled then export a dummy sub instead
            *{"${pkg}::$var_name"} = $profiler || sub { undef };
            # also export a constant sub that can be used to optimize away the
            # call to the profiler - see docs
            *{"${pkg}::${var_name}_enabled"} = ($profiler) ? sub () { 1 } : sub () { 0 };
        }
    }
}

1;
