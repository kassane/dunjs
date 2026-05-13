// HTTP/2 API availability test
const http2 = require('http2');

// Test module availability
console.log("http2 module loaded:", typeof http2 === 'object');

// Test createServer exists
console.log("createServer:", typeof http2.createServer === 'function');

// Test createSecureServer exists
console.log("createSecureServer:", typeof http2.createSecureServer === 'function');

// Test connect exists
console.log("connect:", typeof http2.connect === 'function');

// Test constants
console.log("constants:", typeof http2.constants === 'object');
console.log("HTTP2_HEADER_METHOD:", http2.constants.HTTP2_HEADER_METHOD === ':method');
console.log("HTTP2_HEADER_PATH:", http2.constants.HTTP2_HEADER_PATH === ':path');
console.log("HTTP2_HEADER_STATUS:", http2.constants.HTTP2_HEADER_STATUS === ':status');
console.log("HTTP2_HEADER_SCHEME:", http2.constants.HTTP2_HEADER_SCHEME === ':scheme');

// Test createServer returns server object
const server = http2.createServer();
console.log("server object:", typeof server === 'object');
console.log("server.listen:", typeof server.listen === 'function');
console.log("server.close:", typeof server.close === 'function');
console.log("server.on:", typeof server.on === 'function');

// Test createServer with callback
const server2 = http2.createServer(function(req, res) {});
console.log("server with callback:", typeof server2 === 'object');

// Test connect returns session
const session = http2.connect('http://localhost');
console.log("session object:", typeof session === 'object');
console.log("session.request:", typeof session.request === 'function');
console.log("session.close:", typeof session.close === 'function');

// Test error constants
console.log("NGHTTP2_NO_ERROR:", http2.constants.NGHTTP2_NO_ERROR === 0);
console.log("NGHTTP2_PROTOCOL_ERROR:", http2.constants.NGHTTP2_PROTOCOL_ERROR === 1);
console.log("NGHTTP2_CANCEL:", http2.constants.NGHTTP2_CANCEL === 8);
