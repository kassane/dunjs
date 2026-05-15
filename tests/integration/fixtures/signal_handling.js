// Test signal handler registration via process.on
console.log('=== signal_handling ===');

// Test that process.on returns the process object (chainable)
var result = process.on('SIGTERM', () => {
    console.log('SIGTERM received');
});
console.log('SIGTERM registered:', typeof result === 'object');

result = process.on('SIGINT', () => {
    console.log('SIGINT received');
});
console.log('SIGINT registered:', typeof result === 'object');

// Test multiple handlers on same signal
process.on('SIGTERM', () => {
    console.log('SIGTERM handler 2');
});
console.log('multiple handlers: true');

// Test that process.on still works for other events
process.on('uncaughtException', (err) => {
    console.log('uncaught:', err);
});
console.log('uncaughtException handler: true');

console.log('PASS: signal_handling');
