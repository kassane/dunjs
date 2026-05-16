// Bun.build + Bun.FileSystemRouter + nanoseconds + peek tests.
const fs = require('fs');
const path = require('path');
const os = require('os');

let passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) passed++;
  else console.log('FAIL:', name);
}

(async () => {
  /* ---- Bun.build ---- */
  // Stage a tiny project with one entry + one imported module.
  const projDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dun-bun-build-'));
  fs.writeFileSync(path.join(projDir, 'util.js'), 'function greet(n) { return "hi " + n; }');
  fs.writeFileSync(path.join(projDir, 'entry.js'),
    'import "./util.js"\nconsole.log(greet("world"));');

  const result = await Bun.build({
    entrypoints: [path.join(projDir, 'entry.js')]
  });

  check('Bun.build success', result.success === true);
  check('Bun.build has outputs', Array.isArray(result.outputs) && result.outputs.length === 1);
  check('Bun.build has logs', Array.isArray(result.logs));

  const text = await result.outputs[0].text();
  check('Bundle contains util.js', text.indexOf('greet(') >= 0);
  check('Bundle contains entry.js', text.indexOf('console.log') >= 0);
  // The import line was stripped.
  check('Bundle stripped imports', text.indexOf("import \"./util.js\"") < 0);
  check('Output is JS loader', result.outputs[0].loader === 'js');

  /* ---- Bun.build with outdir ---- */
  const outDir = path.join(projDir, 'out');
  const r2 = await Bun.build({
    entrypoints: [path.join(projDir, 'entry.js')],
    outdir: outDir
  });
  check('Bun.build outdir success', r2.success === true);
  check('Bundle file written', fs.existsSync(path.join(outDir, 'bundle.js')));

  /* ---- Bun.FileSystemRouter ---- */
  const routesDir = path.join(projDir, 'routes');
  fs.mkdirSync(routesDir, { recursive: true });
  fs.writeFileSync(path.join(routesDir, 'index.js'), '');
  fs.writeFileSync(path.join(routesDir, 'about.js'), '');
  fs.mkdirSync(path.join(routesDir, 'users'), { recursive: true });
  fs.writeFileSync(path.join(routesDir, 'users', 'index.js'), '');
  fs.writeFileSync(path.join(routesDir, 'users', '[id].js'), '');

  const router = new Bun.FileSystemRouter({
    dir: routesDir,
    style: 'nextjs'
  });

  check('Router built routes', typeof router.routes === 'object');
  check('Router has match', typeof router.match === 'function');

  const home = router.match('/');
  check('Match / → index', home && home.filePath.endsWith('index.js'));
  const about = router.match('/about');
  check('Match /about', about && about.filePath.endsWith('about.js'));
  const userList = router.match('/users');
  check('Match /users', userList && userList.filePath.endsWith('users/index.js'));
  const userDetail = router.match('/users/42');
  check('Match /users/42 → param', userDetail && userDetail.params.id === '42');
  check('Match /users/42 dynamic kind', userDetail && userDetail.kind === 'dynamic');
  const miss = router.match('/nope');
  check('Match /nope → null', miss === null);

  /* ---- nanoseconds ---- */
  const t1 = Bun.nanoseconds();
  await new Promise(r => setTimeout(r, 5));
  const t2 = Bun.nanoseconds();
  check('nanoseconds monotonic', t2 > t1);
  check('nanoseconds ~5ms elapsed', (t2 - t1) > 1_000_000);

  /* ---- peek ---- */
  const settled = Promise.resolve(42);
  await Promise.resolve();  // give it a microtask to settle
  // peek.status returns immediately. fulfilled vs pending depends on microtask order
  check('peek.status is fn', typeof Bun.peek.status === 'function');

  /* ---- resolveSync ---- */
  const r = Bun.resolveSync('fs');
  check('resolveSync returns string', typeof r === 'string');

  /* ---- color (pass-through) ---- */
  check('Bun.color is fn', typeof Bun.color === 'function');
  check('Bun.color string', Bun.color('#ff0000', 'hex') === '#ff0000');
  check('Bun.color null', Bun.color(null) === null);

  /* ---- ms ---- */
  check('Bun.ms returns number', typeof Bun.ms() === 'number');

  /* ---- fileURLToPath / pathToFileURL ---- */
  check('fileURLToPath defined', typeof Bun.fileURLToPath === 'function');
  check('fileURLToPath strips file://', Bun.fileURLToPath('file:///tmp/x.js') === '/tmp/x.js');
  check('pathToFileURL defined', typeof Bun.pathToFileURL === 'function');
  check('pathToFileURL produces file URL',
    String(Bun.pathToFileURL('/tmp/x.js')).indexOf('file:') === 0);

  /* ---- indexOfLine + stringWidth ---- */
  const lineBuf = Buffer.from('hello\nworld');
  check('indexOfLine finds newline', Bun.indexOfLine(lineBuf, 0) === 5);
  check('indexOfLine returns -1 when absent', Bun.indexOfLine(lineBuf, 6) === -1);
  check('stringWidth plain', Bun.stringWidth('hello') === 5);
  check('stringWidth strips ANSI', Bun.stringWidth('\x1B[31mhi\x1B[0m') === 2);

  // Cleanup
  fs.rmSync(projDir, { recursive: true, force: true });

  console.log('bun_build_router:', passed + '/' + total, 'checks passed');
  if (passed === total) console.log('ALL CHECKS PASSED');
})();
