// node:test compat shim — the minimal Node.js test runner API
// covering the common usage: test/describe/it + before/after hooks +
// strict assertions through node:assert/strict.
const { test, describe, it, before, after } = require("node:test");
const assert = require("node:assert/strict");

let beforeCount = 0;
before(() => { beforeCount++; });

test("basic equality", () => {
  assert.equal(1 + 1, 2);
});

test("deep equality", () => {
  assert.deepEqual({ a: [1, 2] }, { a: [1, 2] });
});

describe("group", () => {
  it("sees before hook", () => {
    assert.equal(beforeCount, 1);
  });

  it("throws assertion error on mismatch", () => {
    assert.throws(() => assert.equal(1, 2));
  });
});

after(() => {
  // hooks fire at the right moment
});
