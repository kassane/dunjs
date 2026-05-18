/// Project-wide named constants. Add an entry here when a value is
/// shared across two+ modules, or when it'd otherwise be a magic
/// number at the call site (sentinels, ABI versions, buffer caps).
module dun.declarations;

private size_t MiB(size_t n) @safe pure nothrow @nogc { return n * 1024 * 1024; }

// ─── Engine limits ──────────────────────────────────────────────

enum DEFAULT_MEMORY_LIMIT = MiB(2048);
enum DEFAULT_MAX_STACK    = MiB(8);
enum TEST_MEMORY_LIMIT    = MiB(64);
enum TEST_MAX_STACK       = MiB(4);

/// Argv slots reserved on the call stack before falling back to a
/// GC-allocated array. Same value used by every backend trampoline,
/// the FFI dispatcher, and NAPI helpers.
enum NATIVE_CALL_STACK_ARGS = 16;

// ─── N-API ABI ─────────────────────────────────────────────────

/// N-API version returned by `napi_get_version` (Node 22 = v9).
enum uint NAPI_VERSION = 9;

/// Node version triple returned by `napi_get_node_version` —
/// feature-detect addons that compare against `>= 22` get a hit.
enum uint NODE_VERSION_MAJOR = 22;
enum uint NODE_VERSION_MINOR = 0;
enum uint NODE_VERSION_PATCH = 0;

/// Non-null opaque returned by handle-scope / async-init stubs.
/// We don't model libuv resource scopes; the value is never read.
enum void* NAPI_ASYNC_SENTINEL = cast(void*) 1;

// ─── FFI / dlopen ───────────────────────────────────────────────

/// POSIX `dlopen(3)` flags. `NOW` resolves all symbols up-front so
/// a missing dep fails at `dlopen()`, not at first `dlsym()`.
enum int RTLD_LAZY = 1;
enum int RTLD_NOW  = 2;

/// Same shape as `NAPI_ASYNC_SENTINEL`, distinct name keeps grep
/// for "where does FFI return its sentinel" answerable.
enum void* FFI_NONNULL_SENTINEL = cast(void*) 1;
