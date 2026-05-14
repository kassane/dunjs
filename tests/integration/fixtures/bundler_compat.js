// Test webpack/esbuild-like bundler patterns
var checks = 0;
var passed = 0;
function check(name, condition) {
  checks++;
  if (condition) { passed++; console.log('PASS: ' + name); }
  else console.log('FAIL: ' + name);
}

// --- fs patterns (file reading, directory traversal) ---
var fs = require('fs');
check('fs.readFileSync', typeof fs.readFileSync === 'function');
check('fs.writeFileSync', typeof fs.writeFileSync === 'function');
check('fs.existsSync', typeof fs.existsSync === 'function');
check('fs.statSync', typeof fs.statSync === 'function');
check('fs.readdirSync', typeof fs.readdirSync === 'function');
check('fs.mkdirSync', typeof fs.mkdirSync === 'function');
check('fs.unlinkSync', typeof fs.unlinkSync === 'function');
check('fs.renameSync', typeof fs.renameSync === 'function');
check('fs.copyFileSync', typeof fs.copyFileSync === 'function');
check('fs.readlinkSync', typeof fs.readlinkSync === 'function');
check('fs.realpathSync', typeof fs.realpathSync === 'function');
check('fs.accessSync', typeof fs.accessSync === 'function');
check('fs.watchFile', typeof fs.watchFile === 'function');
check('fs.unwatchFile', typeof fs.unwatchFile === 'function');
check('fs.promises', typeof fs.promises === 'object');
check('fs.promises.readFile', typeof fs.promises.readFile === 'function');

// Test actual file operations
var tmpPath = '/tmp/dun_bundler_test_' + Date.now() + '.txt';
fs.writeFileSync(tmpPath, 'bundler test content');
check('writeFileSync+readFileSync', fs.readFileSync(tmpPath, 'utf8') === 'bundler test content');
check('existsSync true', fs.existsSync(tmpPath) === true);
check('existsSync false', fs.existsSync('/tmp/nonexistent_' + Date.now()) === false);

var stat = fs.statSync(tmpPath);
check('statSync isFile', stat.isFile() === true);
check('statSync isDirectory', stat.isDirectory() === false);
check('statSync size', stat.size > 0);

fs.unlinkSync(tmpPath);
check('unlinkSync', fs.existsSync(tmpPath) === false);

// --- path patterns (resolution, manipulation) ---
var path = require('path');
check('path.resolve', path.resolve('foo', 'bar').length > 5);
check('path.join', path.join('foo', 'bar') === 'foo/bar');
check('path.normalize', path.normalize('foo//bar/../baz') === 'foo/baz');
check('path.isAbsolute /', path.isAbsolute('/foo') === true);
check('path.isAbsolute rel', path.isAbsolute('foo') === false);
check('path.sep', path.sep === '/');
check('path.delimiter', path.delimiter === ':');

var parsed = path.parse('/home/user/file.js');
check('path.parse dir', parsed.dir === '/home/user');
check('path.parse base', parsed.base === 'file.js');
check('path.parse name', parsed.name === 'file');
check('path.parse ext', parsed.ext === '.js');

check('path.format', path.format(parsed) === '/home/user/file.js');

// --- Module resolution ---
check('require works', typeof require === 'function');
var mod = require('module');
check('module.builtinModules', Array.isArray(mod.builtinModules));
check('module.isBuiltin', mod.isBuiltin('fs') === true);
check('module.isBuiltin false', mod.isBuiltin('nonexistent') === false);

// --- Crypto patterns (integrity checking) ---
var crypto = require('crypto');
function hashContent(content) {
  return crypto.createHash('sha256').update(content).digest('hex');
}
var h1 = hashContent('test content');
var h2 = hashContent('test content');
var h3 = hashContent('different');
check('hash deterministic', h1 === h2);
check('hash unique', h1 !== h3);
check('hash length', h1.length === 64);

// --- String operations (source transforms) ---
var src = 'import { foo } from "bar";\nexport const x = 42;';
check('string includes', src.includes('import'));
check('string indexOf', src.indexOf('export') > 0);
check('string replace', src.replace('42', '99').includes('99'));
check('string split', src.split('\n').length === 2);
check('string trim', '  hello  '.trim() === 'hello');
check('string startsWith', src.startsWith('import'));
check('string endsWith', src.endsWith('42;'));
check('string padStart', '5'.padStart(3, '0') === '005');
check('string repeat', 'ab'.repeat(3) === 'ababab');

// --- RegExp patterns (parsing) ---
var importRe = /import\s+\{([^}]+)\}\s+from\s+["']([^"']+)["']/;
var match = importRe.exec(src);
check('regex exec', match !== null);
check('regex groups', match[1].trim() === 'foo');
check('regex source', match[2] === 'bar');

// --- Map/Set patterns (dependency graphs) ---
var depGraph = new Map();
depGraph.set('a', ['b', 'c']);
depGraph.set('b', ['d']);
depGraph.set('c', []);
depGraph.set('d', []);
check('Map size', depGraph.size === 4);
check('Map has', depGraph.has('a'));
check('Map get', depGraph.get('a').length === 2);
check('Map keys', Array.from(depGraph.keys()).length === 4);

var visited = new Set();
visited.add('a');
visited.add('b');
check('Set size', visited.size === 2);
check('Set has', visited.has('a'));
check('Set add duplicate', (visited.add('a'), visited.size === 2));

// --- WeakMap/WeakRef patterns (caching) ---
check('WeakMap', typeof WeakMap === 'function');
check('WeakSet', typeof WeakSet === 'function');
check('WeakRef', typeof WeakRef === 'function');

// --- Array patterns (transforms, filtering) ---
var files = ['a.js', 'b.ts', 'c.css', 'd.js', 'e.tsx'];
check('filter', files.filter(function(f) { return f.endsWith('.js'); }).length === 2);
check('map', files.map(function(f) { return f.toUpperCase(); })[0] === 'A.JS');
check('find', files.find(function(f) { return f.endsWith('.css'); }) === 'c.css');
check('findIndex', files.findIndex(function(f) { return f.endsWith('.css'); }) === 2);
check('every', files.every(function(f) { return f.length > 0; }));
check('some', files.some(function(f) { return f.endsWith('.tsx'); }));
check('flat', [[1,2],[3,4]].flat().length === 4);
check('flatMap', [[1,2],[3]].flatMap(function(x){return x;}).length === 3);
check('Array.from', Array.from('abc').length === 3);
check('Array.isArray', Array.isArray([]) === true);
check('Array.of', Array.of(1,2,3).length === 3);

// --- Object patterns ---
check('Object.keys', Object.keys({a:1,b:2}).length === 2);
check('Object.values', Object.values({a:1,b:2}).join(',') === '1,2');
check('Object.entries', Object.entries({a:1}).length === 1);
check('Object.assign', Object.assign({}, {a:1}, {b:2}).b === 2);
check('Object.freeze', Object.isFrozen(Object.freeze({a:1})));
check('spread', JSON.stringify({...{a:1}, ...{b:2}}) === '{"a":1,"b":2}');
check('optional chaining', ({a:{b:1}})?.a?.b === 1);
check('nullish coalescing', (null ?? 'default') === 'default');
check('destructuring', (function(){var {a,b} = {a:1,b:2}; return a+b;})() === 3);

// --- Async patterns ---
check('Promise', typeof Promise === 'function');
check('Promise.all', typeof Promise.all === 'function');
check('Promise.allSettled', typeof Promise.allSettled === 'function');
check('Promise.any', typeof Promise.any === 'function');
check('Promise.race', typeof Promise.race === 'function');

// --- Globals needed by bundlers ---
check('process.env.NODE_ENV', process.env.NODE_ENV === undefined || typeof process.env.NODE_ENV === 'string');
check('__filename or import.meta', typeof __filename === 'undefined' || typeof __filename === 'string');

console.log('---');
console.log('Total: ' + passed + '/' + checks + ' passed');
