use strict;

# test period_exclusive
# and period_summary

use Test::More qw(no_plan);
use Data::Dumper;

use DashProfiler::Core;
use DBI qw(dbi_profile_merge);
$|=1;

my ($sample_overhead_time, $sample_inner_time)
      = DashProfiler::Core->estimate_sample_overheads();

print "-- period_exclusive\n";
my $dp = DashProfiler::Core->new("dp_ex", {
    granularity => 1_000_000_000,
    period_exclusive => 'other',
});

is $dp->period_start_time, 0;

my $sampler = $dp->prepare("c1");
my $ps1 = $sampler->("c2");
1 while ($ps1->current_sample_duration < 0.1);
undef $ps1;

my $text = $dp->profile_as_text();
like $text, qr/^dp_ex>1000000000>c1>c2: dur=\d.\d+ count=1 \(max=\d.\d+ avg=\d.\d+\)\n$/;

# should just add an 'other' sample
$dp->start_sample_period;
sleep 1;
$dp->end_sample_period;

is $dp->period_start_time, 0, 'period_start_time should be 0 after end_sample_period';

my @text = $dp->profile_as_text();
is @text, 2;
is $text[0], $text, 'should be same as before';
like $text[1], qr/^dp_ex>1000000000>other>other: dur=\d.\d+ count=1 \(max=\d.\d+ avg=\d.\d+\)\n$/,
    "the 'other' (period_exclusive) sample should be formatted ok"
    .sprintf(" (overhead=%.6f, inner=%.6f)", $sample_overhead_time, $sample_inner_time);

$dp->reset_profile_data;


print "-- period_summary\n";

is $dp->get_dbi_profile("period_summary"), undef;
undef $dp;

undef $dp;
$dp = DashProfiler::Core->new("dp_ex", {
    granularity => 1_000_000_000,
    period_summary => 1,
});
#warn Dumper($dp);

$sampler = $dp->prepare("c1");

is ref $dp->get_dbi_profile("period_summary"), 'DashProfiler::DumpNowhere';
is $dp->profile_as_text("period_summary"), "";

$dp->start_sample_period;
$dp->end_sample_period;

is $dp->profile_as_text("period_summary"), "", 'should be empty before any samples';

$sampler->("c2");
is $dp->profile_as_text("period_summary"), "", 'should be empty after sample that was outside a period';

$dp->start_sample_period;
$sampler->("c2");
ok $dp->period_start_time, 'should have non-zero period_start_time';
$dp->end_sample_period;

like $dp->profile_as_text("period_summary"),
    qr/^dp_ex>c1>c2: dur=\d.\d+ count=1 \(max=\d.\d+ avg=\d.\d+\)\n$/,
    'should have count of 1 and no time in path';

like $dp->profile_as_text(),
    qr/^dp_ex>1000000000>c1>c2: dur=\d.\d+ count=2 \(max=\d.\d+ avg=\d.\d+\)\n$/,
    'main profile should have count of 2';

$dp->reset_profile_data;


print "-- propagate_period_count & flush_hook\n";

undef $dp;
$dp = DashProfiler::Core->new("dp3", {
    granularity => 1,
    period_exclusive => 'ex',
    flush_hook => sub {
        warn "flush_hook";
        return 1;
    },
});

# initial do-nothing edge-cases
my $dbi_profile = $dp->get_dbi_profile();
is $dbi_profile->{Data}, undef;
$dp->propagate_period_count(); # shouldn't fail
is $dbi_profile->{Data}, undef, 'should contain no Data';

$dp->start_sample_period;
$dp->propagate_period_count(); # shouldn't fail
is $dbi_profile->{Data}, undef, 'should contain no Data';

$dp->end_sample_period;
is $dp->period_count, 1;

# should only contain the period_exclusive data
my $data = $dbi_profile->{Data};
is keys(%$data), 1, 'should contain only one time sub-tree';

sleep 2;
$sampler = $dp->prepare("c1");
$sampler->("c2") for (1..100);

$dp->start_sample_period;
$dp->end_sample_period;
is $dp->period_count, 2;

dbi_profile_merge(my $total=[], $dbi_profile->{Data});
is $total->[0], 102; # 100 + 2 period_exclusive's
#warn Dumper($dbi_profile->{Data});

# propagate the count of 2 to the two sub-trees, getting 1 each
$dp->propagate_period_count();
#warn Dumper($dbi_profile->{Data});

# as one sub-tree contains two leaves (the c1c2 sample and the ex sample)
# the total will be 3
dbi_profile_merge($total=[], $dbi_profile->{Data});
is $total->[0], 3;

$dp->reset_profile_data;

__END__
after propagate_period_count
$VAR1 = {
          '1213730165' => {
                            'ex' => {
                                      'ex' => [
                                                '1',
                                                '0.000154972076416016',
                                                '0.000154972076416016',
                                                '0.000154972076416016',
                                                '0.000154972076416016',
                                                '1213730165.44161',
                                                '1213730165.44161'
                                              ]
                                    }
                          },
          '1213730167' => {
                            'ex' => {
                                      'ex' => [
                                                '1',
                                                '0',
                                                '0',
                                                '0',
                                                '0',
                                                '1213730167.44544',
                                                '1213730167.44544'
                                              ]
                                    },
                            'c1' => {
                                      'c2' => [
                                                '1',
                                                '0.000545978546142578',
                                                '8.10623168945312e-06',
                                                '5.00679016113281e-06',
                                                '8.10623168945312e-06',
                                                '1213730167.44263',
                                                '1213730167.44538'
                                              ]
                                    }
                          }
        };
