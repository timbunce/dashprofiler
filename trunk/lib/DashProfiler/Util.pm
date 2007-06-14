package DashProfiler::Util;

=head1 NAME

DashProfiler::Util - handy utility functions for DashProfiler

=head1 SYNOPSIS

This is currently viewed as an internal package. The interface may change.

=cut


use strict;

use Carp;

use base qw(Exporter);

our @EXPORT_OK = qw(
    dbi_profile_as_text
);


sub dbi_profile_as_text {
    my ($dbi_profile, $path, $separator, $format) = @_;
    $separator ||= ">";
    $format ||= '%1$s: dur=%11$fs count=%10$d (max=%14$f avg=%2$f)'."\n";

    my @node_path_list = $dbi_profile->as_node_path_list(undef, $path);
    # XXX sorting

    my @text;
    for my $node_path (@node_path_list) {
        my ($node, @path) = @$node_path;
        push @text, sprintf $format,
            join($separator, @path),                  # 1=path
            ($node->[0] ? $node->[4]/$node->[0] : 0), # 2=avg
            (undef) x 7,    # spare slots
            @$node; # 10=count, 11=dur, 12=first_dur, 13=min, 14=max, 15=first_called, 16=last_called
    }
    return @text if wantarray;
    return join "", @text;
}

1;
