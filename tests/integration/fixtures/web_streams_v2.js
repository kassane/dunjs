// TextEncoderStream / TextDecoderStream / ByteLengthQueuingStrategy /
// CountQueuingStrategy were missing in v0.4.x. WHATWG Streams §6 + §7.
let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

ok("TextEncoderStream defined", typeof TextEncoderStream === "function");
ok("TextDecoderStream defined", typeof TextDecoderStream === "function");
ok("ByteLengthQueuingStrategy defined", typeof ByteLengthQueuingStrategy === "function");
ok("CountQueuingStrategy defined", typeof CountQueuingStrategy === "function");

const encStream = new TextEncoderStream();
ok("encStream.readable", encStream.readable instanceof ReadableStream);
ok("encStream.writable", encStream.writable instanceof WritableStream);
ok("encStream.encoding", encStream.encoding === "utf-8");

const decStream = new TextDecoderStream();
ok("decStream.readable", decStream.readable instanceof ReadableStream);
ok("decStream.writable", decStream.writable instanceof WritableStream);
ok("decStream.encoding", decStream.encoding === "utf-8");

const byteStrat = new ByteLengthQueuingStrategy({ highWaterMark: 1024 });
ok("byte strategy hwm", byteStrat.highWaterMark === 1024);
ok("byte strategy size", typeof byteStrat.size === "function");
ok("byte strategy size of Uint8Array", byteStrat.size(new Uint8Array(10)) === 10);

const countStrat = new CountQueuingStrategy({ highWaterMark: 5 });
ok("count strategy hwm", countStrat.highWaterMark === 5);
ok("count strategy size", typeof countStrat.size === "function");
ok("count strategy size always 1", countStrat.size("anything") === 1);

console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
