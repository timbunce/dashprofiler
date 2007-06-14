use DashProfiler;

my $ref;
BEGIN {
    DashProfiler->add_profile(subsys => { });
    #$ref = DashProfiler->get_profile("subsys")->attach_new_temporary_plain_profile();
}

use DashProfiler::Import subsys_profiler => [ "Context1" ];


DashProfiler->start_sample_period_all_profiles;
my $count = 100_00;
my $t1 = DBI::dbi_time();
for (my $i = $count; $i--;  ) {
    subsys_profiler("c2");
}
my $t2 = DBI::dbi_time();
my $dur = $t2 - $t1;
# 10000 in 0.218141 seconds = 45841.943103/s, 0.000022s -- 12th June consumerdev
warn sprintf "%d in %f seconds = %f/s, %fs\n",
    $count, $dur, $count/$dur, $dur/$count;
DashProfiler->end_sample_period_all_profiles;
DashProfiler->dump_all_profiles();
DashProfiler->reset_all_profiles();

DashProfiler->dump_all_profiles();

DashProfiler->add_profile("subsys1", { });
DashProfiler->add_profile("subsys2", { add_exclusive_sample => 'other' });
my $HP1 = DashProfiler->prepare("subsys1", "SponsoredLinks", undef,
    context2edit => sub {
        return $_[0] . "plus"
    }
);
my $HP2 = DashProfiler->prepare("subsys2", "SponsoredLinks", "context2");
DashProfiler->start_sample_period_all_profiles;
for (1..10) {
    my $ps = $HP1->("getURL");
    $ps = $HP2->();
}
DashProfiler->end_sample_period_all_profiles;
DashProfiler->dump_all_profiles();

