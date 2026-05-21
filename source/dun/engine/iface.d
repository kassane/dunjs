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

/// `@mustuse` forces every `engine.eval` caller to inspect `isError`
/// (DIP 1038) — catches dropped init/eval failures at compile time.
import core.attribute : mustuse;
@mustuse
struct JSResult
{
    JSHandle value;
    bool isError;
    string errorMessage;
}

// Engine limits — defined in `dun.declarations`, re-exported here
// so existing engine-layer imports keep working unchanged.
public import dun.declarations :
    DEFAULT_MEMORY_LIMIT, DEFAULT_MAX_STACK,
    TEST_MEMORY_LIMIT, TEST_MAX_STACK,
    NATIVE_CALL_STACK_ARGS;

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

/// `@mustuse` (DIP 1038): `newPromise()` returns three owned JSHandles
/// (promise + resolve + reject). Dropping the struct leaks all three —
/// on JSC that's 3 leaked `JSValueProtect` slots per drop. Force the
/// compiler to flag any caller that doesn't store + free.
@mustuse
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

    /// Set `obj.name = fn` without consuming `fn` — backends that
    /// would normally consume (QuickJS) dup internally. Use for
    /// cached __gshared method handles that outlive their call sites.
    void bindMethod(JSHandle obj, scope const(char)[] name, JSHandle fn);

    /// `Object.setPrototypeOf(obj, proto)`. Hot-path replacement for
    /// the JS-level factory we used to build Buffers with.
    void setPrototype(JSHandle obj, JSHandle proto);

    /// Fused `new Uint8Array(data) + setPrototypeOf(_, proto)` —
    /// one backend call per Buffer.from/alloc/concat. `data` may be
    /// null when `zeroed` and `len > 0` (Buffer.alloc semantics).
    JSHandle newBufferWithProto(scope const(ubyte)[] data, JSHandle proto, bool zeroed);

    /// Fused `new Uint8Array(size) + setPrototypeOf(_, proto)` for
    /// `Buffer.alloc(size)` — V8 collapses to one Isolate/Context-Scope
    /// entry; QuickJS/JSC fall back to the 2-step path. Returns a
    /// zeroed buffer of `size` bytes with `proto` installed.
    JSHandle newUint8ArrayZeroedWithProto(size_t size, JSHandle proto);

    /// Fused `Buffer.from(jsString, "utf8")` — V8 writes UTF-8 directly;
    /// QuickJS/JSC fall back to the two-step path.
    JSHandle newBufferFromUtf8String(JSHandle jsStr, JSHandle proto);

    // --- Reference management ---
    JSHandle dupValue(JSHandle val);
    void freeValue(JSHandle val);

    // --- Typed arrays ---
    JSHandle newUint8Array(scope const(ubyte)[] data);
    JSHandle newUint8ArrayZeroed(size_t length);

    /// Engine-owned slice tied to `val`'s lifetime — `.dup` if you
    /// need it past the JSHandle. `return scope` is DIP1000-checked.
    ubyte[] getTypedArrayBytes(return scope JSHandle val) @trusted;

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

/// Eval closed-world inline JS and assert success — the canonical
/// drop-only consumer for `@mustuse JSResult` (build-time init code
/// where eval failure is a programmer bug, not user data).
void mustEval(IJSEngine engine, scope const(char)[] source,
    string filename, string what) @trusted
{
    auto r = engine.eval(source, filename);
    assert(!r.isError, what ~ " failed: " ~ r.errorMessage);
    engine.freeValue(r.value);
}
