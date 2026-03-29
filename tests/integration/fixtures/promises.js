// Test Promise support (QuickJS ES2023)
const p = new Promise((resolve) => {
    resolve("promise resolved");
});

p.then((val) => {
    console.log(val);
});

// Async/await
async function greet() {
    const msg = await Promise.resolve("async hello");
    console.log(msg);
}

greet();
