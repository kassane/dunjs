// Node stream pipeline: src -> Transform -> dst with callback.
// Previously the pipe chain didn't pump push-mode Readables
// (Readable.from), and the pipeline callback didn't fire because
// the 'finish' listener was attached AFTER the pipe loop already
// drained synchronously.

const { Readable, Writable, Transform, pipeline } = require("stream");

const upper = new Transform({
    transform(chunk: Buffer, _enc: string, cb: Function) {
        cb(null, chunk.toString().toUpperCase());
    },
});
const src = Readable.from(["hello", " world"]);
const chunks: string[] = [];
const dst = new Writable({
    write(chunk: Buffer, _enc: string, cb: Function) {
        chunks.push(chunk.toString());
        cb();
    },
});

pipeline(src, upper, dst, (err: unknown) => {
    console.log("err:", err);
    console.log("result:", chunks.join(""));
});
