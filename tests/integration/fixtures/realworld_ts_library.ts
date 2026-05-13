// Real-world: TypeScript library with interfaces, type aliases, and typed patterns

interface Result {
  ok: boolean;
  value?: any;
  error?: string;
}

type StringOrNumber = string | number;

interface Config {
  host: string;
  port?: number;
  debug?: boolean;
}

// Typed pipeline function
function pipe(input: any, fn: Function): Result {
  try {
    const value: any = fn(input);
    return { ok: true, value: value };
  } catch (e) {
    return { ok: false, error: e.message as string };
  }
}

// Typed filter
function filterItems(items: number[], pred: Function): number[] {
  return items.filter(pred as any);
}

function formatValue(val: StringOrNumber): string {
  if (typeof val === 'number') {
    return val.toFixed(2);
  }
  return val.toUpperCase();
}

function describeConfig(cfg: Config): string {
  const port: number = cfg.port ?? 8080;
  const debug: boolean = cfg.debug ?? false;
  return cfg.host + ':' + port + (debug ? ' [debug]' : '');
}

// pipe with success
const r1: Result = pipe('hello', function(s: string) { return s.length; });
console.log('pipe ok: ' + r1.ok + ', value: ' + r1.value);

// pipe with failure
const r2: Result = pipe(null, function(s: string) { return s.length; });
console.log('pipe error: ' + r2.ok);

// filterItems
const nums: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const evens: number[] = filterItems(nums, function(n: number) { return n % 2 === 0; });
console.log('evens: ' + evens.join(','));
console.log('even count: ' + evens.length);

// formatValue
console.log('format number: ' + formatValue(3.14159));
console.log('format string: ' + formatValue('hello'));

// describeConfig
console.log('config1: ' + describeConfig({ host: 'localhost' }));
console.log('config2: ' + describeConfig({ host: '0.0.0.0', port: 3000, debug: true }));

// Async with types
async function fetchData(id: number): Promise<string> {
  if (id <= 0) return 'error:invalid id';
  return 'data-' + id;
}

(async function() {
  const d1: string = await fetchData(42);
  console.log('async: ' + d1);
  const d2: string = await fetchData(-1);
  console.log('async: ' + d2);
})();
