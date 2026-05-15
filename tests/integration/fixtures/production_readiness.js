// DunJS Production Readiness: 122-check comprehensive validation
// Tests all critical Node.js APIs needed for production server workloads
var pass = 0, fail = 0;
function check(name, fn) {
  try { if (fn()) { pass++; } else { fail++; console.log("FAIL: " + name); } }
  catch(e) { fail++; console.log("FAIL: " + name + " (" + (e.message || e) + ")"); }
}

// === Core APIs (14) ===
check("require caching", function() { return require('fs') === require('fs'); });
check("process.env Proxy", function() { process.env._T='1'; var v=process.env._T; delete process.env._T; return v==='1'; });
check("process.cwd()", function() { return typeof process.cwd() === 'string'; });
check("process.argv", function() { return Array.isArray(process.argv); });
check("process.exit exists", function() { return typeof process.exit === 'function'; });
check("process.nextTick", function() { return typeof process.nextTick === 'function'; });
check("process.pid", function() { return typeof process.pid === 'number' && process.pid > 0; });
check("process.platform", function() { return process.platform === 'linux' || process.platform === 'darwin'; });
check("console.log/warn/error", function() { return typeof console.log==='function' && typeof console.warn==='function'; });
check("setTimeout/setInterval", function() { return typeof setTimeout==='function' && typeof setInterval==='function'; });
check("JSON.parse/stringify", function() { return JSON.parse(JSON.stringify({a:1})).a === 1; });
check("Error stack traces", function() { return new Error('test').stack.length > 0; });
check("Promise", function() { return typeof Promise === 'function'; });
check("async/await", function() { return typeof (async function(){}) === 'function'; });

// === File System (15) ===
var fs = require('fs');
var _d = '/tmp/dun_pr_' + process.pid;
check("fs.writeFileSync+readFileSync", function() { fs.writeFileSync(_d,'test'); return fs.readFileSync(_d,'utf8')==='test'; });
check("fs.readFileSync Buffer", function() { return Buffer.isBuffer(fs.readFileSync(_d)); });
check("fs.existsSync", function() { return fs.existsSync('/tmp'); });
check("fs.mkdirSync recursive", function() { fs.mkdirSync(_d+'d/a/b',{recursive:true}); return fs.existsSync(_d+'d/a/b'); });
check("fs.statSync", function() { return fs.statSync('/tmp').isDirectory(); });
check("fs.readdirSync", function() { return Array.isArray(fs.readdirSync('/tmp')); });
check("fs.unlinkSync", function() { fs.unlinkSync(_d); return !fs.existsSync(_d); });
check("fs.copyFileSync", function() { fs.writeFileSync(_d,'cp'); fs.copyFileSync(_d,_d+'2'); var ok=fs.readFileSync(_d+'2','utf8')==='cp'; fs.unlinkSync(_d); fs.unlinkSync(_d+'2'); return ok; });
check("fs.renameSync", function() { fs.writeFileSync(_d,'rn'); fs.renameSync(_d,_d+'r'); var ok=fs.readFileSync(_d+'r','utf8')==='rn'; fs.unlinkSync(_d+'r'); return ok; });
check("fs.appendFileSync", function() { fs.writeFileSync(_d,'a'); fs.appendFileSync(_d,'b'); var ok=fs.readFileSync(_d,'utf8')==='ab'; fs.unlinkSync(_d); return ok; });
check("fs.accessSync", function() { try{fs.accessSync('/tmp');return true;}catch(e){return false;} });
check("fs.realpathSync", function() { return typeof fs.realpathSync('/tmp')==='string'; });
check("fs.constants", function() { return typeof fs.constants.F_OK === 'number'; });
check("fs.rmSync recursive", function() { fs.writeFileSync(_d+'d/a/b/f','x'); fs.rmSync(_d+'d',{recursive:true}); return !fs.existsSync(_d+'d'); });
check("fs.createReadStream", function() { return typeof fs.createReadStream === 'function'; });

// === Buffer (10) ===
check("Buffer.from string", function() { return Buffer.from('Hello').toString()==='Hello'; });
check("Buffer.from base64", function() { return Buffer.from('SGVsbG8=','base64').toString()==='Hello'; });
check("Buffer.from hex", function() { return Buffer.from('48656c6c6f','hex').toString()==='Hello'; });
check("Buffer.alloc+fill", function() { return Buffer.alloc(4,'ab').toString()==='abab'; });
check("Buffer.concat", function() { return Buffer.concat([Buffer.from('a'),Buffer.from('b')]).toString()==='ab'; });
check("Buffer.isBuffer", function() { return Buffer.isBuffer(Buffer.from('x')) && !Buffer.isBuffer('x'); });
check("Buffer read/write", function() { var b=Buffer.alloc(4); b.writeUInt32BE(0x12345678,0); return b.readUInt32BE(0)===0x12345678; });
check("typeof Buffer", function() { return typeof Buffer === 'function'; });
check("Buffer.isEncoding case-insensitive", function() { return Buffer.isEncoding('UTF-8') && Buffer.isEncoding('hex'); });
check("Buffer.from Uint8Array", function() { return Buffer.from(new Uint8Array([65,66])).toString()==='AB'; });

// === Crypto (8) ===
var crypto = require('crypto');
check("crypto.createHash", function() { return crypto.createHash('sha256').update('test').digest('hex').length===64; });
check("crypto.createHmac", function() { return crypto.createHmac('sha256','key').update('msg').digest('hex').length===64; });
check("crypto.randomBytes", function() { return crypto.randomBytes(32).length===32; });
check("crypto.randomUUID", function() { return /^[0-9a-f-]{36}$/.test(crypto.randomUUID()); });
check("crypto.pbkdf2Sync", function() { return crypto.pbkdf2Sync('pw','salt',1000,32,'sha256').length===32; });
check("crypto.scryptSync", function() { return crypto.scryptSync('pw','salt',32).length===32; });
check("crypto.createCipheriv", function() { var k=crypto.randomBytes(32),iv=crypto.randomBytes(16); var c=crypto.createCipheriv('aes-256-cbc',k,iv); var e=c.update('t','utf8','hex')+c.final('hex'); var d=crypto.createDecipheriv('aes-256-cbc',k,iv); return d.update(e,'hex','utf8')+d.final('utf8')==='t'; });
check("crypto.timingSafeEqual", function() { return crypto.timingSafeEqual(Buffer.from('abc'),Buffer.from('abc')); });

// === Path (9) ===
var path = require('path');
check("path.join", function() { return path.join('/a','b','c')==='/a/b/c'; });
check("path.resolve", function() { return path.resolve('/a','b')==='/a/b'; });
check("path.dirname", function() { return path.dirname('/a/b/c.js')==='/a/b'; });
check("path.basename", function() { return path.basename('/a/b/c.js')==='c.js'; });
check("path.extname", function() { return path.extname('file.js')==='.js'; });
check("path.parse", function() { var p=path.parse('/a/b.js'); return p.dir==='/a'&&p.base==='b.js'; });
check("path.normalize", function() { return path.normalize('/a/b/../c')==='/a/c'; });
check("path.isAbsolute", function() { return path.isAbsolute('/x')&&!path.isAbsolute('x'); });
check("path.sep", function() { return path.sep==='/'; });

// === Events (4) ===
var EventEmitter = require('events');
check("EventEmitter on/emit", function() { var e=new EventEmitter(); var v=0; e.on('x',function(){v=1;}); e.emit('x'); return v===1; });
check("EventEmitter once", function() { var e=new EventEmitter(); var c=0; e.once('x',function(){c++;}); e.emit('x'); e.emit('x'); return c===1; });
check("EventEmitter removeListener", function() { var e=new EventEmitter(); var fn=function(){}; e.on('x',fn); e.removeListener('x',fn); return e.listenerCount('x')===0; });
check("EventEmitter error", function() { var e=new EventEmitter(); var err=null; e.on('error',function(x){err=x;}); e.emit('error',new Error('t')); return err.message==='t'; });

// === Stream (5) ===
var stream = require('stream');
check("stream.Readable", function() { return typeof new stream.Readable({read:function(){}}).read==='function'; });
check("stream.Writable", function() { var w=new stream.Writable({write:function(c,e,cb){cb();}}); w.write('x'); return true; });
check("stream.Transform", function() { var t=new stream.Transform({transform:function(c,e,cb){this.push(c.toString().toUpperCase());cb();}}); var r=''; t.on('data',function(d){r+=d;}); t.write('hi'); return r==='HI'; });
check("stream.pipeline", function() { return typeof stream.pipeline==='function'; });
check("stream pipe", function() { var r=new stream.Readable({read:function(){}}); var c=[]; var w=new stream.Writable({write:function(d,e,cb){c.push(d.toString());cb();}}); r.pipe(w); r.push('d'); r.push(null); return c.length===1; });

// === URL (3) ===
check("URL constructor", function() { return new URL('https://example.com/p?q=1').pathname==='/p'; });
check("URL with base", function() { return new URL('/api','https://example.com').href==='https://example.com/api'; });
check("URLSearchParams", function() { return new URLSearchParams('a=1&b=2').get('a')==='1'; });

// === OS (8) ===
var os = require('os');
check("os.platform", function() { return os.platform()==='linux'||os.platform()==='darwin'; });
check("os.arch", function() { return typeof os.arch()==='string'; });
check("os.tmpdir", function() { return os.tmpdir()==='/tmp'; });
check("os.homedir", function() { return typeof os.homedir()==='string'; });
check("os.hostname", function() { return typeof os.hostname()==='string'; });
check("os.cpus", function() { return os.cpus().length>0; });
check("os.totalmem", function() { return os.totalmem()>0; });
check("os.EOL", function() { return os.EOL==='\n'; });

// === child_process (2) ===
var cp = require('child_process');
check("execSync", function() { return cp.execSync('echo hello').toString().trim()==='hello'; });
check("spawnSync", function() { return cp.spawnSync('echo',['world']).stdout.toString().trim()==='world'; });

// === zlib (2) ===
var zlib = require('zlib');
check("deflateSync/inflateSync", function() { return zlib.inflateSync(zlib.deflateSync(Buffer.from('test'))).toString()==='test'; });
check("gzipSync/gunzipSync", function() { return zlib.gunzipSync(zlib.gzipSync(Buffer.from('test'))).toString()==='test'; });

// === Module resolution (17) ===
check("require fs", function() { return typeof require('fs').readFileSync==='function'; });
check("require path", function() { return typeof require('path').join==='function'; });
check("require crypto", function() { return typeof require('crypto').createHash==='function'; });
check("require events", function() { return typeof require('events')==='function'; });
check("require stream", function() { return typeof require('stream').Readable==='function'; });
check("require url", function() { return typeof require('url')==='object'; });
check("require os", function() { return typeof require('os').platform==='function'; });
check("require util", function() { return typeof require('util').format==='function'; });
check("require buffer", function() { return typeof require('buffer').Buffer==='function'; });
check("require querystring", function() { return typeof require('querystring').parse==='function'; });
check("require assert", function() { return typeof require('assert')==='function'; });
check("require child_process", function() { return typeof require('child_process').execSync==='function'; });
check("require zlib", function() { return typeof require('zlib').deflateSync==='function'; });
check("require dns", function() { return typeof require('dns').lookup==='function'; });
check("require net", function() { return typeof require('net').createServer==='function'; });
check("require http", function() { return typeof require('http').createServer==='function'; });
check("require string_decoder", function() { return typeof require('string_decoder')==='object'; });

// === Web APIs (12) ===
check("TextEncoder/TextDecoder", function() { return new TextDecoder().decode(new TextEncoder().encode('Hi'))==='Hi'; });
check("fetch global", function() { return typeof fetch==='function'; });
check("Headers", function() { return new Headers({'x':'1'}).get('x')==='1'; });
check("Request", function() { return new Request('https://example.com').url==='https://example.com'; });
check("Response", function() { return new Response('ok').status===200; });
check("AbortController", function() { var ac=new AbortController(); ac.abort(); return ac.signal.aborted; });
check("structuredClone", function() { return structuredClone({a:1}).a===1; });
check("atob/btoa", function() { return atob(btoa('test'))==='test'; });
check("performance.now", function() { return typeof performance.now()==='number'; });
check("queueMicrotask", function() { return typeof queueMicrotask==='function'; });
check("Blob", function() { return new Blob(['test']).size===4; });
check("crypto.randomUUID global", function() { return typeof crypto.randomUUID==='function'; });

// === ES2020+ (13) ===
check("Optional chaining", function() { return {a:{b:1}}?.a?.b===1; });
check("Nullish coalescing", function() { return (null??'def')==='def'; });
check("Promise.allSettled", function() { return typeof Promise.allSettled==='function'; });
check("Promise.any", function() { return typeof Promise.any==='function'; });
check("Array.flat/flatMap", function() { return [1,[2]].flat().length===2; });
check("Object.fromEntries", function() { return Object.fromEntries([['a',1]]).a===1; });
check("String.replaceAll", function() { return 'aaa'.replaceAll('a','b')==='bbb'; });
check("WeakRef", function() { var o={x:1}; return new WeakRef(o).deref().x===1; });
check("globalThis", function() { return typeof globalThis==='object'; });
check("Array.at", function() { return [1,2,3].at(-1)===3; });
check("Array.findLast", function() { return [1,2,3].findLast(function(x){return x<3;})===2; });
check("Error.cause", function() { return new Error('x',{cause:new Error('y')}).cause.message==='y'; });
check("structuredClone deep", function() { var o={a:[1,{b:2}]}; var c=structuredClone(o); c.a[1].b=9; return o.a[1].b===2; });

console.log("Production readiness: " + pass + "/" + (pass + fail) + " passed");
