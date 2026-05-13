// nextTick fires before queueMicrotask
process.nextTick(() => console.log('nextTick'));
queueMicrotask(() => console.log('microtask'));
console.log('sync');

// microtask scheduling a new microtask
queueMicrotask(() => {
    console.log('outer');
    queueMicrotask(() => console.log('inner'));
});

// handled rejection: must NOT appear on stderr
Promise.reject('handled').catch(() => {});
