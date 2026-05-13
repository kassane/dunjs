// Advanced Promise patterns (inspired by Bun setTimeout.test.js / Deno promise_test.ts)

// Promise.all
Promise.all([
    Promise.resolve(1),
    Promise.resolve(2),
    Promise.resolve(3),
]).then(values => {
    console.log(values.join(","));
});

// Promise.race
Promise.race([
    new Promise(resolve => resolve("first")),
    new Promise(resolve => resolve("second")),
]).then(winner => {
    console.log(winner);
});

// Promise.any
Promise.any([
    Promise.reject("no"),
    Promise.resolve("yes"),
    Promise.resolve("also"),
]).then(result => {
    console.log(result);
});

// Chained .then
Promise.resolve(1)
    .then(v => v + 1)
    .then(v => v * 3)
    .then(v => {
        console.log(v);
    });

// Async/await with error handling
async function safeDivide(a, b) {
    if (b === 0) throw new Error("division by zero");
    return a / b;
}

async function main() {
    console.log(await safeDivide(10, 2));
    try {
        await safeDivide(1, 0);
    } catch (e) {
        console.log(e.message);
    }

    // Async iteration simulation
    const results = await Promise.all(
        [1, 2, 3].map(async n => n * n)
    );
    console.log(results.join(","));
}

main();
