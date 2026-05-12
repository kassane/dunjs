// Test zlib module
const zlib = require('zlib');

// deflate/inflate round-trip
var input = 'Hello, zlib compression!';
var deflated = zlib.deflateSync(input);
console.log('deflated type: ' + (deflated instanceof Uint8Array || typeof deflated === 'object'));
console.log('deflated smaller: ' + (deflated.length < input.length * 2));

var inflated = zlib.inflateSync(deflated);
var inflatedStr = '';
for (var i = 0; i < inflated.length; i++) {
  inflatedStr += String.fromCharCode(inflated[i]);
}
console.log('inflate match: ' + (inflatedStr === input));

// gzip/gunzip round-trip
var gzipped = zlib.gzipSync(input);
console.log('gzipped exists: ' + (gzipped.length > 0));

var gunzipped = zlib.gunzipSync(gzipped);
var gunzipStr = '';
for (var i = 0; i < gunzipped.length; i++) {
  gunzipStr += String.fromCharCode(gunzipped[i]);
}
console.log('gunzip match: ' + (gunzipStr === input));

console.log('zlib done');
