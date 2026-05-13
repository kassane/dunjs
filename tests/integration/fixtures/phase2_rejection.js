// Case 1: handler attached sync — must NOT print to stderr
Promise.reject('x').catch(() => {});

// Case 2: handler attached via microtask — must NOT print to stderr
const p = Promise.reject('a');
queueMicrotask(() => p.catch(() => {}));

// Case 3: two simultaneous unhandled rejections — both must appear
Promise.reject('error1');
Promise.reject('error2');

// Case 4: non-stringifiable reason — must print <unknown>, no crash
Promise.reject(Object.create(null));
