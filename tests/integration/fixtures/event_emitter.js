// Test EventEmitter module
const ee = new EventEmitter();
const results = [];

ee.on('data', (x) => results.push('data:' + x));
ee.emit('data', 'hello');
ee.emit('data', 'world');
console.log('basic: ' + results.join(', '));

ee.once('done', (msg) => results.push('done:' + msg));
ee.emit('done', 'yes');
ee.emit('done', 'no');
console.log('once: ' + results.length);

const handler = (x) => results.push('removed:' + x);
ee.on('test', handler);
ee.off('test', handler);
ee.emit('test', 'x');
console.log('off: ' + results.length);

ee.on('a', () => results.push('a'))
  .on('b', () => results.push('b'));
ee.emit('a');
ee.emit('b');
console.log('chain: ' + results.join(', '));

ee.on('multi', () => {});
ee.on('multi', () => {});
console.log('count: ' + ee.listenerCount('multi'));

console.log('events: ' + ee.eventNames().sort().join(', '));

ee.on('error', (e) => results.push('error:' + e.message));
ee.on('crash', () => { throw new Error('boom'); });
ee.emit('crash');
console.log('error caught: ' + results[results.length - 1]);

ee.removeAllListeners();
console.log('cleared: ' + ee.eventNames().length);
