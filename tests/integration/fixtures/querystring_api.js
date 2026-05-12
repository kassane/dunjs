// querystring module integration test
const qs = require('querystring');

// parse
var parsed = qs.parse('foo=bar&baz=qux&baz=quux');
console.log('parse foo:', parsed.foo);
console.log('parse baz:', Array.isArray(parsed.baz) ? parsed.baz.join(',') : parsed.baz);

// stringify
console.log('stringify:', qs.stringify({a: '1', b: '2'}));

// escape
console.log('escape:', qs.escape('hello world&foo=bar'));

// unescape
console.log('unescape:', qs.unescape('hello%20world'));

// round-trip
var obj = {name: 'test', tags: ['a', 'b']};
var str = qs.stringify(obj);
console.log('roundtrip ok:', str.includes('name=test'));

// decode/encode aliases
console.log('decode alias:', typeof qs.decode === 'function');
console.log('encode alias:', typeof qs.encode === 'function');

console.log('All querystring tests passed');
