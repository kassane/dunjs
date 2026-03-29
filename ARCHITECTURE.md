# DunJS Architecture

## Overview

DunJS is a 7-layer JavaScript runtime that embeds QuickJS-NG (C) into a D host
application, with an eventcore-based event loop and a Deno-inspired permission system.

## System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    JavaScript User Code                       │
│              (ES2023 modules, async/await, etc.)              │
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
│  Layer 2: JS Engine Bindings (QuickJS-NG)                    │
│  ┌──────────┐ ┌─────────┐ ┌─────────┐ ┌───────┐            │
│  │ bindings │ │ runtime │ │ context │ │ value │            │
│  └──────────┘ └─────────┘ └─────────┘ └───────┘            │
├──────────────────────────────────────────────────────────────┤
│  Layer 1: Platform Abstraction                               │
│  ┌────────┐ ┌───────────┐ ┌────┐ ┌───────┐                  │
│  │ memory │ │ threading │ │ io │ │ paths │                  │
│  └────────┘ └───────────┘ └────┘ └───────┘                  │
├──────────────────────────────────────────────────────────────┤
│  Vendor: QuickJS-NG (C) │ eventcore (D) │ OS (POSIX/Win32) │
└──────────────────────────────────────────────────────────────┘
```

## Data Flow: Script Execution

```
CLI (args.d) ──parse──> CliConfig
                              │
                    ┌─────────▼──────────┐
                    │ Runtime.create()    │  JS_NewRuntime()
                    │ Context.create(rt)  │  JS_NewContext()
                    │ installGlobals(ctx) │  console, timers, process
                    │ eventLoop.init(rt)  │  eventcore + timer wheel
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │ ctx.eval(source)    │  JS_Eval() with file contents
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │ eventLoop.run()     │  Loop until no more work
                    │  ├─ drainJobs()     │  Promise microtasks
                    │  ├─ processTimers() │  setTimeout/setInterval
                    │  ├─ pollIO()        │  eventcore.processEvents
                    │  └─ drainJobs()     │  Post-I/O microtasks
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │ Context.~this()     │  JS_FreeContext()
                    │ Runtime.~this()     │  JS_FreeRuntime()
                    └────────────────────┘
```

## Memory Management Bridge

```
┌─────────────────────┐        ┌─────────────────────┐
│   D World (GC)      │        │  C World (malloc)    │
│                     │        │                     │
│  JSVal (RAII)  ─────┼─free──>│  JSValue (refcount) │
│  DunState*     <────┼─opaque─│  JSContext opaque    │
│  GC.addRoot()  ─────┼─pin───>│  JS class opaque    │
│  @trusted block ────┼─call──>│  JS_Eval, JS_Call   │
│                     │        │                     │
│  Phobos std.file ───┼─result>│  (not visible)      │
│                     │        │                     │
└─────────────────────┘        └─────────────────────┘
```

### Rules

1. Every `JSValue` returned by QuickJS **MUST** be freed via `JSVal` RAII or explicit `JS_FreeValue`
2. D objects stored as QuickJS opaques **MUST** be pinned with `GC.addRoot`
3. `extern(C)` callbacks **MUST** be `nothrow` (C cannot handle D exceptions)
4. Custom allocator (`JS_NewRuntime2`) enforces memory limits
5. `JS_DupValue` must be called when storing a `JSValue` beyond its original scope
6. `JS_FreeCString` must be called after every `JS_ToCStringLen2`

## Permission Enforcement Flow

```
JS code calls:  import { readFileSync } from "dun:fs";
                readFileSync("/etc/passwd")
                        │
                        ▼
               extern(C) jsReadFileSync(ctx, ...)
                        │
                        ▼
               DunState* state = JS_GetContextOpaque(ctx)
                        │
                        ▼
               state.permissions.check(Permission.read, "/etc/passwd")
                        │
                ┌───────┴───────┐
                │               │
              DENIED          GRANTED
                │               │
                ▼               ▼
        JS_ThrowTypeError   std.file.read("/etc/passwd")
        "Requires           return JS_NewString(ctx, content)
         --allow-read"
```

## Event Loop Phases

Each `tick()` of the event loop executes these phases in order:

```
┌──────────────────────────────────────────────────┐
│                 One tick()                         │
│                                                   │
│  Phase 1: Drain microtask queue                  │
│    - QuickJS pending jobs (Promise .then())      │
│    - queueMicrotask() callbacks                  │
│                     │                             │
│                     ▼                             │
│  Phase 2: Process expired timers                 │
│    - Fire setTimeout callbacks (deadline <= now)  │
│    - Re-queue setInterval callbacks              │
│                     │                             │
│                     ▼                             │
│  Phase 3: Drain microtasks from Phase 2          │
│                     │                             │
│                     ▼                             │
│  Phase 4: Poll I/O (eventcore)                   │
│    - Block until I/O ready or next timer         │
│    - Fire socket/file/signal callbacks           │
│                     │                             │
│                     ▼                             │
│  Phase 5: Drain microtasks from Phase 4          │
│                                                   │
│  hasWork() ? ──yes──> loop back to Phase 1       │
│              ──no───> exit                        │
└──────────────────────────────────────────────────┘
```

## Key Type Signatures

### DunState (Central runtime state)

```d
struct DunState {
    EventLoop* eventLoop;
    PermissionRegistry* permissions;
    ModuleLoader* moduleLoader;
    string[] scriptArgs;
    bool verbose;
}
```

### extern(C) Native Function Pattern

```d
extern(C) JSValue nativeFunc(
    JSContext* ctx,
    JSValueConst this_val,
    int argc,
    JSValueConst* argv
) nothrow {
    // 1. Validate argc
    // 2. Extract arguments
    // 3. Get DunState* from context opaque
    // 4. Check permissions
    // 5. Perform operation
    // 6. Return JSValue
}
```

### Async Native Function Pattern

```d
extern(C) JSValue nativeAsyncFunc(
    JSContext* ctx,
    JSValueConst this_val,
    int argc,
    JSValueConst* argv
) nothrow {
    // 1. Create promise: JS_NewPromiseCapability(ctx, resolving_funcs)
    // 2. Submit work to event loop / thread pool
    // 3. On completion: call resolving_funcs[0] (resolve) or [1] (reject)
    // 4. Return the promise
}
```

## Comparison with Other Runtimes

| Aspect | Node.js | Deno | Bun | **DunJS** |
|--------|---------|------|-----|-----------|
| Language | C++ | Rust | Zig | **D** |
| JS Engine | V8 | V8 | JSC | **QuickJS-NG** |
| Event Loop | libuv | Tokio | io_uring | **eventcore** |
| Permission | None | Deny-all | None | **Deny-all** |
| Module Prefix | `node:` | `node:` | `bun:` | **`dun:`** |
| Memory Safety | Manual | Borrow checker | Manual | **@safe/@trusted** |
| Binary Size | ~50MB | ~100MB | ~60MB | **Target: <5MB** |
| Startup | 60-120ms | 40-60ms | 8-15ms | **Target: <10ms** |

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| JS Engine | QuickJS-NG | Pure C API for trivial `extern(C)` FFI, ES2023, small binary, MIT |
| Event loop | eventcore | D-native, proactor pattern, cross-platform (epoll/kqueue/IOCP) |
| Build system | DUB (SDL) | Standard D tooling, SDL format more readable than JSON |
| QuickJS integration | Git submodule + preBuildCommands | Reproducible builds, no system dependency |
| Async model | Callback-based loop + QuickJS Promise jobs | Matches QuickJS internal async handling |
| Module prefix | `dun:` | Distinct from `node:`/`bun:`, avoids confusion |
| Permission default | Deny all | Security-first, following Deno's proven model |
| RAII wrappers | D structs with `~this()` | Deterministic cleanup, zero-cost abstraction |
| No dstep | Manual bindings | QuickJS uses macros/inline functions dstep can't translate |
