Deno.bench("string concat", () => {
    let s = "";
    for (let i = 0; i < 100; i++) s += "x";
});

Deno.bench("array push", () => {
    const arr = [];
    for (let i = 0; i < 100; i++) arr.push(i);
});

Deno.bench("object create", () => {
    const obj = {};
    for (let i = 0; i < 100; i++) obj["k" + i] = i;
});
