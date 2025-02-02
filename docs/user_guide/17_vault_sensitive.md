---
title: "Chapter 17: Vault Sensitive — Encoding for Privacy"
weight: 17
---
<!---
-- Copyright (c) sample Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

### Introduction

The general idea of "vaulted" values is that some fields in your
database might contain sensitive data and you might not want to make
this data visible to all the code in your whole project.  The data could
be sensitive for a number of reasons, maybe it's PII, or maybe it's
confidential for some other reason.  The idea here is that you can't
very well limit access to this data in a lower layer like CQL can provide
because it's likely that the functions accessing the data at this layer
are in the business of processing this data.  For instance in Meta's
Messenger application, the body of messages, the "text" if you will,
is _highly_ sensitive, it might contain extremely valuable information
like phone numbers, medical information, literally anything.  And yet
the Messenger application is _in the business_ of displaying this data;
this is literally _what it does_.  However, sensitive data is supposed
to be handled in certain very specific ways in certain very specific
places. It shouldn't be appearing just willy nilly. For instance sensitive
data should never appear in debug logs.

In fact, in any given application, there there is typically a lot of code
that simply passes the data along and never looks at it. This is in some
sense what we want, most places just flow data to where it needs to go and
only when it is actually needed, for instance to draw some pixels on the
screen, do we crack the data.  We can search our codebase carefully for
these "cracking" operations and indeed we can limit them with compilation
tools to certain places.  All of this is in the name of avoiding mistakes.

It's not perfect, but it adds a level of resistance and discoverability
that is useful for highly sensitive data.

### Basics of Operation

The normal situation is that the presentation layer of your application
uses various stored procedures to create result sets full of the data
that it needs to get the job done.  It passes these around to its
various layers.  It may extract some fields and pass those around,
maybe row by row.  The idea is that some of the values in the result
set, the sensitive ones, are not the real values, they are proxies.
The reason the attribute that drives all this is called "vault_sensitive"
is because it imagines the (optional) existence of a "vault" that stores
the real value of sensitive items and instead offers a proxy value that
is useless.  For instance the vaulted value of a text message might be
the next available vaulted message number, "12".  It's still a string.
It flows like a string.  All the places that thing text is a string get
a string but the actual string is useless.

If you were to accidentally log this string in a debug file you would
see a useless number.  The vault storage is typically set up so that
the key "12" is weakly held and when it vanishes the storage associated
with it also vanishes.  This is particularly easy to do in some runtimes
(like iOS).  In other runtimes (Java) it's actually quite hard.  In that
case you could opt to instead do some locally reversible encryption of
the message text.  Like maybe there is a local key that is globally known
but is not durable, it's persisted nowhere.  Messages can be decoded
locally with ease but any message that actually left the device would
be encrypted forever with no hope of recovery.

The CQL position on this is that the encoding is entirely up to the
`cqlrt`` runtime which is replaceable.  So it's entirely up to the
customer to decide whether encoding is even useful and if so what encoding
is suitable in their context.  The primitives simply make this possible.

To light up encoding you apply one of three attribute forms to any given
procedure to "vault" its sensitive columns.

Let's consider these examples:

```sql
create table test
(
  a integer,
  b text,
  x integer @sensitive,
  y text @sensitive
);

proc foo1()
begin
  select * from test;
end;

@attribute(cql:vault_sensitive)
proc foo2()
begin
  select * from test;
end;

@attribute(cql:vault_sensitive=(x))
proc foo3()
begin
  select * from test;
end;

@attribute(cql:vault_sensitive=(a,(x)))
proc foo4()
begin
  select * from test;
end;
```

Looking at each of these in turn.

* `foo1`: did not opt-in to vaulting, the storage is normal
* `foo2`: opted all sensitive columns in to vaulting, `x` and `y` will be encoded
* `foo3`: specified the sensitive columsn to vault, so just `x`
* `foo4`: specified that `x` is to be encoded but the value of column `a` is "context" for the encoding
  * in this case effectively every row is encoded differently depending on the value of `a` so to decode you'll need to use the decoder function and provide `a`
  * this provides even more "mistake resistence"

Importantly, the CQL runtime calls the encoding functions (below) automatically but it never decodes anything.
How and when to decode is a function of what the encoding was and so it's usually necessary to provide your upper
layers with a convenient way to reverse whatever encoding you selected.

### Vaulting Mechanics

The difference in code generation is very trivial. To the extent that
there is any heavy lifting, the runtime is doing it.

The metadata block generated for `foo1` looks like this:

```C
uint8_t foo1_data_types[foo1_data_types_count] = {
  CQL_DATA_TYPE_INT32, // a
  CQL_DATA_TYPE_STRING, // b
  CQL_DATA_TYPE_INT32, // x
  CQL_DATA_TYPE_STRING, // y
};
```

And `foo2` looks like this:

```C
uint8_t foo2_data_types[foo2_data_types_count] = {
  CQL_DATA_TYPE_INT32, // a
  CQL_DATA_TYPE_STRING, // b
  CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_ENCODED, // x
  CQL_DATA_TYPE_STRING | CQL_DATA_TYPE_ENCODED, // y
};
```

The _only_ difference between these procedures is the presence of
`CQL_DATA_TYPE_ENCODED` (twice) in the metadata for the result set.
>Note: Lua codegen doesn't support vaulting at this time but if it
did, it would do it an analogous way. Lua uses a metadata string like
"isis" (int string int string) to describe the columns, it could use a
different characters like "j" and "t" to get "isjt" for encoded types.
The C runtime stores the types in a byte.

Unsurprisingly the next variant has metadata that looks like this:

```C
uint8_t foo3_data_types[foo3_data_types_count] = {
  CQL_DATA_TYPE_INT32, // a
  CQL_DATA_TYPE_STRING, // b
  CQL_DATA_TYPE_INT32 | CQL_DATA_TYPE_ENCODED, // x
  CQL_DATA_TYPE_STRING, // y
};
```

The final case, with context, is a little different.  It has the same
metadata as case 3 but the rowset fetching function gets a little extra
information:

```C
  cql_fetch_info info = {
    .rc = rc,
    .db = _db_,
    .stmt = stmt,
    .data_types = foo4_data_types,
    .col_offsets = foo4_col_offsets,
    .refs_count = 2,
    .refs_offset = foo4_refs_offset,
    .encode_context_index = 0,
    .rowsize = sizeof(foo4_row),
    .crc = CRC_foo4,
    .perf_index = &foo4_perf_index,
  };
```

The index of the context field was initialized to `0` which is the index
of `a`.  In the other cases the `cql_fetch_info` was `-1` indicating
no context.

The result of these bits being set is that the encoders will be called
on those columns after the data has been fetched from the database but
before the result set is visible to consumers.

For instance, to encode a string this sequence happens:

```C
// prototype
cql_object_ref cql_copy_encoder(sqlite3* db);

encoder = cql_copy_encoder(db);
```

First the runtime copy an encoder reference.  It's called _copy_
because the normal situation is that there is only one shared encoder
per database connection and all the runtime has to is add a reference and
return the same encoder again.  By default there is no encoder object so
the default `cqlrt` just returns `NULL`. However, if there was a "vault"
then you wouldn't want to have to find it again on every encoded column
of every row so this gives you a place to load it up.

Then, for each encoded string a call like this is made:

```C
cql_string_ref new_str_ref = cql_encode_string_ref_new(encoder, *str_ref, encode_context_type, encode_context_field);
```

* `encoder` is the previously fetched encoder object, it could be anything
* `str_ref` will be a string reference
* `encode_context_type` will be either `-1` or else one of data type constants seen above such as `CQL_DATA_TYPE_STRING | CQL_DATA_TYPE_NOTNULL`
* `encode_context_field` will be a byte pointer to the context value (it has been fetched for sure)
  * if the context is itself encoded then the sequence becomes not-deterministic so this is strongly discouraged
  * if your runtime only supports certain kinds of context (e.g. long integer) the type of the context column may be constrained with `@enforce_strict encode context type long;` and similar variants for other types.

There are similar functions in the runtime like `cql_encode_double`
with a similar signature.

The default encodings are very lame and only useful for
testing.  Like many things in `cqlrt.c` you should [replace
them](developer_guide.html#part-5-cql-runtime) with something
appropriate for your environment.  See the section on [encoding sensitive
columns](developer_guide.html#encoding-of-sensitive-columns).

Even very simple encoders can help avoid mistakes because they force the
use of the decoder and that usage gives you a "code smell" to look for.
Some sections of code, maybe even most sections, have no business decoding
anything.  And even the super-lame "just add '#'" strategy in the defeault
implementation gives you something you can look for in tests. If you ever
saw '#' anywhere in debug output that likely is a data leak and should
fail the test.  And it's pretty clear we can do better than "just add '#'".

### Adopting Vault Sensitive

Importantly, vaulting never happens by default. The presence of the vault
sensitive attribute will let you adopt sensitive vaulting gradually.
If you have a codebase that already works with normal data types you
can "break" it gradually adding the needed decoders a little at a time.
There are even helpers that will let you dynamically turn off encoding.
For instance in the `foo2` example above, this function was generated:

```C
void foo2_set_encoding(cql_int32 col, cql_bool encode) {
  return cql_set_encoding(foo2_data_types, foo2_data_types_count, col, encode);
}
```

This lets you disable or enable encoding of a column dyamically, so you
can roll out encoding to say 1% of your users in a trial.

And finally, the abbreviated syntax for `cql:` attributes works here as
always so `[[vault_sensitive]]` or `[[vault_sensitive=(x,y)]]` are less
verbose options to `@attribute(cql:vault_sensitive=(x,y))` and they are
totally equivalent.
