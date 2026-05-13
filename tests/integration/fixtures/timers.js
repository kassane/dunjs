// Test setTimeout/setInterval (requires Phase 2 event loop)
console.log("start");

setTimeout(() => {
    console.log("timeout 100ms");
}, 100);

setTimeout(() => {
    console.log("timeout 50ms");
}, 50);

console.log("end sync");

// Expected order: start, end sync, timeout 50ms, timeout 100ms
