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
check('EventEmitter.listenerCount', typeof EventEmitter.listenerCount === 'function');
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
check('tty module', typeof require('tty') === 'object');
check('constants module', typeof require('constants') === 'object');
check('module module', typeof require('module') === 'object');
check('timers module', typeof require('timers') === 'object');
check('process module', typeof require('process') === 'object');
check('console module', typeof require('console') === 'object');

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
check('crypto.getHashes', typeof crypto.getHashes === 'function');
check('crypto.getHashes returns array', Array.isArray(crypto.getHashes()));
check('crypto.getHashes includes sha256', crypto.getHashes().indexOf('sha256') !== -1);
check('crypto.getCiphers', typeof crypto.getCiphers === 'function');
check('crypto.constants', typeof crypto.constants === 'object');

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
check('net.Socket', typeof net.Socket === 'function');

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
check('process.uptime', typeof process.uptime === 'function');
check('process.chdir', typeof process.chdir === 'function');
check('process.execPath', typeof process.execPath === 'string');
check('process.argv0', typeof process.argv0 === 'string');
check('process.title', typeof process.title === 'string');
check('process.ppid', typeof process.ppid === 'number');
check('process.on', typeof process.on === 'function');
check('process.once', typeof process.once === 'function');
check('process.off', typeof process.off === 'function');
check('process.removeListener', typeof process.removeListener === 'function');
check('process.removeAllListeners', typeof process.removeAllListeners === 'function');
check('process.listeners', typeof process.listeners === 'function');
check('process.listenerCount', typeof process.listenerCount === 'function');
check('process.emit', typeof process.emit === 'function');
check('process.prependListener', typeof process.prependListener === 'function');
check('process.eventNames', typeof process.eventNames === 'function');
check('process.setMaxListeners', typeof process.setMaxListeners === 'function');

// process.on('exit') test
var exitCalled = false;
process.on('exit', function() { exitCalled = true; });
check('process.listenerCount exit', process.listenerCount('exit') === 1);
process.emit('exit', 0);
check('process.on exit fires', exitCalled === true);
process.removeAllListeners('exit');

var http = require('http');
check('http.createServer', typeof http.createServer === 'function');
check('http.request', typeof http.request === 'function');
check('http.get', typeof http.get === 'function');
check('http.METHODS', Array.isArray(http.METHODS));
check('http.STATUS_CODES', typeof http.STATUS_CODES === 'object');
check('http.Agent', typeof http.Agent === 'function');
check('http.globalAgent', typeof http.globalAgent === 'object');

// Server properties (express compat)
var srv = http.createServer(function(){});
check('server.address', typeof srv.address === 'function');
check('server.listening', srv.listening === false);
check('server.timeout', typeof srv.timeout === 'number');
check('server.keepAliveTimeout', typeof srv.keepAliveTimeout === 'number');

// http.request finished property (Node.js compat)
var req = http.request({hostname: 'localhost', port: 1});
check('http req.finished initial', req.finished === false);

var https = require('https');
check('https.createServer', typeof https.createServer === 'function');
check('https.request', typeof https.request === 'function');
check('https.get', typeof https.get === 'function');

var tty = require('tty');
check('tty.isatty', typeof tty.isatty === 'function');
check('tty.ReadStream', typeof tty.ReadStream === 'function');
check('tty.WriteStream', typeof tty.WriteStream === 'function');

var mod = require('module');
check('module.builtinModules', Array.isArray(mod.builtinModules));
check('module.isBuiltin', typeof mod.isBuiltin === 'function');
check('module.createRequire', typeof mod.createRequire === 'function');

// New: spawn/execFile
var cp = require('child_process');
check('child_process.spawn', typeof cp.spawn === 'function');
check('child_process.execFile', typeof cp.execFile === 'function');

// New: dgram
var dgram = require('dgram');
check('dgram.createSocket', typeof dgram.createSocket === 'function');

// New: tls connect/getCiphers
var tls = require('tls');
check('tls.connect', typeof tls.connect === 'function');
check('tls.getCiphers', typeof tls.getCiphers === 'function');
check('tls.TLSSocket', typeof tls.TLSSocket === 'function');
check('tls.DEFAULT_MIN_VERSION', tls.DEFAULT_MIN_VERSION === 'TLSv1.2');

// New: dns enhancements
var dns = require('dns');
check('dns.resolve', typeof dns.resolve === 'function');
check('dns.getServers', typeof dns.getServers === 'function');
check('dns.promises', typeof dns.promises === 'object');
check('dns.promises.lookup', typeof dns.promises.lookup === 'function');

// New: stream enhancements
var stream = require('stream');
check('stream.Stream', typeof stream.Stream === 'function');
check('stream.addAbortSignal', typeof stream.addAbortSignal === 'function');
check('stream.promises', typeof stream.promises === 'object');
check('stream.promises.pipeline', typeof stream.promises.pipeline === 'function');
check('Readable.toWeb', typeof stream.Readable.toWeb === 'function');

// New: os enhancements
var os = require('os');
check('os.networkInterfaces', typeof os.networkInterfaces === 'function');
check('os.userInfo', typeof os.userInfo === 'function');
check('os.loadavg', typeof os.loadavg === 'function');
check('os.version', typeof os.version === 'function');
check('os.machine', typeof os.machine === 'function');
var ui = os.userInfo();
check('os.userInfo().uid', typeof ui.uid === 'number');
check('os.userInfo().username', typeof ui.username === 'string');
check('os.userInfo().homedir', typeof ui.homedir === 'string');
var la = os.loadavg();
check('os.loadavg() is array', Array.isArray(la) && la.length === 3);
check('os.networkInterfaces() is object', typeof os.networkInterfaces() === 'object');
check('os.constants', typeof os.constants === 'object');
check('os.constants.signals', typeof os.constants.signals === 'object');
check('os.constants.signals.SIGTERM', os.constants.signals.SIGTERM === 15);
check('os.constants.signals.SIGINT', os.constants.signals.SIGINT === 2);
check('os.constants.signals.SIGKILL', os.constants.signals.SIGKILL === 9);
check('os.constants.errno', typeof os.constants.errno === 'object');
check('os.constants.errno.ENOENT', os.constants.errno.ENOENT === 2);
check('os.constants.errno.EACCES', os.constants.errno.EACCES === 13);
check('os.constants.errno.EEXIST', os.constants.errno.EEXIST === 17);
check('os.constants.priority', typeof os.constants.priority === 'object');
check('os.constants.priority.PRIORITY_NORMAL', os.constants.priority.PRIORITY_NORMAL === 0);

// New: perf_hooks
var perf_hooks = require('perf_hooks');
check('perf_hooks.performance', typeof perf_hooks.performance === 'object');
check('perf_hooks.performance.mark', typeof perf_hooks.performance.mark === 'function');
check('perf_hooks.performance.measure', typeof perf_hooks.performance.measure === 'function');
check('perf_hooks.PerformanceObserver', typeof perf_hooks.PerformanceObserver === 'function');
check('perf_hooks.constants', typeof perf_hooks.constants === 'object');

// New: fs.watchFile/unwatchFile/mkdtempSync/cpSync/utimesSync
check('fs.watchFile', typeof fs.watchFile === 'function');
check('fs.unwatchFile', typeof fs.unwatchFile === 'function');
check('fs.mkdtempSync', typeof fs.mkdtempSync === 'function');
check('fs.cpSync', typeof fs.cpSync === 'function');
check('fs.utimesSync', typeof fs.utimesSync === 'function');

// Buffer iteration methods
var buf = Buffer.from([1, 2, 3]);
check('Buffer.keys', typeof buf.keys === 'function');
check('Buffer.values', typeof buf.values === 'function');
check('Buffer.entries', typeof buf.entries === 'function');
check('Buffer[Symbol.iterator]', typeof buf[Symbol.iterator] === 'function');
var keys = [];
for (var k of buf.keys()) keys.push(k);
check('Buffer.keys() iteration', keys.length === 3 && keys[0] === 0 && keys[1] === 1 && keys[2] === 2);
var vals = [];
for (var v of buf.values()) vals.push(v);
check('Buffer.values() iteration', vals.length === 3 && vals[0] === 1 && vals[1] === 2 && vals[2] === 3);
var entries = [];
for (var e of buf.entries()) entries.push(e);
check('Buffer.entries() iteration', entries.length === 3 && entries[0][0] === 0 && entries[0][1] === 1 && entries[2][0] === 2 && entries[2][1] === 3);
var iterVals = [];
for (var iv of buf) iterVals.push(iv);
check('Buffer for-of iteration', iterVals.length === 3 && iterVals[0] === 1 && iterVals[1] === 2 && iterVals[2] === 3);

// util.types checks
check('util.types.isPromise', util.types.isPromise(Promise.resolve(1)) === true);
check('util.types.isDate', util.types.isDate(new Date()) === true);
check('util.types.isRegExp', util.types.isRegExp(/abc/) === true);
check('util.types.isMap', util.types.isMap(new Map()) === true);
check('util.types.isSet', util.types.isSet(new Set()) === true);
check('util.types.isTypedArray', util.types.isTypedArray(new Uint8Array(1)) === true);
check('util.types.isArrayBuffer', util.types.isArrayBuffer(new ArrayBuffer(1)) === true);
check('util.types.isDataView', util.types.isDataView(new DataView(new ArrayBuffer(1))) === true);
check('util.types.isWeakMap', util.types.isWeakMap(new WeakMap()) === true);
check('util.types.isWeakSet', util.types.isWeakSet(new WeakSet()) === true);
check('util.types.isGeneratorFunction', util.types.isGeneratorFunction(function*(){}) === true);
check('util.types.isAsyncFunction', util.types.isAsyncFunction(async function(){}) === true);
check('util.types.isNumberObject', util.types.isNumberObject(new Number(1)) === true);
check('util.types.isStringObject', util.types.isStringObject(new String('a')) === true);
check('util.types.isBooleanObject', util.types.isBooleanObject(new Boolean(true)) === true);

// assert module API surface
var assert = require('assert');
check('assert.ok', typeof assert.ok === 'function');
check('assert.equal', typeof assert.equal === 'function');
check('assert.notEqual', typeof assert.notEqual === 'function');
check('assert.strictEqual', typeof assert.strictEqual === 'function');
check('assert.notStrictEqual', typeof assert.notStrictEqual === 'function');
check('assert.deepEqual', typeof assert.deepEqual === 'function');
check('assert.deepStrictEqual', typeof assert.deepStrictEqual === 'function');
check('assert.notDeepEqual', typeof assert.notDeepEqual === 'function');
check('assert.notDeepStrictEqual', typeof assert.notDeepStrictEqual === 'function');
check('assert.throws', typeof assert.throws === 'function');
check('assert.doesNotThrow', typeof assert.doesNotThrow === 'function');
check('assert.rejects', typeof assert.rejects === 'function');
check('assert.doesNotReject', typeof assert.doesNotReject === 'function');
check('assert.match', typeof assert.match === 'function');
check('assert.doesNotMatch', typeof assert.doesNotMatch === 'function');
check('assert.fail', typeof assert.fail === 'function');
check('assert.ifError', typeof assert.ifError === 'function');

// querystring enhancements
var qs = require('querystring');
check('querystring.escape', typeof qs.escape === 'function');
check('querystring.unescape', typeof qs.unescape === 'function');
check('querystring.encode', typeof qs.encode === 'function');
check('querystring.decode', typeof qs.decode === 'function');
check('querystring.encode is stringify', qs.encode === qs.stringify);
check('querystring.decode is parse', qs.decode === qs.parse);
check('querystring.escape works', qs.escape('hello world') === 'hello%20world');
check('querystring.unescape works', qs.unescape('hello%20world') === 'hello world');

// url legacy API
var url = require('url');
check('url.parse', typeof url.parse === 'function');
check('url.format', typeof url.format === 'function');
check('url.resolve', typeof url.resolve === 'function');
check('url.fileURLToPath', typeof url.fileURLToPath === 'function');
check('url.pathToFileURL', typeof url.pathToFileURL === 'function');
check('url.domainToASCII', typeof url.domainToASCII === 'function');
check('url.domainToUnicode', typeof url.domainToUnicode === 'function');

// url.parse checks
var parsed = url.parse('https://user:pass@example.com:8080/path?query=1#hash');
check('url.parse protocol', parsed.protocol === 'https:');
check('url.parse hostname', parsed.hostname === 'example.com');
check('url.parse port', parsed.port === '8080');
check('url.parse pathname', parsed.pathname === '/path');
check('url.parse search', parsed.search === '?query=1');
check('url.parse query', parsed.query === 'query=1');
check('url.parse hash', parsed.hash === '#hash');
check('url.parse auth', parsed.auth === 'user:pass');
check('url.parse host', parsed.host === 'example.com:8080');
check('url.parse path', parsed.path === '/path?query=1');

// url.format check
check('url.format works', url.format({ protocol: 'https:', hostname: 'example.com', pathname: '/path' }) === 'https://example.com/path');

// url.resolve check
check('url.resolve works', url.resolve('https://example.com/a/b', '/c') === 'https://example.com/c');

// url.fileURLToPath check
check('url.fileURLToPath works', url.fileURLToPath('file:///tmp/test.txt') === '/tmp/test.txt');

// globalThis.global (Node.js legacy compat)
check('globalThis.global exists', typeof global !== 'undefined');
check('globalThis.global === globalThis', global === globalThis);

// process.versions.node
check('process.versions.node', typeof process.versions.node === 'string');
check('process.versions.node is 20.0.0', process.versions.node === '20.0.0');

// util.TextEncoder / util.TextDecoder
check('util.TextEncoder', typeof util.TextEncoder === 'function');
check('util.TextDecoder', typeof util.TextDecoder === 'function');
check('util.TextEncoder is global', util.TextEncoder === TextEncoder);
check('util.TextDecoder is global', util.TextDecoder === TextDecoder);

// events.on (async iterator)
var events = require('events');
check('events.on', typeof events.on === 'function');
check('EventEmitter.on', typeof EventEmitter.on === 'function');
var ee = new EventEmitter();
var iter = events.on(ee, 'data');
check('events.on returns async iterator', typeof iter[Symbol.asyncIterator] === 'function');
check('events.on iterator has next', typeof iter.next === 'function');
check('events.on iterator has return', typeof iter['return'] === 'function');

// http.IncomingMessage / http.ServerResponse / http.ClientRequest
check('http.IncomingMessage', typeof http.IncomingMessage === 'function');
check('http.ServerResponse', typeof http.ServerResponse === 'function');
check('http.ClientRequest', typeof http.ClientRequest === 'function');

// Globals
check('Buffer', typeof Buffer !== 'undefined');
check('setTimeout', typeof setTimeout === 'function');
check('setInterval', typeof setInterval === 'function');
check('clearTimeout', typeof clearTimeout === 'function');
check('console.log', typeof console.log === 'function');
check('console.error', typeof console.error === 'function');
check('console.warn', typeof console.warn === 'function');

// process.getuid/getgid (POSIX)
check('process.getuid', typeof process.getuid === 'function');
check('process.getgid', typeof process.getgid === 'function');
check('process.geteuid', typeof process.geteuid === 'function');
check('process.getegid', typeof process.getegid === 'function');
check('process.getgroups', typeof process.getgroups === 'function');
check('process.getuid returns number', typeof process.getuid() === 'number');
check('process.getgroups returns array', Array.isArray(process.getgroups()));

// child_process extras
check('child_process.execFileSync', typeof cp.execFileSync === 'function');
check('child_process.fork', typeof cp.fork === 'function');

// fs.constants and fs.Dirent
check('fs.constants', typeof fs.constants === 'object');
check('fs.constants.R_OK', fs.constants.R_OK === 4);
check('fs.constants.W_OK', fs.constants.W_OK === 2);
check('fs.constants.F_OK', fs.constants.F_OK === 0);
check('fs.constants.O_RDONLY', fs.constants.O_RDONLY === 0);
check('fs.constants.S_IFDIR', fs.constants.S_IFDIR === 16384);
check('fs.constants.S_IFREG', fs.constants.S_IFREG === 32768);
check('fs.Dirent', typeof fs.Dirent === 'function');
var dirent = new fs.Dirent('test.txt', 1);
check('Dirent.isFile', dirent.isFile() === true);
check('Dirent.isDirectory', dirent.isDirectory() === false);

// Buffer extras
check('Buffer.allocUnsafeSlow', typeof Buffer.allocUnsafeSlow === 'function');
check('Buffer.poolSize', Buffer.poolSize === 8192);

// process gaps
check('process.debugPort', process.debugPort === 9229);
check('process.channel', process.channel === undefined);
check('process.connected', process.connected === false);
check('process.report', typeof process.report === 'object');
check('process.report.writeReport', typeof process.report.writeReport === 'function');
check('process.report.getReport', typeof process.report.getReport === 'function');
check('process.report.reportOnSignal', process.report.reportOnSignal === false);
check('process.report.reportOnFatalError', process.report.reportOnFatalError === false);
check('process.report.reportOnUncaughtException', process.report.reportOnUncaughtException === false);
check('process.resourceUsage', typeof process.resourceUsage === 'function');
var ru = process.resourceUsage();
check('process.resourceUsage returns object', typeof ru === 'object');
check('process.resourceUsage.userCPUTime', typeof ru.userCPUTime === 'number');
check('process.resourceUsage.maxRSS', typeof ru.maxRSS === 'number');
check('process.resourceUsage.voluntaryContextSwitches', typeof ru.voluntaryContextSwitches === 'number');
check('process.allowedNodeEnvironmentFlags', process.allowedNodeEnvironmentFlags instanceof Set);

// http gaps
check('http.maxHeaderSize', http.maxHeaderSize === 16384);
check('http.validateHeaderName', typeof http.validateHeaderName === 'function');
check('http.validateHeaderValue', typeof http.validateHeaderValue === 'function');
// Test that valid header name does not throw
var validHeaderOk = true;
try { http.validateHeaderName('content-type'); } catch(e) { validHeaderOk = false; }
check('http.validateHeaderName valid', validHeaderOk);
// Test that invalid header name throws
var invalidHeaderThrew = false;
try { http.validateHeaderName('bad header\x00'); } catch(e) { invalidHeaderThrew = true; }
check('http.validateHeaderName invalid throws', invalidHeaderThrew);
// Test that valid header value does not throw
var validValueOk = true;
try { http.validateHeaderValue('x-test', 'hello'); } catch(e) { validValueOk = false; }
check('http.validateHeaderValue valid', validValueOk);

// os gaps
check('os.availableParallelism', typeof os.availableParallelism === 'function');
check('os.availableParallelism returns number', typeof os.availableParallelism() === 'number');
check('os.availableParallelism > 0', os.availableParallelism() > 0);
check('os.getPriority', typeof os.getPriority === 'function');
check('os.setPriority', typeof os.setPriority === 'function');
check('os.getPriority returns number', typeof os.getPriority() === 'number');

// crypto extended APIs
check('crypto.createECDH', typeof crypto.createECDH === 'function');
var ecdh = crypto.createECDH('prime256v1');
check('crypto.createECDH returns object', typeof ecdh === 'object');
check('crypto.createECDH.generateKeys', typeof ecdh.generateKeys === 'function');
check('crypto.generateKeySync', typeof crypto.generateKeySync === 'function');
check('crypto.hkdfSync', typeof crypto.hkdfSync === 'function');
check('crypto.hkdf', typeof crypto.hkdf === 'function');
check('crypto.X509Certificate', typeof crypto.X509Certificate === 'function');
check('crypto.KeyObject', typeof crypto.KeyObject === 'function');
check('crypto.createSecretKey', typeof crypto.createSecretKey === 'function');
check('crypto.createPublicKey', typeof crypto.createPublicKey === 'function');
check('crypto.createPrivateKey', typeof crypto.createPrivateKey === 'function');
check('crypto.webcrypto', typeof crypto.webcrypto === 'object');
check('crypto.webcrypto.subtle', typeof crypto.webcrypto.subtle === 'object');
check('crypto.webcrypto.getRandomValues', typeof crypto.webcrypto.getRandomValues === 'function');
check('crypto.webcrypto.randomUUID', typeof crypto.webcrypto.randomUUID === 'function');
check('crypto.subtle', typeof crypto.subtle === 'object');
check('crypto.generateKey', typeof crypto.generateKey === 'function');
check('crypto.generateKeyPair', typeof crypto.generateKeyPair === 'function');
check('crypto.getDiffieHellman', typeof crypto.getDiffieHellman === 'function');
check('crypto.createDiffieHellmanGroup', typeof crypto.createDiffieHellmanGroup === 'function');
check('crypto.diffieHellman', typeof crypto.diffieHellman === 'function');
check('crypto.getCurves', typeof crypto.getCurves === 'function');
check('crypto.getCurves returns array', Array.isArray(crypto.getCurves()));
check('crypto.getCurves has prime256v1', crypto.getCurves().indexOf('prime256v1') >= 0);
check('crypto.secureHeapUsed', typeof crypto.secureHeapUsed === 'function');
check('crypto.setFips', typeof crypto.setFips === 'function');
check('crypto.getFips', typeof crypto.getFips === 'function');
check('crypto.getFips returns 0', crypto.getFips() === 0);
check('crypto.checkPrime', typeof crypto.checkPrime === 'function');
check('crypto.checkPrimeSync', typeof crypto.checkPrimeSync === 'function');
check('crypto.generatePrime', typeof crypto.generatePrime === 'function');
check('crypto.generatePrimeSync', typeof crypto.generatePrimeSync === 'function');
check('crypto.hash', typeof crypto.hash === 'function');
var hashResult = crypto.hash('sha256', 'hello');
check('crypto.hash sha256 works', typeof hashResult === 'string' && hashResult.length === 64);

// stream extended APIs
check('stream.compose', typeof stream.compose === 'function');
check('stream.isErrored', typeof stream.isErrored === 'function');
check('stream.isReadable', typeof stream.isReadable === 'function');
check('stream.isDisturbed', typeof stream.isDisturbed === 'function');
check('stream.consumers', typeof stream.consumers === 'object');
check('stream.consumers.text', typeof stream.consumers.text === 'function');
check('stream.consumers.json', typeof stream.consumers.json === 'function');
check('stream.consumers.arrayBuffer', typeof stream.consumers.arrayBuffer === 'function');
check('stream.Duplex', typeof stream.Duplex === 'function');
check('stream.PassThrough', typeof stream.PassThrough === 'function');

// events extended APIs
check('events.captureRejectionSymbol', typeof events.captureRejectionSymbol === 'symbol');
check('events.captureRejections', events.captureRejections === false);
check('events.errorMonitor', typeof events.errorMonitor === 'symbol');
check('events.getEventListeners', typeof events.getEventListeners === 'function');
check('events.getMaxListeners', typeof events.getMaxListeners === 'function');
check('events.setMaxListeners', typeof events.setMaxListeners === 'function');
check('events.addAbortListener', typeof events.addAbortListener === 'function');

// util extended APIs
check('util.getSystemErrorName', typeof util.getSystemErrorName === 'function');
check('util.getSystemErrorName ENOENT', util.getSystemErrorName(-2) === 'ENOENT');
check('util.parseArgs', typeof util.parseArgs === 'function');
check('util.styleText', typeof util.styleText === 'function');
check('util.MIMEType', typeof util.MIMEType === 'function');
var mime = new util.MIMEType('text/html; charset=utf-8');
check('util.MIMEType.type', mime.type === 'text');
check('util.MIMEType.subtype', mime.subtype === 'html');
check('util.MIMEType.essence', mime.essence === 'text/html');
check('util.aborted', typeof util.aborted === 'function');
check('util.transferableAbortController', typeof util.transferableAbortController === 'function');
check('util.transferableAbortSignal', typeof util.transferableAbortSignal === 'function');
check('util.getCallSites', typeof util.getCallSites === 'function');

// fs extended APIs
check('fs.ftruncateSync', typeof fs.ftruncateSync === 'function');
check('fs.futimesSync', typeof fs.futimesSync === 'function');
check('fs.lutimesSync', typeof fs.lutimesSync === 'function');
check('fs.fdatasyncSync', typeof fs.fdatasyncSync === 'function');

// net extended APIs
check('net.BlockList', typeof net.BlockList === 'function');
var bl = new net.BlockList();
check('net.BlockList.addAddress', typeof bl.addAddress === 'function');
check('net.BlockList.check', typeof bl.check === 'function');
check('net.SocketAddress', typeof net.SocketAddress === 'function');
var sa = new net.SocketAddress({ address: '10.0.0.1', port: 8080 });
check('net.SocketAddress.address', sa.address === '10.0.0.1');
check('net.SocketAddress.port', sa.port === 8080);

// path extended APIs
check('path.matchesGlob', typeof path.matchesGlob === 'function');
check('path.matchesGlob works', path.matchesGlob('foo.js', '*.js') === true);
check('path.matchesGlob negative', path.matchesGlob('foo.ts', '*.js') === false);

console.log('---');
console.log('Total: ' + passed + '/' + checks + ' passed');
