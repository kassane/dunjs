// ts-advanced.ts — TypeScript 5.x Advanced Features Showcase
// Unique patterns: branded types, template literal type magic,
// builder pattern, type-safe state machine, deep mapped types,
// variadic tuples, satisfies, const type params, recursive types,
// exhaustive discriminated unions, type-level path extraction.
// No top-level await — runs on DunJS, Node, Bun, Deno.

// ─── §1. BRANDED / NOMINAL TYPES ──────────────────────────────────────────
type Brand<T, B extends string> = T & { readonly __brand: B };
type UserId   = Brand<string,  "UserId">;
type OrderId  = Brand<number,  "OrderId">;
type Cents    = Brand<number,  "Cents">;
type Seconds  = Brand<number,  "Seconds">;

const uid   = (s: string): UserId  => s as UserId;
const oid   = (n: number): OrderId => n as OrderId;
const cents = (n: number): Cents   => n as Cents;

const u1 = uid("user-42");
const o1 = oid(1001);
const price = cents(4999);

console.log("=== §1 Branded Types ===");
console.log(u1, o1, price);  // "user-42" 1001 4999

// ─── §2. TEMPLATE LITERAL TYPE MACHINE ────────────────────────────────────
type EventName<T extends string> = `on${Capitalize<T>}`;
type CRUD<E extends string> =
  | `create${Capitalize<E>}` | `read${Capitalize<E>}`
  | `update${Capitalize<E>}` | `delete${Capitalize<E>}`;

type UserOps    = CRUD<"user">;
type ProductOps = CRUD<"product">;

function makeHandler<T extends string>(event: EventName<T>, cb: () => void) {
  // runtime: just call it
  cb();
  return event;
}

console.log("\n=== §2 Template Literal Events ===");
const fired: string[] = [];
makeHandler("onClick", () => fired.push("click"));
makeHandler("onSubmit", () => fired.push("submit"));
makeHandler("onChange", () => fired.push("change"));
console.log("fired:", fired.join(", "));  // click, submit, change

// ─── §3. DEEP READONLY + DEEP PARTIAL ─────────────────────────────────────
type DeepReadonly<T> =
  T extends (infer U)[]     ? ReadonlyArray<DeepReadonly<U>> :
  T extends object          ? { readonly [K in keyof T]: DeepReadonly<T[K]> } :
  T;

type DeepPartial<T> =
  T extends object ? { [K in keyof T]?: DeepPartial<T[K]> } : T;

interface AppConfig {
  db:     { host: string; port: number; ssl: boolean };
  cache:  { ttl: number; maxSize: number };
  feature: { darkMode: boolean; beta: boolean };
}

const cfg: DeepReadonly<AppConfig> = {
  db:      { host: "localhost", port: 5432, ssl: true },
  cache:   { ttl: 300, maxSize: 1000 },
  feature: { darkMode: false, beta: true },
};

function merge<T extends object>(base: DeepReadonly<T>, patch: DeepPartial<T>): T {
  return { ...base as T, ...patch as Partial<T> };
}

const patched = merge(cfg, { cache: { ttl: 600 } });

console.log("\n=== §3 Deep Readonly + Partial ===");
console.log("host:", cfg.db.host);          // localhost
console.log("ttl patched:", patched.cache.ttl);  // 600
console.log("ssl intact:", patched.db.ssl); // true

// ─── §4. TYPE-SAFE QUERY BUILDER ──────────────────────────────────────────
type QueryHas<T extends string> = { readonly [K in T]: true };

class QB<State extends object = {}> {
  private clauses: string[] = [];
  private _params: unknown[] = [];

  select<F extends string>(...fields: F[]): QB<State & QueryHas<"select">> {
    this.clauses.push(`SELECT ${fields.join(", ")}`);
    return this as any;
  }
  from<T extends string>(table: T): QB<State & QueryHas<"from">> {
    this.clauses.push(`FROM ${table}`);
    return this as any;
  }
  where(cond: string, ...values: unknown[]): QB<State & QueryHas<"where">> {
    this.clauses.push(`WHERE ${cond}`);
    this._params.push(...values);
    return this as any;
  }
  orderBy(col: string, dir: "ASC" | "DESC" = "ASC"): QB<State> {
    this.clauses.push(`ORDER BY ${col} ${dir}`);
    return this;
  }
  limit(n: number): QB<State & QueryHas<"limit">> {
    this.clauses.push(`LIMIT ${n}`);
    return this as any;
  }
  // build() is only callable when both select and from are satisfied
  build(this: QB<State & QueryHas<"select"> & QueryHas<"from">>): { sql: string; params: unknown[] } {
    return { sql: this.clauses.join(" "), params: this._params };
  }
}

const q = new QB()
  .select("id", "name", "email")
  .from("users")
  .where("active = ? AND age > ?", true, 18)
  .orderBy("name")
  .limit(10)
  .build();

console.log("\n=== §4 Type-Safe Query Builder ===");
console.log("sql:", q.sql);
console.log("params:", JSON.stringify(q.params));

// ─── §5. EXHAUSTIVE DISCRIMINATED UNIONS ──────────────────────────────────
type Expr =
  | { tag: "num";   value: number }
  | { tag: "str";   value: string }
  | { tag: "bool";  value: boolean }
  | { tag: "null" }
  | { tag: "array"; items: Expr[] }
  | { tag: "obj";   fields: Record<string, Expr> };

function evalExpr(e: Expr): unknown {
  switch (e.tag) {
    case "num":   return e.value;
    case "str":   return e.value;
    case "bool":  return e.value;
    case "null":  return null;
    case "array": return e.items.map(evalExpr);
    case "obj": {
      const r: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(e.fields)) r[k] = evalExpr(v);
      return r;
    }
    default: {
      const _: never = e;
      throw new Error("unreachable");
    }
  }
}

const ast: Expr = {
  tag: "obj",
  fields: {
    id:     { tag: "num", value: 42 },
    name:   { tag: "str", value: "Alice" },
    active: { tag: "bool", value: true },
    tags:   { tag: "array", items: [
      { tag: "str", value: "admin" },
      { tag: "str", value: "beta" },
    ]},
  },
};

console.log("\n=== §5 Exhaustive Expression Evaluator ===");
const evaled = evalExpr(ast) as Record<string, unknown>;
console.log("id:", evaled.id);
console.log("name:", evaled.name);
console.log("tags:", JSON.stringify(evaled.tags));

// ─── §6. CONDITIONAL TYPES + INFER ────────────────────────────────────────
type UnwrapPromise<T> = T extends Promise<infer U> ? UnwrapPromise<U> : T;
type Flatten<T>       = T extends (infer U)[] ? Flatten<U> : T;
type Keys<T>          = T extends object ? keyof T : never;
type ValueOf<T>       = T extends Record<string, infer V> ? V : never;

type Overloaded<T> =
  T extends {
    (...a: infer A1): infer R1;
    (...a: infer A2): infer R2;
  } ? [A1, R1] | [A2, R2] : never;

function pipe<A, B, C>(a: A, f: (x: A) => B, g: (x: B) => C): C {
  return g(f(a));
}

function compose<A, B, C>(f: (x: A) => B, g: (x: B) => C): (x: A) => C {
  return x => g(f(x));
}

const double     = (n: number): number => n * 2;
const stringify  = (n: number): string => `n=${n}`;
const emphasize  = (s: string): string => `[${s}!]`;

const transform  = compose(compose(double, stringify), emphasize);

console.log("\n=== §6 Conditional Types + Compose ===");
console.log(pipe(21, double, stringify));   // n=42
console.log(transform(5));                 // [n=10!]

// ─── §7. MAPPED TYPE KEY REMAPPING ────────────────────────────────────────
type Getters<T> = {
  [K in keyof T as `get${Capitalize<string & K>}`]: () => T[K];
};
type Setters<T> = {
  [K in keyof T as `set${Capitalize<string & K>}`]: (v: T[K]) => void;
};
type Accessors<T> = T & Getters<T> & Setters<T>;

function makeAccessors<T extends Record<string, unknown>>(obj: T): Accessors<T> {
  const proxy = { ...obj } as Record<string, unknown>;
  for (const key of Object.keys(obj)) {
    const cap = key[0].toUpperCase() + key.slice(1);
    proxy[`get${cap}`] = () => proxy[key];
    proxy[`set${cap}`] = (v: unknown) => { proxy[key] = v; };
  }
  return proxy as Accessors<T>;
}

interface User { name: string; age: number; role: string }

const user = makeAccessors<User>({ name: "Bob", age: 25, role: "admin" });

console.log("\n=== §7 Mapped Key Remapping (Accessors) ===");
console.log((user as any).getName());        // Bob
(user as any).setAge(26);
console.log((user as any).getAge());         // 26
console.log((user as any).getRole());        // admin

// ─── §8. VARIADIC TUPLE TYPES ─────────────────────────────────────────────
type Concat<A extends unknown[], B extends unknown[]> = [...A, ...B];
type Head<T extends unknown[]>  = T extends [infer H, ...unknown[]] ? H : never;
type Tail<T extends unknown[]>  = T extends [unknown, ...infer T]   ? T : never;
type Last<T extends unknown[]>  = T extends [...unknown[], infer L]  ? L : never;

function tupleConcat<A extends unknown[], B extends unknown[]>(a: A, b: B): [...A, ...B] {
  return [...a, ...b] as any;
}

function zipWith<A, B, C>(a: A[], b: B[], f: (x: A, y: B) => C): C[] {
  return a.map((x, i) => f(x, b[i]));
}

const nums   = tupleConcat([1, 2, 3] as const, [4, 5] as const);
const zipped = zipWith(["a","b","c"], [1,2,3], (s,n) => `${s}:${n}`);

console.log("\n=== §8 Variadic Tuples ===");
console.log("concat:", nums.join(","));       // 1,2,3,4,5
console.log("zipped:", zipped.join(" "));     // a:1 b:2 c:3

// ─── §9. SATISFIES OPERATOR ───────────────────────────────────────────────
type ColorSpec = string | [number, number, number];

const palette = {
  red:    [255, 0, 0]   ,
  green:  "#00ff00"     ,
  blue:   [0, 0, 255]   ,
  alpha:  [255,255,255] ,
} satisfies Record<string, ColorSpec>;

// palette.red is inferred as [number, number, number], not ColorSpec
// palette.green is inferred as string, not ColorSpec
const redHex = `rgb(${palette.red.join(",")})`;
const g      = palette.green.toUpperCase();

console.log("\n=== §9 satisfies operator ===");
console.log("red:", redHex);   // rgb(255,0,0)
console.log("green:", g);      // #00FF00

// ─── §10. TYPE-SAFE STATE MACHINE ─────────────────────────────────────────
type FSMState  = "idle" | "pending" | "fulfilled" | "rejected";
type FSMEvent  = "fetch" | "resolve" | "reject" | "reset";

type Transitions = {
  idle:      { fetch:   "pending"   };
  pending:   { resolve: "fulfilled"; reject: "rejected" };
  fulfilled: { reset:   "idle"      };
  rejected:  { reset:   "idle";     fetch: "pending" };
};

class FSM<S extends FSMState = "idle"> {
  private _state: FSMState;
  private _log: FSMState[];

  constructor(initial: FSMState = "idle") {
    this._state = initial;
    this._log   = [initial];
  }

  get state(): FSMState { return this._state; }
  get log():   FSMState[] { return [...this._log]; }

  send(event: FSMEvent): boolean {
    const table: Partial<Record<FSMState, Partial<Record<FSMEvent, FSMState>>>> = {
      idle:      { fetch:   "pending"   },
      pending:   { resolve: "fulfilled", reject: "rejected" },
      fulfilled: { reset:   "idle"      },
      rejected:  { reset:   "idle",     fetch: "pending" },
    };
    const next = table[this._state]?.[event];
    if (!next) return false;
    this._state = next;
    this._log.push(next);
    return true;
  }
}

const fsm = new FSM();
console.log("\n=== §10 Type-Safe State Machine ===");
console.log("state:", fsm.state);           // idle
fsm.send("fetch");
console.log("after fetch:", fsm.state);     // pending
fsm.send("resolve");
console.log("after resolve:", fsm.state);   // fulfilled
fsm.send("reset");
console.log("after reset:", fsm.state);     // idle
fsm.send("fetch");
fsm.send("reject");
fsm.send("fetch");   // can re-fetch from rejected
console.log("log:", fsm.log.join(" -> ")); // idle -> pending -> fulfilled -> idle -> pending -> rejected -> pending

// ─── §11. RECURSIVE JSON PATH EXTRACTION ──────────────────────────────────
type JSONPrimitive  = string | number | boolean | null;
type JSONObject     = { [k: string]: JSONVal };
type JSONArray      = JSONVal[];
type JSONVal        = JSONPrimitive | JSONObject | JSONArray;

// Get nested value by dot-path
function getPath(obj: JSONVal, path: string): JSONVal | undefined {
  const parts = path.split(".");
  let cur: JSONVal | undefined = obj;
  for (const p of parts) {
    if (cur === null || typeof cur !== "object" || Array.isArray(cur)) return undefined;
    cur = (cur as JSONObject)[p];
  }
  return cur;
}

function setPaths(obj: JSONObject, paths: string[]): Record<string, JSONVal | undefined> {
  return Object.fromEntries(paths.map(p => [p, getPath(obj, p)]));
}

const data: JSONObject = {
  user: { name: "Carol", address: { city: "SF", zip: "94105" } },
  meta: { version: 3, tags: ["ts", "dun"] },
};

console.log("\n=== §11 JSON Path Extraction ===");
const extracted = setPaths(data, ["user.name", "user.address.city", "meta.version", "user.address.zip"]);
for (const [k, v] of Object.entries(extracted)) console.log(`  ${k}: ${v}`);

// ─── §12. CONST TYPE PARAMS + INFERENCE ───────────────────────────────────
function makeTag<const T extends string>(tag: T): `<${T}>` {
  return `<${tag}>` as `<${T}>`;
}

function literal<const T>(v: T): T { return v; }

const tagDiv  = makeTag("div");    // type: "<div>"
const tagSpan = makeTag("span");   // type: "<span>"
const three   = literal(3 as const);

console.log("\n=== §12 Const Type Parameters ===");
console.log(tagDiv, tagSpan, three);  // <div> <span> 3

// ─── §13. SCHEMA VALIDATOR (type-safe parse) ──────────────────────────────
type Schema<T> = {
  [K in keyof T]: (v: unknown) => T[K];
};

function createValidator<T>(schema: Schema<T>) {
  return (raw: unknown): T => {
    if (typeof raw !== "object" || raw === null) throw new Error("not an object");
    const out = {} as T;
    for (const key of Object.keys(schema) as (keyof T)[]) {
      out[key] = schema[key]((raw as Record<string, unknown>)[key as string]);
    }
    return out;
  };
}

const parseUser = createValidator({
  id:    (v: unknown) => { if (typeof v !== "number") throw new Error("id must be number"); return v; },
  name:  (v: unknown) => { if (typeof v !== "string") throw new Error("name must be string"); return v; },
  email: (v: unknown) => { if (typeof v !== "string" || !v.includes("@")) throw new Error("bad email"); return v; },
  age:   (v: unknown) => {
    const n = Number(v);
    if (!Number.isFinite(n) || n < 0 || n > 150) throw new Error("bad age");
    return n;
  },
});

console.log("\n=== §13 Schema Validator ===");
try {
  const valid = parseUser({ id: 7, name: "Dan", email: "dan@example.com", age: "32" });
  console.log("valid:", JSON.stringify(valid));
} catch (e: unknown) {
  console.log("unexpected error:", (e as Error).message);
}
try {
  parseUser({ id: "bad", name: "Eve", email: "eve@x.com", age: 25 });
  console.log("should have thrown");
} catch (e: unknown) {
  console.log("caught:", (e as Error).message);  // id must be number
}

// ─── §14. HIGHER-KINDED TYPES SIMULATION ──────────────────────────────────
interface Functor<F extends string> {
  map<A, B>(fa: { __kind: F; value: A }, f: (a: A) => B): { __kind: F; value: B };
}

type Box<T> = { __kind: "Box"; value: T };
const Box = {
  of:  <T>(value: T): Box<T> => ({ __kind: "Box", value }),
  map: <A, B>(b: Box<A>, f: (a: A) => B): Box<B> => Box.of(f(b.value)),
  chain: <A, B>(b: Box<A>, f: (a: A) => Box<B>): Box<B> => f(b.value),
};

type Result<T, E = Error> = { ok: true; value: T } | { ok: false; err: E };
const Ok  = <T>(value: T): Result<T, never>  => ({ ok: true,  value });
const Err = <E>(err: E):   Result<never, E>  => ({ ok: false, err });

function resultMap<T, U, E>(r: Result<T, E>, f: (v: T) => U): Result<U, E> {
  return r.ok ? Ok(f(r.value)) : r;
}
function resultChain<T, U, E>(r: Result<T, E>, f: (v: T) => Result<U, E>): Result<U, E> {
  return r.ok ? f(r.value) : r;
}

const computation = resultChain(
  resultMap(Ok(10), x => x * 3),
  n => n > 20 ? Ok(`big: ${n}`) : Err(new Error("too small"))
);

console.log("\n=== §14 Higher-Kinded Simulation (Box + Result) ===");
const boxResult = Box.chain(Box.of(5), n => Box.map(Box.of(n * 2), x => x + 1));
console.log("Box:", boxResult.value);   // 11
console.log("Result ok:", computation.ok);
if (computation.ok) console.log("Result value:", computation.value); // big: 30

// ─── §15. TEMPLATE LITERAL SQL TAG ────────────────────────────────────────
type SQLTag = { sql: string; values: unknown[] };

function sql(strings: TemplateStringsArray, ...values: unknown[]): SQLTag {
  const parts: string[] = [];
  strings.forEach((s, i) => {
    parts.push(s);
    if (i < values.length) parts.push("?");
  });
  return { sql: parts.join(""), values };
}

const minAge = 21;
const role   = "admin";
const query  = sql`SELECT * FROM users WHERE age > ${minAge} AND role = ${role} LIMIT ${10}`;

console.log("\n=== §15 Tagged Template SQL ===");
console.log("sql:   ", query.sql);
console.log("values:", JSON.stringify(query.values));

// ─── FINAL SUMMARY ────────────────────────────────────────────────────────
console.log("\n✓ All 15 TypeScript advanced sections completed");
