var fs = require('fs');
var checks = 0, passed = 0;
function check(name, cond) { checks++; if (cond) { passed++; console.log('PASS: ' + name); } else console.log('FAIL: ' + name); }

// fs errors should have .code property
try { fs.readFileSync('/nonexistent/path/to/file'); } catch(e) {
  check('readFileSync ENOENT code', e.message && e.message.indexOf('ENOENT') !== -1);
}
try { fs.statSync('/nonexistent/path/to/file'); } catch(e) {
  check('statSync ENOENT code', e.message && e.message.indexOf('ENOENT') !== -1);
}
// existsSync should return false, not throw
check('existsSync returns false', fs.existsSync('/nonexistent/path/to/file') === false);

// path module
var path = require('path');
check('path.resolve absolute', path.resolve('/foo/bar', './baz') === '/foo/bar/baz');
check('path.relative', path.relative('/a/b/c', '/a/d') === '../../d');

// Error types
try { null.x; } catch(e) {
  check('TypeError instanceof', e instanceof TypeError);
}
try { undeclaredVariable; } catch(e) {
  check('ReferenceError instanceof', e instanceof ReferenceError);
}
try { JSON.parse('{bad}'); } catch(e) {
  check('SyntaxError instanceof', e instanceof SyntaxError);
}
check('RangeError exists', typeof RangeError === 'function');
check('URIError exists', typeof URIError === 'function');
check('EvalError exists', typeof EvalError === 'function');

console.log('---');
console.log('Total: ' + passed + '/' + checks + ' passed');
