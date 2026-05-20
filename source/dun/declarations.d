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

// ─── UTF-8 / Unicode ────────────────────────────────────────────
//
// Shared between the SIMD latin1 encoder (`dun.platform.simd.latin1ToUtf8Buf`)
// and the JSC backend UTF-8 → UTF-16 decoder (`dun.engine.jsc.backend.newString`
// slow path). Centralized here so the lead-byte / continuation / surrogate
// constants aren't duplicated across two modules — historically that's
// where "fixed UTF-8 here but not there" bugs come from.

enum uint UTF8_ASCII_MAX        = 0x7Fu;     /// last 1-byte code point
enum uint UTF8_CONT_BASE        = 0x80u;     /// 10xxxxxx continuation
enum uint UTF8_CONT_MASK        = 0x3Fu;     /// payload bits in continuation
enum uint UTF8_2BYTE_LEAD       = 0xC0u;     /// 110xxxxx start of 2-byte
enum uint UTF8_3BYTE_LEAD       = 0xE0u;     /// 1110xxxx start of 3-byte
enum uint UTF8_4BYTE_LEAD       = 0xF0u;     /// 11110xxx start of 4-byte
enum uint UTF8_2BYTE_MASK       = 0x1Fu;     /// payload bits in 2-byte lead
enum uint UTF8_3BYTE_MASK       = 0x0Fu;     ///   ... 3-byte lead
enum uint UTF8_4BYTE_MASK       = 0x07u;     ///   ... 4-byte lead

enum uint UNICODE_BMP_MAX       = 0x10000u;  /// first non-BMP (astral) code point
enum uint UNICODE_REPLACEMENT_CHAR = 0xFFFDu;/// U+FFFD for malformed input
enum uint UTF16_HIGH_SURROGATE_BASE = 0xD800u; /// U+D800 start of high half
enum uint UTF16_LOW_SURROGATE_BASE  = 0xDC00u; /// U+DC00 start of low half
enum uint UTF16_SURROGATE_LOW_MASK  = 0x3FFu;  /// low 10 bits in surrogate
