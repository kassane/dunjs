# Build & Test DunJS

## Prerequisites

| Tool | Required | Purpose |
|------|----------|---------|
| LDC >= 1.42.0 | Yes | D compiler (preferred) |
| DMD >= 2.112.1 | Alt | D compiler (alternative) |
| GCC/Clang | Yes | C compiler for QuickJS |
| CMake | QuickJS | Build system for QuickJS-NG |
| pkg-config | JSC/Linux | Find libjavascriptcoregtk |
| libjavascriptcoregtk-4.1-dev | JSC/Linux | JavaScriptCore headers + lib |

## Build Steps

### 1. Vendor Dependencies

```sh
# QuickJS-NG (downloads + CMake build)
ldc2 -run build.d --backend=quickjs --verbose

# JSC (Linux: needs system libjavascriptcoregtk-4.1-dev, macOS: system framework)
ldc2 -run build.d --backend=jsc --verbose

# V8 (compiles v8shim.cpp against vendored Node.js headers)
ldc2 -run build.d --backend=v8 --verbose
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
# Unit tests (engine + TypeScript + security)
dub test -c unittest

# Integration tests (requires built binary)
dub build -c quickjs
for f in tests/integration/fixtures/*.js; do
    name=$(basename "$f" .js)
    expected="tests/integration/expected/${name}.txt"
    [ -f "$expected" ] && diff <(./build/dun run "$f" 2>&1) "$expected" && echo "PASS $name" || echo "FAIL $name"
done
```

## CI Pipeline

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs:
1. **Build matrix**: QuickJS (Linux/macOS/Windows), JSC (Linux/macOS), V8 (Linux compile-check)
2. **Unit tests**: `dub test -c unittest` on all platforms
3. **Integration tests**: Run 14 fixtures against expected output

## DUB Configurations

| Config | Version Flag | Vendor Deps | Link Flags |
|--------|-------------|-------------|------------|
| `quickjs` | `EngineQuickJS` | CMake-built libqjs.a | `-lqjs`, `-lm`, `-ldl` |
| `jsc` | `EngineJSC` | System library | `-ljavascriptcoregtk-4.1` or `-framework JavaScriptCore` |
| `v8` | `EngineV8` | v8shim.cpp compiled | `-lv8`, `-lv8_libplatform` |
| `unittest` | `EngineQuickJS` + `DunTest` | Same as quickjs | Same as quickjs |

## Troubleshooting

- **"cannot find -lquickjs"**: Run `ldc2 -run build.d --backend=quickjs` first
- **"cannot find -lv8"**: Expected on CI -- V8 compile-check only verifies D compilation
- **JSC link errors on Linux**: Install `libjavascriptcoregtk-4.1-dev`
- **Windows MSVC errors**: Ensure `ilammy/msvc-dev-cmd` or VS Developer prompt is active
