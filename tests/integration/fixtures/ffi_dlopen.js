// Deno.dlopen — minimal native FFI against libc.
// Supports a curated set of common signatures (no libffi yet).
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

ok("Deno.dlopen defined", typeof Deno.dlopen === "function");
ok("Deno.UnsafePointer defined", typeof Deno.UnsafePointer === "function");

try {
  const lib = Deno.dlopen("libc.so.6", {
    atoi:  { parameters: ["cstring"], result: "i32" },
    abs:   { parameters: ["i32"], result: "i32" },
    strlen:{ parameters: ["cstring"], result: "i32" },
  });

  ok("symbols object", typeof lib.symbols === "object");
  ok("close() defined", typeof lib.close === "function");
  ok("atoi('42') === 42", lib.symbols.atoi("42") === 42);
  ok("atoi('123abc') === 123", lib.symbols.atoi("123abc") === 123);
  ok("atoi('not a num') === 0", lib.symbols.atoi("not a num") === 0);
  ok("abs(-100) === 100", lib.symbols.abs(-100) === 100);
  ok("abs(42) === 42", lib.symbols.abs(42) === 42);
  ok("strlen('') === 0", lib.symbols.strlen("") === 0);
  ok("strlen('abc') === 3", lib.symbols.strlen("abc") === 3);
  ok("strlen('hello world') === 11", lib.symbols.strlen("hello world") === 11);

  lib.close();
  ok("close() succeeds", true);
} catch (e) {
  fail++;
  console.log("CRASH", e && e.message);
}

// Unsupported signatures should throw a clear error.
try {
  Deno.dlopen("libc.so.6", {
    // f128 isn't supported anywhere — should throw "unsupported signature".
    bad: { parameters: ["f128"], result: "f128" },
  });
  fail++;
  console.log("FAIL: should have thrown on f128");
} catch (e) {
  ok("rejects unsupported signature", true);
}

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
