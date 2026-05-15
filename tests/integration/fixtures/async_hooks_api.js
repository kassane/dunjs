const { AsyncLocalStorage } = require('async_hooks');
const als = new AsyncLocalStorage();

console.log('=== async_hooks ===');
console.log('getStore outside:', als.getStore());

als.run({ id: 42 }, () => {
    const store = als.getStore();
    console.log('getStore inside:', store.id);
});

console.log('getStore after:', als.getStore());

// Test nested runs
als.run({ level: 1 }, () => {
    console.log('nested L1:', als.getStore().level);
    als.run({ level: 2 }, () => {
        console.log('nested L2:', als.getStore().level);
    });
    console.log('back to L1:', als.getStore().level);
});

// Test enterWith
const als2 = new AsyncLocalStorage();
als2.enterWith({ entered: true });
console.log('enterWith:', als2.getStore().entered);

// Test disable
als2.disable();
console.log('after disable:', als2.getStore());

// Test run with extra args
als.run({ ctx: 'extra' }, (a, b) => {
    console.log('extra args:', a, b);
    console.log('store in extra:', als.getStore().ctx);
}, 'hello', 'world');

console.log('PASS: async_hooks');
