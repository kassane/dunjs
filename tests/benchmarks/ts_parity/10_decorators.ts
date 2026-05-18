// TC39 Stage 3 decorators (class + method + accessor).
function logged<T extends (...a: any[]) => any>(
  target: T, ctx: ClassMethodDecoratorContext
): T {
  return function (this: any, ...args: any[]) {
    const r = (target as any).apply(this, args);
    return r;
  } as T;
}

function tag(name: string) {
  return function <T extends new (...a: any[]) => any>(
    cls: T, _ctx: ClassDecoratorContext<T>
  ): T {
    (cls as any).tag = name;
    return cls;
  };
}

@tag("service")
class Greeter {
  @logged
  hello(who: string): string { return `hi ${who}`; }

  @logged
  add(a: number, b: number): number { return a + b; }
}

const g = new Greeter();
console.log(g.hello("world"));
console.log(g.add(3, 4));
console.log((Greeter as any).tag);
