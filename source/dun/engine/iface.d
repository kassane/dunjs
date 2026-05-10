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

struct EngineConfig
{
    size_t memoryLimit = 256 * 1024 * 1024;
    size_t maxStackSize = 8 * 1024 * 1024;
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

IJSEngine createEngine(EngineBackend backend = EngineBackend.quickjs)
{
    final switch (backend)
    {
    case EngineBackend.quickjs:
        import dun.engine.quickjs.backend : QuickJSEngine;
        return new QuickJSEngine();
    case EngineBackend.jsc:
        import dun.engine.jsc.backend : JSCEngine;
        return new JSCEngine();
    case EngineBackend.v8:
        import dun.engine.v8.backend : V8Engine;
        return new V8Engine();
    }
}
