use strict;

# test period_exclusive
# and period_summary

use Test::More qw(no_plan);
use Data::Dumper;

use DashProfiler::Core;
$|=1;

print "-- period_exclusive\n";
my $dp1 = DashProfiler::Core->new("dp_ex", {
    granularity => 1_000_000_000,
    period_exclusive => 'other',
});

my $sampler1 = $dp1->prepare("c1");
my $ps1 = $sampler1->("c2");
undef $ps1;

my $text = $dp1->profile_as_text();
like $text, qr/^dp_ex>1000000000>c1>c2: dur=0.\d+ count=1 \(max=0.\d+ avg=0.\d+\)\n$/;

# should just add an 'other' sample
$dp1->start_sample_period;
$dp1->end_sample_period;

my @text = $dp1->profile_as_text();
is @text, 2;
is $text[0], $text, 'should be same as before';
like $text[1], qr/^dp_ex>1000000000>other>other: dur=0.\d+ count=1 \(max=0.\d+ avg=0.\d+\)\n$/;

$dp1->reset_profile_data;


print "-- period_summary\n";

is $dp1->get_dbi_profile("period_summary"), undef;
undef $dp1;

my $dp2 = DashProfiler::Core->new("dp_ex", {
    granularity => 1_000_000_000,
    period_summary => 1,
});
#warn Dumper($dp2);

my $sampler2 = $dp2->prepare("c1");

is ref $dp2->get_dbi_profile("period_summary"), 'DashProfiler::DumpNowhere';
is $dp2->profile_as_text("period_summary"), "";

$dp2->start_sample_period;
$dp2->end_sample_period;

is $dp2->profile_as_text("period_summary"), "", 'should be empty before any samples';

$sampler2->("c2");
is $dp2->profile_as_text("period_summary"), "", 'should be empty after sample that was outside a period';

$dp2->start_sample_period;
$sampler2->("c2");
$dp2->end_sample_period;

like $dp2->profile_as_text("period_summary"),
    qr/^dp_ex>c1>c2: dur=0.\d+ count=1 \(max=0.\d+ avg=0.\d+\)\n$/,
    'should have count of 1 and no time in path';

like $dp2->profile_as_text(),
    qr/^dp_ex>1000000000>c1>c2: dur=0.\d+ count=2 \(max=0.\d+ avg=0.\d+\)\n$/,
    'main profile should have count of 2';

$dp2->reset_profile_data;

__END__

1;
