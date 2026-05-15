// Production gaps round 3: console.group, TypedArray.from, zlib Buffer, sqlite bind
var pass = 0, fail = 0;
function check(name, fn) {
  try { if (fn()) { pass++; } else { fail++; console.log("FAIL: " + name); } }
  catch(e) { fail++; console.log("FAIL: " + name + " (" + (e.message || e) + ")"); }
}

// === console.group with indentation ===
console.group("Group1");
console.log("indented1");
console.group("Group1.1");
console.log("indented2");
console.groupEnd();
console.log("back1");
console.groupEnd();
console.log("root");

// === TypedArray.from/of ===
check("Int32Array.from", function() { return Int32Array.from([1,2,3]).length === 3; });
check("Int32Array.of", function() { return Int32Array.of(10,20).length === 2; });
check("Int32Array.from mapFn", function() {
  var arr = Int32Array.from([1,2,3], function(x) { return x * 2; });
  return arr[0] === 2 && arr[1] === 4 && arr[2] === 6;
});
check("Uint8Array.from", function() { return Uint8Array.from([1,2,3]).length === 3; });
check("Float64Array.from", function() { return Float64Array.from([1.5, 2.5]).length === 2; });

// === zlib returns Buffer ===
check("deflateSync returns Buffer", function() {
  var zlib = require('zlib');
  var compressed = zlib.deflateSync(Buffer.from('Hello'));
  return Buffer.isBuffer(compressed);
});
check("deflateSync/inflateSync roundtrip", function() {
  var zlib = require('zlib');
  var input = Buffer.from('Hello World from DunJS!');
  var compressed = zlib.deflateSync(input);
  var decompressed = zlib.inflateSync(compressed);
  return decompressed.toString() === 'Hello World from DunJS!';
});
check("gzipSync/gunzipSync roundtrip", function() {
  var zlib = require('zlib');
  var input = Buffer.from('gzip test data');
  var compressed = zlib.gzipSync(input);
  var decompressed = zlib.gunzipSync(compressed);
  return decompressed.toString() === 'gzip test data';
});

// === sqlite bind array ===
check("sqlite bind array params", function() {
  var sqlite = require('sqlite');
  var db = sqlite.open(':memory:');
  db.exec('CREATE TABLE t (id INTEGER, name TEXT)');
  db.run('INSERT INTO t VALUES (?, ?)', [1, 'Alice']);
  db.run('INSERT INTO t VALUES (?, ?)', [2, 'Bob']);
  var row = db.get('SELECT * FROM t WHERE id = ?', [2]);
  var all = db.all('SELECT * FROM t ORDER BY id');
  db.close();
  return row.name === 'Bob' && all.length === 2;
});

// === console methods ===
check("console.time/timeEnd", function() {
  return typeof console.time === 'function' && typeof console.timeEnd === 'function';
});
check("console.count", function() {
  return typeof console.count === 'function' && typeof console.countReset === 'function';
});
check("console.table exists", function() { return typeof console.table === 'function'; });
check("console.trace exists", function() { return typeof console.trace === 'function'; });
check("console.dir exists", function() { return typeof console.dir === 'function'; });
check("console.clear exists", function() { return typeof console.clear === 'function'; });

console.log("Production gaps 3: " + pass + "/" + (pass + fail) + " checks passed");
