// Test npm-critical module availability and basic API surface
var checks = 0;
var passed = 0;

function check(name, condition) {
  checks++;
  if (condition) { passed++; console.log('PASS: ' + name); }
  else console.log('FAIL: ' + name);
}

// Core modules that npm packages commonly require
check('fs module', typeof require('fs') === 'object');
check('path module', typeof require('path') === 'object');
check('crypto module', typeof require('crypto') === 'object');
check('net module', typeof require('net') === 'object');
check('http module', typeof require('http') === 'object');
check('https module', typeof require('https') === 'object');
check('os module', typeof require('os') === 'object');
check('buffer module', typeof require('buffer') === 'object');
check('events module', typeof require('events') === 'object');
check('url module', typeof require('url') === 'object');
check('stream module', typeof require('stream') === 'object');
check('util module', typeof require('util') === 'object');
check('assert module', typeof require('assert') === 'function' || typeof require('assert') === 'object');
check('querystring module', typeof require('querystring') === 'object');
check('string_decoder module', typeof require('string_decoder') === 'object');
check('child_process module', typeof require('child_process') === 'object');
check('zlib module', typeof require('zlib') === 'object');
check('dns module', typeof require('dns') === 'object');
check('readline module', typeof require('readline') === 'object');
check('vm module', typeof require('vm') === 'object');
check('tls module', typeof require('tls') === 'object');
check('dgram module', typeof require('dgram') === 'object');
check('perf_hooks module', typeof require('perf_hooks') === 'object');
check('punycode module', typeof require('punycode') === 'object');
check('domain module', typeof require('domain') === 'object');
check('diagnostics_channel module', typeof require('diagnostics_channel') === 'object');
check('cluster module', typeof require('cluster') === 'object');
check('async_hooks module', typeof require('async_hooks') === 'object');
check('worker_threads module', typeof require('worker_threads') === 'object');

// Key API surface checks
var fs = require('fs');
check('fs.readFileSync', typeof fs.readFileSync === 'function');
check('fs.writeFileSync', typeof fs.writeFileSync === 'function');
check('fs.existsSync', typeof fs.existsSync === 'function');
check('fs.mkdirSync', typeof fs.mkdirSync === 'function');
check('fs.statSync', typeof fs.statSync === 'function');
check('fs.createReadStream', typeof fs.createReadStream === 'function');
check('fs.createWriteStream', typeof fs.createWriteStream === 'function');

var path = require('path');
check('path.join', typeof path.join === 'function');
check('path.resolve', typeof path.resolve === 'function');
check('path.relative', typeof path.relative === 'function');
check('path.dirname', typeof path.dirname === 'function');
check('path.basename', typeof path.basename === 'function');
check('path.extname', typeof path.extname === 'function');
check('path.parse', typeof path.parse === 'function');
check('path.sep', typeof path.sep === 'string');

var crypto = require('crypto');
check('crypto.createHash', typeof crypto.createHash === 'function');
check('crypto.createHmac', typeof crypto.createHmac === 'function');
check('crypto.randomBytes', typeof crypto.randomBytes === 'function');
check('crypto.randomUUID', typeof crypto.randomUUID === 'function');
check('crypto.createCipheriv', typeof crypto.createCipheriv === 'function');
check('crypto.createDecipheriv', typeof crypto.createDecipheriv === 'function');
check('crypto.timingSafeEqual', typeof crypto.timingSafeEqual === 'function');
check('crypto.pbkdf2Sync', typeof crypto.pbkdf2Sync === 'function');
check('crypto.scryptSync', typeof crypto.scryptSync === 'function');

var net = require('net');
check('net.createServer', typeof net.createServer === 'function');
check('net.createConnection', typeof net.createConnection === 'function');
check('net.isIP', typeof net.isIP === 'function');
check('net.isIPv4', typeof net.isIPv4 === 'function');
check('net.isIPv6', typeof net.isIPv6 === 'function');

// net.isIP checks
check('isIP 127.0.0.1', net.isIP('127.0.0.1') === 4);
check('isIP ::1', net.isIP('::1') === 6);
check('isIP invalid', net.isIP('not-an-ip') === 0);
check('isIPv4 true', net.isIPv4('192.168.1.1') === true);
check('isIPv4 false', net.isIPv4('::1') === false);

var stream = require('stream');
check('stream.Readable', typeof stream.Readable === 'function');
check('stream.Writable', typeof stream.Writable === 'function');
check('stream.Transform', typeof stream.Transform === 'function');
check('stream.pipeline', typeof stream.pipeline === 'function');
check('stream.finished', typeof stream.finished === 'function');
check('Readable.from', typeof stream.Readable.from === 'function');

var util = require('util');
check('util.format', typeof util.format === 'function');
check('util.inspect', typeof util.inspect === 'function');
check('util.promisify', typeof util.promisify === 'function');
check('util.inherits', typeof util.inherits === 'function');
check('util.types', typeof util.types === 'object');
check('util.debuglog', typeof util.debuglog === 'function');
check('util.deprecate', typeof util.deprecate === 'function');

// process APIs
check('process.nextTick', typeof process.nextTick === 'function');
check('process.env', typeof process.env === 'object');
check('process.cwd', typeof process.cwd === 'function');
check('process.exit', typeof process.exit === 'function');
check('process.hrtime', typeof process.hrtime === 'function');
check('process.memoryUsage', typeof process.memoryUsage === 'function');
check('process.cpuUsage', typeof process.cpuUsage === 'function');
check('process.emitWarning', typeof process.emitWarning === 'function');
check('process.kill', typeof process.kill === 'function');
check('process.pid', typeof process.pid === 'number');
check('process.platform', typeof process.platform === 'string');
check('process.arch', typeof process.arch === 'string');
check('process.version', typeof process.version === 'string');
check('process.versions', typeof process.versions === 'object');

// Globals
check('Buffer', typeof Buffer !== 'undefined');
check('setTimeout', typeof setTimeout === 'function');
check('setInterval', typeof setInterval === 'function');
check('clearTimeout', typeof clearTimeout === 'function');
check('console.log', typeof console.log === 'function');
check('console.error', typeof console.error === 'function');
check('console.warn', typeof console.warn === 'function');

console.log('---');
console.log('Total: ' + passed + '/' + checks + ' passed');
