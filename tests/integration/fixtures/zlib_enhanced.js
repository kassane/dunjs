// Test enhanced zlib module: async methods, stream classes, constants
var zlib = require('zlib');
var checks = 0;
var passed = 0;

function check(name, condition) {
  checks++;
  if (condition) {
    passed++;
    console.log('PASS: ' + name);
  } else {
    console.log('FAIL: ' + name);
  }
}

// --- Type checks for async methods ---
check('deflate is function', typeof zlib.deflate === 'function');
check('inflate is function', typeof zlib.inflate === 'function');
check('gzip is function', typeof zlib.gzip === 'function');
check('gunzip is function', typeof zlib.gunzip === 'function');
check('deflateRaw is function', typeof zlib.deflateRaw === 'function');
check('inflateRaw is function', typeof zlib.inflateRaw === 'function');
check('brotliCompress is function', typeof zlib.brotliCompress === 'function');
check('brotliDecompress is function', typeof zlib.brotliDecompress === 'function');

// --- Type checks for stream classes ---
check('createDeflate is function', typeof zlib.createDeflate === 'function');
check('createInflate is function', typeof zlib.createInflate === 'function');
check('createGzip is function', typeof zlib.createGzip === 'function');
check('createGunzip is function', typeof zlib.createGunzip === 'function');
check('createDeflateRaw is function', typeof zlib.createDeflateRaw === 'function');
check('createInflateRaw is function', typeof zlib.createInflateRaw === 'function');
check('createBrotliCompress is function', typeof zlib.createBrotliCompress === 'function');
check('createBrotliDecompress is function', typeof zlib.createBrotliDecompress === 'function');

// --- Constants ---
check('constants is object', typeof zlib.constants === 'object');
check('Z_BEST_COMPRESSION === 9', zlib.constants.Z_BEST_COMPRESSION === 9);
check('Z_DEFAULT_COMPRESSION === -1', zlib.constants.Z_DEFAULT_COMPRESSION === -1);
check('Z_NO_FLUSH === 0', zlib.constants.Z_NO_FLUSH === 0);
check('Z_FINISH === 4', zlib.constants.Z_FINISH === 4);
check('Z_OK === 0', zlib.constants.Z_OK === 0);
check('Z_STREAM_ERROR === -2', zlib.constants.Z_STREAM_ERROR === -2);
check('Z_DEFAULT_CHUNK === 16384', zlib.constants.Z_DEFAULT_CHUNK === 16384);
check('BROTLI_OPERATION_FINISH === 2', zlib.constants.BROTLI_OPERATION_FINISH === 2);

// --- Async deflate/inflate round-trip ---
var input = 'Hello, async zlib!';
zlib.deflate(input, function(err, deflated) {
  check('async deflate no error', err === null || err === undefined);
  check('async deflate produced data', deflated && deflated.length > 0);

  zlib.inflate(deflated, function(err2, inflated) {
    check('async inflate no error', err2 === null || err2 === undefined);
    var str = '';
    for (var i = 0; i < inflated.length; i++) str += String.fromCharCode(inflated[i]);
    check('async deflate/inflate round-trip', str === input);

    // --- Async gzip/gunzip round-trip ---
    zlib.gzip(input, function(err3, gzipped) {
      check('async gzip no error', err3 === null || err3 === undefined);
      check('async gzip produced data', gzipped && gzipped.length > 0);

      zlib.gunzip(gzipped, function(err4, gunzipped) {
        check('async gunzip no error', err4 === null || err4 === undefined);
        var str2 = '';
        for (var i = 0; i < gunzipped.length; i++) str2 += String.fromCharCode(gunzipped[i]);
        check('async gzip/gunzip round-trip', str2 === input);

        console.log(passed + '/' + checks + ' checks passed');
      });
    });
  });
});
