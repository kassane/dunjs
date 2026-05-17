// Explicit-resource-management `using` declarations (ES2026).
// V8 14+ supports natively; QJS / JSC don't, so strip.d rewrites
// `using x = ...` to `const x = ...` + a synthetic try / finally
// pair around the rest of the enclosing block that calls
// `Symbol.dispose` deterministically -- regardless of how the
// scope exits.

function makeRes(label: string) {
    return {
        label,
        [Symbol.dispose]() { console.log("dispose:", this.label); },
    };
}

// (1) Normal scope exit -- LIFO dispose order.
function basic() {
    using a = makeRes("a");
    using b = makeRes("b");
    console.log("basic body");
}
basic();

// (2) Throw inside the scope -- dispose still fires.
function throwInside() {
    try {
        using r = makeRes("throw-1");
        throw new Error("boom");
    } catch (e: any) {
        console.log("caught:", e.message);
    }
}
throwInside();

// (3) Throw that propagates out of the using scope.
function propagate() {
    using r = makeRes("propagate-1");
    throw new Error("up");
}
try { propagate(); } catch (e: any) { console.log("outer:", e.message); }

// (4) Nested blocks -- inner dispose fires before outer.
function nested() {
    using outer = makeRes("outer");
    {
        using inner = makeRes("inner");
        console.log("inner block");
    }
    console.log("outer body after inner block");
}
nested();

// (5) No trailing semicolon (ASI) -- `using x = {...}` still parses
// because strip leads the synthetic `try{` with a `;`.
function noSemi() {
    using r = makeRes("no-semi")
    console.log("no-semi body")
}
noSemi()
