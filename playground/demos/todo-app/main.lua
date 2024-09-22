local ffi = require("ffi")
local sqlite3 = ffi.load("sqlite3")
local todo_sdk = ffi.load("../../out/todo_sdk/todo_sdk")

local content = assert(io.open("../../out/todo_sdk/todo_sdk.h", "r")):read("*a")

ffi.cdef[[
  // SQLite
  typedef struct sqlite3 sqlite3;
  typedef struct sqlite3_stmt sqlite3_stmt;
  typedef long long int sqlite3_int64;

  int sqlite3_open(const char *filename, sqlite3 **ppDb);
  int sqlite3_close(sqlite3*);
  int sqlite3_exec(sqlite3*, const char *sql, int (*callback)(void*,int,char**,char**), void *, char **errmsg);
  int sqlite3_close_v2(sqlite3*);

  // cqrt.h
  typedef unsigned char cql_bool;
  typedef uint64_t cql_hash_code;
  typedef int32_t cql_int32;
  typedef uint32_t cql_uint32;
  typedef uint16_t cql_uint16;
  typedef sqlite3_int64 cql_int64;
  typedef double cql_double;
  typedef int cql_code;

  typedef struct cql_type *cql_type_ref;
  typedef struct cql_type { int type; int ref_count; void (*finalize)(cql_type_ref ref); } cql_type;
  typedef struct cql_string *cql_string_ref;
  typedef struct cql_string { cql_type base; const char *ptr; } cql_string;

  cql_string_ref cql_string_ref_new(const char* cstr);

  typedef struct cql_nullable_int32 { cql_bool is_null; cql_int32 value; } cql_nullable_int32;
  typedef struct cql_nullable_int64 { cql_bool is_null; cql_int64 value; } cql_nullable_int64;
  typedef struct cql_nullable_double { cql_bool is_null; cql_double value; } cql_nullable_double;
  typedef struct cql_nullable_bool { cql_bool is_null; cql_bool value; } cql_nullable_bool;

  // todo_sdk.h
  typedef struct get_all_tasks_result_set *get_all_tasks_result_set_ref;

  cql_code get_all_tasks(sqlite3* _db_, sqlite3_stmt _result_stmt);
  cql_code create_tasks_table(sqlite3* _db_);
  cql_code add_task(sqlite3* _db_, cql_int32 id, cql_string_ref title, cql_string_ref description);
  cql_code get_all_tasks_fetch_results(sqlite3* _db_, get_all_tasks_result_set_ref result_set);
  cql_code get_all_tasks(sqlite3* _db_, sqlite3_stmt _result_stmt);
  cql_code update_task(sqlite3* _db_, cql_int32 id_, cql_string_ref title_, cql_string_ref description_, cql_nullable_bool is_done_);
  cql_code delete_task(sqlite3* _db_, cql_int32 id_);
  cql_code print_tasks(sqlite3* _db_);
  cql_code entrypoint(sqlite3* _db_);
]]

local SQLITE_SUCCESS = 0;
local SQLITE_ROW = 100;
local SQLITE_DONE = 101;

local function E(code, message)
  if code == SQLITE_SUCCESS then return end

  error(message .. " failed with error code: " .. code)
end

local db = ffi.new("sqlite3*[1]")

E(sqlite3.sqlite3_open(":memory:", db), "Open database")

-- @TODO:
-- - Create proxy to dynamically wrap procedures based on json and translate lua to cql types
-- - Release
-- - error handling


E(todo_sdk.create_tasks_table(db[0]), "Create tables")

E(todo_sdk.add_task(db[0], 1, todo_sdk.cql_string_ref_new("Buy groceries"), todo_sdk.cql_string_ref_new("Milk, Eggs, Bread")))
E(todo_sdk.add_task(db[0], 2, todo_sdk.cql_string_ref_new("Call John"), todo_sdk.cql_string_ref_new("Discuss the project details")))

E(todo_sdk.print_tasks(db[0]));

E(todo_sdk.update_task(db[0], 1, nil, nil, ffi.new("cql_nullable_bool", {is_null = 0, value = 1})))
E(todo_sdk.print_tasks(db[0]))
E(todo_sdk.update_task(db[0], 2, todo_sdk.cql_string_ref_new("Call John Joe"), nil, ffi.new("cql_nullable_bool", {is_null = 0, value = 0})))
E(todo_sdk.print_tasks(db[0]))
E(todo_sdk.delete_task(db[0], 2))
E(todo_sdk.print_tasks(db[0]))
