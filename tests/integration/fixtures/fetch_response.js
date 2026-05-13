// Test that fetch() returns a proper Response object with all standard methods

let pass = 0, fail = 0;
function check(name, cond) {
  if (cond) { pass++; }
  else { fail++; console.log('FAIL: ' + name); }
}

// Test Response constructor exists and works
check('Response exists', typeof Response === 'function');
const r = new Response('hello world', { status: 200, statusText: 'OK' });
check('Response.status', r.status === 200);
check('Response.statusText', r.statusText === 'OK');
check('Response.ok', r.ok === true);
check('Response has text()', typeof r.text === 'function');
check('Response has json()', typeof r.json === 'function');
check('Response has clone()', typeof r.clone === 'function');
check('Response has blob()', typeof r.blob === 'function');
check('Response has arrayBuffer()', typeof r.arrayBuffer === 'function');

// Response.json() static
const jsonRes = Response.json({ key: 'value' });
check('Response.json() status', jsonRes.status === 200);

// Response.redirect()
const redirRes = Response.redirect('https://example.com', 301);
check('Response.redirect() status', redirRes.status === 301);

// Response.error()
const errRes = Response.error();
check('Response.error() type', errRes.type === 'error');

// Clone
const cloned = r.clone();
check('clone.status', cloned.status === r.status);

// process.stdin
check('process.stdin exists', typeof process.stdin === 'object');
check('process.stdin.readable', process.stdin.readable === true);
check('process.stdin.isTTY', typeof process.stdin.isTTY === 'boolean');
check('process.stdin.read', typeof process.stdin.read === 'function');
check('process.stdin.setEncoding', typeof process.stdin.setEncoding === 'function');
check('process.stdin.fd', process.stdin.fd === 0);

console.log(`\nFetch Response: ${pass}/${pass + fail} passed`);
if (fail > 0) console.log(`${fail} FAILED`);
