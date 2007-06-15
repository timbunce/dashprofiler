use strict;

use Test::More qw(no_plan);

use DashProfiler::Core;
$|=1;

my $dp1 = DashProfiler::Core->new("dp1", {
});

isa_ok $dp1, 'DashProfiler::Core';

is $dp1->get_dbi_profile("nonesuch"), undef;
my $dbi_p1 = $dp1->get_dbi_profile("main");
isa_ok $dbi_p1, 'DBI::Profile';

# prepare a new sampler
my $sampler1 = $dp1->prepare("c1");
isa_ok $sampler1, 'CODE';

# no profile data yet
is $dp1->profile_as_text(), "";
is $dp1->profile_as_text("main"), "";
is $dp1->profile_as_text("nonesuch"), undef;

# start a sample
my $ps1 = $sampler1->("c2");

# still no samples recorded
is $dp1->profile_as_text(), "";

# end the sample
undef $ps1;

like $dp1->profile_as_text(),
    qr/^DashProfiler::Core dp1>\d+>c1>c2: dur=0.\d+s count=1 \(max=0.\d+ avg=0.\d+\)\n$/;

$dp1->reset_profile_data;

is $dp1->profile_as_text(), "";

$dp1->start_sample_period;
$dp1->end_sample_period;

# no change because neither period_summary nor exclusive_sample were enabled
is $dp1->profile_as_text(), "";

# check nested samples are detected
do {
    my @warn;
    local $SIG{__WARN__} = sub { push @warn, @_ };
       $ps1 = $sampler1->("c3");
    my $ps1a = $sampler1->("c3");
    is $ps1a, undef;
    is scalar @warn, 1, 'should generate one warning';
    like $warn[0], qr/^DashProfiler::Sample dp1 already active in outer scope/;
};
undef $ps1;

$dp1->reset_profile_data;

# check more prepare() args
my $sampler2 = $dp1->prepare("c1a", "c2a");
my $ps2 = $sampler2->(); # no context2
undef $ps2;
like $dp1->profile_as_text(),
    qr/^DashProfiler::Core dp1>\d+>c1a>c2a: dur=0.\d+s count=1 \(max=0.\d+ avg=0.\d+\)\n$/,
    'should include c2a';


$dp1->reset_profile_data;

__END__

1;
