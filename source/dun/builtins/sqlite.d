module dun.builtins.sqlite;

import dun.engine.iface : IJSEngine, JSHandle, NativeCallback;
import dun.runtime.globals : DunState;
import dun.platform.sqlite3;

void registerSqliteModule(IJSEngine engine) @trusted
{
    assert(engine !is null, "Null IJSEngine in registerSqliteModule");
    auto obj = engine.newObject();

    engine.setProperty(obj, "open", engine.newFunction(&jsSqliteOpen, "open", 1));
    engine.setProperty(obj, "version_", engine.newFunction(&jsSqliteVersion, "version", 0));

    auto global = engine.getGlobal();
    engine.setProperty(global, "__dun_cjs_sqlite__", obj);

    version (EngineQuickJS)
        registerQuickJSModule(engine);
}

version (EngineQuickJS)
{
    import dun.engine.quickjs.bindings;

    private void registerQuickJSModule(IJSEngine engine) @trusted
    {
        auto ctx = cast(JSContext*) engine.rawContext();
        assert(ctx !is null, "Null JSContext in registerQuickJSModule (sqlite)");
        auto m = JS_NewCModule(ctx, "dun:sqlite", &sqliteModuleInit);
        if (m is null) return;
        foreach (name; ["open", "version"])
            JS_AddModuleExport(ctx, m, name.ptr);
    }

    private extern (C) int sqliteModuleInit(JSContext* ctx, JSModuleDef* m) nothrow @trusted
    {
        assert(ctx !is null, "Null JSContext in sqliteModuleInit");
        assert(m !is null, "Null JSModuleDef in sqliteModuleInit");
        auto global = JS_GetGlobalObject(ctx);
        auto sqliteObj = JS_GetPropertyStr(ctx, global, "__dun_cjs_sqlite__");
        foreach (name; ["open", "version"])
        {
            auto fn = JS_GetPropertyStr(ctx, sqliteObj, name.ptr);
            JS_SetModuleExport(ctx, m, name.ptr, fn);
        }
        JS_FreeValue(ctx, sqliteObj);
        JS_FreeValue(ctx, global);
        return 0;
    }
}

private:

// ── Handle Management ────────────────────────────────────────────────
// Maps integer IDs to native sqlite3* and sqlite3_stmt* pointers.
// Thread-local (D default), safe for single-threaded JS execution.

sqlite3*[int] activeDBs;
int nextDbId = 1;

sqlite3* getDbHandle(IJSEngine engine, JSHandle thisVal) @trusted
{
    assert(engine !is null, "Null engine in getDbHandle");
    auto idHandle = engine.getProperty(thisVal, "__dbId__");
    int id = engine.extractInt(idHandle);
    engine.freeValue(idHandle);
    if (auto p = id in activeDBs)
        return *p;
    return null;
}

// ── JS API Functions ─────────────────────────────────────────────────

JSHandle jsSqliteOpen(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSqliteOpen");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsSqliteOpen");
    auto engine = state.engine;

    if (args.length < 1)
        return engine.throwTypeError("sqlite.open() requires a filename argument");

    string path = engine.extractString(args[0]);

    import std.string : toStringz;
    sqlite3* db;
    int rc = sqlite3_open(cast(const(char)*) path.toStringz, &db);
    if (rc != SQLITE_OK)
    {
        string msg = sqliteErrMsg(db);
        sqlite3_close(db);
        return engine.throwTypeError("SQLite open error: " ~ msg);
    }
    assert(db !is null, "sqlite3_open returned OK but db is null");

    int id = nextDbId++;
    activeDBs[id] = db;

    auto dbObj = engine.newObject();
    engine.setProperty(dbObj, "__dbId__", engine.newInt(id));
    engine.setProperty(dbObj, "exec", engine.newFunction(&jsSqliteExec, "exec", 1));
    engine.setProperty(dbObj, "run", engine.newFunction(&jsSqliteRun, "run", 10));
    engine.setProperty(dbObj, "get", engine.newFunction(&jsSqliteGet, "get", 10));
    engine.setProperty(dbObj, "all", engine.newFunction(&jsSqliteAll, "all", 10));
    engine.setProperty(dbObj, "close", engine.newFunction(&jsSqliteClose, "close", 0));
    engine.setProperty(dbObj, "filename", engine.newString(path));

    return dbObj;
}

JSHandle jsSqliteExec(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSqliteExec");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsSqliteExec");
    auto engine = state.engine;

    auto db = getDbHandle(engine, thisVal);
    if (db is null)
        return engine.throwTypeError("Database is closed");
    if (args.length < 1)
        return engine.throwTypeError("exec() requires a SQL string");

    import std.string : toStringz;
    string sql = engine.extractString(args[0]);
    char* errmsg;
    int rc = sqlite3_exec(db, sql.toStringz, null, null, &errmsg);
    if (rc != SQLITE_OK)
    {
        string msg = errmsg !is null
            ? (() @trusted { import std.string : fromStringz; return fromStringz(errmsg).idup; })()
            : "unknown error";
        if (errmsg !is null)
            sqlite3_free(errmsg);
        return engine.throwTypeError("SQL error: " ~ msg);
    }
    return engine.newUndefined();
}

JSHandle jsSqliteRun(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSqliteRun");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsSqliteRun");
    auto engine = state.engine;

    auto db = getDbHandle(engine, thisVal);
    if (db is null)
        return engine.throwTypeError("Database is closed");
    if (args.length < 1)
        return engine.throwTypeError("run() requires a SQL string");

    import std.string : toStringz;
    string sql = engine.extractString(args[0]);

    sqlite3_stmt* stmt;
    int rc = sqlite3_prepare_v2(db, sql.toStringz, -1, &stmt, null);
    if (rc != SQLITE_OK)
        return engine.throwTypeError("SQL prepare error: " ~ sqliteErrMsg(db));
    assert(stmt !is null, "sqlite3_prepare_v2 returned OK but stmt is null");

    bindArgs(engine, stmt, args[1 .. $]);

    rc = sqlite3_step(stmt);
    int changes = sqlite3_changes(db);
    long lastId = sqlite3_last_insert_rowid(db);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE && rc != SQLITE_ROW)
        return engine.throwTypeError("SQL run error: " ~ sqliteErrMsg(db));

    auto result = engine.newObject();
    engine.setProperty(result, "changes", engine.newInt(changes));
    engine.setProperty(result, "lastInsertRowid", engine.newFloat(cast(double) lastId));
    return result;
}

JSHandle jsSqliteGet(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSqliteGet");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsSqliteGet");
    auto engine = state.engine;

    auto db = getDbHandle(engine, thisVal);
    if (db is null)
        return engine.throwTypeError("Database is closed");
    if (args.length < 1)
        return engine.throwTypeError("get() requires a SQL string");

    import std.string : toStringz;
    string sql = engine.extractString(args[0]);

    sqlite3_stmt* stmt;
    int rc = sqlite3_prepare_v2(db, sql.toStringz, -1, &stmt, null);
    if (rc != SQLITE_OK)
        return engine.throwTypeError("SQL prepare error: " ~ sqliteErrMsg(db));
    assert(stmt !is null, "sqlite3_prepare_v2 returned OK but stmt is null");

    bindArgs(engine, stmt, args[1 .. $]);

    rc = sqlite3_step(stmt);
    if (rc == SQLITE_ROW)
    {
        auto row = extractRow(engine, stmt);
        sqlite3_finalize(stmt);
        return row;
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE)
        return engine.throwTypeError("SQL get error: " ~ sqliteErrMsg(db));

    return engine.newNull();
}

JSHandle jsSqliteAll(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSqliteAll");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsSqliteAll");
    auto engine = state.engine;

    auto db = getDbHandle(engine, thisVal);
    if (db is null)
        return engine.throwTypeError("Database is closed");
    if (args.length < 1)
        return engine.throwTypeError("all() requires a SQL string");

    import std.string : toStringz;
    string sql = engine.extractString(args[0]);

    sqlite3_stmt* stmt;
    int rc = sqlite3_prepare_v2(db, sql.toStringz, -1, &stmt, null);
    if (rc != SQLITE_OK)
        return engine.throwTypeError("SQL prepare error: " ~ sqliteErrMsg(db));
    assert(stmt !is null, "sqlite3_prepare_v2 returned OK but stmt is null");

    bindArgs(engine, stmt, args[1 .. $]);

    auto results = engine.newArray();
    uint rowIdx = 0;
    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW)
    {
        auto row = extractRow(engine, stmt);
        engine.setPropertyIndex(results, rowIdx++, row);
    }
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE)
        return engine.throwTypeError("SQL all error: " ~ sqliteErrMsg(db));

    return results;
}

JSHandle jsSqliteClose(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSqliteClose");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsSqliteClose");
    auto engine = state.engine;

    auto idHandle = engine.getProperty(thisVal, "__dbId__");
    int id = engine.extractInt(idHandle);
    engine.freeValue(idHandle);

    if (auto p = id in activeDBs)
    {
        sqlite3_close(*p);
        activeDBs.remove(id);
    }
    return engine.newUndefined();
}

JSHandle jsSqliteVersion(void* ctx, JSHandle thisVal, JSHandle[] args) @trusted
{
    assert(ctx !is null, "Null ctx in jsSqliteVersion");
    auto state = cast(DunState*) ctx;
    assert(state.engine !is null, "Null engine in jsSqliteVersion");
    auto engine = state.engine;

    auto ver = sqlite3_libversion();
    if (ver is null)
        return engine.newString("unknown");
    import std.string : fromStringz;
    return engine.newString(fromStringz(ver).idup);
}

// ── Helpers ──────────────────────────────────────────────────────────

void bindArgs(IJSEngine engine, sqlite3_stmt* stmt, JSHandle[] args) @trusted
{
    assert(engine !is null, "Null engine in bindArgs");
    assert(stmt !is null, "Null stmt in bindArgs");

    import std.string : toStringz;

    foreach (i, arg; args)
    {
        int idx = cast(int)(i + 1);
        if (engine.isNull(arg) || engine.isUndefined(arg))
        {
            sqlite3_bind_null(stmt, idx);
        }
        else if (engine.isNumber(arg))
        {
            double val = engine.extractFloat(arg);
            if (val == cast(double) cast(long) val && val >= -2_147_483_648.0 && val <= 2_147_483_647.0)
                sqlite3_bind_int(stmt, idx, cast(int) val);
            else
                sqlite3_bind_double(stmt, idx, val);
        }
        else if (engine.isBool(arg))
        {
            sqlite3_bind_int(stmt, idx, engine.extractBool(arg) ? 1 : 0);
        }
        else
        {
            string s = engine.extractString(arg);
            sqlite3_bind_text(stmt, idx, s.toStringz, cast(int) s.length, SQLITE_TRANSIENT);
        }
    }
}

JSHandle extractRow(IJSEngine engine, sqlite3_stmt* stmt) @trusted
{
    assert(engine !is null, "Null engine in extractRow");
    assert(stmt !is null, "Null stmt in extractRow");

    import std.string : fromStringz;

    auto row = engine.newObject();
    int cols = sqlite3_column_count(stmt);

    foreach (i; 0 .. cols)
    {
        auto namePtr = sqlite3_column_name(stmt, i);
        if (namePtr is null) continue;
        string name = fromStringz(namePtr).idup;

        int colType = sqlite3_column_type(stmt, i);
        JSHandle val;
        switch (colType)
        {
            case SQLITE_INTEGER:
                val = engine.newInt(sqlite3_column_int(stmt, i));
                break;
            case SQLITE_FLOAT:
                val = engine.newFloat(sqlite3_column_double(stmt, i));
                break;
            case SQLITE_TEXT:
                auto textPtr = cast(const(char)*) sqlite3_column_text(stmt, i);
                val = engine.newString(textPtr !is null ? fromStringz(textPtr).idup : "");
                break;
            case SQLITE_NULL:
                val = engine.newNull();
                break;
            case SQLITE_BLOB:
                val = engine.newNull();
                break;
            default:
                val = engine.newNull();
                break;
        }
        engine.setProperty(row, name, val);
    }
    return row;
}

string sqliteErrMsg(sqlite3* db) @trusted
{
    if (db is null) return "database handle is null";
    auto ptr = sqlite3_errmsg(db);
    if (ptr is null) return "unknown error";
    import std.string : fromStringz;
    return fromStringz(ptr).idup;
}

// ── Unit Tests ───────────────────────────────────────────────────────

version (unittest)
{
    @("sqlite3 bindings link correctly")
    @trusted unittest
    {
        auto ver = sqlite3_libversion();
        assert(ver !is null, "sqlite3_libversion returned null");
        import std.string : fromStringz;
        auto s = fromStringz(ver);
        assert(s.length > 0, "sqlite3 version string is empty");
    }

    @("sqlite3 open/close in-memory database")
    @trusted unittest
    {
        sqlite3* db;
        int rc = sqlite3_open(":memory:", &db);
        assert(rc == SQLITE_OK, "Failed to open in-memory database");
        assert(db !is null, "db is null after successful open");
        rc = sqlite3_close(db);
        assert(rc == SQLITE_OK, "Failed to close database");
    }

    @("sqlite3 exec and query")
    @trusted unittest
    {
        sqlite3* db;
        assert(sqlite3_open(":memory:", &db) == SQLITE_OK);

        char* errmsg;
        int rc = sqlite3_exec(db,
            "CREATE TABLE t (id INTEGER PRIMARY KEY, val TEXT);" ~
            "INSERT INTO t (val) VALUES ('hello');" ~
            "INSERT INTO t (val) VALUES ('world');",
            null, null, &errmsg);
        assert(rc == SQLITE_OK, "exec failed");

        sqlite3_stmt* stmt;
        rc = sqlite3_prepare_v2(db, "SELECT * FROM t ORDER BY id", -1, &stmt, null);
        assert(rc == SQLITE_OK, "prepare failed");

        rc = sqlite3_step(stmt);
        assert(rc == SQLITE_ROW, "expected row");
        assert(sqlite3_column_int(stmt, 0) == 1);

        import std.string : fromStringz;
        auto text = fromStringz(cast(const(char)*) sqlite3_column_text(stmt, 1));
        assert(text == "hello", "expected 'hello', got '" ~ text.idup ~ "'");

        rc = sqlite3_step(stmt);
        assert(rc == SQLITE_ROW, "expected second row");
        assert(sqlite3_column_int(stmt, 0) == 2);

        rc = sqlite3_step(stmt);
        assert(rc == SQLITE_DONE, "expected done");

        sqlite3_finalize(stmt);
        sqlite3_close(db);
    }

    @("sqlite3 bind parameters")
    @trusted unittest
    {
        sqlite3* db;
        assert(sqlite3_open(":memory:", &db) == SQLITE_OK);

        char* errmsg;
        sqlite3_exec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, score REAL)",
            null, null, &errmsg);

        sqlite3_stmt* stmt;
        sqlite3_prepare_v2(db, "INSERT INTO t (name, score) VALUES (?, ?)", -1, &stmt, null);

        import std.string : toStringz;
        sqlite3_bind_text(stmt, 1, "alice".toStringz, 5, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, 95.5);
        assert(sqlite3_step(stmt) == SQLITE_DONE);
        sqlite3_finalize(stmt);

        sqlite3_prepare_v2(db, "SELECT name, score FROM t WHERE name = ?", -1, &stmt, null);
        sqlite3_bind_text(stmt, 1, "alice".toStringz, 5, SQLITE_TRANSIENT);
        assert(sqlite3_step(stmt) == SQLITE_ROW);

        import std.string : fromStringz;
        assert(fromStringz(cast(const(char)*) sqlite3_column_text(stmt, 0)) == "alice");
        assert(sqlite3_column_double(stmt, 1) == 95.5);

        sqlite3_finalize(stmt);
        sqlite3_close(db);
    }
}
