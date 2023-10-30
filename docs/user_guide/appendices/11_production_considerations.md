---
title: "Appendix 11: Production Considerations"
weight: 11
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

### Production Considerations

This system as it appears in the sources here is designed to get some basic SQLite scenarios working but
the runtime systems that are packaged here are basic, if only for clarity.  There are some important
things you should think about improving or customizing for your production environment. Here's a brief list.


#### Concurrency

The reference counting solution in the stock `CQLRT` implementation is single threaded.  This might be ok,
in many environments only one thread is doing all the data access.  But if you plan to share objects
between threads this is something you'll want to address.  `CQLRT` is designed to be replacable.  In fact
there is another version included in the distribution `cqlrt_cf` that is more friendly to iOS and CoreFoundation.
This alternate version is an excellent demonstration of what is possible.  There are more details
in [Internals Part 5: CQL Runtime](developer_guide.html#part-5-cql-runtime)

#### Statement Caching

SQLite statement management includes the ability to reset and re-prepare statements.  This is an
important performance optimization but the stock `CQLRT` does not take advantage of this.  This is
for two reasons:  first, simplicity, and secondly (though more importantly), any kind of statement cache would require
a caching policy and this simple `CQLRT` cannot possibly know what might consitute a good policy
for your application.

The following three macros can be defined in your `cqlrt.h` and they can be directed at a version that
keeps a cache of your choice.

```c
#ifndef cql_sqlite3_exec
#define cql_sqlite3_exec(db, sql) sqlite3_exec((db), (sql), NULL, NULL, NULL)
#endif

#ifndef cql_sqlite3_prepare_v2
#define cql_sqlite3_prepare_v2(db, sql, len, stmt, tail) sqlite3_prepare_v2((db), (sql), (len), (stmt), (tail))
#endif

#ifndef cql_sqlite3_finalize
#define cql_sqlite3_finalize(stmt) sqlite3_finalize((stmt))
#endif
```
As you might expect, `prepare` creates a statement or else returns one from the cache.
When the `finalize` API is called the indicated statement can be returned to the cache or discarded.
The `exec` API does both of these operations, but also, recall that `exec` can get a semicolon
separated list of statements. Your `exec` implementation will have to use SQLite's prepare functions
to split the list and get prepared statements for part of the string.  Alternately, you could choose
not to cache in the `exec` case.

#### Your Underlying Runtime

As you can see in `cqlrt_cf`, there is considerable ability to define what the basic data types mean.  Importantly,
the reference types `text`, `blob`, and `object` can become something different (e.g., something
already supported by your environment).  For instance, on Windows you could use COM or .NET types
for your objects.  All object references are substantially opaque to `CQLRT`; they have comparatively
few APIs that are defined in the runtime:  things like getting the text out of the string reference
and so forth.

In addition to the basic types and operations you can also define a few helper functions that
allow you to create some more complex object types.  For instance, list, set, and dictionary
creation and management functions can be readily created and then you can declare them using
the `DECLARE FUNCTION` language features.  These objects will then be whatever list, set, or
dictionary they need to be in order to interoperate with the rest of your environment.  You can
define all the data types you might need in your `CQLRT` and you can employ whatever
threading model and locking primitives you need for correctness.

#### Debugging and Tracing

The `CQLRT` interface includes some helper macros for logging.  These are defined
as no-ops by default but, of course, they can be changed.

```
#define cql_contract assert
#define cql_invariant assert
#define cql_tripwire assert
#define cql_log_database_error(...)
#define cql_error_trace()
```

`cql_contract` and `cql_invariant` are for fatal errors. They both assert something
that is expected to always be true (like `assert`) with the only difference being that
the former is conventionally used to validate preconditions of functions.

`cql_tripwire` is a slightly softer form of assert that should crash in debug
builds but only log an error in production builds. It is generally used to enforce
a new condition that may not always hold with the goal of eventually transitioning
over to `cql_contract` or `cql_invariant` once logging has demonstrated that the
tripwire is never hit.
When a `fetch_results` method is called, a failure results in a call to `cql_log_database_error`.
Presently the log format is very simple.  The invocation looks like this:

```c
 cql_log_database_error(info->db, "cql", "database error");
```
The logging facility is expected to send the message to wherever is appropriate for your environment.
Additionally it will typically get the failing result code and error message from SQLite, however
these are likely to be stale. Failed queries usually still require cleanup and so the SQLite error
codes be lost because (e.g.) a `finalize` has happened, clearing the code. You can do better if,
for instance, your runtime caches the results of recent failed `prepare` calls. In any case,
what you log and where you log it is entirely up to you.

The `cql_error_trace` macro is described in [Internals Part 3](../../developer_guide/03_c_code_generation.md#cleanup-and-errors)
It will typically invoke `printf` or `fprintf` or something like that to trace the origin of thrown
exceptions and to get the error text from SQLite as soon as possible.

An example might be:

```
#define cql_error_trace() fprintf(stderr, "error %d in %s %s:%d\n", _rc_, _PROC_, __FILE__, __LINE_)
```
Typically the cost of all these diagnostics is too high to include in production code so this is
turned on when debugging failures.  But you can make that choice for yourself.

#### Customizing Code Generation

The file `rt_common.c` defines the common result types, but the skeleton file `rt.c`
includes affordances to add your own types without having to worry about conflicts with the
common types.  These macros define

```c
#define RT_EXTRAS
#define RT_EXTRA_CLEANUP
```

Simply define these two to create whatever `rt_` data structures you want and add any
cleanup function that might be needed to release resources.  The other cleanup
functions should provide a good template for you to make your own.

The C data type `rtdata` includes many text fragments that directly control the
code generation.  If you want to make your generated code look more like say
CoreFoundation you can define an `rtdata` that will do the job.  This will mean
a lot of your generated code won't require the `#defines` for the CQL types,
it can use your runtime directly.  You can also enable things like Pascal casing
for procedure names and a common prefix on procedure names if those are useful
in your environment.  However, the system is designed so that such changes
aren't necessary.  The data types in `cqlrt.h` are enough for any remapping,
additional changes with `rtdata` are merely cosmetic.

#### Summary

The `CQLRT` macros are very powerful, they allow you to target almost any
runtime with a C API.  The `cqlrt_cf` version is a good example of the
sorts of changes you can make.

Concurrency and Statement Caching are not supported in the basic version
for `cqlrt.h`.  If this is important to you you might want to customize for that.

Helper functions for additional data types can be added, and they can be
unique to your runtime.

There are tracing macros to help with debugability.  Providing some
useful versions of those can be of great help in production environments.
