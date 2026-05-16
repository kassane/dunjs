// Deno.serve + Deno.openKv + Deno.cron shim test.

let passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) passed++;
  else console.log('FAIL:', name);
}

check('Deno.serve is fn', typeof Deno.serve === 'function');
check('Deno.openKv is fn', typeof Deno.openKv === 'function');
check('Deno.cron is fn', typeof Deno.cron === 'function');

(async () => {
  /* ---- Deno.openKv basic round-trip ---- */
  const kv = await Deno.openKv();
  check('kv has get/set/delete', typeof kv.get === 'function' && typeof kv.set === 'function');

  await kv.set(['users', 'alice'], { age: 30 });
  const got = await kv.get(['users', 'alice']);
  check('kv.get returns value', got && got.value && got.value.age === 30);
  check('kv.get returns versionstamp', typeof got.versionstamp === 'string');

  await kv.delete(['users', 'alice']);
  const gone = await kv.get(['users', 'alice']);
  check('kv.delete clears value', gone.value === null);

  /* ---- Deno.openKv atomic ---- */
  const ar = await kv.atomic().set(['a'], 1).set(['b'], 2).commit();
  check('kv.atomic commit ok', ar.ok === true);
  const aval = await kv.get(['a']);
  check('kv.atomic set persists', aval.value === 1);

  /* ---- Deno.openKv list ---- */
  await kv.set(['users', 'bob'], 'b');
  await kv.set(['users', 'carol'], 'c');
  let count = 0;
  for await (const entry of kv.list({ prefix: ['users'] })) {
    count++;
  }
  check('kv.list iterates prefix', count >= 2);

  /* ---- Deno.serve with shutdown ---- */
  const srv = Deno.serve({ port: 0, hostname: '127.0.0.1' }, (req) => {
    return new Response('pong');
  });
  check('serve returned addr', srv.addr && typeof srv.addr.port === 'number');
  check('serve has shutdown', typeof srv.shutdown === 'function');
  await srv.shutdown();
  check('serve shutdown awaited', true);

  console.log('deno_serve_kv:', passed + '/' + total, 'checks passed');
  if (passed === total) console.log('ALL CHECKS PASSED');
})();
