// Async iterators, for-await-of, AsyncGenerator return types.
async function* range(start: number, end: number): AsyncGenerator<number, void, void> {
  for (let i = start; i < end; i++) {
    yield await Promise.resolve(i);
  }
}

class Stream<T> {
  constructor(private items: T[]) {}
  async *[Symbol.asyncIterator](): AsyncGenerator<T> {
    for (const x of this.items) {
      yield await Promise.resolve(x);
    }
  }
}

(async () => {
  const out: number[] = [];
  for await (const n of range(0, 5)) out.push(n * 10);
  console.log(out.join(","));

  const s = new Stream(["x", "y", "z"]);
  const collected: string[] = [];
  for await (const v of s) collected.push(v);
  console.log(collected.join("-"));
})();
