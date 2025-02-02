---
title: "Chapter 1: Introduction"
weight: 1
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

CQL was designed as a precompiled addition to the SQLite runtime system.  SQLite lacks
stored procedures, but has a rich C runtime interface that allows you to create any kind
of control flow mixed with any SQL operations that you might need.  However, SQLite's programming
interface is both verbose and error-prone in that small changes in SQL statements can require
significant swizzling of the C code that calls them. Additionally, many of the SQLite runtime functions have error codes
which must be strictly checked to ensure correct behavior.  In practice, it's easy to get some or all of this wrong.

CQL simplifies this situation by providing a high level SQL language not unlike the stored procedure
forms that are available in client/server SQL solutions and lowering that language to "The C you could
have written to do that job using the normal SQLite interfaces."

As a result, the C generated is generally very approachable but now the source language does not suffer from
brittleness due to query or table changes and CQL always generates correct column indices, nullability
checks, error checks, and the other miscellany needed to use SQLite correctly.

CQL is also strongly typed, whereas SQLite is very forgiving with regard to what operations
are allowed on which data.  Strict type checking is much more reasonable given CQL's compiled programming model.

>NOTE:
>CQL was created to help solve problems in the building of Meta Platforms's Messenger application, but this
>content is free from references to Messenger. The CQL code generation here is done in the simplest mode with the
>fewest runtime dependencies allowed for illustration.

### Getting Started

Before starting this tutorial, make sure you have built the `cql`
executable first in [Building CG/SQL](../quick_start/getting-started.md)

The "Hello World" program rendered in CQL looks like this:

```sql
-- needed to allow vararg calls to C functions
declare procedure printf no check;

create proc hello()
begin
  call printf("Hello, world\n");
end;
```

This very nearly works exactly as written but we'll need a little bit of glue to wire it all up.

First, assuming you have [built](../quick_start/getting-started.md#building) `cql`, you should have the power to do this:

```bash
$ cql --in hello.sql --cg hello.h hello.c
```

This will produce the C output files `hello.c` and `hello.h` which can be readily compiled.

However, hello.c will not have a `main` -- rather it will have a function like this:

```c
...
void hello(void);
...
```

The declaration of this function can be found in `hello.h`.


>NOTE: `hello.h` tries to include `cqlrt.h`. To
>avoid configuring include paths for the compiler, you might keep `cqlrt.h` in the same directory as the examples and
>avoid that complication. Otherwise you must make arrangements for the compiler to be able to find `cqlrt.h` either by
>adding it to an `INCLUDE` path or by adding some `-I` options to help the compiler find the source.

That `hello` function is not quite adequate to get a running program, which brings us to the next step in
getting things running.  Typically you have some kind of client program that will execute the procedures you
create in CQL.  Let's create a simple one in a file we'll creatively name `main.c`.

A very simple CQL main might look like this:

```c
#include <stdlib.h>
#include "hello.h"
int main(int argc, char **argv)
{
   hello();
   return 0;
}
```

Now we should be able to do the following:

```bash
$ cc -o hello main.c hello.c
$ ./hello
Hello, world
```

Congratulations, you've printed `"Hello, world"` with CG/SQL!

### Why did this work?

A number of things are going on even in this simple program that are worth discussing:

* the procedure `hello` had no arguments, and did not use the database
  * therefore its type signature when compiled will be simply `void hello(void);` so we know how to call it
  * you can see the declaration for yourself by examining the `hello.c` or `hello.h`
* since nobody used a database we didn't need to initialize one
* since there are no actual uses of SQLite we didn't need to provide that library
* for the same reason we didn't need to include a reference to the CQL runtime
* the function `printf` was declared "no check", so calling it creates a regular C call using whatever arguments are provided, in this case a string
* the `printf` function is declared in `stdio.h` which is pulled in by `cqlrt.h`, which appears in `hello.c`, so it will be available to call in the generated C code
* CQL allows string literals with double quotes, and those literals may have most C escape sequences in them, so the "\n" bit works
  * Normal SQL string literals (also supported) use single quotes and do not allow, or need escape characters other than `''` to mean one single quote

All of these facts put together mean that the normal, simple linkage rules result in an executable that prints
the string "Hello, world" and then a newline.

### Variables and Arithmetic

Borrowing once again from examples in "The C Programming Language",
it's possible to do significant control flow in CQL without reference
to databases.  The following program illustrates a variety of concepts:

```sql
-- needed to allow vararg calls to C functions
declare procedure printf no check;

-- print a conversion table  for temperatures from 0 to 300
create proc conversions()
begin
  -- not null can be abbreviated with '!'
  declare fahr, celsius int!;

  -- variable type can be implied
  -- these are all int not null  (or int!)
  let lower := 0;   /* lower limit of range */
  let upper := 300; /* upper limit of range */
  let step := 20;   /* step size */

  -- this is the canonical SQL assignment syntax
  -- but there are shorthand versions available in CQL
  set fahr := lower;
  while fahr <= upper
  begin
    -- top level assignment without 'set' is ok
    celsius := 5 * (fahr - 32) / 9;
    call printf("%d\t%d\n", fahr, celsius);

    -- the usual assignment ops are supported
    fahr += step;
  end;
end;
```

You may notice that both the SQL style `--` line prefix comments and the C style `/* */` forms
are acceptable comment forms. Indeed, it's actually quite normal to pass CQL source through the C pre-processor before giving
it to the CQL compiler, thereby gaining `#define` and `#include` as well as other pre-processing options
like token pasting in addition to the aforementioned comment forms.  More on this later.

Like C, in CQL all variables must be declared before they are used.  They remain in scope until the end of the
procedure in which they are declared, or they are global scoped if they are declared outside of any procedure.  The
declarations announce the names and types of the local variables.   Importantly, variables stay in scope for the whole
procedure even if they are declared within a nested `begin` and `end` block.

The most basic types are the scalar or "unitary" types (as they are referred to in the compiler)

|type        |aliases      | notes                              |
|------------|-------------|------------------------------------|
|`integer`   |int          | a 32 bit integer                   |
|`long`      |long integer | a 64 bit integer                   |
|`bool`      |boolean      | an 8 bit integer, normalized to 0/1|
|`real`      |n/a          | a C double                         |
|`text`      |n/a          | an immutable string reference      |
|`blob`      |n/a          | an immutable blob reference        |
|`object`    |n/a          | an object reference                |
|`X not null`|x!           | `!` means `not null` in types      |

>NOTE: SQLite makes no distinction between integer storage and long integer storage, but the declarations
>tell CQL whether it should use the SQLite methods for binding and reading 64-bit or 32-bit quantities
>when using the variable or column so declared.

There will be more notes on these types later, but importantly, all keywords and names in CQL
are case insensitive just like in the underlying SQL language.   Additionally all of the
above may be combined with `not null` to indicate that a `null` value may not be stored
in that variable (as in the example).  When generating the C code, the case used in the declaration
becomes the canonical case of the variable and all other cases are converted to that in the emitted
code.  As a result the C remains case sensitively correct.

The size of the reference types is machine dependent, whatever the local pointer size is.  The
non-reference types use machine independent declarations like `int32_t` to get exactly the desired
sizes in a portable fashion.

All variables of a reference type are set to `NULL` when they are declared,
including those that are declared `NOT NULL`. For this reason, all nonnull
reference variables must be initialized (i.e., assigned a value) before anything
is allowed to read from them. This is not the case for nonnull variables of a
non-reference type, however: They are automatically assigned an initial value of
0, and thus may be read from at any point.

The programs execution begins with three assignments:

```sql
let lower := 0;
let upper := 300;
let step := 20;
```

This initializes the variables just like in the isomorphic C code.  Statements are seperated by semicolons,
just like in C.  Here the data type of the variable is inferred because of `let`.

The table is then printed using a `while` loop

```sql
while fahr <= upper
begin
  ...
end;
```

This has the usual meaning, with the statements in the `begin/end` block being executed repeatedly
until the condition becomes false.

The body of a `begin/end` block such as the one in the `while` statement can contain one or more statements.

The typical computation of Celsius temperature ensues with this code:

```sql
celsius := 5 * (fahr - 32) / 9;
call printf("%d\t%d\n", fahr, celsius);
fahr += step;
```

This computes the celsius and then prints it out, moving on to the next entry in the table. Note that we
have started using some shorthand.  `SET` can be elided.  And the `+=` assignment operators are also
supported.  Top level procedure calls can also be made without the `call` keyword, that, too, could have
been elided.

Importantly, the CQL compiler uses the normal SQLite order of operations, which is NOT the C order of operations.
As a result, the compiler may need to add parentheses in the C output to get the correct order; or it may remove
some parentheses because they are not needed in the C order even though they were in the SQL order.

The `printf` call operates as before, with the `fahr` and `celsius` variables being passed on to the C runtime library
for formatting, unchanged.

>NOTE: when calling unknown foreign functions like `printf` string literals are simply passed right through unchanged
>as C string literals. No CQL string object is created.

### Basic Conversion Rules

As a rule, CQL does not perform its own conversions, leaving that instead to the C compiler.  An exception
to this is that boolean expressions are normalized to a 0 or 1 result before they are stored.

However, even with no explicit conversions, there are compatibility checks to ensure that letting the C compiler
do the conversions will result in something sensible.  The following list summarizes the essential facts/rules as
they might be applied when performing a `+` operation.

* the numeric types are bool, int, long, real
* non-numeric types cannot be combined with numerics, e.g. 1 + 'x' always yields an error
* any numeric type combined with itself yields the same type
* bool combined with int yields int
* bool or int combined with long yields long
* bool, int, or long combined with real yields real

### Preprocessing Features

CQL does not include its own pre-processor but it is designed to consume
the output of the C pre-processor.  To do this, you can either write the
output of the pre-processor to a temporary file and read it into CQL as
usual or you can set up a pipeline something like this:

```bash
$ cc -x c -E your_program.sql | cql --cg your_program.h your_program.c
```

The above causes the C compiler to invoke only the pre-processor `-E`
and to treat the input as though it were C code `-x c` even though it
is in a `.sql` file. Later examples will assume that you have configured
CQL to be used with the C pre-processor as above.
