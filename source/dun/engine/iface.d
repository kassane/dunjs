module dun.engine.iface;

struct JSHandle
{
    void*[2] opaque;
    long tag;
}

static assert(JSHandle.sizeof >= 2 * (void*).sizeof,
    "JSHandle must hold at least two pointers for engine value storage");
static assert(JSHandle.sizeof <= 24,
    "JSHandle unexpectedly large -- review layout");

struct JSResult
{
    JSHandle value;
    bool isError;
    string errorMessage;
}

private size_t MiB(size_t n) @safe pure nothrow @nogc
{
    return n * 1024 * 1024;
}

enum DEFAULT_MEMORY_LIMIT = MiB(2048);
enum DEFAULT_MAX_STACK = MiB(8);
enum TEST_MEMORY_LIMIT = MiB(64);
enum TEST_MAX_STACK = MiB(4);
enum NATIVE_CALL_STACK_ARGS = 16;

struct EngineConfig
{
    size_t memoryLimit = DEFAULT_MEMORY_LIMIT;
    size_t maxStackSize = DEFAULT_MAX_STACK;
}

alias NativeCallback = JSHandle function(
    void* engineCtx, JSHandle thisVal, scope JSHandle[] args);

alias NativeCCallback = extern (C) JSHandle function(
    void* ctx, JSHandle thisVal, int argc, JSHandle* argv) nothrow;

alias ModuleLoaderCallback = void* function(
    void* engineCtx, const(char)[] moduleName) nothrow;

struct PromiseHandles
{
    JSHandle promise;
    JSHandle resolve;
    JSHandle reject;
}

interface IJSEngine
{
    // --- Lifecycle ---
    void initialize(EngineConfig config);
    void shutdown();

    // --- Evaluation ---
    JSResult eval(scope const(char)[] source, string filename);

    // --- Value creation ---
    JSHandle newUndefined();
    JSHandle newNull();
    JSHandle newString(scope const(char)[] s);
    JSHandle newInt(int v);
    JSHandle newFloat(double v);
    JSHandle newBool(bool v);
    JSHandle newObject();
    JSHandle newArray();
    JSHandle newFunction(NativeCallback cb, string name, int argc);

    // --- Value extraction ---
    string extractString(JSHandle val);
    int extractInt(JSHandle val);
    double extractFloat(JSHandle val);
    bool extractBool(JSHandle val);

    // --- Properties ---
    JSHandle getProperty(JSHandle obj, scope const(char)[] name);
    void setProperty(JSHandle obj, scope const(char)[] name, JSHandle val);
    JSHandle getGlobal();

    /// Bind a long-lived function value as a property of `obj` without
    /// transferring ownership of `fn`. Use this for "method binding" of
    /// cached function handles (e.g. `_cachedUpdateFn`) that are stored
    /// in `__gshared` slots and must outlive every call site that copies
    /// them onto per-call objects.
    ///
    /// Backends:
    /// - QuickJS: `JS_SetPropertyStr` consumes the value, so we
    ///   internally `JS_DupValue` first — caller's `fn` handle stays
    ///   valid afterwards.
    /// - JSC: `JSObjectSetProperty` does not consume — the property
    ///   table inside the JS object roots `fn` for us — no extra
    ///   `JSValueProtect` needed. (Avoiding the per-call protect is
    ///   what keeps hot loops like `crypto.createHash().update().digest()`
    ///   from leaking one entry on JSC's protect table per call.)
    void bindMethod(JSHandle obj, scope const(char)[] name, JSHandle fn);

    // --- Reference management ---
    JSHandle dupValue(JSHandle val);
    void freeValue(JSHandle val);

    // --- Typed arrays ---
    JSHandle newUint8Array(scope const(ubyte)[] data);
    JSHandle newUint8ArrayZeroed(size_t length);
    ubyte[] getTypedArrayBytes(JSHandle val) @trusted;

    // --- Indexed property access (O(1) for arrays) ---
    void setPropertyIndex(JSHandle obj, uint idx, JSHandle val);
    JSHandle getPropertyIndex(JSHandle obj, uint idx);

    // --- Array operations ---
    bool isArray(JSHandle val);
    int getArrayLength(JSHandle val);

    // --- Type checks ---
    bool isException(JSHandle val);
    bool isUndefined(JSHandle val);
    bool isNull(JSHandle val);
    bool isString(JSHandle val);
    bool isObject(JSHandle val);
    bool isFunction(JSHandle val);
    bool isBool(JSHandle val);
    bool isNumber(JSHandle val);

    // --- Invocation ---
    JSHandle callFunction(JSHandle func, JSHandle thisVal, JSHandle[] args);

    // --- Exceptions ---
    string getException();
    JSHandle throwTypeError(scope const(char)[] msg);
    JSHandle throwRangeError(scope const(char)[] msg);
    JSHandle throwValue(JSHandle val);

    // --- Promises ---
    PromiseHandles newPromise();

    // --- Microtasks / Promise jobs ---
    bool hasPendingJobs();
    bool executePendingJob();
    void drainJobs();

    // --- Opaque state ---
    void setContextOpaque(void* ptr);
    void* getContextOpaque();

    // --- Modules ---
    void setModuleLoader(ModuleLoaderCallback loader);
    JSResult evalModule(scope const(char)[] source, string filename) @trusted;
    void registerNativeModule(string name, void* initFunc) @trusted;

    // --- Limits ---
    void setMemoryLimit(size_t bytes);
    void setMaxStackSize(size_t bytes);

    // --- Garbage collection ---
    void collectGarbage();

    // --- Raw engine access (for backend-specific code) ---
    void* rawRuntime();
    void* rawContext();
}

enum EngineBackend
{
    quickjs,
    jsc,
    v8,
}

static assert(__traits(allMembers, EngineBackend).length == 3,
    "EngineBackend member count changed -- update createEngine and CLAUDE.md");

IJSEngine createEngine()
{
    version (EngineJSC)
    {
        import dun.engine.jsc.backend : JSCEngine;
        return new JSCEngine();
    }
    else version (EngineV8)
    {
        import dun.engine.v8.backend : V8Engine;
        return new V8Engine();
    }
    else
    {
        import dun.engine.quickjs.backend : QuickJSEngine;
        return new QuickJSEngine();
    }
}
