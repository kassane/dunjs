// Test console methods (inspired by Node test-console.js / Deno console_test.ts)
// stdout: log, info, debug
// stderr: warn, error (merged via 2>&1 in test runner)
console.log("log message");
console.info("info message");
console.debug("debug message");
console.log("multiple", "args", 42, true);
console.log("types:", null, undefined, NaN, Infinity);
console.log("empty call follows");
console.log();
console.log("nested", { a: 1 }, [1, 2, 3]);
