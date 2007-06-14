package DashProfiler::DumpNowhere;

use strict;

our $VERSION = sprintf("2.%06d", q$Revision$ =~ /(\d+)/o);

use base qw(DBI::ProfileDumper);


sub flush_to_disk {
    return;
}

1;
