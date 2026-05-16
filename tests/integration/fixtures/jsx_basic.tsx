// JSX/TSX support — the source is .tsx so it goes through both the TS
// stripper AND the JSX transform. We assert on the resulting React
// element tree structure since DunJS's React shim returns plain
// objects with { type, props, children }.

function check(name: string, cond: boolean) {
  (globalThis as any).__t++;
  if (cond) (globalThis as any).__p++;
  else console.log('FAIL:', name);
}
(globalThis as any).__p = 0;
(globalThis as any).__t = 0;

// --- DOM tag ---
const div = <div className="hello">world</div>;
check('lowercase tag is string', div.type === 'div');
check('attr is normalized prop', div.props.className === 'hello');
check('children flattened', div.children[0] === 'world');

// --- Component (uppercase) ---
function Foo(props: any) { return props; }
const c = <Foo name="alice" />;
check('component tag is fn ref', c.type === Foo);
check('component prop', c.props.name === 'alice');

// --- Expression child ---
const x = 42;
const exprChild = <p>n={x}</p>;
check('expr child preserved', exprChild.children[1] === 42);

// --- Self-closing + numeric attr ---
const img = <img src="logo.png" width={100} />;
check('numeric attr', img.props.width === 100);

// --- Nested ---
const nested = <ul><li>a</li><li>b</li></ul>;
check('nested type', nested.type === 'ul');
check('nested children count', nested.children.length === 2);
check('nested inner tag', nested.children[0].type === 'li');

// --- Fragment ---
const frag = <>{x}<span>y</span></>;
check('fragment type', typeof frag.type === 'symbol');
check('fragment children', frag.children.length === 2);

// --- Member-expression tag ---
const ns: any = { Header: (p: any) => p };
const h = <ns.Header title="x" />;
check('member tag', h.type === ns.Header);

// --- Spread props ---
const baseProps = { id: 'main', role: 'banner' };
const sp = <header {...baseProps} className="top" />;
check('spread id', sp.props.id === 'main');
check('spread role', sp.props.role === 'banner');
check('spread + named', sp.props.className === 'top');

// --- Division still works (regex-vs-divide ambiguity around `<`) ---
const half = 10 / 2;
check('division still arithmetic', half === 5);
const cond = (a: number, b: number) => a < b ? 'l' : 'r';
check('less-than still comparison', cond(1, 2) === 'l');

console.log('jsx_basic:', (globalThis as any).__p + '/' + (globalThis as any).__t, 'checks passed');
if ((globalThis as any).__p === (globalThis as any).__t) console.log('ALL CHECKS PASSED');
