// Error handling tests (inspired by Node test-error*.js / Deno error_test.ts)

// try/catch basic
try {
    throw new Error("test error");
} catch (e) {
    console.log(e.message);
    console.log(e instanceof Error);
}

// TypeError
try {
    null.property;
} catch (e) {
    console.log(e instanceof TypeError);
}

// RangeError
try {
    new Array(-1);
} catch (e) {
    console.log(e instanceof RangeError);
}

// Error.cause (ES2022)
try {
    try {
        throw new Error("original");
    } catch (inner) {
        throw new Error("wrapper", { cause: inner });
    }
} catch (e) {
    console.log(e.message);
    console.log(e.cause.message);
}

// finally always runs
try {
    throw new Error("boom");
} catch (e) {
    console.log("caught");
} finally {
    console.log("finally");
}

// Custom error
class MyError extends Error {
    constructor(msg) {
        super(msg);
        this.name = "MyError";
    }
}
try {
    throw new MyError("custom");
} catch (e) {
    console.log(e.name);
    console.log(e.message);
    console.log(e instanceof MyError);
    console.log(e instanceof Error);
}
