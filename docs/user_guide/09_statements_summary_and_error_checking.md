---
title: "Chapter 9: Statements Summary and Error Checking"
weight: 9
---
<!---
-- Copyright (c) Meta Platforms, Inc. and affiliates.
--
-- This source code is licensed under the MIT license found in the
-- LICENSE file in the root directory of this source tree.
-->

The following is a brief discussion of the major statement types and the
semantic rules that CQL enforces for each of the statements.  A detailed
discussion of SQL statements (the bulk of these) is beyond the scope of
this document and you should refer to the SQLite documentation for most
details.  However, in many cases CQL does provide additional enforcement
and it is helpful to describe the basic checking that happens for each
fragment of CQL.  A much more authoritative list of the things CQL checks
for can be inferred from the error documentation.  "Tricky" errors have
examples and suggested remediation.

### The Primary SQL Statements

These are, roughly, the statements that involve the database.

#### The `SELECT` Statement
Top level statement list processing for select.  This is easily the hardest
statement to process. Each clause has its own set of complex rules and
the result of previous clauses constrains the next in a complex fashion.
Among the things that are verified:
* the mentioned tables exist and have the mentioned columns
* the columns are type compatible in their context
* any variables in the expressions are compatible
* aggregate functions are used only in places where aggregation makes sense
* column and table names are unambiguous, especially when self-joins are involved
* compound selects (e.g. with UNION) are type-consistent in all the fragments
* the projection of a select has unique column labels if they are used

#### The `SELECT *` Statement
`SELECT *` is special in that it creates its own struct type by assembling
all the columns of all the tables in the select's join result.  CQL rewrites these
column names into a new `SELECT` with the specific columns explicitly listed.
While this makes the program slightly bigger it means that logically deleted columns
are never present in results because `SELECT *` won't select them and attempting
to use a logically deleted column results in an error.

#### The `CREATE TABLE` Statement
Unlike the other parts of DDL we actually deeply care about the tables.
We have to grab all the columns and column types out of it and create
the appropriate structure type for the table.
Along the way we validate a bunch of stuff like:
* verify unique table name
* no duplicate column names
* recursive correctness of constraints (see constraints discussion below)

##### The `UNIQUE KEY` Clause
Similar to other constraints, we don't actually do anything with this
other than offer some validation.  Again, we use the usual helpers
for name lookup within the context of the table that contains the constraint.

##### The `FOREIGN KEY` Clause
Similar to other constraints, we don't actually do anything with this
other than offer some validation.  Again, we use the usual helpers
for name lookup within the context of the table with the foreign key.
 Note that the foreign key has to be validated against two tables to fully validate it.

##### The `PRIMARY KEY` Clause
Similar to other constraints, we don't actually do anything with this
other than offer some validation.  Again, we use the usual helpers
for name lookup within the context of the table with the primary key.

##### The `CHECK` Clause
Similar to other constraints, we don't actually do anything with this
other than offer some validation.  The `CHECK` clause is validated
after the entire table has been processed so that even if it appears
early in the table, the clause can use any columns defined later in the
table.

#### The `CREATE INDEX` Statement
CQL doesn't really do anything with indices but it does validate that they
make sense (so we lookup all the names of all the columns and so forth.)

#### The `CREATE VIEW` Statement
Create view analysis is very simple because the `select` analysis does
the heavy lifting.  All the compiler has to do is validate that the view
is unique, then validate the select statement.

Additionally, views must not be allowed to have any NULL type columns;
all nulls must be converted to some type with a CAST.   e.g. `create
view foo as select NULL n` is not valid.  NULL is not a real storage type.

#### The `CREATE TRIGGER` Statement

The create trigger statement is quite a beast, and validations include:

 * The trigger name must be unique
 * For `insert` the "new.*" table is available in expressions/statement
 * For `delete` the "old.*" table is available in expressions/statements
 * For `update` both are available
    * If optional columns present in the `update`, they must be unique/valid
 * The `when` expression must evaluate to a numeric
 * The statement list must be error free with the usual rules plus new/old
 * The `raise` function may be used inside a trigger (NYI)
 * The table name must be a table (not a view) UNLESS the trigger type is `INSTEAD OF`
 * Select statements inside the statement block do not count as returns for the procedure and that includes the create trigger

#### The `DROP TABLE` Statement

This is the basic checking for the drop table statement:

* the table must exist in some version
* it has to be a table and not a view

#### The `DROP VIEW` Statement

This is the basic checking for the drop view statement:

* the view must exist in some version
* it has to be a view and not a table

#### The `DROP INDEX` Statement

This is the basic checking for the drop index statement:

* the index must exist in some version
* it could be deleted now, that's ok, but the name has to be valid

#### The `DROP TRIGGER` Statement

This is the basic checking for the drop trigger statement

* the trigger  must exist in some version
* it could be deleted now, that's ok, but the name has to be valid

#### The `RAISE` Statement

CQL validates that `RAISE` is being used in the context of a trigger
and that it has the correct arguments

#### The `ALTER TABLE ADD COLUMN` Statement

To validate `alter table add column` we check the following:

* the table must exist and not be a view (in any version)
* the column definition of the new column must be self-consistent
* no auto-increment columns may be added
* added columns must be either nullable or have a default value

>NOTE: Alter statements are typically used in the context of migration,
>so it's possible the table that is mentioned is condemned in a future
>version.  We still have to run the intervening upgrade steps so basically
>DDL gets to ignore the current deadness of the table as in context it
>might be "not dead yet".  This will be more obvious in the context of
>the schema maintenance features. (q.v.)

#### The `DELETE` Statement

The delete analyzer sets up a scope for the table being deleted and then
validates the WHERE clause, if present, against that scope.  Additionally,
we verify that the table actually was defined and is not a view.

#### The `UPDATE` Statement

The update analyzer sets up the scope for the table(s) being updated.
If there are optional clauses (e.g. `LIMIT`), they are evaluated just
like in a select statement with those same helper methods.  Expression
fragments are evaluated similarly as in a select statement.

#### The `INSERT` Statement

We check that the table exists and then we walk the columns and the
value list to make sure they are valid for the table. Also, we cannot
insert into a view.

Details:
* The column list specifies the columns we will provide; they must exist and be unique.
* The columns specified must suffice to insert a row (all not nulls and not default present.)
* The insert list specifies the values that are to be inserted.
* The type of each value must match the type of the column.
* Auto-increment columns may be specified as NULL.
* If there are too many or too few columns, that is considered an error.
* If no columns are specified, that is the same as if all columns had been specified, in table order.

#### The `THROW` Statement

Throw can literally go anywhere, so it's always ok.

#### The `BEGIN TRANSACTION` Statement

Begin transaction can go anywhere, so it's always ok.

The sqlite documentation can be helpful here (CQL syntax is a subset).
See: https://www.sqlite.org/lang_transaction.html

#### The `COMMIT TRANSACTION` Statement

Commit transaction can go anywhere, so it's always ok.

The sqlite documentation can be helpful here (CQL syntax is a subset).
See: https://www.sqlite.org/lang_transaction.html

#### The `ROLLBACK TRANSACTION` Statement

Rollback transaction can go anywhere but if you're using the format where
you rollback to a particular save point, then the compiler must have seen
that savepoint name in a `savepoint` statement previously. Otherwise,
it's an error.

The sqlite documentation can be helpful here again (CQL syntax is
a subset).  See: https://www.sqlite.org/lang_transaction.html

#### The `SAVEPOINT` Statement

The `savepoint` statement can go anywhere but we do record this savepoint
name as having been seen, so that we can verify it in rollback.  So this
is sort of a weak declaration of the savepoint name.

The sqlite documentation can be helpful here (CQL syntax is a subset).
https://www.sqlite.org/lang_savepoint.html

#### The `RELEASE SAVEPOINT` Statement

Release savepoint can go anywhere but we must have seen that name in a
previous `savepoint` statement, otherwise it's an error.

The sqlite documentation can be helpful here (CQL syntax is a subset). https://www.sqlite.org/lang_savepoint.html

#### The `PROCEDURE SAVEPOINT` Statement

A common pattern is to have a savepoint associated with a particular
procedure. The savepoint's scope is the same as the procedure's scope.
More precisely

```sql
create procedure foo()
begin
  proc savepoint
  begin
   -- your code
  end;
end;
```

becomes:

```sql
create procedure foo()
begin
  savepoint @proc;  -- @proc is always the name of the current procedure
  begin try
    -- your code
    release savepoint @proc;
  end try;
  begin catch
    rollback transaction to savepoint @proc;
    release savepoint @proc;
    throw;
  end catch;
end;
```

This form is not quite syntactic sugar because there are some interesting rules:

* the `proc savepoint` form must be used at the top level of the procedure, hence no `leave` or `continue` may escape it
* within `begin`/`end` the `return` form may not be used; you must use `rollback return` or `commit return` (see below)
* `throw` may be used to return an error as usual
* `proc savepoint` may be used again, at the top level, in the same procedure, if there are, for instance, several sequential stages
* a procedure using `proc savepoint` could call another such procedure, or a procedure that manipulates savepoints in some other way

#### The `ROLLBACK RETURN` Statement

This form may be used only inside of  a `proc savepoint` block.
It indicates that the savepoint should be rolled back and then the
procedure should return.  It is exactly equivalent to:

```sql
  rollback transaction to savepoint @proc;
  release savepoint @proc;
  return; -- wouldn't actually be allowed inside of proc savepoint; see note below
```

>NOTE: to avoid errors, the loose `return` above is not actually allowed
>inside of `proc savepoint` -- you must use `rollback return` or `commit
>return`.

#### The `COMMIT RETURN` Statement

This form may be used only inside of  a `proc savepoint` block.
It indicates that the savepoint should be released and then the procedure
should return.  It is exactly equivalent to:

```sql
  release savepoint @proc;
  return; -- wouldn't actually be allowed inside of proc savepoint; see note below
```

Of course this isn't exactly a commit, in that there might be an outer
savepoint or outer transaction that might still be rolled back, but it
is commited at its level of nesting, if you will.  Or, equivalently, you
can think of it as merging the savepoint into the transaction in flight.

>NOTE: to avoid errors, the loose `return` above is not actually
>allowed inside of `proc savepoint` and you must use `rollback return`
>or `commit return`.

#### The `CREATE VIRTUAL TABLE` Statement

The SQLite `CREATE VIRTUAL TABLE` form
(https://sqlite.org/lang_createvtab.html) is problematic from CQL because:

* it is not parseable, because the module arguments can be literally anything (or nothing), even a letter to your grandma
* the arguments do not necessarily say anything about the table's schema at all, but they often do

So in this area CQL substaintially departs from the standard syntax to this form:

```sql
create virtual table virt_table using my_module [(module arguments)]  as (
  id integer not null,
  name text
);
```

The part after the `AS` is used by CQL as a table declaration for the
virtual table.  The grammar for that is exactly the same as a normal
`CREATE TABLE` statement.  However, that part is not transmitted to
SQLite; when the table is created, SQLite sees only the part it cares
about, which is the part before the `AS`.

In order to have strict parsing rules, the module arguments follow one
of these forms:

1. no arguments at all
2. a list of identifiers, constants, and parenthesized sublists, just like in the `@attribute` form
3. the words `arguments following`


##### Case 1 Example

```sql
create virtual table virt_table using my_module as (
  id integer not null,
  name text
);
```

becomes (to SQLite)

```sql
CREATE VIRTUAL TABLE virt_table USING my_module;
```

>NOTE: empty arguments `USING my_module()` are not allowed in the SQLite
>docs but do seem to work in SQLite.  We take the position that no args
>should be formatted with no parentheses, at least for now.

##### Case 2 Example

```
create virtual table virt_table using my_module(foo, 'goo', (1.5, (bar, baz))) as (
  id integer not null,
  name text
);
```

```
CREATE VIRTUAL TABLE virt_table USING my_module(foo, "goo", (1.5, (bar, baz)));
```

This form allows for very flexible arguments but not totally arbitrary
arguments, so it can still be
parsed and validated.

##### Case 3 Example

This case recognizes the popular choice that the arguments are often
the actual schema declaration for the table in question. So:

```
create virtual table virt_table using my_module(arguments following) as (
  id integer not null,
  name text
);
```

becomes

```
CREATE VIRTUAL TABLE virt_table USING my_module(
  id INTEGER NOT NULL,
  name TEXT
);
```

The normalized text (keywords capitalized, whitespace normalized) of
the table declaration in the `as` clause is used as the arguments.

##### Other details

Virtual tables go into their own section in the JSON and they include
the `module` and `moduleArgs` entries; they are additionally marked
`isVirtual` in case you want to use the same processing code for
virtual tables as normal tables.  The JSON format is otherwise the same,
although some things can't happen in virtual tables (e.g. there is no
`TEMP` option so `"isTemp"` must be false in the JSON.)

For purposes of schema processing, virtual tables are on the `@recreate`
plan, just like indices, triggers, etc.  This is the only option since
the `alter table` form is not allowed on a virtual table.

Semantic validation enforces "no alter statements on virtual tables"
as well as other things like no indices, and no triggers, since SQLite
does not support any of those things.

CQL supports the notion of [eponymous virtual
tables](https://www.sqlite.org/vtab.html#epovtab).  If you intend to
register the virtual table's module in this fashion, you can use `create
virtual table @eponymous ...` to declare this to CQL.  The only effect
this has is to ensure that CQL will not try to drop this table during
schema maintenance as dropping such a table is an invalid operation.
In all other ways, the fact that the table is eponymous makes no
difference.

Finally, because virtual tables are on the `@recreate` plan, you may not
have foreign keys that reference virtual tables. Such keys seem like a
bad idea in any case.


### The Primary Procedure Statements

These are the statements which form the language of procedures, and do not involve the database.

#### The `CREATE PROCEDURE` Statement

Semantic analysis of stored procedures is fairly easy at the core:

 * check for duplicate names
 * validate the parameters are well formed
 * set the current proc in flight (this not allowed to nest)
 * recurse on the statement list and prop errors
 * record the name of the procedure for callers
In addition, while processing the statement:
 * we determine if it uses the database; this will change the emitted signature of the proc to include a `sqlite3 *db`
     input argument and it will return a sqlite error code (e.g. `SQLITE_OK`)
 * select statements that are loose in the proc represent the "return" of that
   select;  this changes the signature to include a `sqlite3_stmt **pstmt` parameter corresponding to the returned statement

#### The `IF` Statement

The top level if node links the initial condition with a possible
series of else_if nodes and then the else node.  Each condition is
checked for validity. The conditions must be valid expressions that
can each be converted to a boolean.

#### The `SET` Statement

The set statement is for variable assignment.  We just validate
that the target exists and is compatible with the source.
Cursor variables cannot be set with simple assignment and CQL generates
errors if you attempt to do so.

#### The `LET` Statement

Let combines a `DECLARE` and a `SET`.  The variable is declared to be
the exact type of the right hand side.  All the validations for `DECLARE`
and `SET` are applicable, but there is no chance that the variable will
not be compatible with the expression.  The expression could still be
erroneous in the first place.  The variable could be a duplicate.

#### The `SWITCH` Statement

The `SWITCH` form requires a number of conditions to successfully map
down to a `C` `switch` statement.  These are:

* the switch-expression must be a not-null integral type (`integer not null` or `long integer not null`)
  * the `WHEN` expressions must be losslessly promotable to the type of the switch-expression
* the values in the `WHEN` clauses must be unique
* If `ALL VALUES` is present then:
   * the switch-expression must be of an enum type
   * the `WHEN` values must cover every value of the enum except those beginning with '_'
   * there can be no extra `WHEN` values not in the enum
   * there can be no `ELSE` clause

#### The `DECLARE PROCEDURE` Statement
There are three forms of this declaration:
* a regular procedure with no DML
   * e.g. `declare proc X(id integer);`
* a regular procedure that uses DML (it will need a db parameter and returns a result code)
   * e.g. `declare proc X(id integer) using transaction;`
* a procedure that returns a result set, and you provide the result columns
   * e.g. `declare proc X(id integer) : (A bool not null, B text);`
The main validations here are that there are no duplicate parameter names, or return value columns.

#### The `DECLARE FUNCTION` Statement
Function declarations are similar to procedures; there must be a return type
(use proc if there is none).  The `DECLARE SELECT FUNCTION` form indicates a function
visible to SQLite; other functions are usable in the `call` statement.

#### The `DECLARE` Variable Statement
This declares a new local or global variable that is not a cursor.
The type is computed with the same helper that is used for analyzing
column definitions.  Once we have the type we walk the list of variable
names, check them for duplicates and such (see above) and assign their type.  The canonical
name of the variable is defined here. If it is later used with a different casing the output
will always be as declared.   e.g. `declare Foo integer;  set foo = 1;` is legal but the output
will always contain the variable written as `Foo`.

#### The `DECLARE` Cursor Statement
There are two forms of the declare cursor, both of which allow CQL to infer the exact type of the cursor.
  * `declare foo cursor for select etc.`
    * the type of the cursor is the net struct type of the select list
  * `declare foo cursor for call proc();`
    * proc must be statement that produces a result set via select (see above)
    * the type of the cursor is the struct of the select returned by the proc
    * note if there is more than one loose select in the proc they must match exactly
  * cursor names have the same rules regarding duplicates as other variables
With this in mind, both cases simply recurse on either the select or the call
and then pull out the structure type of that thing and use it for the cursor's shape.  If the
`call` is not semantically valid according to the rules for calls or the `select` is not semantically valid,
 then of course this declaration will generate errors.

#### The `DECLARE` Value Cursor Statement
This statement declares a cursor that will be based on the return type of a procedure.
When using this form the cursor is also fetched, hence the name.  The fetch result of
the stored proc will be used for the value.  At this point, we use its type only.
* the call must be semantically valid
* the procedure must return an OUT parameter (not a result set)
* the cursor name must be unique

#### The `WHILE` Statement
While semantic analysis is super simple.
 * the condition must be numeric
 * the statement list must be error-free
 * loop_depth is increased allowing the use of interior leave/continue

#### The `LOOP` Statement
Loop analysis is just as simple as "while" -- because the loop_stmt
literally has an embedded fetch, you simply use the fetch helper to
validate that the fetch is good and then visit the statement list.
Loop depth is increased as it is with while.

#### The `CALL` Statement
There are three ways that a call can happen:
  * signatures of procedures that we know in full:
    * call foo();
    * declare cursor for call foo();
  * some external call to some outside function we don't know
    * e.g. call printf('hello, world\n');

The cursor form can be used if and only if the procedure has a loose
select or a call to a procedure with a loose select. In that case, the
procedure will have a structure type, rather than just "ok" (the normal
signature for a proc).  If the user is attempting to do the second case,
cursor_name will be set and the appropriate verification happens here.

>NOTE:  Recursively calling fetch cursor is not really doable in general
>because at the point in the call we might not yet know that the method
>does in fact return a select.  You could make it work if you put the select
>before the recursive call.

Semantic rules:
 * for all cases each argument must be error-free (no internal type conflicts)
 * for known procs
   * the call has to have the correct number of arguments
   * if the formal is an out parameter the argument must be a variable
     * the type of the variable must be an exact type match for the formal
   * non-out parameters must be type-compatible, but exact match is not required

#### The `DECLARE OUT CALL` Statement

This form is syntactic sugar and corresponds to declaring any `OUT`
parameters of the `CALL` portion that are not already declared as the
exact type of the `OUT` parameter.  This is intended to save you from
declaring a lot of variables just so that you can use them as `OUT`
arguments.

Since any variables that already exist are not re-declared, there are no
additional semantic rules beyond the normal call except that it is an error
to use this form if no `OUT` variables needed to be declared.

#### The `FETCH` Statement

The fetch statement has two forms:

  * fetch C into var1, var2, var3 etc.
  * fetch C;

The second form is the so-called automatic cursor form.

In the first form the variables of the cursor must be assignment
compatible with declared structure type of the cursor and the count must
be correct.  In the second form, the codegen will implicitly create local
variables that are exactly the correct type, but we'll cover that later.
Since no semantic error is possible in that case, we simply record that
this is an automatic cursor and then later we will allow the use of C.field
during analysis.  Of course "C" must be a valid cursor.

#### The `CONTINUE` Statement

We just need to ensure that `continue` is inside a `loop` or `while`.

#### The `LEAVE` Statement

We only need to ensure that `leave` is inside a `loop`, `while` or `switch`.

#### The `TRY/CATCH` Statements

No analysis needed here other than that the two statement lists are ok.

#### The `CLOSE` CURSOR Statement

For close [cursor], we just validate that the name is in fact a cursor
and it is not a boxed cursor.  Boxed cursor lifetime is managed by the
box object so manually closing it is not allowed.  Instead, the usual
reference-counting semantics apply; the boxed cursor variable typically falls out of
scope and is released, or is perhaps set to NULL to release its reference early.

#### The `OUT` CURSOR Statement

For out [cursor], we first validate that the name is a cursor
then we set the output type of the procedure we're in accordingly.

### The "Meta" Statements

The program's control/ the overall meaning of the program / or may give
the compiler specific directives as to how the program should be compiled.

#### the `@ATTRIBUTE` Notation

Zero or more miscellaneous attributes can be added to any statement,
or any column definition.  See the `misc_attrs` node in the grammar for
the exact placement.  Each attribute notation has the general form:

* `@attribute`(_namespace_ : _attribute-name_ ) or
* `@attribute`(_namespace_ : _attribute-name_ = _attribute-value_)

The _namespace_ portion is optional and attributes with
special meaning to the compiler are all in the `cql:` namespace.
e.g. @attribute(cql:private).  This form is so common that the special
abbreviation `[[foo]]`` can be used instead of `@attribute(cql:foo)`.

* The _attribute-name_ can be any valid name
* Each _attribute-value_ can be:
  * any literal
  * an array of _attribute-values_

Since the _attribute-values_ can nest it's possible to represent
arbitrarily complex data types in an attribute.  You can even represent
a LISP program.

By convention, CQL lets you define "global" attributes by applying them
to a global variable of type `object` ending with the suffix "database".

The main usage of global attributes is as a way to propagate
configurations into the JSON output (q.v.).

Examples:

```sql
-- "global" attributes
@attribute(attribute_1 = "value_1")
@attribute(attribute_2 = "value_2")
declare database object;

-- cql:private marking on a method to make it private, using simplified syntax
[[private]]
proc foo()
begin
end;
```

#### The `@ECHO` Statement

Echo is valid in any top level contexts.

#### The `@PREVIOUS SCHEMA` Statement

Begins the region where previous schema will be compared against what
has been declared before this directive for alterations that could not
be upgraded.

#### The `@SCHEMA_UPGRADE_SCRIPT` Statement

When upgrading the DDL, it's necessary to emit create table statements for
the original version of the schema.  These create statements may conflict
with the current version of the schema.  This attribute tells CQL to

1) ignore DDL in stored procedures for declaration purposes; only DDL outside of a proc counts
2) do not make any columns "hidden" thereby allowing all annotations to be present so they can be used to validate other aspects of the migration script.

#### The `@SCHEMA_UPGRADE_VERSION` Statement

For sql stored procedures that are supposed to update previous schema
versions you can use this attribute to put CQL into that mindset.
This will make the columns hidden for the version in question rather than
the current version.  This is important because older schema migration
procedures might still refer to old columns.  Those columns truly exist
at that schema version.

#### The `@ENFORCE_STRICT` Statement

Switch to strict mode for the indicated item.  The choices and their meanings are:

  * "FOREIGN KEY ON DELETE" indicates there must be some `ON DELETE` action in every FK
  * "FOREIGN KEY ON UPDATE" indicates there must be some `ON UPDATE` action in every FK
  * "INSERT SELECT" indicates that insert with `SELECT` for values may not include top level joins (avoiding a SQLite bug)
  * "IS TRUE" indicates that `IS TRUE` `IS FALSE` `IS NOT TRUE` `IS NOT FALSE` may not be used (*)
  * "JOIN" indicates only ANSI style joins may be used, and "from A,B" is rejected
  * "PROCEDURE" indicates no calls to undeclared procedures (like loose printf calls)
  * "SELECT IF NOTHING" indicates `(select ...)` expressions must include an `IF NOTHING` clause if they have a `FROM` part
  * "TABLE FUNCTIONS" indicates table valued functions cannot be used on left/right joins (avoiding a SQLite bug)
  * "TRANSACTION" indicates no transactions may be started, committed, or aborted
  * "UPSERT" indicates no upsert statement may be used (*)
  * "WINDOW FUNCTION" indicates no window functions may be used (*)
  * "WITHOUT ROWID" indicates `WITHOUT ROWID` may not be used

The items marked with * are present so that features can be disabled to
target downlevel versions of SQLite that may not have those features.

Most of the strict options were discovered via "The School of Hard Knocks", they are all recommended.

See the grammar details for exact syntax.

#### The `@ENFORCE_NORMAL` Statement

Turn off strict enforcement for the indicated item.

#### The `@ENFORCE_PUSH` Statement

Push the current strict settings onto the enforcement stack.  This does
not change the current settings.

#### The `@ENFORCE_POP` Statement

Pop the previous current strict settings from the enforcement stack.

#### The `@ENFORCE_RESET` Statement

Turns off all the strict modes.  Best used immediately after `@ENFORCE_PUSH`.

#### The `@DECLARE_SCHEMA_REGION` Statement
A schema region is a partitioning of the schema such that it only
uses objects in the same partition or one of its declared dependencies.
One schema region may be upgraded independently from any others (assuming
they happen such that dependents are done first.)

Here we validate:

 * the region name is unique
 * the dependencies (if any) are unique and exist
 * the directive is not inside a procedure

#### The `@BEGIN_SCHEMA_REGION` Statement

Entering a schema region makes all the objects that follow part of
that region.  It also means that all the contained objects must refer to
only pieces of schema that are in the same region or a dependent region.
Here we validate that region we are entering is in fact a valid region
and that there isn't already a schema region.

#### The `@END_SCHEMA_REGION` Statement

Leaving a schema region puts you back in the default region.
Here we check that we are in a schema region.

#### The `@EMIT_ENUMS` Statement

Declared enumarations can be voluminous and it is undesirable for every
emitted `.h` file to contain every enumeration.  To avoid this problem
you can emit enumeration values of your choice using `@emit_enums x, y, z`
which places the named enumerations into the `.h` file associated with
the current translation unit. If no enumerations are listed, all enums
are emitted.

NOTE: generated enum definitions are protected by `#ifndef X ... #endif`
so multiple definitions are harmless and hence you can afford to use
`@emit_enums` for the same enum in several translations units, if desired.

>NOTE: Enumeration values also appear in the JSON output in their own section.

#### The `@EMIT_CONSTANTS` Statement

This statement is entirely analogous to the the `@EMIT_ENUMS` except
that the parameters are one or more constant groups.  In fact constants
are put into groups precisely so that they can be emitted in logical
bundles (and to encourage keeping related constants together).  Placing
`@EMIT_CONSTANTS` causes the C version of the named groups to go into
the current `.h` file.

>NOTE: Global constants also appear in the JSON output in their own section.

### Important Program Fragments

These items appear in a variety of places and are worthy of discussion.  They are generally handled uniformly.

#### Argument Lists

In each case we walk the entire list and do the type inference on each
argument.  Note that this happens in the context of a function call,
and depending on what the function is, there may be additional rules
for compatibility of the arguments with the function.  The generic code
doesn't do those checks, there is per-function code that handles that
sort of thing.

At this stage the compiler computes the type of each argument and makes
sure that, independently, they are not bogus.

#### Procedures that return a Result Set

If a procedure is returning a select statement then we need to attach a
result type to the procedure's semantic info.  We have to do some extra
validation at this point, especially if the procedure already has some
other select that might be returned.  The compiler ensures that all the
possible select results are are 100% compatible.

#### General Name Lookups

Every name is checked in a series of locations.  If the name is known
to be a table, view, cursor, or some other specific type of object then
only those name are considered.  If the name is more general a wider
search is used.

Among the places that are considered:

* columns in the current join if any (this must not conflict with #2)
* local or global variables
* fields in an open cursor
* fields in enumerations and global constants

#### Data Types with a Discriminator

Discriminators can appear on any type, `int`, `real`, `object`, etc.

Where there is a discriminator the compiler checks that (e.g.) `object<Foo>` only combines
with `object<Foo>` or `object`.  `real<meters>` only combines with `real<meters>` or `real`.
In this way its not possible to accidentally add `meters` to `kilograms` or to store
an `int<task_id>` where an `int<person_id>` is required.

#### The `CASE` Expression

There are two parts to this: the "when" expression and the "then"
expression.  We compute the aggregate type of the "when" expressions as
we go, promoting it up to a larger type if needed (e.g. if one "when"
is an int and the other is a real, then the result is a real).  Likewise,
nullability is computed as the aggregate.  Note that if nothing matches,
the result is null, so we always get a nullable resultm unless there is an
"else" expression.  If we started with case expression, then each "when"
expression must be comparable to the case expression.  If we started
with case when xx then yy;  then each case expression must be numeric
(typically boolean).

#### The `BETWEEN` Expression

Between requires type compatibility between all three of its arguments.
Nullability follows the usual rules: if any might be null then the result
type might be null.  In any case, the result's core type is BOOL.

#### The `CAST` Expression

For cast expressions we use the provided semantic type; the only trick is
that we preserve the extra properties of the input argument.  e.g. CAST
does not remove `NOT NULL`.

#### The `COALESCE` Function

Coalesce requires type compatibility between all of its arguments.
The result is a not null type if we find a not null item in the list.
There should be nothing after that item.  Note that ifnull and coalesce
are really the same thing except ifnull must have exactly two arguments.

#### The `IN` AND `NOT IN` Expressions

The in predicate is like many of the other multi-argument operators.
All the items must be type compatible.  Note that in this case the
nullablity of the items does not matter, only the nullability of the
item being tested.  Note that null in (null) is null, not true.

#### Aggregate Functions

Aggregate functions can only be used in certain places.  For instance
they may not appear in a `WHERE` clause.

#### User Defined Functions

User defined function - this is an external function.
There are a few things to check:

* If this is declared without the select keyword then
  * we can't use these in SQL, so this has to be a loose expression
* If this is declared with the select keyword then
  * we can ONLY use these in SQL, not in a loose expression
* args have to be compatible with formals

#### Calling a procedure as a function

There are a few things to check:

* we can't use these in SQL, so this has to be a loose expression
* args have to be compatible with formals, except
* the last formal must be an OUT arg and it must be a scalar type
* that out arg will be treated as the return value of the "function"
* in code-gen we will create a temporary for it; semantic analysis doesn't care

#### Root Expressions

A top level expression defines the context for that evaluation.
Different expressions can have constraints.  e.g. aggregate functions
may not appear in the `WHERE` clause of a statement.  There are cases
where expression nesting can happen. This nesting changes the evaluation
context accordingly, e.g. you can put a nested select in a where clause
and that nested select could legally have aggregates.  Root expressions
keep a stack of nested contexts to facilitate the changes.

#### Table Factors

A table factor is one of three things:

* a table name (a string), the x in `select * from X`
* a select subquery e.g. `(select X,Y from..) as T2`
* a list of table references, the X, Y, Z in `select * from (X, Y, Z)`

Each of these has its own rules discussed elsewhere.

#### Joining with the `USING` Clause

When specifying joins, one of the alternatives is to give the shared
columns in the join e.g. select * from X inner join Y using (a,b).
This method validates that all the columns are present on both sides
of the join, that they are unique, and they are comparable.  The return
code tells us if any columns had SENSITIVE data.   See the Special Note on
JOIN...USING below

#### JOIN WITH THE `ON` Clause

The most explicit join condition is a full expression in an ON clause this
is like `select a,b from X inner join Y on X.id = Y.id;` The on expression
should be something that can be used as a bool, so any numeric will do.
The return code tells us if the ON condition used SENSITIVE data.

#### TABLE VALUED FUNCTIONS

Table valued functions can appear anywhere a table is allowed.
The validation rules are:

* must be a valid function
* must return a struct type (i.e. a table-valued-function)
* must have valid arg expressions
* arg expressions must match formal parameters
The name of the resulting table is the name of the function
 * but it can be aliased later with "AS"

 ### Special Note on the `select *` and `select T.*` forms

 The `select *` construct is very popular in many codebases but it can
 be unsafe to use in production code because, if the schema changes,
 the code might get columns it does not expect.  Note the extra
 columns could have appeared anywhere in the result set because the
 `*` applies to the entire result of the `FROM` clause, joins and all,
 so extra columns are not necessarily at the end and column ordinals
 are not preserved.  CQL mitigates this situation somewhat with some
 useful constraints/features:

* in a `select *`, and indeed in any query, the column names of the select must be unique, this is because:
   * they could form the field names of an automatically generated cursor (see the section on cursors)
   * they could form the field names in a CQL result set (see section on result sets)
   * it's weird/confusing to not have unique names generally
* when issuing a `select *` or a `select T.*` CQL will automatically expand the `*` into the actual logical columns that exist in the schema at the time the code was compiled
   * this is important because if a column had been logically deleted from a table it would be unexpected in the result set even though it is still present in the database and would throw everything off
   * likewise if the schema were to change without updating the code, the code will still get the columns it was compiled with, not new columns

Expanding the `*` at compile time means Sqlite cannot see anything that
might tempt it to include different columns in the result than CQL saw
at compile time.

With this done we just have to look at the places a `select *` might
appear so we can see if it is safe (or at least reasonably safe) to use
`*` and, by extension of the same argument, `T.*`.

In an `EXISTS` or `NOT EXISTS` clause like `where not exists (select * from x)`*

* this is perfectly safe; the particular columns do not matter; `select *` is not even expanded in this case.

In a statement that produces a result set like `select * from table_or_view`*

* binding to a CQL result set is done by column name and we know those names are unique
* we won't include any columns that are logically deleted, so if you try to use a deleted column you'll get a compile time error

In a cursor statement like `declare C cursor for select * from table_or_view` there are two cases here:

*Automatic Fetch  `fetch C;`*

* in this case you don't specify the column names yourself;2 they are inferred
* you are therefore binding to the columns by name, so new columns in the cursor would be unused (until you choose to start using them)
* if you try to access a deleted column you get a compile-time error

*Manual Fetch:  `fetch C into a, b, c;`*

* In this case the number and type of the columns must match exactly with the specified variables
* If new columns are added, deleted, or changed, the above code will not compile

So considering the cases above we can conclude that auto expanding
the `*` into the exact columns present in the compile-time schema
version ensures that any incompatible changes result in compile time
errors. Adding columns to tables does not cause problems even if the
code is not recompiled. This makes the `*` construct much safer, if not
perfect, but no semantic would be safe from arbitrary schema changes
without recompilation.  At the very least here we can expect a meaningful
runtime error rather than silently fetching the wrong columns.

### Special Note on the JOIN...USING form

CQL varies slightly from SQLite in terms of the expected results for joins
if the USING syntax is employed.  This is not the most common syntax
(typically an ON clause is used) but Sqlite has special rules for this
kind of join.

Let's take a quick look.  First some sample data:

```
create table A( id integer, a text, b text);
create table B( id integer, c text, d text);

insert into A values(1, 'a1', 'b1');
insert into B values(1, 'c1', 'd1');
insert into A values(2, 'a2', 'b2');
insert into B values(2, 'c2', 'd2');
```

Now let's look at the normal join; this is our reference:
```
select * from A T1 inner join B T2 on T1.id = T2.id;

result:

1|a1|b1|1|c1|d1
2|a2|b2|2|c2|d2
```
As expected, you get all the columns of A, and all the columns of B.  The 'id' column appears twice.


However, with the `USING` syntax:

```
select * T1 inner join B T2 using (id);

result:

1|a1|b1|c1|d1
2|a2|b2|c2|d2
```
The `id` column is now appearing exactly once.  However, the situation
is not so simple as that.  It seems that what hapened was that the `*`
expansion has not included two copies of the `id`.  The following cases
show that both copies of `id` are still logically in the join.

```
select T1.*, 'xxx', T2.* from A T1 inner join B T2 using (id);

result:

1|a1|b1|xxx|1|c1|d1
2|a2|b2|xxx|2|c2|d2
```
The `T2.id` column is part of the join, it just wasn't part of the `*`


In fact, looking further:

```
select T1.id, T1.a, T1.b, 'xxx', T2.id, T2.c, T2.d from A T1 inner join B T2 using (id);

result:

1|a1|b1|xxx|1|c1|d1
2|a2|b2|xxx|2|c2|d2
```
There is no doubt, `T2.id` is a valid column and can be used in
expressions freely. That means the column cannot be removed from the
type calculus.

Now in CQL, the `*` and `T.*` forms are automatically expanded; SQLite
doesn't see the `*`.  This is done so that if any columns have been
logically deleted they can be elided from the result set.  Given that
this happens, the `*` operator will expand to ALL the columns.  Just the
same as if you did `T1.*` and `T2.*`.

*As a result, in CQL, there is no difference between  the `USING` form of a join and the `ON` form of a join.*

In fact, only the `select *` form could possibly be different, so in most
cases this ends up being moot anyway.  Typically, you can't use
`*` in the presence of joins because of name duplication and ambiguity
of the column names of the result set.  CQL's automatic expansion means
you have a much better idea exactly what columns you will get - those
that were present in the schema you declared.  The CQL `@COLUMNS` function
(q.v.) can also help you to make good select lists more easily.
