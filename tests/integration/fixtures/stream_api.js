// Test stream module
const stream = require('stream');

// Readable
var r = new stream.Readable({
  read: function() {
    this.push('hello');
    this.push(' stream');
    this.push(null);
  }
});

var data = r.read();
console.log('readable: ' + data);

// Writable
var written = '';
var w = new stream.Writable({
  write: function(chunk, encoding, callback) {
    written += chunk;
    callback();
  }
});
w.write('A');
w.write('B');
w.end('C');
console.log('writable: ' + written);

// PassThrough
var pt = new stream.PassThrough();
pt.write('pass');
pt.write('through');
pt.end();
var ptData = pt.read();
console.log('passthrough: ' + ptData);

// Transform
var t = new stream.Transform({
  transform: function(chunk, encoding, callback) {
    callback(null, chunk.toUpperCase());
  }
});
t.write('hello');
t.end();
var tData = t.read();
console.log('transform: ' + tData);

// pipeline exists
console.log('pipeline: ' + (typeof stream.pipeline));

console.log('stream done');
