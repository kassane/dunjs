// HTTP/3 API availability test
const http3 = require('http3');

// Test module availability
console.log("http3 module loaded:", typeof http3 === 'object');

// Test createServer exists
console.log("createServer:", typeof http3.createServer === 'function');

// Test connect exists
console.log("connect:", typeof http3.connect === 'function');

// Test constants
console.log("constants:", typeof http3.constants === 'object');

// Test createServer returns server object
const server = http3.createServer();
console.log("server object:", typeof server === 'object');
console.log("server.listen:", typeof server.listen === 'function');
console.log("server.close:", typeof server.close === 'function');
console.log("server.on:", typeof server.on === 'function');

// Test connect returns session
const session = http3.connect('https://localhost');
console.log("session object:", typeof session === 'object');
console.log("session.request:", typeof session.request === 'function');
console.log("session.close:", typeof session.close === 'function');

// Test stream from request
const stream = session.request({ ':path': '/' });
console.log("stream object:", typeof stream === 'object');
console.log("stream.on:", typeof stream.on === 'function');
console.log("stream.write:", typeof stream.write === 'function');
console.log("stream.end:", typeof stream.end === 'function');

// Test HTTP/3 error code constants
console.log("H3_NO_ERROR:", http3.constants.NGHTTP3_H3_NO_ERROR === 256);
console.log("H3_GENERAL_PROTOCOL_ERROR:", http3.constants.NGHTTP3_H3_GENERAL_PROTOCOL_ERROR === 257);
console.log("H3_INTERNAL_ERROR:", http3.constants.NGHTTP3_H3_INTERNAL_ERROR === 258);
console.log("H3_SETTINGS_ERROR:", http3.constants.NGHTTP3_H3_SETTINGS_ERROR === 265);
console.log("H3_REQUEST_CANCELLED:", http3.constants.NGHTTP3_H3_REQUEST_CANCELLED === 268);

// Test QUIC version constants
console.log("QUIC_VERSION_1:", http3.constants.QUIC_VERSION_1 === 1);
console.log("QUIC_VERSION_2:", http3.constants.QUIC_VERSION_2 === 2);

// Test default settings
console.log("DEFAULT_MAX_HEADER_LIST_SIZE:", http3.constants.DEFAULT_MAX_HEADER_LIST_SIZE === 65536);
