// Bun.* compat surface — verify the shims that real Bun apps depend on.
let passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) passed++;
  else console.log('FAIL:', name);
}

/* ---- constants / env ---- */
check('Bun.version is a string', typeof Bun.version === 'string');
check('Bun.revision is a string', typeof Bun.revision === 'string');
check('Bun.env === process.env', Bun.env === process.env);
check('Bun.argv is array', Array.isArray(Bun.argv));

/* ---- helpers ---- */
check('Bun.escapeHTML', Bun.escapeHTML('<b>') === '&lt;b&gt;');
check('Bun.escapeHTML quotes', Bun.escapeHTML('"&\'') === '&quot;&amp;&#39;');
check('Bun.hash string', typeof Bun.hash('hello') === 'number');
check('Bun.hash deterministic', Bun.hash('hello') === Bun.hash('hello'));
check('Bun.hash different inputs differ', Bun.hash('a') !== Bun.hash('b'));
check('Bun.hash bytes', typeof Bun.hash(new Uint8Array([1,2,3])) === 'number');
check('Bun.deepEquals true', Bun.deepEquals({a:1, b:[1,2]}, {a:1, b:[1,2]}));
check('Bun.deepEquals false', !Bun.deepEquals({a:1}, {a:2}));
check('Bun.deepEquals primitives', Bun.deepEquals(1, 1) && !Bun.deepEquals(1, 2));
check('Bun.inspect', typeof Bun.inspect({a:1}) === 'string');
check('Bun.which echo', Bun.which('echo') !== null);
check('Bun.gc returns number', typeof Bun.gc() === 'number');

/* ---- sleep ---- */
const sleepP = Bun.sleep(1);
check('Bun.sleep returns Promise', sleepP && typeof sleepP.then === 'function');

/* ---- password (sync path so we can assert in-line) ---- */
const hash = Bun.password.hashSync('hunter2');
check('hashSync returns string', typeof hash === 'string');
check('hashSync prefix', hash.startsWith('$dun-scrypt$'));
check('verifySync ok', Bun.password.verifySync('hunter2', hash) === true);
check('verifySync wrong', Bun.password.verifySync('wrong', hash) === false);

/* ---- file ---- */
const fs = require('fs');
const tmpPath = require('os').tmpdir() + '/dun_bun_compat_test.txt';
fs.writeFileSync(tmpPath, 'hello bun');
const f = Bun.file(tmpPath);
check('Bun.file has size', f.size === 9);
check('Bun.file has type', typeof f.type === 'string');
check('Bun.file.text returns Promise', typeof f.text().then === 'function');
f.text().then(t => {
  check('Bun.file.text content', t === 'hello bun');
  fs.unlinkSync(tmpPath);
  setTimeout(emit, 5);
});

function emit() {
  /* ---- spawnSync ---- */
  const r = Bun.spawnSync({ cmd: ['echo', 'spawned'] });
  check('spawnSync exitCode 0', r.exitCode === 0);
  check('spawnSync stdout contains spawned', r.stdout.toString().indexOf('spawned') >= 0);

  console.log('bun_compat:', passed + '/' + total, 'checks passed');
  if (passed === total) console.log('ALL CHECKS PASSED');
}
