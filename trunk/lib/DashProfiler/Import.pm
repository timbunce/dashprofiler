package DashProfiler::Import;

use strict;

use base qw(Exporter);

use Carp;

use DashProfiler;

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
            no strict 'refs';
            # if profile has been disabled then export a dummy sub instead
            *{"${pkg}::$var_name"} = $profiler || sub { undef };
            # also export a constant sub that can be used to optimize away the
            # call to the profiler - see docs
            *{"${pkg}::${var_name}_enabled"} = ($profiler) ? sub () { 1 } : sub () { 0 };
        }
    }
}

1;
