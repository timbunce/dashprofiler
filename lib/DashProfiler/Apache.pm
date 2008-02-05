package DashProfiler::Apache;

use strict;
use warnings;
use Carp;

use DashProfiler;

our $VERSION = sprintf("1.%06d", q$Revision$ =~ /(\d+)/o);

use constant MP2 => ( ($ENV{MOD_PERL_API_VERSION}||0) >= 2 or eval "require Apache2::Const");
BEGIN {
  if (MP2) {
    require Apache2::ServerUtil;
    require Apache2::Const;
    Apache2::Const->import(qw(OK DECLINED));
  }
  else {
    require Apache::Constants;
    Apache::Constants->import(qw(OK DECLINED));
  }
}

my $server = eval {
    (MP2) ? Apache2::ServerUtil->server : Apache->server;
};
warn $@ unless $server;


=head1 NAME

DashProfiler::Apache - Hook DashProfiler into Apache mod_perl (v1 or v2)

=head1 SYNOPSIS

To hook DashProfiler into Apache you can just add this line to your httpd.conf:

    PerlModule DashProfiler::Apache;

You'll also need to define at least one profile. An easy way of doing that
is to use DashProfiler::Auto to get a predefined profile called 'auto':

    PerlModule DashProfiler::Auto;

Or you can define your own, like this:

    PerlModule DashProfiler::Apache;
    <Perl>
	DashProfile->add_profile( foo => { ... } );
    </Perl>

=head1 DESCRIPTION

=head2 Example Apache mod_perl Configuration

    PerlModule DashProfiler::Apache;
    <Perl>
        # files will be written to $spool_directory/dashprofiler.subsys.ppid.pid
        DashProfiler->add_profile('subsys', {
            granularity => 30,
            flush_interval => 60,
            add_exclusive_sample => 'other',
            spool_directory => '/tmp', # needs write permission for apache user
        });
    </Perl>

The DashProfiler::Apache module arranges for start_sample_period_all_profiles()
to be called via a PerlPostReadRequestHandler at the start of each I<initial
request>, and end_sample_period_all_profiles() to be called via a
PerlCleanupHandler at the end of each initial request.

Also flush_all_profiles() will be called via a PerlChildExitHandler.

=cut

# initially do nothing except arrange to setup when a child is started
$server->push_handlers(PerlChildInitHandler => sub {
    DashProfiler->reset_all_profiles();
    my %handlers = (
        PerlPostReadRequestHandler => \&apache_start_sample_period_all_profiles,
        PerlCleanupHandler         => \&apache_end_sample_period_all_profiles,
        PerlChildExitHandler       => \&apache_flush_all_profiles,
    );
    $server->push_handlers($_ => $handlers{$_}) for keys %handlers;
}) if $server;


sub apache_start_sample_period_all_profiles {
    my $r = shift;
    # we only start a period for initial requests
    # because we only end them in PerlCleanupHandler and that's only
    # called for initial requests
    return DECLINED unless $r->is_initial_req;
    DashProfiler->start_sample_period_all_profiles();
    return DECLINED;
}

sub apache_end_sample_period_all_profiles {
    DashProfiler->end_sample_period_all_profiles();
    return DECLINED;
}

sub apache_flush_all_profiles {
    DashProfiler->flush_all_profiles();
    return DECLINED;
}


1;
