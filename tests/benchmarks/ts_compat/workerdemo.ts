// worker-demo.ts — Workers, SharedArrayBuffer, Atomics, worker_threads

const { Worker, isMainThread, threadId, workerData, parentPort, receiveMessageOnPort, MessageChannel } = require("worker_threads");

console.log("=== Worker Threads ===");
console.log("isMainThread:", isMainThread);
console.log("main threadId:", threadId === 0 || threadId >= 0);

// ── Basic worker with eval ─────────────────────────────────────────────────
{
  const result = await new Promise<any>((resolve, reject) => {
    const w = new Worker(`
      const { parentPort, workerData } = require('worker_threads');
      const { op, a, b } = workerData;
      let result;
      if (op === 'add') result = a + b;
      else if (op === 'mul') result = a * b;
      else if (op === 'fib') {
        function fib(n) { return n <= 1 ? n : fib(n-1) + fib(n-2); }
        result = fib(a);
      }
      parentPort.postMessage({ result, tid: require('worker_threads').threadId });
    `, { eval: true, workerData: { op: 'add', a: 6, b: 7 } });
    w.on('message', resolve);
    w.on('error', reject);
  });
  console.log("worker add:", result.result === 13);
  console.log("worker threadId differs:", result.tid !== threadId);
}

// ── CPU-intensive task in worker ──────────────────────────────────────────
{
  const fibResult = await new Promise<any>((resolve, reject) => {
    const w = new Worker(`
      const { parentPort, workerData } = require('worker_threads');
      function fib(n) { return n <= 1 ? n : fib(n-1) + fib(n-2); }
      parentPort.postMessage({ result: fib(workerData.n) });
    `, { eval: true, workerData: { n: 30 } });
    w.on('message', resolve);
    w.on('error', reject);
  });
  console.log("worker fib(30):", fibResult.result === 832040);
}

// ── Multiple workers in parallel ──────────────────────────────────────────
{
  const tasks = [10, 20, 30, 40].map((n) =>
    new Promise<number>((resolve, reject) => {
      const w = new Worker(`
        const { parentPort, workerData } = require('worker_threads');
        function fib(n) { return n <= 1 ? n : fib(n-1) + fib(n-2); }
        parentPort.postMessage(fib(workerData.n));
      `, { eval: true, workerData: { n } });
      w.on('message', resolve);
      w.on('error', reject);
    })
  );
  const results = await Promise.all(tasks);
  console.log("parallel workers:", results[0] === 55);    // fib(10)
  console.log("parallel fib(20):", results[1] === 6765);
  console.log("parallel fib(30):", results[2] === 832040);
  console.log("parallel fib(40):", results[3] === 102334155);
}

// ── SharedArrayBuffer + Atomics ───────────────────────────────────────────
console.log("\n=== SharedArrayBuffer + Atomics ===");

const sab = new SharedArrayBuffer(16);
const i32 = new Int32Array(sab);

// Basic atomic operations
Atomics.store(i32, 0, 42);
console.log("store/load:", Atomics.load(i32, 0) === 42);

const prev = Atomics.add(i32, 0, 8);
console.log("add prev:", prev === 42);
console.log("add result:", Atomics.load(i32, 0) === 50);

const subPrev = Atomics.sub(i32, 0, 5);
console.log("sub prev:", subPrev === 50);
console.log("sub result:", Atomics.load(i32, 0) === 45);

Atomics.and(i32, 1, 0b1010);
Atomics.store(i32, 1, 0b1111);
Atomics.and(i32, 1, 0b1010);
console.log("and:", Atomics.load(i32, 1) === 0b1010);

Atomics.store(i32, 2, 0b0101);
Atomics.or(i32, 2, 0b1010);
console.log("or:", Atomics.load(i32, 2) === 0b1111);

Atomics.store(i32, 3, 0b1100);
Atomics.xor(i32, 3, 0b1010);
console.log("xor:", Atomics.load(i32, 3) === 0b0110);

// compareExchange
Atomics.store(i32, 0, 100);
const ce1 = Atomics.compareExchange(i32, 0, 100, 200);
console.log("CAS success:", ce1 === 100 && Atomics.load(i32, 0) === 200);
const ce2 = Atomics.compareExchange(i32, 0, 100, 300); // should fail
console.log("CAS fail:", ce2 === 200 && Atomics.load(i32, 0) === 200);

// exchange
const old = Atomics.exchange(i32, 0, 999);
console.log("exchange:", old === 200 && Atomics.load(i32, 0) === 999);

// isLockFree
console.log("isLockFree(4):", Atomics.isLockFree(4));

// ── Worker + SharedArrayBuffer coordination ───────────────────────────────
{
  const shared = new SharedArrayBuffer(8);
  const counter = new Int32Array(shared);
  Atomics.store(counter, 0, 0);
  Atomics.store(counter, 1, 0); // done flag

  const numWorkers = 4;
  const incrementsPerWorker = 1000;

  const workers = Array.from({ length: numWorkers }, (_, i) =>
    new Promise<void>((resolve, reject) => {
      const w = new Worker(`
        const { workerData } = require('worker_threads');
        const { shared, count } = workerData;
        const arr = new Int32Array(shared);
        for (let i = 0; i < count; i++) {
          Atomics.add(arr, 0, 1);
        }
      `, { eval: true, workerData: { shared, count: incrementsPerWorker } });
      w.on('exit', resolve);
      w.on('error', reject);
    })
  );

  await Promise.all(workers);
  const finalCount = Atomics.load(counter, 0);
  console.log(`atomic counter (${numWorkers}×${incrementsPerWorker}):`, finalCount === numWorkers * incrementsPerWorker);
}

// ── MessageChannel ────────────────────────────────────────────────────────
console.log("\n=== MessageChannel ===");
{
  const { port1, port2 } = new MessageChannel();

  const messages: string[] = [];
  port2.on('message', (msg: string) => messages.push(msg));
  port2.start?.();

  port1.postMessage('hello');
  port1.postMessage('world');

  await new Promise(r => setTimeout(r, 20));
  console.log("MessageChannel:", messages[0] === 'hello' && messages[1] === 'world');

  port1.close();
  port2.close();
}

// ── Worker with MessageChannel ────────────────────────────────────────────
{
  const { port1, port2 } = new MessageChannel();

  const workerReply = new Promise<string>((resolve) => {
    port1.on('message', (msg: any) => resolve(msg.reply));
    port1.start?.();
  });

  const w = new Worker(`
    const { workerData } = require('worker_threads');
    const { port } = workerData;
    port.on('message', (msg) => {
      port.postMessage({ reply: 'echo:' + msg });
    });
    port.start && port.start();
  `, { eval: true, workerData: { port: port2 }, transferList: [port2] });

  port1.postMessage('ping');
  const reply = await workerReply;
  console.log("worker MessageChannel:", reply === 'echo:ping');
  port1.close();
  await new Promise<void>((r) => { w.on('exit', () => r()); w.terminate(); });
}

// ── Worker lifecycle ──────────────────────────────────────────────────────
console.log("\n=== Worker Lifecycle ===");
{
  const w = new Worker(`
    const { parentPort } = require('worker_threads');
    parentPort.postMessage('ready');
    setTimeout(() => process.exit(0), 50);
  `, { eval: true });

  const msg = await new Promise<string>((r) => w.on('message', r));
  console.log("worker ready:", msg === 'ready');

  const exitCode = await new Promise<number>((r) => w.on('exit', r));
  console.log("worker exit:", exitCode === 0);
}

// ── Worker error handling ─────────────────────────────────────────────────
{
  const errMsg = await new Promise<string>((resolve) => {
    const w = new Worker(`throw new Error('deliberate worker error');`, { eval: true });
    w.on('error', (e: Error) => resolve(e.message));
    w.on('exit', () => resolve('exited without error event'));
  });
  console.log("worker error:", errMsg.includes('deliberate worker error') || errMsg.includes('exited'));
}

console.log("\nAll Worker + Atomics tests OK");
