use strict;

# test period_exclusive
# and period_summary

use Test::More qw(no_plan);
use Data::Dumper;
$|=1;

use DashProfiler;

eval 'package t1; use DashProfiler::Import nonesuch => 42';
like $@, qr/DashProfiler::Import name 'nonesuch' must end with _profiler/;


eval 'package t2; use DashProfiler::Import nonesuch_profiler => 42';
like $@, qr/No profile called 'nonesuch' has been defined/;

my $dp = DashProfiler::Core->new( imp => {
});
eval 'package t3; use DashProfiler::Import imp_profiler';
like $@, qr/No profile called 'imp' has been defined/; # must be via DashProfiler not DashProfiler::Core


eval 'package t4; use DashProfiler::Import -optional, nonesuch_profiler => [ 42 ]';
ok !$@, $@;
ok defined &t4::nonesuch_profiler;
ok defined &t4::nonesuch_profiler_enabled;
ok !t4::nonesuch_profiler(1);
ok !t4::nonesuch_profiler_enabled();

# old deprecated form
eval 'package t5; use DashProfiler::Import ":optional", nonesuch_profiler => [ 42 ]';
ok !$@, $@;
ok defined &t5::nonesuch_profiler;
ok defined &t5::nonesuch_profiler_enabled;
ok !t5::nonesuch_profiler(1);
ok !t5::nonesuch_profiler_enabled();


$dp = DashProfiler->add_profile( imp => {
});
eval 'package t6; use DashProfiler::Import imp_profiler';
like $@, qr/requires an array ref containing at least one element/;


eval 'package t7; use DashProfiler::Import -optional, imp_profiler => [ 42 ]';
ok defined &t7::imp_profiler;
ok defined &t7::imp_profiler_enabled;
ok t7::imp_profiler(1);
ok t7::imp_profiler_enabled();


# end
$dp->reset_profile_data;
exit 0;
