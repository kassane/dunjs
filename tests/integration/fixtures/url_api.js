// Test URL and URLSearchParams
const url = new URL('https://user:pass@example.com:8080/path/to?q=1&r=2#hash');
console.log('protocol: ' + url.protocol);
console.log('hostname: ' + url.hostname);
console.log('port: ' + url.port);
console.log('pathname: ' + url.pathname);
console.log('search: ' + url.search);
console.log('hash: ' + url.hash);
console.log('username: ' + url.username);
console.log('host: ' + url.host);
console.log('origin: ' + url.origin);
console.log('href: ' + url.href);
console.log('toString: ' + url.toString());

// URLSearchParams
const params = new URLSearchParams('a=1&b=2&a=3');
console.log('get a: ' + params.get('a'));
console.log('getAll a: ' + params.getAll('a').join(','));
console.log('has b: ' + params.has('b'));
console.log('has c: ' + params.has('c'));

params.set('b', '20');
console.log('set b: ' + params.get('b'));

params.append('c', '30');
console.log('append c: ' + params.get('c'));

params.delete('a');
console.log('delete a: ' + params.has('a'));

console.log('toString: ' + params.toString());
console.log('size: ' + params.size);

// URL with base
const rel = new URL('/api/data', 'https://example.com');
console.log('relative: ' + rel.href);

// forEach
const sp = new URLSearchParams('x=1&y=2');
const pairs = [];
sp.forEach((v, k) => pairs.push(k + '=' + v));
console.log('forEach: ' + pairs.join(', '));
