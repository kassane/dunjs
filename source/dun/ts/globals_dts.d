/// Built-in ambient TypeScript declarations injected by --typecheck.
/// Mirrors the runtime globals registered by `dun.runtime.globals`:
/// Deno.* (30+ APIs), Bun.*, Node-style require / process / Buffer,
/// and the common web globals. Without this, `tsc --typecheck` flags
/// every reference to `Deno`, `Bun`, `require`, etc. as "Cannot find
/// name". The declarations are deliberately loose (`any` for the
/// open-ended object shapes) — DunJS exposes more surface than is
/// worth re-typing, and --typecheck's job is to catch *user* type
/// errors, not validate the runtime API.
module dun.ts.globals_dts;

/// Returns the synthetic .d.ts contents. Stored as a string so the
/// typecheck driver can inject it through the in-memory CompilerHost
/// without touching the filesystem.
string dunGlobalsDts() pure nothrow @safe
{
    return q"DTS
// Auto-injected by `dun run --typecheck`. NOT a real file on disk.
// Declarations are intentionally permissive (`any`-typed) so that
// user TS programs targeting Deno/Bun/Node-style globals typecheck
// without import boilerplate.

declare const Deno: {
    args: string[];
    env: {
        get(key: string): string | undefined;
        set(key: string, value: string): void;
        delete(key: string): void;
        toObject(): Record<string, string>;
        has(key: string): boolean;
    };
    pid: number;
    ppid: number;
    cwd(): string;
    chdir(path: string): void;
    exit(code?: number): never;
    hostname(): string;
    build: {
        os: "linux" | "darwin" | "windows" | string;
        arch: "x86_64" | "aarch64" | string;
        target: string;
        vendor?: string;
        env?: string;
    };
    version: { deno: string; v8: string; typescript: string };
    osRelease(): string;
    osUptime(): number;
    memoryUsage(): { rss: number; heapTotal: number; heapUsed: number; external: number };
    consoleSize(): { columns: number; rows: number };
    loadavg(): number[];
    networkInterfaces(): Array<any>;
    systemMemoryInfo(): any;
    permissions: {
        query(desc: any): Promise<{ state: "granted" | "denied" | "prompt" }>;
        request(desc: any): Promise<{ state: "granted" | "denied" }>;
        revoke(desc: any): Promise<{ state: "denied" }>;
    };
    errors: {
        NotFound: new (msg?: string) => Error;
        PermissionDenied: new (msg?: string) => Error;
        AlreadyExists: new (msg?: string) => Error;
        InvalidData: new (msg?: string) => Error;
        TimedOut: new (msg?: string) => Error;
        NotSupported: new (msg?: string) => Error;
        [k: string]: new (msg?: string) => Error;
    };
    readTextFileSync(path: string | URL): string;
    readTextFile(path: string | URL): Promise<string>;
    writeTextFileSync(path: string | URL, data: string): void;
    writeTextFile(path: string | URL, data: string): Promise<void>;
    readFileSync(path: string | URL): Uint8Array;
    readFile(path: string | URL): Promise<Uint8Array>;
    writeFileSync(path: string | URL, data: Uint8Array): void;
    writeFile(path: string | URL, data: Uint8Array): Promise<void>;
    statSync(path: string | URL): any;
    stat(path: string | URL): Promise<any>;
    lstatSync(path: string | URL): any;
    lstat(path: string | URL): Promise<any>;
    mkdirSync(path: string | URL, opts?: any): void;
    mkdir(path: string | URL, opts?: any): Promise<void>;
    removeSync(path: string | URL, opts?: any): void;
    remove(path: string | URL, opts?: any): Promise<void>;
    renameSync(oldp: string | URL, newp: string | URL): void;
    rename(oldp: string | URL, newp: string | URL): Promise<void>;
    copyFileSync(src: string | URL, dst: string | URL): void;
    copyFile(src: string | URL, dst: string | URL): Promise<void>;
    realPathSync(path: string | URL): string;
    realPath(path: string | URL): Promise<string>;
    readDirSync(path: string | URL): IterableIterator<{ name: string; isFile: boolean; isDirectory: boolean }>;
    readDir(path: string | URL): AsyncIterableIterator<{ name: string; isFile: boolean; isDirectory: boolean }>;
    truncateSync(path: string | URL, len?: number): void;
    truncate(path: string | URL, len?: number): Promise<void>;
    inspect(value: any, opts?: any): string;
    [k: string]: any;
};

declare const Bun: {
    version: string;
    revision: string;
    env: Record<string, string>;
    argv: string[];
    main: string;
    sleep(ms: number): Promise<void>;
    sleepSync(ms: number): void;
    write(dest: any, data: any): Promise<number>;
    file(path: string | URL, opts?: any): any;
    hash: {
        (data: any): bigint;
        wyhash(data: any): bigint;
        crc32(data: any): number;
        adler32(data: any): number;
        xxh32(data: any): number;
        xxh64(data: any): bigint;
        [k: string]: any;
    };
    nanoseconds(): number;
    spawnSync(...args: any[]): any;
    spawn(...args: any[]): any;
    inspect(value: any, opts?: any): string;
    [k: string]: any;
};

// Node-style CommonJS-ish globals (DunJS supports both ESM and CJS).
declare function require(id: string): any;
declare namespace NodeJS {
    interface ProcessEnv { [key: string]: string | undefined }
    interface Process {
        env: ProcessEnv;
        argv: string[];
        argv0: string;
        platform: string;
        arch: string;
        version: string;
        versions: Record<string, string>;
        pid: number;
        ppid: number;
        cwd(): string;
        chdir(dir: string): void;
        exit(code?: number): never;
        nextTick(fn: () => void, ...args: any[]): void;
        hrtime: ((time?: [number, number]) => [number, number]) & { bigint(): bigint };
        stdout: any;
        stderr: any;
        stdin: any;
        memoryUsage(): { rss: number; heapTotal: number; heapUsed: number; external: number };
        on(event: string, listener: (...args: any[]) => void): Process;
        off(event: string, listener: (...args: any[]) => void): Process;
        emit(event: string, ...args: any[]): boolean;
        kill(pid: number, signal?: string | number): void;
        [k: string]: any;
    }
}
declare const process: NodeJS.Process;

declare class Buffer extends Uint8Array {
    static from(input: any, enc?: string): Buffer;
    static alloc(size: number, fill?: any, enc?: string): Buffer;
    static allocUnsafe(size: number): Buffer;
    static concat(list: Buffer[], totalLength?: number): Buffer;
    static byteLength(s: any, enc?: string): number;
    static isBuffer(x: any): x is Buffer;
    toString(enc?: string, start?: number, end?: number): string;
    write(s: string, off?: number, len?: number, enc?: string): number;
    slice(start?: number, end?: number): Buffer;
    [k: string]: any;
}

declare const __dirname: string;
declare const __filename: string;
declare const global: typeof globalThis;
declare const exports: any;
declare const module: { exports: any; id: string; filename: string; loaded: boolean; parent: any };

// JSX support — `dun.ts.jsx` rewrites `<x/>` to React.createElement, so
// React has to be a value in scope (TS2874). Permissive `any`-typed
// shim matches the runtime shape DunJS injects automatically.
declare const React: {
    createElement(type: any, props?: any, ...children: any[]): any;
    Fragment: any;
    Children: any;
    cloneElement(el: any, props?: any, ...children: any[]): any;
    createContext(defaultValue: any): any;
    forwardRef(fn: any): any;
    isValidElement(x: any): boolean;
    memo(c: any, eq?: any): any;
    useState(init: any): [any, (v: any) => void];
    useEffect(fn: any, deps?: any[]): void;
    useLayoutEffect(fn: any, deps?: any[]): void;
    useRef(init?: any): { current: any };
    useMemo<T>(fn: () => T, deps?: any[]): T;
    useCallback<T>(fn: T, deps?: any[]): T;
    useContext(ctx: any): any;
    useReducer(reducer: any, init: any): [any, (a: any) => void];
    [k: string]: any;
};
declare namespace JSX {
    interface Element { type: any; props: any; children: any[]; key?: any }
    interface IntrinsicElements { [k: string]: any }
    interface ElementAttributesProperty { props: any }
    interface ElementChildrenAttribute { children: any }
}

// dun:* synthetic modules (the require()/import targets DunJS ships).
declare module "dun:fs" { const x: any; export = x; }
declare module "dun:path" { const x: any; export = x; }
declare module "dun:crypto" { const x: any; export = x; }
declare module "dun:net" { const x: any; export = x; }
declare module "dun:http" { const x: any; export = x; }
declare module "dun:http2" { const x: any; export = x; }
declare module "dun:http3" { const x: any; export = x; }
declare module "dun:os" { const x: any; export = x; }
declare module "dun:buffer" { const x: any; export = x; }
declare module "dun:events" { const x: any; export = x; }
declare module "dun:url" { const x: any; export = x; }
declare module "dun:stream" { const x: any; export = x; }
declare module "dun:zlib" { const x: any; export = x; }
declare module "dun:dns" { const x: any; export = x; }
declare module "dun:ws" { const x: any; export = x; }
declare module "dun:sqlite" { const x: any; export = x; }
declare module "dun:util" { const x: any; export = x; }
declare module "dun:assert" { const x: any; export = x; }
declare module "dun:querystring" { const x: any; export = x; }
declare module "dun:string_decoder" { const x: any; export = x; }
declare module "dun:timers/promises" { const x: any; export = x; }
declare module "dun:vm" { const x: any; export = x; }
declare module "dun:cluster" { const x: any; export = x; }
declare module "dun:async_hooks" { const x: any; export = x; }
declare module "dun:worker_threads" { const x: any; export = x; }
declare module "dun:https" { const x: any; export = x; }
declare module "dun:fs/promises" { const x: any; export = x; }
declare module "dun:readline" { const x: any; export = x; }
declare module "dun:tls" { const x: any; export = x; }
declare module "dun:dgram" { const x: any; export = x; }
declare module "dun:perf_hooks" { const x: any; export = x; }
declare module "dun:wasi" { const x: any; export = x; }
declare module "dun:child_process" { const x: any; export = x; }

// node:* alias surface (same handlers; declared so `import * from "node:fs"` typechecks).
declare module "node:fs" { const x: any; export = x; }
declare module "node:path" { const x: any; export = x; }
declare module "node:crypto" { const x: any; export = x; }
declare module "node:net" { const x: any; export = x; }
declare module "node:http" { const x: any; export = x; }
declare module "node:http2" { const x: any; export = x; }
declare module "node:os" { const x: any; export = x; }
declare module "node:buffer" { const x: any; export = x; }
declare module "node:events" { const x: any; export = x; }
declare module "node:url" { const x: any; export = x; }
declare module "node:stream" { const x: any; export = x; }
declare module "node:zlib" { const x: any; export = x; }
declare module "node:dns" { const x: any; export = x; }
declare module "node:util" { const x: any; export = x; }
declare module "node:assert" { const x: any; export = x; }
declare module "node:vm" { const x: any; export = x; }
declare module "node:cluster" { const x: any; export = x; }
declare module "node:async_hooks" { const x: any; export = x; }
declare module "node:worker_threads" { const x: any; export = x; }
declare module "node:https" { const x: any; export = x; }
declare module "node:fs/promises" { const x: any; export = x; }
declare module "node:readline" { const x: any; export = x; }
declare module "node:tls" { const x: any; export = x; }
declare module "node:dgram" { const x: any; export = x; }
declare module "node:perf_hooks" { const x: any; export = x; }
declare module "node:wasi" { const x: any; export = x; }
declare module "node:child_process" { const x: any; export = x; }
declare module "node:timers/promises" { const x: any; export = x; }

// Bare-name aliases for Node's "magic" specifiers (no `node:` prefix).
// Bun and Node both resolve `import "fs"` -> the node:fs builtin, so
// scripts targeting either runtime omit the prefix all the time.
declare module "fs" { const x: any; export = x; }
declare module "path" { const x: any; export = x; }
declare module "crypto" { const x: any; export = x; }
declare module "net" { const x: any; export = x; }
declare module "http" { const x: any; export = x; }
declare module "http2" { const x: any; export = x; }
declare module "os" { const x: any; export = x; }
declare module "buffer" { const x: any; export = x; }
declare module "events" { const x: any; export = x; }
declare module "url" { const x: any; export = x; }
declare module "stream" { const x: any; export = x; }
declare module "zlib" { const x: any; export = x; }
declare module "dns" { const x: any; export = x; }
declare module "util" { const x: any; export = x; }
declare module "assert" { const x: any; export = x; }
declare module "vm" { const x: any; export = x; }
declare module "cluster" { const x: any; export = x; }
declare module "async_hooks" { const x: any; export = x; }
declare module "worker_threads" { const x: any; export = x; }
declare module "https" { const x: any; export = x; }
declare module "fs/promises" { const x: any; export = x; }
declare module "readline" { const x: any; export = x; }
declare module "tls" { const x: any; export = x; }
declare module "dgram" { const x: any; export = x; }
declare module "perf_hooks" { const x: any; export = x; }
declare module "wasi" { const x: any; export = x; }
declare module "child_process" { const x: any; export = x; }
declare module "timers/promises" { const x: any; export = x; }
DTS";
}

unittest
{
    // Sanity-check that the .d.ts blob has the expected shape. The
    // actual size shifts as we add declarations; the floor below is
    // 1 KB (anything smaller means the heredoc lost most of its body).
    enum size_t MIN_DTS_SIZE = 1024;
    auto dts = dunGlobalsDts();
    assert(dts.length > MIN_DTS_SIZE, "dts should be non-trivial");
    import std.algorithm : canFind;
    // Cover the main names referenced by ts_compat fixtures.
    assert(canFind(dts, "declare const Deno:"));
    assert(canFind(dts, "declare const Bun:"));
    assert(canFind(dts, "declare function require"));
    assert(canFind(dts, "declare class Buffer"));
    assert(canFind(dts, `"dun:fs"`));
    assert(canFind(dts, `"node:fs"`));
}
