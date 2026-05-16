// Frontend framework patterns: React virtual DOM, Vue reactivity, Angular DI,
// Next.js routing. All exercised without the real packages so the test stays
// hermetic; the heavier real-package suites live under tests/benchmarks/.

let p = 0, f = 0;
const ok = (n, c) => { if (c) { p++; } else { f++; console.log('FAIL:', n); } };

// React-style virtual DOM + SSR
const h = (type, props, ...kids) => ({ type, props: props || {}, kids: kids.flat() });
function render(v) {
  if (v == null || v === false || v === true) return '';
  if (typeof v !== 'object') return String(v);
  if (typeof v.type === 'function') return render(v.type({ ...v.props, children: v.kids }));
  const a = Object.entries(v.props).filter(([k]) => k !== 'children')
    .map(([k, val]) => ` ${k}="${val}"`).join('');
  return `<${v.type}${a}>${v.kids.map(render).join('')}</${v.type}>`;
}
const App = ({ name }) => h('div', { class: 'app' }, h('h1', null, 'Hello, ', name));
ok('react: SSR', render(h(App, { name: 'World' })) === '<div class="app"><h1>Hello, World</h1></div>');
ok('react: nested', render(h('ul', null, h('li', null, 'a'), h('li', null, 'b'))) === '<ul><li>a</li><li>b</li></ul>');

// Vue-style reactivity (Proxy-based)
function reactive(obj) {
  const subs = new Set();
  return [new Proxy(obj, {
    get(t, k) { return t[k]; },
    set(t, k, v) { t[k] = v; subs.forEach(fn => fn(k, v)); return true; }
  }), fn => subs.add(fn)];
}
const [state, watch] = reactive({ count: 0 });
let changes = 0;
watch(() => changes++);
state.count = 1; state.count = 2;
ok('vue: reactivity fires on set', changes === 2);
ok('vue: state read', state.count === 2);

// Angular-style DI
class Injector {
  constructor() { this.services = new Map(); }
  register(token, factory) { this.services.set(token, factory); }
  get(token) {
    const f = this.services.get(token);
    if (!f) throw new Error('no provider for ' + token);
    return f(this);
  }
}
const inj = new Injector();
inj.register('config', () => ({ baseUrl: '/api' }));
inj.register('http', i => ({ get: p => i.get('config').baseUrl + p }));
ok('angular: DI singleton resolution', inj.get('http').get('/users') === '/api/users');

// Next.js-style file-based router
function makeRouter(routes) {
  const compiled = Object.entries(routes).map(([pat, h]) => {
    const keys = [];
    const re = '^' + pat.replace(/\[(\w+)\]/g, (_, k) => (keys.push(k), '([^/]+)')) + '$';
    return { re: new RegExp(re), keys, h };
  });
  return path => {
    for (const r of compiled) {
      const m = path.match(r.re);
      if (m) {
        const params = {};
        r.keys.forEach((k, i) => params[k] = m[i + 1]);
        return r.h(params);
      }
    }
    return null;
  };
}
const route = makeRouter({
  '/': () => 'home',
  '/users/[id]': ({ id }) => `user-${id}`,
  '/posts/[slug]/comments/[cid]': ({ slug, cid }) => `${slug}#${cid}`,
});
ok('next: static route', route('/') === 'home');
ok('next: single param', route('/users/42') === 'user-42');
ok('next: nested params', route('/posts/hello/comments/7') === 'hello#7');
ok('next: 404', route('/nope') === null);

// Svelte-style stores
function writable(initial) {
  let value = initial;
  const subs = new Set();
  return {
    set(v) { value = v; subs.forEach(fn => fn(v)); },
    update(fn) { this.set(fn(value)); },
    subscribe(fn) { fn(value); subs.add(fn); return () => subs.delete(fn); }
  };
}
const count = writable(0);
let last = -1;
count.subscribe(v => last = v);
count.set(5); count.update(v => v * 2);
ok('svelte: store subscribe fires immediately', last === 10);

console.log(`framework_patterns: ${p}/${p + f} passed`);
if (f > 0) process.exit(1);
