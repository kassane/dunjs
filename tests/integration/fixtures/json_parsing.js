// JSON parsing and serialization (inspired by Node test-json.js)

// Basic parse
const obj = JSON.parse('{"name":"dun","version":1}');
console.log(obj.name);
console.log(obj.version);

// Nested
const nested = JSON.parse('{"a":{"b":{"c":true}}}');
console.log(nested.a.b.c);

// Arrays
const arr = JSON.parse('[1,2,3]');
console.log(arr.length);
console.log(arr.join(","));

// Stringify
console.log(JSON.stringify({ x: 1, y: [2, 3] }));

// Stringify with indent
const pretty = JSON.stringify({ a: 1, b: 2 }, null, 2);
console.log(pretty);

// Replacer function
const filtered = JSON.stringify(
    { name: "test", secret: "hidden", value: 42 },
    (key, val) => key === "secret" ? undefined : val
);
console.log(filtered);

// Reviver function
const parsed = JSON.parse('{"date":"2024-01-01","count":"42"}', (key, val) => {
    if (key === "count") return Number(val);
    return val;
});
console.log(typeof parsed.count);
console.log(parsed.count);

// Parse error
try {
    JSON.parse("{invalid}");
} catch (e) {
    console.log(e instanceof SyntaxError);
}
