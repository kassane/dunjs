// Dynamic `import("specifier")` works on all three backends.
// JSC and V8 don't wire HostImportModuleDynamicallyCallback, so
// DunJS rewrites the call site to `__dunImport__(...)` which wraps
// `require(...)` in a Promise.

const fs = await import("fs");
console.log("fs.mkdirSync:", typeof fs.mkdirSync);

// Destructure form -- compiler emits the same await-call shape.
const { statSync } = await import("fs");
console.log("statSync:", typeof statSync);

// Variable-specifier form.
const name = "path";
const path = await import(name);
console.log("path.join:", typeof path.join);

// Sequential awaits.
const [util, os] = await Promise.all([
    import("util"),
    import("os"),
]);
console.log("util.format:", typeof util.format);
console.log("os.platform:", typeof os.platform);

// `import.meta` (static) must NOT be touched by the rewriter.
console.log("import.meta.url:", typeof import.meta.url === "string");
