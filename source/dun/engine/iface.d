module dun.engine.iface;

struct JSHandle
{
    void*[2] opaque;
    long tag;
}

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

enum DEFAULT_MEMORY_LIMIT = MiB(256);
enum DEFAULT_MAX_STACK = MiB(8);
enum TEST_MEMORY_LIMIT = MiB(64);
enum TEST_MAX_STACK = MiB(4);

struct EngineConfig
{
    size_t memoryLimit = DEFAULT_MEMORY_LIMIT;
    size_t maxStackSize = DEFAULT_MAX_STACK;
}

alias NativeCallback = JSHandle function(
    void* engineCtx, JSHandle thisVal, JSHandle[] args) nothrow;

alias NativeCCallback = extern (C) JSHandle function(
    void* ctx, JSHandle thisVal, int argc, JSHandle* argv) nothrow;

alias ModuleLoaderCallback = void* function(
    void* engineCtx, const(char)[] moduleName) nothrow;

interface IJSEngine
{
    // --- Lifecycle ---
    void initialize(EngineConfig config);
    void shutdown();

    // --- Evaluation ---
    JSResult eval(const(char)[] source, string filename);

    // --- Value creation ---
    JSHandle newString(const(char)[] s);
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
    JSHandle getProperty(JSHandle obj, const(char)[] name);
    void setProperty(JSHandle obj, const(char)[] name, JSHandle val);
    JSHandle getGlobal();

    // --- Reference management ---
    JSHandle dupValue(JSHandle val);
    void freeValue(JSHandle val);

    // --- Type checks ---
    bool isException(JSHandle val);
    bool isUndefined(JSHandle val);
    bool isNull(JSHandle val);
    bool isString(JSHandle val);
    bool isObject(JSHandle val);
    bool isFunction(JSHandle val);
    bool isBool(JSHandle val);
    bool isNumber(JSHandle val);

    // --- Exceptions ---
    string getException();
    JSHandle throwTypeError(const(char)[] msg);
    JSHandle throwRangeError(const(char)[] msg);

    // --- Microtasks / Promise jobs ---
    bool hasPendingJobs();
    bool executePendingJob();
    void drainJobs();

    // --- Opaque state ---
    void setContextOpaque(void* ptr);
    void* getContextOpaque();

    // --- Modules ---
    void setModuleLoader(ModuleLoaderCallback loader);
    JSResult evalModule(const(char)[] source, string filename) @trusted;
    void registerNativeModule(string name, void* initFunc) @trusted;

    // --- Limits ---
    void setMemoryLimit(size_t bytes);
    void setMaxStackSize(size_t bytes);

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
