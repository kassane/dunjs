Deno.test("addition works", () => {
    assertEquals(1 + 1, 2);
});

Deno.test("string concat", () => {
    assertEquals("hello" + " " + "world", "hello world");
});

Deno.test("array length", () => {
    assertEquals([1, 2, 3].length, 3);
});

Deno.test("object keys", () => {
    const obj = { a: 1, b: 2, c: 3 };
    assertEquals(Object.keys(obj).length, 3);
});

Deno.test("async test", async () => {
    const result = await Promise.resolve(42);
    assertEquals(result, 42);
});
