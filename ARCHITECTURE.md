# DunJS Architecture

## Overview

DunJS is a 7-layer JavaScript runtime with a **pluggable engine architecture**
(IJSEngine interface), an eventcore-based event loop, and a Deno-inspired permission system.

Reference: [Bun's Zig→Rust port](https://github.com/oven-sh/bun/pull/30412) — modular
workspace with `bun_jsc` engine layer, `*_jsc` suffix pattern for engine-specific modules,
RAII wrappers, and pointer safety auditing.

## System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    JavaScript User Code                       │
│              (ES2023+ modules, async/await, etc.)             │
├──────────────────────────────────────────────────────────────┤
│  Layer 7: CLI & REPL                                         │
│  ┌─────────┐ ┌──────┐ ┌──────┐ ┌─────────┐                  │
│  │  args   │ │ repl │ │ run  │ │   fmt   │                  │
│  └─────────┘ └──────┘ └──────┘ └─────────┘                  │
├──────────────────────────────────────────────────────────────┤
│  Layer 6: Runtime API (Globals)                              │
│  ┌─────────┐ ┌────────────┐ ┌─────────┐ ┌──────────┐       │
│  │ console │ │ timers_api │ │ process │ │ encoding │       │
│  └─────────┘ └────────────┘ └─────────┘ └──────────┘       │
├──────────────────────────────────────────────────────────────┤
│  Layer 5: Module System                                      │
│  ┌──────────┐ ┌────────┐ ┌─────┐ ┌──────────┐              │
│  │ resolver │ │ loader │ │ esm │ │ builtins │              │
│  └──────────┘ └────────┘ └─────┘ └──────────┘              │
├──────────────────────────────────────────────────────────────┤
│  Layer 4: Built-in Modules                                   │
│  ┌────┐ ┌──────┐ ┌─────┐ ┌──────┐ ┌────────┐ ┌─────┐      │
│  │ fs │ │ path │ │ net │ │ http │ │ crypto │ │ url │      │
│  └────┘ └──────┘ └─────┘ └──────┘ └────────┘ └─────┘      │
├──────────────────────────────────────────────────────────────┤
│  Security: Permission System (cross-cutting)                 │
│  ┌─────────────┐ ┌─────────┐ ┌────────┐                     │
│  │ permissions │ │ sandbox │ │ policy │                     │
│  └─────────────┘ └─────────┘ └────────┘                     │
├──────────────────────────────────────────────────────────────┤
│  Layer 3: Event Loop & Async Runtime                         │
│  ┌───────────┐ ┌────────┐ ┌────────────┐ ┌───────┐         │
│  │ eventloop │ │ timers │ │ microtasks │ │ tasks │         │
│  └───────────┘ └────────┘ └────────────┘ └───────┘         │
├──────────────────────────────────────────────────────────────┤
│  Layer 2: JS Engine Abstraction                              │
│  ┌───────────────────────────────────────────────┐           │
│  │  IJSEngine (iface.d)                          │           │
│  │  ┌──────────────┬──────────────┬──────────┐    │           │
│  │  │ quickjs/     │  jsc/        │  v8/     │    │           │
│  │  │ backend.d    │ backend.d    │ backend.d│    │           │
│  │  │ bindings.d   │ bindings.d   │ bindings.d    │           │
│  │  │ cimport.c    │ cppbindings.d│ cppbindings.d │           │
│  │  │ runtime.d    │              │          │    │           │
│  │  │ context.d    │              │ v8shim/  │    │           │
│  │  │ value.d      │              │ (C++ shim)    │           │
│  │  └──────────────┴──────────────┴──────────┘    │           │
│  └───────────────────────────────────────────────┘           │
├──────────────────────────────────────────────────────────────┤
│  Layer 1: Platform Abstraction                               │
│  ┌────────┐ ┌───────────┐ ┌────┐ ┌───────┐                  │
│  │ memory │ │ threading │ │ io │ │ paths │                  │
│  └────────┘ └───────────┘ └────┘ └───────┘                  │
├──────────────────────────────────────────────────────────────┤
│  Vendor: Engine (C/C++) │ eventcore (D) │ OS (POSIX/Win32)  │
└──────────────────────────────────────────────────────────────┘
```

## Engine Abstraction Pattern

```
  Upper Layers (app, runtime, builtins, loop)
            │
            ▼
  ┌─────────────────────┐
  │   IJSEngine          │  interface in iface.d
  │   - eval()           │
  │   - newString()      │
  │   - getProperty()    │
  │   - drainJobs()      │
  │   - ...              │
  └──────────┬──────────┘
             │ implements
    ┌────────┼────────┐
    ▼        ▼        ▼
 QuickJS    JSC      V8
 Engine   Engine   Engine
```

`createEngine()` factory returns the selected backend (compile-time via
`version(EngineQuickJS)`, `version(EngineJSC)`, `version(EngineV8)`).
Backends live in `source/dun/engine/<name>/` and only they import
engine-specific C/C++ bindings.

## Data Flow: Script Execution

```
CLI (args.d) ──parse──> CliConfig
                              │
                    ┌─────────▼──────────┐
                    │ createEngine()      │  IJSEngine factory
                    │ engine.initialize() │  EngineConfig
                    │ installGlobals()    │  console, timers, process
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │ engine.eval(source) │  Evaluates JS source
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │ engine.drainJobs()  │  Promise microtasks
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │ engine.shutdown()   │  Cleanup
                    └────────────────────┘
```

## Memory Management Bridge

```
┌─────────────────────┐        ┌─────────────────────┐
│   D World (GC)      │        │  Engine World (C)    │
│                     │        │                     │
│  IJSEngine    ──────┼─call──>│  Engine C API        │
│  JSHandle     ──────┼─map───>│  JSValue / JSObjectRef│
│  DunState*    <─────┼─opaque─│  Context opaque      │
│  GC.addRoot() ──────┼─pin───>│  Engine class opaque │
│  @trusted block ────┼─call──>│  eval, call          │
│                     │        │                     │
└─────────────────────┘        └─────────────────────┘
```

### Rules

1. Every value returned by the engine **MUST** be freed via RAII or explicit `freeValue()`
2. D objects stored as engine opaques **MUST** be pinned with `GC.addRoot`
3. `extern(C)` callbacks **MUST** be `nothrow`
4. Custom allocator enforces memory limits
5. `dupValue()` must be called when storing a handle beyond its original scope

## Permission Enforcement Flow

```
JS code calls:  import { readFileSync } from "dun:fs";
                readFileSync("/etc/passwd")
                        │
                        ▼
               extern(C) jsReadFileSync(ctx, ...)
                        │
                        ▼
               DunState* state = getContextOpaque()
                        │
                        ▼
               state.permissions.check(Permission.read, "/etc/passwd")
                        │
                ┌───────┴───────┐
                │               │
              DENIED          GRANTED
                │               │
                ▼               ▼
        throwTypeError()    std.file.read("/etc/passwd")
        "Requires           return newString(content)
         --allow-read"
```

## Key Type Signatures

### DunState (Central runtime state)

```d
struct DunState {
    IJSEngine engine;
    EventLoop eventLoop;
    PermissionRegistry* permissions;
    string[] scriptArgs;
    bool verbose;
}
```

### IJSEngine Interface (abbreviated)

```d
interface IJSEngine {
    void initialize(EngineConfig config);
    void shutdown();
    JSResult eval(const(char)[] source, string filename);
    JSHandle newString(const(char)[] s);
    JSHandle getGlobal();
    void setProperty(JSHandle obj, const(char)[] name, JSHandle val);
    string getException();
    void drainJobs();
    void* rawContext();   // Escape hatch for backend-specific code
}
```

## Comparison with Other Runtimes

| Aspect | Node.js | Deno | Bun | **DunJS** |
|--------|---------|------|-----|-----------|
| Language | C++ | Rust | Zig→Rust | **D** |
| JS Engine | V8 | V8 | JSC | **Pluggable (QuickJS, JSC, V8)** |
| Event Loop | libuv | Tokio | io_uring | **eventcore** |
| Permission | None | Deny-all | None | **Deny-all** |
| Module Prefix | `node:` | `node:` | `bun:` | **`dun:`** |
| Memory Safety | Manual | Borrow checker | Manual | **@safe/@trusted** |

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| JS Engine | Pluggable (IJSEngine) | Swap backends without rewriting upper layers |
| Default backend | QuickJS-NG | Pure C API, ES2023, easy extern(C), MIT license |
| Target backend | JSC or V8 | Tier 1 JIT performance for production use |
| C FFI | ImportC + extern(C) | Auditable bindings, no external tooling |
| C++ FFI | extern(C++) + C shim | For V8 (templates require C shim), JSC C++ internals |
| Event loop | eventcore | D-native, proactor pattern, cross-platform |
| Build system | DUB (JSON) | Standard D tooling, configurations per engine |
| Build orchestrator | build.d | CMake, toolchain detection, findProgram pattern |
| Async model | Callback loop + Promise jobs | Matches engine internal async handling |
| Permission | Default deny-all | Security-first, Deno's proven model |
| RAII wrappers | D structs with `~this()` | Deterministic cleanup, zero-cost |
| Engine selection | `dub build -c quickjs/jsc/v8` | DUB configurations switch backends |
