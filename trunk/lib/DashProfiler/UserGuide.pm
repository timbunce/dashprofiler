package DashProfiler::UserGuide;

our $VERSION = sprintf("1.%06d", q$Revision$ =~ /(\d+)/o);

=head1 NAME

DashProfiler::UserGuide - a user guide for the DashProfiler modules

=head1 INTRODUCTION

The DashProfiler modules provide an efficient, simple, flexible, and powerful
way to collect aggregate timing (performance) information for your code.

=head1 CONCEPTS

The core of DashProfiler are DashProfiler::Core objects.

                         DashProfiler::Core

The DashProfiler module provides a by-name interface to DashProfiler::Core objects
to avoid needing to manage object references yourself.

                             DashProfiler
                                  |
                                  |
                         DashProfiler::Core

Behind the scenes, DashProfiler::Core uses L<DBI::Profile> to efficiently aggregate timing samples.

                             DashProfiler
                                  |
                                  |
                         DashProfiler::Core  ---  DBI::Profile

DBI::Profile aggregate timing samples into a tree structure. By default
DashProfiler::Core arranges for the samples to be aggregated into a tree with
two levels. We refer to these as 'context1' and 'context2'. You provide values
for these that make the most sense for you and your application.
For example, context1 might a type of network service and context2 might be the
specific host name being used to provide that service.

To add timing samples you need to use a Sampler. A Sampler is a code reference
that, when called, creates a new L<DashProfiler::Sample> object and returns a
reference to it. The code reference is customized to contain the value for 'context1'
to be used for the created DashProfiler::Sample.

Typically you'll have one customized Sampler per module using DashProfiler.

                             DashProfiler
                                  |
   sampler code ref -.            v
   sampler code ref ---  DashProfiler::Core  ---  DBI::Profile
   sampler code ref -'            ^
                                  |
                        DashProfiler::Sample

When the Sampler code reference is called it creates a new DashProfiler::Sample
object.  That DashProfiler::Sample object contains a reference to the
DashProfiler::Core it was created for, the exact time it was created, and the
value for 'context1'.

When that DashProfiler::Sample object is destroyed, typically by going out of
scope, it adds a timing sample to all the DBI::Profile objects attached to the
Core it's associated with. The timing is from object creation to object destruction.

The DashProfiler::Import module lets you import customized Sampler code references
as if they were ordinary functions.

  DashProfiler::Import  ---  DashProfiler
          |                       |
   sampler function -.            v
   sampler function ---  DashProfiler::Core  ---  DBI::Profile
   sampler function -'            ^
                                  |
                        DashProfiler::Sample

=cut
