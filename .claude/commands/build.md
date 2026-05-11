# Build & Test DunJS

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| LDC >= 1.42.0 | Yes | D compiler (preferred) |
| DMD >= 2.112.1 | Alt | D compiler (alternative) |
| GDC >= GCC 15 | Alt | D compiler (alternative) |
| GCC/Clang | Yes | C compiler for QuickJS |
| CMake | QuickJS | Build system for QuickJS-NG |
| pkg-config | JSC/Linux | Find libjavascriptcoregtk |
| libjavascriptcoregtk-4.1-dev | JSC/Linux | JavaScriptCore headers + lib |
| OpenSSL (libssl, libcrypto) | TLS/fetch | HTTPS support |

## Build Steps

### 1. Vendor Dependencies

```sh
# QuickJS-NG (downloads + CMake build)
ldc2 -run build.d --backend=quickjs --verbose

# JSC (Linux: needs system libjavascriptcoregtk-4.1-dev, macOS: system framework)
ldc2 -run build.d --backend=jsc --verbose

# V8 (compiles v8shim.cpp against vendored Node.js headers)
ldc2 -run build.d --backend=v8 --verbose

# Force rebuild (clears cached artifacts)
ldc2 -run build.d --backend=quickjs --verbose --force
```

### 2. Build

```sh
dub build -c quickjs              # QuickJS debug
dub build -c jsc                  # JSC debug
dub build -c v8                   # V8 debug (link fails without system libv8)
dub build -c quickjs -b release   # QuickJS release (optimized + stripped)
```

### 3. Test

```sh
# Unit tests (engine contract ~50, fuzz ~50, TypeScript 20, security 27)
dub test -c unittest

# Integration tests (44 fixtures, requires built binary)
dub build -c quickjs
./tests/integration/run.sh

# Integration tests for other backends
dub build -c jsc && BACKEND=jsc ./tests/integration/run.sh
dub build -c v8  && BACKEND=v8  ./tests/integration/run.sh
```

Backend test scores: QuickJS 44/44, JSC 43/43+1skip, V8 43/43+1skip (workers QuickJS-only).

## CI Pipeline

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs:
1. **Build matrix**: QuickJS (Linux/macOS/Windows), JSC (Linux/macOS), V8 (Linux compile-check)
2. **Unit tests**: `dub test -c unittest` on Linux/macOS/Windows
3. **Integration tests**: Run 44 fixtures against expected output on Linux/macOS/Windows

## DUB Configurations

| Config | Version Flag | Vendor Deps | Link Flags |
|--------|-------------|-------------|------------|
| `quickjs` | `EngineQuickJS` | CMake-built libqjs.a | `-lqjs`, `-lm`, `-ldl` |
| `jsc` | `EngineJSC` | System library | `-ljavascriptcoregtk-4.1` or `-framework JavaScriptCore` |
| `v8` | `EngineV8` | v8shim.cpp compiled | `-lv8`, `-lv8_libplatform` |
| `unittest` | `EngineQuickJS` + `DunTest` | Same as quickjs | Same as quickjs |

## Troubleshooting

- **"cannot find -lqjs"**: Run `ldc2 -run build.d --backend=quickjs` first
- **"cannot find -lv8"**: Expected on CI -- V8 compile-check only verifies D compilation
- **JSC link errors on Linux**: Install `libjavascriptcoregtk-4.1-dev`
- **Windows MSVC errors**: Ensure `ilammy/msvc-dev-cmd` or VS Developer prompt is active
- **Windows __imp_fesetround**: QuickJS CRT mismatch -- build.d forces `/MT` via CMake flags
- **OpenSSL not found (macOS)**: Install via `brew install openssl`, paths auto-detected
- **segfault debugging**: Use `gdb ./build/dun` with `run script.js`, check backtrace
