Makes it trivial to add flexible and efficient performance monitoring to applications.

Want to monitor the time it takes to execute a block of code?
Or the lifespan of an object?

Once configured you typically need to add just one function call in each place you want to measure. The lifespan of the returned reference what gets measured.

Supports multiple concurrent profilers with diferent configurations.

Uses DBI::Profile to perform the data aggregation (in C) so it's very fast and supports all the 'dynamic tree path' features of the DBI's own profiling mechanism.

See http://dashprofiler.googlecode.com/svn/trunk/lib/DashProfiler/UserGuide.pm for an overview.