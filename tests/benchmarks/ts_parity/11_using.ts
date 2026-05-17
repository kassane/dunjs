// `using` declarations (Symbol.dispose) for sync resource cleanup.
const log: string[] = [];

class Resource {
  constructor(private name: string) { log.push(`open ${name}`); }
  [Symbol.dispose](): void { log.push(`close ${this.name}`); }
}

function run(): void {
  using r1 = new Resource("A");
  using r2 = new Resource("B");
  log.push(`use ${(r1 as any).name},${(r2 as any).name}`);
}

run();
console.log(log.join("\n"));
