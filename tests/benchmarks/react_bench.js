// React & Frontend Framework Performance Benchmark
// Measures VDOM creation, diffing, rendering, state management throughput
// Runs on: Node, Bun, Deno, DunJS (all backends)

function bench(name, fn, iterations) {
  // Warmup
  for (let i = 0; i < Math.min(100, iterations / 10); i++) fn();
  const start = Date.now();
  for (let i = 0; i < iterations; i++) fn();
  const elapsed = Date.now() - start;
  const opsPerSec = Math.round(iterations / (elapsed / 1000));
  console.log(`  ${name}: ${opsPerSec.toLocaleString()} ops/sec (${elapsed}ms)`);
  return opsPerSec;
}

let totalOps = 0;

// ═══════════════════════════════════
// VDOM helpers
// ═══════════════════════════════════

function h(type, props, ...children) {
  return { type, props: props || {}, children: children.flat() };
}

function renderToString(vnode) {
  if (typeof vnode === 'string' || typeof vnode === 'number') return String(vnode);
  if (!vnode || typeof vnode === 'boolean') return '';
  const { type, props, children } = vnode;
  if (typeof type === 'function') return renderToString(type({ ...props, children }));
  let attrs = '';
  for (const k in props) {
    if (k === 'children' || k === 'key' || k === 'ref') continue;
    const v = props[k];
    if (typeof v === 'boolean') { if (v) attrs += ` ${k}`; continue; }
    if (typeof v === 'function') continue;
    attrs += ` ${k}="${String(v)}"`;
  }
  return `<${type}${attrs}>${children.map(c => renderToString(c)).join('')}</${type}>`;
}

console.log('=== React/Framework Performance Benchmark ===\n');

// ═══════════════════════════════════
// 1. VDOM Creation
// ═══════════════════════════════════
console.log('--- VDOM Creation ---');

totalOps += bench('createElement simple', () => {
  h('div', { class: 'app' }, h('h1', null, 'Hello'), h('p', null, 'World'));
}, 500000);

totalOps += bench('createElement deep tree (depth 10)', () => {
  let node = h('span', null, 'leaf');
  for (let i = 0; i < 10; i++) node = h('div', { class: `level-${i}` }, node);
}, 200000);

totalOps += bench('createElement list (100 items)', () => {
  h('ul', null, ...Array.from({ length: 100 }, (_, i) => h('li', { key: i }, `Item ${i}`)));
}, 20000);

totalOps += bench('createElement with component', () => {
  const Item = ({ text }) => h('li', null, text);
  h('ul', null, ...['a', 'b', 'c', 'd', 'e'].map(t => h(Item, { text: t })));
}, 200000);

// ═══════════════════════════════════
// 2. renderToString (SSR)
// ═══════════════════════════════════
console.log('\n--- SSR Rendering ---');

const simpleTree = h('div', { class: 'app' },
  h('header', null, h('h1', null, 'Title')),
  h('main', null, h('p', null, 'Content')),
  h('footer', null, h('span', null, '2024'))
);
totalOps += bench('renderToString simple', () => renderToString(simpleTree), 200000);

const listTree = h('ul', null,
  ...Array.from({ length: 50 }, (_, i) => h('li', { class: 'item' }, `Item ${i}`))
);
totalOps += bench('renderToString list (50 items)', () => renderToString(listTree), 20000);

function TableRow({ cells }) {
  return h('tr', null, ...cells.map(c => h('td', null, c)));
}
function Table({ rows }) {
  return h('table', null, h('tbody', null,
    ...rows.map(r => h(TableRow, { cells: r }))
  ));
}
const tableData = Array.from({ length: 20 }, (_, i) =>
  [`Row ${i}`, `Value ${i * 10}`, `Status ${i % 2 ? 'active' : 'inactive'}`]
);
const tableTree = h(Table, { rows: tableData });
totalOps += bench('renderToString table (20x3)', () => renderToString(tableTree), 10000);

// Full page
function Page({ title, items }) {
  return h('html', null,
    h('head', null,
      h('title', null, title),
      h('meta', { charset: 'utf-8' }),
    ),
    h('body', null,
      h('div', { id: 'root' },
        h('nav', null, h('a', { href: '/' }, 'Home'), h('a', { href: '/about' }, 'About')),
        h('main', null,
          h('h1', null, title),
          h('ul', null, ...items.map(i => h('li', null, i)))
        ),
        h('footer', null, h('p', null, '(c) 2024'))
      )
    )
  );
}
const pageTree = h(Page, { title: 'Test', items: Array.from({ length: 30 }, (_, i) => `Item ${i}`) });
totalOps += bench('renderToString full page', () => renderToString(pageTree), 10000);

// ═══════════════════════════════════
// 3. VDOM Diffing
// ═══════════════════════════════════
console.log('\n--- VDOM Diffing ---');

function diff(a, b) {
  if (a === b) return null;
  if (!a) return { type: 'CREATE', node: b };
  if (!b) return { type: 'REMOVE' };
  if (typeof a !== typeof b || (typeof a === 'string' && a !== b)) return { type: 'REPLACE', node: b };
  if (typeof a === 'string') return null;
  if (a.type !== b.type) return { type: 'REPLACE', node: b };
  const propChanges = [];
  const allKeys = new Set([...Object.keys(a.props), ...Object.keys(b.props)]);
  for (const k of allKeys) { if (a.props[k] !== b.props[k]) propChanges.push(k); }
  const childDiffs = [];
  const max = Math.max(a.children.length, b.children.length);
  for (let i = 0; i < max; i++) {
    const d = diff(a.children[i], b.children[i]);
    if (d) childDiffs.push({ index: i, ...d });
  }
  if (propChanges.length === 0 && childDiffs.length === 0) return null;
  return { type: 'UPDATE', props: propChanges, children: childDiffs };
}

const treeA = h('div', { class: 'old' },
  ...Array.from({ length: 20 }, (_, i) => h('p', { key: i }, `Item ${i}`))
);
const treeB = h('div', { class: 'new' },
  ...Array.from({ length: 20 }, (_, i) => h('p', { key: i }, `Item ${i % 2 === 0 ? i : i * 10}`))
);
totalOps += bench('diff 20-node tree', () => diff(treeA, treeB), 100000);

const bigA = h('div', null, ...Array.from({ length: 100 }, (_, i) => h('span', null, String(i))));
const bigB = h('div', null, ...Array.from({ length: 100 }, (_, i) => h('span', null, String(i + 1))));
totalOps += bench('diff 100-node flat', () => diff(bigA, bigB), 20000);

// ═══════════════════════════════════
// 4. Hooks / State
// ═══════════════════════════════════
console.log('\n--- State Management ---');

totalOps += bench('useState create+set', () => {
  let s = [0]; // state array
  const set = (v) => { s[0] = typeof v === 'function' ? v(s[0]) : v; };
  set(1);
  set(n => n + 1);
  set(n => n * 2);
}, 1000000);

totalOps += bench('useReducer dispatch', () => {
  let state = { count: 0, items: [] };
  const reducer = (s, a) => {
    switch (a.type) {
      case 'inc': return { ...s, count: s.count + 1 };
      case 'add': return { ...s, items: [...s.items, a.item] };
      default: return s;
    }
  };
  state = reducer(state, { type: 'inc' });
  state = reducer(state, { type: 'inc' });
  state = reducer(state, { type: 'add', item: 'x' });
}, 500000);

// Redux-style store
totalOps += bench('Redux store dispatch (100 actions)', () => {
  let state = { todos: [], filter: 'all' };
  const reducer = (s, a) => {
    switch (a.type) {
      case 'ADD': return { ...s, todos: [...s.todos, { text: a.text, done: false }] };
      case 'TOGGLE': return { ...s, todos: s.todos.map((t, i) => i === a.i ? { ...t, done: !t.done } : t) };
      case 'FILTER': return { ...s, filter: a.filter };
      default: return s;
    }
  };
  for (let i = 0; i < 100; i++) state = reducer(state, { type: 'ADD', text: `Todo ${i}` });
}, 5000);

// Signal-style reactivity
totalOps += bench('Signal read/write (1000 ops)', () => {
  let val = 0;
  const subs = [];
  const get = () => val;
  const set = (v) => { val = v; for (const fn of subs) fn(v); };
  subs.push(() => {});
  subs.push(() => {});
  for (let i = 0; i < 1000; i++) { set(i); get(); }
}, 5000);

// Proxy reactivity (Vue-style)
totalOps += bench('Proxy reactive read/write', () => {
  const obj = new Proxy({ a: 0, b: 0, c: 0 }, {
    get(t, k) { return t[k]; },
    set(t, k, v) { t[k] = v; return true; },
  });
  for (let i = 0; i < 100; i++) { obj.a = i; obj.b = obj.a * 2; obj.c = obj.a + obj.b; }
}, 50000);

// ═══════════════════════════════════
// 5. Router Matching
// ═══════════════════════════════════
console.log('\n--- Router ---');

function matchRoute(pattern, path) {
  const pp = pattern.split('/');
  const pa = path.split('/');
  if (pp.length !== pa.length) return null;
  const params = {};
  for (let i = 0; i < pp.length; i++) {
    if (pp[i][0] === ':') params[pp[i].slice(1)] = pa[i];
    else if (pp[i] !== pa[i]) return null;
  }
  return params;
}

const routes = [
  '/api/users/:id',
  '/api/users/:id/posts/:postId',
  '/api/products/:category/:id',
  '/dashboard/:section',
  '/auth/login',
  '/auth/register',
  '/settings/:tab',
  '/',
];

totalOps += bench('route matching (8 routes)', () => {
  for (const r of routes) matchRoute(r, '/api/users/42/posts/7');
}, 200000);

// ═══════════════════════════════════
// 6. JSON / Serialization (API responses)
// ═══════════════════════════════════
console.log('\n--- Serialization ---');

const apiResponse = {
  data: Array.from({ length: 50 }, (_, i) => ({
    id: i, name: `User ${i}`, email: `user${i}@example.com`,
    profile: { bio: `Bio for user ${i}`, avatar: `https://example.com/avatar/${i}.png` },
    posts: Array.from({ length: 3 }, (_, j) => ({ id: j, title: `Post ${j}`, likes: j * 10 })),
  })),
  meta: { total: 50, page: 1, perPage: 50 },
};

const jsonStr = JSON.stringify(apiResponse);
totalOps += bench('JSON.stringify API response', () => JSON.stringify(apiResponse), 10000);
totalOps += bench('JSON.parse API response', () => JSON.parse(jsonStr), 10000);

// ═══════════════════════════════════
// 7. Immutable Updates
// ═══════════════════════════════════
console.log('\n--- Immutable Updates ---');

totalOps += bench('spread operator chain', () => {
  let s = { a: 1, b: { c: 2, d: { e: 3 } }, items: [1, 2, 3] };
  s = { ...s, a: 2 };
  s = { ...s, b: { ...s.b, c: 10 } };
  s = { ...s, b: { ...s.b, d: { ...s.b.d, e: 99 } } };
  s = { ...s, items: [...s.items, 4] };
}, 500000);

totalOps += bench('structuredClone + mutate', () => {
  const base = { users: [{ name: 'A' }, { name: 'B' }], count: 0 };
  const copy = JSON.parse(JSON.stringify(base));
  copy.users.push({ name: 'C' });
  copy.count++;
}, 100000);

// ═══════════════════════════════════
// 8. CSS-in-JS
// ═══════════════════════════════════
console.log('\n--- CSS-in-JS ---');

let classCounter = 0;
function css(rules) {
  const name = 'c' + (classCounter++).toString(36);
  let sheet = `.${name} { `;
  for (const [k, v] of Object.entries(rules)) {
    sheet += `${k.replace(/([A-Z])/g, '-$1').toLowerCase()}: ${v}; `;
  }
  sheet += '}';
  return { className: name, sheet };
}

totalOps += bench('CSS-in-JS class generation', () => {
  css({ backgroundColor: 'blue', color: 'white', padding: '8px 16px', borderRadius: '4px', fontSize: '14px' });
  css({ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '8px' });
  css({ position: 'absolute', top: '0', left: '0', width: '100%', height: '100%' });
}, 100000);

// ═══════════════════════════════════
// Summary
// ═══════════════════════════════════

console.log('\n=== Summary ===');
console.log(`Total throughput: ${totalOps.toLocaleString()} ops/sec`);
