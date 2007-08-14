use strict;

# test period_exclusive
# and period_summary

use Test::More qw(no_plan);
use Data::Dumper;
$|=1;

use DashProfiler;

eval 'use DashProfiler::Import nonesuch => 42';
like $@, qr/DashProfiler::Import name 'nonesuch' must end with _profiler/;


eval 'use DashProfiler::Import nonesuch_profiler => 42';
like $@, qr/No profile called 'nonesuch' has been defined/;


my $dp = DashProfiler::Core->new( imp => {
});
eval 'use DashProfiler::Import imp_profiler';
like $@, qr/No profile called 'imp' has been defined/; # must be via DashProfiler not DashProfiler::Core


eval 'use DashProfiler::Import ":optional", nonesuch_profiler => [ 42 ]';
ok !$@;
ok defined &nonesuch_profiler;
ok defined &nonesuch_profiler_enabled;
ok !nonesuch_profiler();
ok !nonesuch_profiler_enabled();


$dp = DashProfiler->add_profile( imp => {
});
eval 'use DashProfiler::Import imp_profiler';
like $@, qr/requires an array ref containing at least one element/;


eval 'use DashProfiler::Import ":optional", imp_profiler => [ 42 ]';
ok defined &imp_profiler;
ok defined &imp_profiler_enabled;
ok imp_profiler();
ok imp_profiler_enabled();


# end
$dp->reset_profile_data;
exit 0;
