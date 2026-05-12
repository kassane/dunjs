// React & Frontend Framework Compatibility Test
// Tests patterns used by React, Preact, Vue, Svelte, Solid, and common SSR frameworks
// Runs on: Node, Bun, Deno, DunJS (all backends)

let passed = 0, failed = 0;
function assert(cond, msg) {
  if (cond) { passed++; }
  else { failed++; console.log('FAIL:', msg); }
}

// ═══════════════════════════════════════════════════
// 1. Virtual DOM (React/Preact core pattern)
// ═══════════════════════════════════════════════════

function createElement(type, props, ...children) {
  return { type, props: props || {}, children: children.flat() };
}

function renderToString(vnode) {
  if (typeof vnode === 'string' || typeof vnode === 'number') return String(vnode);
  if (vnode === null || vnode === undefined) return '';
  if (typeof vnode === 'boolean') return '';
  const { type, props, children } = vnode;
  if (typeof type === 'function') return renderToString(type({ ...props, children }));
  let attrs = '';
  for (const [k, v] of Object.entries(props)) {
    if (k === 'children' || k === 'key' || k === 'ref') continue;
    if (typeof v === 'boolean') { if (v) attrs += ` ${k}`; continue; }
    if (typeof v === 'function') continue;
    attrs += ` ${k}="${String(v).replace(/"/g, '&quot;')}"`;
  }
  const selfClosing = ['br', 'hr', 'img', 'input', 'meta', 'link'];
  if (selfClosing.includes(type)) return `<${type}${attrs} />`;
  const inner = children.map(c => renderToString(c)).join('');
  return `<${type}${attrs}>${inner}</${type}>`;
}

// Test basic VDOM
const vdom = createElement('div', { class: 'app' },
  createElement('h1', null, 'Hello'),
  createElement('p', null, 'World')
);
assert(vdom.type === 'div', 'vdom type');
assert(vdom.children.length === 2, 'vdom children');

// Test renderToString
const html = renderToString(vdom);
assert(html === '<div class="app"><h1>Hello</h1><p>World</p></div>', 'renderToString basic: ' + html);

// Test functional components (React-style)
function Greeting({ name }) {
  return createElement('span', null, `Hello, ${name}!`);
}
const greetHtml = renderToString(createElement(Greeting, { name: 'React' }));
assert(greetHtml === '<span>Hello, React!</span>', 'functional component: ' + greetHtml);

// Test nested components
function Layout({ title, children }) {
  return createElement('html', null,
    createElement('head', null, createElement('title', null, title)),
    createElement('body', null, ...(children || []))
  );
}
const page = createElement(Layout, { title: 'Test' },
  createElement('h1', null, 'Page'),
  createElement('p', null, 'Content')
);
const pageHtml = renderToString(page);
assert(pageHtml.includes('<title>Test</title>'), 'nested layout title');
assert(pageHtml.includes('<h1>Page</h1>'), 'nested layout body');

// Self-closing tags
const selfClose = renderToString(createElement('br', null));
assert(selfClose === '<br />', 'self-closing tag: ' + selfClose);

const img = renderToString(createElement('img', { src: 'test.png', alt: 'test' }));
assert(img === '<img src="test.png" alt="test" />', 'img self-closing: ' + img);

// Boolean attributes
const checked = renderToString(createElement('input', { type: 'checkbox', checked: true, disabled: false }));
assert(checked.includes('checked'), 'boolean attr true');
assert(!checked.includes('disabled'), 'boolean attr false');

// ═══════════════════════════════════════════════════
// 2. VDOM Diffing (React reconciliation pattern)
// ═══════════════════════════════════════════════════

function diff(oldNode, newNode) {
  const patches = [];
  if (oldNode === null || oldNode === undefined) {
    patches.push({ type: 'CREATE', node: newNode });
  } else if (newNode === null || newNode === undefined) {
    patches.push({ type: 'REMOVE' });
  } else if (typeof oldNode !== typeof newNode) {
    patches.push({ type: 'REPLACE', node: newNode });
  } else if (typeof oldNode === 'string') {
    if (oldNode !== newNode) patches.push({ type: 'TEXT', value: newNode });
  } else if (oldNode.type !== newNode.type) {
    patches.push({ type: 'REPLACE', node: newNode });
  } else {
    const propPatches = diffProps(oldNode.props, newNode.props);
    const childPatches = diffChildren(oldNode.children, newNode.children);
    if (propPatches.length > 0 || childPatches.length > 0) {
      patches.push({ type: 'UPDATE', props: propPatches, children: childPatches });
    }
  }
  return patches;
}

function diffProps(oldProps, newProps) {
  const patches = [];
  for (const [k, v] of Object.entries(newProps)) {
    if (oldProps[k] !== v) patches.push({ type: 'SET', key: k, value: v });
  }
  for (const k of Object.keys(oldProps)) {
    if (!(k in newProps)) patches.push({ type: 'REMOVE', key: k });
  }
  return patches;
}

function diffChildren(oldChildren, newChildren) {
  const patches = [];
  const max = Math.max(oldChildren.length, newChildren.length);
  for (let i = 0; i < max; i++) {
    patches.push(...diff(oldChildren[i], newChildren[i]));
  }
  return patches;
}

const old1 = createElement('div', { class: 'a' }, 'hello');
const new1 = createElement('div', { class: 'b' }, 'hello');
const d1 = diff(old1, new1);
assert(d1.length === 1 && d1[0].type === 'UPDATE', 'diff prop change');
assert(d1[0].props.length === 1 && d1[0].props[0].value === 'b', 'diff prop value');

const old2 = createElement('div', null, 'hello');
const new2 = createElement('div', null, 'world');
const d2 = diff(old2, new2);
assert(d2.length === 1, 'diff text change');

const old3 = createElement('div', null);
const new3 = createElement('span', null);
const d3 = diff(old3, new3);
assert(d3.length === 1 && d3[0].type === 'REPLACE', 'diff type change');

// ═══════════════════════════════════════════════════
// 3. Hooks System (React Hooks pattern)
// ═══════════════════════════════════════════════════

let hookState = [];
let hookIndex = 0;

function useState(initial) {
  const idx = hookIndex++;
  if (hookState[idx] === undefined) hookState[idx] = initial;
  const setState = (val) => {
    hookState[idx] = typeof val === 'function' ? val(hookState[idx]) : val;
  };
  return [hookState[idx], setState];
}

function useEffect(fn, deps) {
  const idx = hookIndex++;
  const oldDeps = hookState[idx];
  let hasChanged = true;
  if (oldDeps) {
    hasChanged = deps.some((d, i) => d !== oldDeps[i]);
  }
  if (hasChanged) {
    fn();
    hookState[idx] = deps;
  }
}

function useMemo(fn, deps) {
  const idx = hookIndex++;
  const old = hookState[idx];
  if (old && deps.every((d, i) => d === old.deps[i])) return old.value;
  const value = fn();
  hookState[idx] = { value, deps };
  return value;
}

function useReducer(reducer, initialState) {
  const [state, setState] = useState(initialState);
  const dispatch = (action) => setState(s => reducer(s, action));
  return [state, dispatch];
}

// Test useState
hookState = []; hookIndex = 0;
const [count, setCount] = useState(0);
assert(count === 0, 'useState initial');
setCount(5);
hookIndex = 0;
const [count2] = useState(0);
assert(count2 === 5, 'useState after set');

// Test useReducer
hookState = []; hookIndex = 0;
function counterReducer(state, action) {
  switch (action.type) {
    case 'inc': return { count: state.count + 1 };
    case 'dec': return { count: state.count - 1 };
    default: return state;
  }
}
const [state, dispatch] = useReducer(counterReducer, { count: 0 });
assert(state.count === 0, 'useReducer initial');
dispatch({ type: 'inc' });
hookIndex = 0;
const [state2] = useReducer(counterReducer, { count: 0 });
assert(state2.count === 1, 'useReducer after dispatch');

// Test useMemo
hookState = []; hookIndex = 0;
let computeCount = 0;
const val = useMemo(() => { computeCount++; return 42; }, [1, 2]);
assert(val === 42, 'useMemo value');
assert(computeCount === 1, 'useMemo computed once');
hookIndex = 0;
const val2 = useMemo(() => { computeCount++; return 42; }, [1, 2]);
assert(val2 === 42, 'useMemo cached');
assert(computeCount === 1, 'useMemo not recomputed');
hookIndex = 0;
const val3 = useMemo(() => { computeCount++; return 99; }, [1, 3]);
assert(val3 === 99, 'useMemo recomputed on dep change');
assert(computeCount === 2, 'useMemo recomputed count');

// Test useEffect
hookState = []; hookIndex = 0;
let effectRan = 0;
useState(0); // idx 0
useEffect(() => { effectRan++; }, [1]);
assert(effectRan === 1, 'useEffect ran');
hookIndex = 0;
useState(0);
useEffect(() => { effectRan++; }, [1]);
assert(effectRan === 1, 'useEffect skipped same deps');
hookIndex = 0;
useState(0);
useEffect(() => { effectRan++; }, [2]);
assert(effectRan === 2, 'useEffect ran on dep change');

// ═══════════════════════════════════════════════════
// 4. Reactive System (Vue/Solid pattern)
// ═══════════════════════════════════════════════════

function reactive(obj) {
  const subscribers = new Map();
  return new Proxy(obj, {
    get(target, key) {
      return target[key];
    },
    set(target, key, value) {
      target[key] = value;
      const subs = subscribers.get(key);
      if (subs) subs.forEach(fn => fn(value));
      return true;
    }
  });
}

function watch(obj, key, fn) {
  // Simple watcher (Vue-style)
  const origSet = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(obj), 'set');
  // For proxy-based reactivity, we track via a side map
  if (!obj.__watchers) obj.__watchers = new Map();
  if (!obj.__watchers.has(key)) obj.__watchers.set(key, []);
  obj.__watchers.get(key).push(fn);
}

// Test Proxy reactivity
const state3 = reactive({ count: 0, name: 'Vue' });
assert(state3.count === 0, 'reactive get');
state3.count = 10;
assert(state3.count === 10, 'reactive set');
state3.name = 'Solid';
assert(state3.name === 'Solid', 'reactive set string');

// ═══════════════════════════════════════════════════
// 5. Signal System (Solid/Preact Signals pattern)
// ═══════════════════════════════════════════════════

function createSignal(initial) {
  let value = initial;
  const listeners = new Set();
  const get = () => value;
  const set = (newVal) => {
    if (typeof newVal === 'function') newVal = newVal(value);
    if (newVal !== value) {
      value = newVal;
      listeners.forEach(fn => fn(value));
    }
  };
  get.subscribe = (fn) => { listeners.add(fn); return () => listeners.delete(fn); };
  return [get, set];
}

function createEffect(fn) {
  fn();
}

function createMemo(fn, sources) {
  let cached;
  let dirty = true;
  sources.forEach(s => {
    if (s.subscribe) s.subscribe(() => { dirty = true; });
  });
  return () => {
    if (dirty) { cached = fn(); dirty = false; }
    return cached;
  };
}

// Test signals
const [count3, setCount3] = createSignal(0);
assert(count3() === 0, 'signal initial');
setCount3(5);
assert(count3() === 5, 'signal set');
setCount3(n => n + 1);
assert(count3() === 6, 'signal updater');

// Test signal subscription
let notified = 0;
const unsub = count3.subscribe(() => notified++);
setCount3(10);
assert(notified === 1, 'signal subscription notified');
setCount3(10); // same value, no notify
assert(notified === 1, 'signal no notify same value');
unsub();
setCount3(20);
assert(notified === 1, 'signal unsubscribed');

// Test createMemo
const [a, setA] = createSignal(2);
const [b, setB] = createSignal(3);
const sum = createMemo(() => a() + b(), [a, b]);
assert(sum() === 5, 'memo initial');
setA(10);
assert(sum() === 13, 'memo after dep change');

// ═══════════════════════════════════════════════════
// 6. JSX Transform (Babel/SWC output pattern)
// ═══════════════════════════════════════════════════

// This is what JSX compiles to:
const h = createElement;

// <div className="app"><h1>Hello</h1><ul>{items.map(i => <li key={i}>{i}</li>)}</ul></div>
const items = ['React', 'Vue', 'Svelte'];
const jsx = h('div', { className: 'app' },
  h('h1', null, 'Hello'),
  h('ul', null, ...items.map(i => h('li', { key: i }, i)))
);
const jsxHtml = renderToString(jsx);
assert(jsxHtml.includes('<li>React</li>'), 'JSX list item 1');
assert(jsxHtml.includes('<li>Vue</li>'), 'JSX list item 2');
assert(jsxHtml.includes('<li>Svelte</li>'), 'JSX list item 3');

// Fragment (React.Fragment)
function Fragment({ children }) {
  return createElement('', null, ...(children || []));
}
const frag = h(Fragment, null, h('span', null, 'a'), h('span', null, 'b'));
// Fragments render children directly — pass children in props like renderToString does
const fragChildren = frag.type({ ...frag.props, children: frag.children });
assert(fragChildren.children.length === 2, 'fragment children');

// ═══════════════════════════════════════════════════
// 7. Context System (React Context pattern)
// ═══════════════════════════════════════════════════

function createContext(defaultValue) {
  let current = defaultValue;
  return {
    Provider: ({ value, children }) => {
      current = value;
      return createElement('', null, ...children);
    },
    useContext: () => current,
  };
}

const ThemeContext = createContext('light');
assert(ThemeContext.useContext() === 'light', 'context default');

// Simulate providing a value
const provided = ThemeContext.Provider({
  value: 'dark',
  children: [createElement('div', null, 'child')]
});
assert(ThemeContext.useContext() === 'dark', 'context provided');

// ═══════════════════════════════════════════════════
// 8. Event Emitter (React synthetic events / EventTarget)
// ═══════════════════════════════════════════════════

class EventEmitter {
  constructor() { this._events = new Map(); }
  on(event, fn) {
    if (!this._events.has(event)) this._events.set(event, []);
    this._events.get(event).push(fn);
    return this;
  }
  off(event, fn) {
    const fns = this._events.get(event);
    if (fns) this._events.set(event, fns.filter(f => f !== fn));
    return this;
  }
  emit(event, ...args) {
    const fns = this._events.get(event) || [];
    fns.forEach(fn => fn(...args));
    return fns.length > 0;
  }
  once(event, fn) {
    const wrapped = (...args) => { this.off(event, wrapped); fn(...args); };
    return this.on(event, wrapped);
  }
}

const ee = new EventEmitter();
let msgs = [];
ee.on('msg', (m) => msgs.push(m));
ee.emit('msg', 'hello');
ee.emit('msg', 'world');
assert(msgs.length === 2, 'event emitter on');
assert(msgs[0] === 'hello' && msgs[1] === 'world', 'event emitter values');

let onceCalled = 0;
ee.once('single', () => onceCalled++);
ee.emit('single');
ee.emit('single');
assert(onceCalled === 1, 'event emitter once');

// ═══════════════════════════════════════════════════
// 9. Store Pattern (Redux/Zustand)
// ═══════════════════════════════════════════════════

function createStore(reducer, initialState) {
  let state = initialState;
  const listeners = new Set();
  return {
    getState: () => state,
    dispatch: (action) => {
      state = reducer(state, action);
      listeners.forEach(fn => fn(state));
    },
    subscribe: (fn) => {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
  };
}

// Middleware pattern (Redux-style)
function applyMiddleware(...middlewares) {
  return (createStore) => (reducer, initialState) => {
    const store = createStore(reducer, initialState);
    let dispatch = store.dispatch;
    const api = { getState: store.getState, dispatch: (a) => dispatch(a) };
    const chain = middlewares.map(mw => mw(api));
    dispatch = chain.reduceRight((next, mw) => mw(next), store.dispatch);
    return { ...store, dispatch };
  };
}

const todoReducer = (state, action) => {
  switch (action.type) {
    case 'ADD': return { ...state, todos: [...state.todos, action.text] };
    case 'REMOVE': return { ...state, todos: state.todos.filter((_, i) => i !== action.index) };
    case 'CLEAR': return { ...state, todos: [] };
    default: return state;
  }
};

const store = createStore(todoReducer, { todos: [] });
store.dispatch({ type: 'ADD', text: 'Learn React' });
store.dispatch({ type: 'ADD', text: 'Learn Vue' });
assert(store.getState().todos.length === 2, 'store add');
store.dispatch({ type: 'REMOVE', index: 0 });
assert(store.getState().todos.length === 1, 'store remove');
assert(store.getState().todos[0] === 'Learn Vue', 'store remove correct item');

// Test middleware
let loggedActions = [];
const logger = (api) => (next) => (action) => {
  loggedActions.push(action.type);
  return next(action);
};
const enhanced = applyMiddleware(logger)(createStore);
const store2 = enhanced(todoReducer, { todos: [] });
store2.dispatch({ type: 'ADD', text: 'Test' });
assert(loggedActions.length === 1, 'middleware logged');
assert(loggedActions[0] === 'ADD', 'middleware logged action');

// ═══════════════════════════════════════════════════
// 10. Router Pattern (React Router / Vue Router)
// ═══════════════════════════════════════════════════

function createRouter(routes) {
  return {
    match(path) {
      for (const route of routes) {
        const params = matchPath(route.path, path);
        if (params !== null) return { ...route, params };
      }
      return null;
    }
  };
}

function matchPath(pattern, path) {
  const patternParts = pattern.split('/').filter(Boolean);
  const pathParts = path.split('/').filter(Boolean);
  if (patternParts.length !== pathParts.length) return null;
  const params = {};
  for (let i = 0; i < patternParts.length; i++) {
    if (patternParts[i].startsWith(':')) {
      params[patternParts[i].slice(1)] = pathParts[i];
    } else if (patternParts[i] !== pathParts[i]) {
      return null;
    }
  }
  return params;
}

const router = createRouter([
  { path: '/', component: 'Home' },
  { path: '/about', component: 'About' },
  { path: '/user/:id', component: 'User' },
  { path: '/post/:id/comment/:commentId', component: 'Comment' },
]);

assert(router.match('/').component === 'Home', 'router root');
assert(router.match('/about').component === 'About', 'router about');
const userMatch = router.match('/user/42');
assert(userMatch.component === 'User', 'router user');
assert(userMatch.params.id === '42', 'router user param');
const commentMatch = router.match('/post/1/comment/99');
assert(commentMatch.params.id === '1', 'router nested param 1');
assert(commentMatch.params.commentId === '99', 'router nested param 2');
assert(router.match('/nonexistent') === null, 'router no match');

// ═══════════════════════════════════════════════════
// 11. Template Literals / Tagged Templates (Lit, htm)
// ═══════════════════════════════════════════════════

function htmlTag(strings, ...values) {
  let result = '';
  strings.forEach((str, i) => {
    result += str;
    if (i < values.length) {
      const v = values[i];
      if (Array.isArray(v)) result += v.join('');
      else if (typeof v === 'object' && v !== null) result += JSON.stringify(v);
      else result += String(v ?? '');
    }
  });
  return result;
}

const name = 'World';
const list = ['a', 'b', 'c'];
const tpl = htmlTag`<h1>Hello ${name}</h1><ul>${list.map(i => htmlTag`<li>${i}</li>`)}</ul>`;
assert(tpl.includes('Hello World'), 'tagged template value');
assert(tpl.includes('<li>a</li>'), 'tagged template list');

// ═══════════════════════════════════════════════════
// 12. CSS-in-JS Pattern (styled-components, emotion)
// ═══════════════════════════════════════════════════

let styleSheet = new Map();
let styleCounter = 0;

function css(strings, ...values) {
  let result = '';
  strings.forEach((str, i) => {
    result += str + (i < values.length ? values[i] : '');
  });
  const hash = 'css-' + (styleCounter++);
  styleSheet.set(hash, result.trim());
  return hash;
}

function styled(tag) {
  return (strings, ...values) => {
    const className = css(strings, ...values);
    return (props) => createElement(tag, { ...props, class: className }, ...(props.children || []));
  };
}

const buttonClass = css`
  background: blue;
  color: white;
  padding: 8px 16px;
`;
assert(buttonClass.startsWith('css-'), 'css class generated');
assert(styleSheet.get(buttonClass).includes('background: blue'), 'css content');

const Button = styled('button')`
  background: red;
  border-radius: 4px;
`;
const btnHtml = renderToString(Button({ children: ['Click'] }));
assert(btnHtml.includes('<button'), 'styled component renders');
assert(btnHtml.includes('class="css-'), 'styled component has class');

// ═══════════════════════════════════════════════════
// 13. Immutable State Updates (Immer pattern)
// ═══════════════════════════════════════════════════

function produce(base, recipe) {
  const draft = JSON.parse(JSON.stringify(base));
  recipe(draft);
  return draft;
}

const baseState = { users: [{ name: 'Alice', age: 30 }], settings: { theme: 'light' } };
const nextState = produce(baseState, draft => {
  draft.users.push({ name: 'Bob', age: 25 });
  draft.settings.theme = 'dark';
});
assert(nextState.users.length === 2, 'produce add');
assert(nextState.settings.theme === 'dark', 'produce modify');
assert(baseState.users.length === 1, 'produce immutable original');
assert(baseState.settings.theme === 'light', 'produce immutable original 2');

// ═══════════════════════════════════════════════════
// 14. Async Patterns (React Suspense / data fetching)
// ═══════════════════════════════════════════════════

function createResource(fetcher) {
  let status = 'pending';
  let result;
  let error;
  const promise = fetcher().then(
    r => { status = 'success'; result = r; },
    e => { status = 'error'; error = e; }
  );
  return {
    read() {
      if (status === 'pending') throw promise;
      if (status === 'error') throw error;
      return result;
    },
    status: () => status,
  };
}

const resource = createResource(() => Promise.resolve({ data: 42 }));
assert(resource.status() === 'pending', 'resource initial pending');

// ═══════════════════════════════════════════════════
// 15. Form Validation (React Hook Form / Formik)
// ═══════════════════════════════════════════════════

function createForm(schema) {
  const values = {};
  const errors = {};
  const touched = {};

  return {
    register(name, rules) {
      values[name] = '';
      return {
        name,
        onChange: (val) => {
          values[name] = val;
          touched[name] = true;
          if (rules) {
            if (rules.required && !val) errors[name] = 'Required';
            else if (rules.minLength && val.length < rules.minLength) errors[name] = `Min ${rules.minLength} chars`;
            else if (rules.pattern && !rules.pattern.test(val)) errors[name] = 'Invalid format';
            else delete errors[name];
          }
        },
      };
    },
    getValues: () => ({ ...values }),
    getErrors: () => ({ ...errors }),
    isValid: () => Object.keys(errors).length === 0,
  };
}

const form = createForm();
const email = form.register('email', { required: true, pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/ });
const password = form.register('password', { required: true, minLength: 8 });

email.onChange('');
assert(!form.isValid(), 'form invalid empty');
assert(form.getErrors().email === 'Required', 'form required error');

email.onChange('bad');
assert(form.getErrors().email === 'Invalid format', 'form pattern error');

email.onChange('test@example.com');
password.onChange('short');
assert(form.getErrors().password === 'Min 8 chars', 'form minLength error');

password.onChange('longpassword');
assert(form.isValid(), 'form valid');

// ═══════════════════════════════════════════════════
// 16. Scheduler (React Concurrent Mode pattern)
// ═══════════════════════════════════════════════════

function createScheduler() {
  const tasks = { immediate: [], normal: [], idle: [] };
  return {
    schedule(priority, fn) {
      tasks[priority].push(fn);
    },
    flush() {
      const results = [];
      for (const p of ['immediate', 'normal', 'idle']) {
        while (tasks[p].length > 0) {
          results.push(tasks[p].shift()());
        }
      }
      return results;
    },
  };
}

const scheduler = createScheduler();
const order = [];
scheduler.schedule('normal', () => order.push('B'));
scheduler.schedule('immediate', () => order.push('A'));
scheduler.schedule('idle', () => order.push('C'));
scheduler.flush();
assert(order.join(',') === 'A,B,C', 'scheduler priority order: ' + order.join(','));

// ═══════════════════════════════════════════════════
// 17. SSR Streaming Pattern
// ═══════════════════════════════════════════════════

function renderToChunks(vnode, chunkSize) {
  const full = renderToString(vnode);
  const chunks = [];
  for (let i = 0; i < full.length; i += chunkSize) {
    chunks.push(full.slice(i, i + chunkSize));
  }
  return chunks;
}

const bigVdom = createElement('div', null,
  ...Array.from({ length: 100 }, (_, i) => createElement('p', null, `Item ${i}`))
);
const chunks = renderToChunks(bigVdom, 200);
assert(chunks.length > 1, 'SSR chunking produced multiple chunks');
assert(chunks.join('') === renderToString(bigVdom), 'SSR chunks reassemble correctly');

// ═══════════════════════════════════════════════════
// 18. Key-based Reconciliation (React list keys)
// ═══════════════════════════════════════════════════

function reconcileList(oldList, newList, keyFn) {
  const oldMap = new Map(oldList.map((item, i) => [keyFn(item), { item, index: i }]));
  const ops = [];
  const used = new Set();

  newList.forEach((item, newIdx) => {
    const key = keyFn(item);
    if (oldMap.has(key)) {
      const old = oldMap.get(key);
      used.add(key);
      if (old.index !== newIdx) ops.push({ type: 'MOVE', key, from: old.index, to: newIdx });
      if (JSON.stringify(old.item) !== JSON.stringify(item)) ops.push({ type: 'UPDATE', key, item });
    } else {
      ops.push({ type: 'INSERT', key, item, index: newIdx });
    }
  });

  oldList.forEach(item => {
    const key = keyFn(item);
    if (!used.has(key)) ops.push({ type: 'DELETE', key });
  });

  return ops;
}

const oldItems = [{ id: 1, text: 'a' }, { id: 2, text: 'b' }, { id: 3, text: 'c' }];
const newItems = [{ id: 2, text: 'b' }, { id: 3, text: 'c!' }, { id: 4, text: 'd' }];
const ops = reconcileList(oldItems, newItems, x => x.id);
assert(ops.some(o => o.type === 'DELETE' && o.key === 1), 'reconcile delete');
assert(ops.some(o => o.type === 'INSERT' && o.key === 4), 'reconcile insert');
assert(ops.some(o => o.type === 'UPDATE' && o.key === 3), 'reconcile update');

// ═══════════════════════════════════════════════════
// Summary
// ═══════════════════════════════════════════════════

console.log(`\n=== React/Framework Compat Test ===`);
console.log(`${passed + failed} checks completed`);
console.log(`${passed} passed, ${failed} failed`);
console.log(`RESULT: ${failed === 0 ? 'ALL PASSED' : 'SOME FAILED'}`);
