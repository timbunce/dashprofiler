package DashProfiler::UserGuide;

our $VERSION = sprintf("1.%06d", q$Revision$ =~ /(\d+)/o);

=head1 NAME

DashProfiler::UserGuide - a user guide for the DashProfiler modules

=head1 INTRODUCTION

The DashProfiler modules provide an efficient, simple, flexible, and powerful
way to collect aggregate timing (performance) information for your code.

=head1 CONCEPTS

The core of DashProfiler are DashProfiler::Core objects, naturally.

                         DashProfiler::Core

The L<DashProfiler> module provides a by-name interface to L<DashProfiler::Core> objects
to avoid needing to manage object references yourself. Most DashProfiler::Core
object methods have corresponding DashProfiler static methods that take a profiler name
as the first argument.

                             DashProfiler
                                  |
                                  v
                         DashProfiler::Core

Behind the scenes, DashProfiler::Core uses L<DBI::Profile> to efficiently aggregate timing samples.

                             DashProfiler
                                  |
                                  v
                         DashProfiler::Core  -->  DBI::Profile

DBI::Profile aggregates timing samples into a tree structure. By default
DashProfiler::Core arranges for the samples to be aggregated into a tree with
two levels. We refer to these as C<context1> and C<context2>. You provide values
for these that make the most sense for you and your application.
For example, context1 might a type of network service and context2 might be the
specific host name being used to provide that service.

To add timing samples you need to use a Sampler. A Sampler is a code reference
that, when called, creates a new L<DashProfiler::Sample> object and returns a
reference to it. The Sampler code reference is customized to contain the value
for C<context1> to be used for the created DashProfiler::Sample.

Samplers are created using the prepare() method.
Typically you'll have one customized Sampler per module using DashProfiler.

                             DashProfiler
                                  |
  sampler code ref -.             v
  sampler code ref --->  DashProfiler::Core  -->  DBI::Profile
  sampler code ref -'             ^
                                  |
                        DashProfiler::Sample

When you call the Sampler code reference you pass it a value for C<context2> to
be used for this sample and it returns a new DashProfiler::Sample object
containing the relevant information, including the exact time it was created.

When that DashProfiler::Sample object is destroyed, typically by going out of
scope, it adds a timing sample to all the DBI::Profile objects attached to the
Core it's associated with. The timing is from object creation to object destruction.

The L<DashProfiler::Import> module lets you import customized Sampler code references
as if they were ordinary functions.

 DashProfiler::Import  <---  DashProfiler
         |                        |
         v                        |
  sampler function -.             v
  sampler function --->  DashProfiler::Core  -->  DBI::Profile
  sampler function -'             ^
                                  |
                                  |
                        DashProfiler::Sample

The L<DashProfiler::Auto> module gives you a simple way to start using DashProfiler.
It creates a DashProfiler called 'auto' with a useful default configuration.
It also uses L<DashProfiler::Import> to import an auto_profiler() sampler function
pre-configured with the name of the source file it's imported into.

Where next? Well L<DashProfiler::Auto> is a good place to start if you're keen to try it.

=cut
