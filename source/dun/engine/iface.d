module dun.engine.iface;


/++
 + `@trusted policy`: this is the engine-agnostic interface
 + declaration + helpers. Every `@trusted` here is one of:
 +
 +   1. Interface method declarations annotated `@trusted` (the
 +      policy in CLAUDE.md §"Engine Abstraction" — every engine
 +      method touches FFI and is `@trusted` at the contract level,
 +      letting `@safe` callers use them without further escape).
 +   2. `mustEval(engine, src, name, what)` — drops the @mustuse
 +      JSResult while asserting `!isError`. The `@trusted` is for
 +      the unconditional `freeValue(r.value)` even on error,
 +      matching the cross-backend "callFunction returns owned"
 +      contract documented in CLAUDE.md.
 +/
struct JSHandle
{
    void*[2] opaque;
    long tag;
}

static assert(JSHandle.sizeof >= 2 * (void*).sizeof,
    "JSHandle must hold at least two pointers for engine value storage");
static assert(JSHandle.sizeof <= 24,
    "JSHandle unexpectedly large -- review layout");

/++
 + `@mustuse` forces every `engine.eval` caller to inspect `isError`
 + (DIP 1038) — catches dropped init/eval failures at compile time.
 +/
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

/++
 + `@mustuse` (DIP 1038): `newPromise()` returns three owned JSHandles
 + (promise + resolve + reject). Dropping the struct leaks all three —
 + on JSC that's 3 leaked `JSValueProtect` slots per drop. Force the
 + compiler to flag any caller that doesn't store + free.
 +/
@mustuse
struct PromiseHandles
{
    JSHandle promise;
    JSHandle resolve;
    JSHandle reject;
}

/++
 + All interface methods are `@trusted` because every backend
 + implementation touches a C/C++ FFI surface (QJS JSContext*, JSC
 + JSContextRef, V8 v8shim handles). The backends already carry
 + `@trusted` on each override — declaring it here lets `@safe`
 + callers use the engine without an `@trusted` escape of their own.
 + `rawRuntime` / `rawContext` stay `@system` because they hand the
 + caller a raw FFI pointer they can do anything with.
 +/
interface IJSEngine
{
    // --- Lifecycle ---
    void initialize(EngineConfig config) @trusted;
    void shutdown() @trusted;

    // --- Evaluation ---
    JSResult eval(scope const(char)[] source, string filename) @trusted;

    // --- Value creation ---
    JSHandle newUndefined() @trusted;
    JSHandle newNull() @trusted;
    JSHandle newString(scope const(char)[] s) @trusted;
    JSHandle newInt(int v) @trusted;
    JSHandle newFloat(double v) @trusted;
    JSHandle newBool(bool v) @trusted;
    JSHandle newObject() @trusted;
    JSHandle newArray() @trusted;
    JSHandle newFunction(NativeCallback cb, string name, int argc) @trusted;

    // --- Value extraction ---
    string extractString(JSHandle val) @trusted;
    int extractInt(JSHandle val) @trusted;
    double extractFloat(JSHandle val) @trusted;
    bool extractBool(JSHandle val) @trusted;

    // --- Properties ---
    JSHandle getProperty(JSHandle obj, scope const(char)[] name) @trusted;
    void setProperty(JSHandle obj, scope const(char)[] name, JSHandle val) @trusted;
    JSHandle getGlobal() @trusted;

    /++
     + Set `obj.name = fn` without consuming `fn` — backends that
     + would normally consume (QuickJS) dup internally. Use for
     + cached __gshared method handles that outlive their call sites.
     +/
    void bindMethod(JSHandle obj, scope const(char)[] name, JSHandle fn) @trusted;

    /++
     + `Object.setPrototypeOf(obj, proto)`. Hot-path replacement for
     + the JS-level factory we used to build Buffers with.
     +/
    void setPrototype(JSHandle obj, JSHandle proto) @trusted;

    /++
     + Fused `new Uint8Array(data) + setPrototypeOf(_, proto)` —
     + one backend call per Buffer.from/alloc/concat. `data` may be
     + null when `zeroed` and `len > 0` (Buffer.alloc semantics).
     +/
    JSHandle newBufferWithProto(scope const(ubyte)[] data, JSHandle proto, bool zeroed) @trusted;

    /++
     + Fused `new Uint8Array(size) + setPrototypeOf(_, proto)` for
     + `Buffer.alloc(size)` — V8 collapses to one Isolate/Context-Scope
     + entry; QuickJS/JSC fall back to the 2-step path. Returns a
     + zeroed buffer of `size` bytes with `proto` installed.
     +/
    JSHandle newUint8ArrayZeroedWithProto(size_t size, JSHandle proto) @trusted;

    /++
     + Fused `Buffer.from(jsString, "utf8")` — V8 writes UTF-8 directly;
     + QuickJS/JSC fall back to the two-step path.
     +/
    JSHandle newBufferFromUtf8String(JSHandle jsStr, JSHandle proto) @trusted;

    /++
     + Fused `Buffer.concat(list, totalLen)` — V8 iterates the array of
     + TypedArrays inside a single withContext scope, allocates one
     + Uint8Array of the requested total length, memcpy's each element
     + in order, and sets the Buffer prototype. Returns an empty handle
     + if the backend can't accelerate (caller falls back to the generic
     + engine-agnostic loop path).
     +/
    JSHandle bufferConcatFused(JSHandle arrayHandle, int count,
        size_t totalLen, JSHandle proto) @trusted;

    // --- Reference management ---
    JSHandle dupValue(JSHandle val) @trusted;
    void freeValue(JSHandle val) @trusted;

    // --- Typed arrays ---
    JSHandle newUint8Array(scope const(ubyte)[] data) @trusted;
    JSHandle newUint8ArrayZeroed(size_t length) @trusted;

    /++
     + Engine-owned slice tied to `val`'s lifetime — `.dup` if you
     + need it past the JSHandle. `return scope` is DIP1000-checked.
     +/
    ubyte[] getTypedArrayBytes(return scope JSHandle val) @trusted;

    // --- Indexed property access (O(1) for arrays) ---
    void setPropertyIndex(JSHandle obj, uint idx, JSHandle val) @trusted;
    JSHandle getPropertyIndex(JSHandle obj, uint idx) @trusted;

    // --- Array operations ---
    bool isArray(JSHandle val) @trusted;
    int getArrayLength(JSHandle val) @trusted;

    // --- Type checks ---
    bool isException(JSHandle val) @trusted;
    bool isUndefined(JSHandle val) @trusted;
    bool isNull(JSHandle val) @trusted;
    bool isString(JSHandle val) @trusted;
    bool isObject(JSHandle val) @trusted;
    bool isFunction(JSHandle val) @trusted;
    bool isBool(JSHandle val) @trusted;
    bool isNumber(JSHandle val) @trusted;

    // --- Invocation ---
    JSHandle callFunction(JSHandle func, JSHandle thisVal, JSHandle[] args) @trusted;

    // --- Exceptions ---
    string getException() @trusted;
    JSHandle throwTypeError(scope const(char)[] msg) @trusted;
    JSHandle throwRangeError(scope const(char)[] msg) @trusted;
    JSHandle throwValue(JSHandle val) @trusted;

    // --- Promises ---
    PromiseHandles newPromise() @trusted;

    // --- Microtasks / Promise jobs ---
    bool hasPendingJobs() @trusted;
    bool executePendingJob() @trusted;
    void drainJobs() @trusted;

    // --- Opaque state ---
    void setContextOpaque(void* ptr) @trusted;
    void* getContextOpaque() @trusted;

    // --- Modules ---
    void setModuleLoader(ModuleLoaderCallback loader) @trusted;
    JSResult evalModule(scope const(char)[] source, string filename) @trusted;
    void registerNativeModule(string name, void* initFunc) @trusted;

    // --- Limits ---
    void setMemoryLimit(size_t bytes) @trusted;
    void setMaxStackSize(size_t bytes) @trusted;

    // --- Garbage collection ---
    void collectGarbage() @trusted;

    // --- Raw engine access (for backend-specific code) ---
    // Stays @system: hands the caller a raw FFI pointer that anything
    // can be done with — pretending it's `@trusted` would be a lie.
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

/++
 + Eval closed-world inline JS and assert success — the canonical
 + drop-only consumer for `@mustuse JSResult` (build-time init code
 + where eval failure is a programmer bug, not user data).
 +/
void mustEval(IJSEngine engine, scope const(char)[] source,
    string filename, string what) @trusted
{
    auto r = engine.eval(source, filename);
    assert(!r.isError, what ~ " failed: " ~ r.errorMessage);
    engine.freeValue(r.value);
}
