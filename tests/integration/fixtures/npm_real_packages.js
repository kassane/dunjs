// Test real installed npm packages
var passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) { passed++; }
  else { console.log('FAIL:', name); }
}

// chalk v5 (ESM with alias exports)
try {
  const chalk = require('chalk');
  check('chalk loads', typeof chalk === 'object');
  check('chalk.Chalk is function', typeof chalk.Chalk === 'function');
  check('chalk.foregroundColors array', Array.isArray(chalk.foregroundColors));
  check('chalk.backgroundColors array', Array.isArray(chalk.backgroundColors));
  check('chalk.modifierNames array', Array.isArray(chalk.modifierNames));
  check('chalk.colorNames array', Array.isArray(chalk.colorNames));
} catch(e) { console.log('FAIL: chalk load:', e.message); total += 6; }

// ms (CJS, simple)
try {
  const ms = require('ms');
  check('ms("2 days")', ms('2 days') === 172800000);
  check('ms(60000)', ms(60000) === '1m');
  check('ms("1h")', ms('1h') === 3600000);
  check('ms("10s")', ms('10s') === 10000);
} catch(e) { console.log('FAIL: ms load:', e.message); total += 4; }

// semver (CJS, complex)
try {
  const semver = require('semver');
  check('semver.valid("1.2.3")', semver.valid('1.2.3') !== null);
  check('semver.valid("invalid")', semver.valid('invalid') === null);
  check('semver.gt', semver.gt('2.0.0', '1.0.0'));
  check('semver.lt', semver.lt('1.0.0', '2.0.0'));
  check('semver.satisfies >=', semver.satisfies('1.2.3', '>=1.0.0'));
  check('semver.satisfies ^', semver.satisfies('1.2.3', '^1.0.0'));
  check('semver.clean', semver.clean(' =v1.2.3 ') === '1.2.3');
  check('semver.coerce', semver.coerce('v2').version === '2.0.0');
} catch(e) { console.log('FAIL: semver load:', e.message); total += 8; }

// debug (CJS, factory pattern)
try {
  const debug = require('debug');
  check('debug is function', typeof debug === 'function');
  var d = debug('test:app');
  check('debug() returns function', typeof d === 'function');
  check('debug.enable exists', typeof debug.enable === 'function');
  check('debug.disable exists', typeof debug.disable === 'function');
} catch(e) { console.log('FAIL: debug load:', e.message); total += 4; }

// minimist (CJS)
try {
  const minimist = require('minimist');
  var args = minimist(['--foo', 'bar', '-x', '3', '--no-beep', 'extra']);
  check('minimist --foo', args.foo === 'bar');
  check('minimist -x number', args.x === 3);
  check('minimist --no-beep', args.beep === false);
  check('minimist positional', args._[0] === 'extra');
  check('minimist boolean', minimist(['--debug'], { boolean: ['debug'] }).debug === true);
} catch(e) { console.log('FAIL: minimist load:', e.message); total += 5; }

// dotenv (CJS)
try {
  const dotenv = require('dotenv');
  check('dotenv.parse exists', typeof dotenv.parse === 'function');
  var result = dotenv.parse('KEY=value\nFOO=bar\nQUOTED="hello world"');
  check('dotenv.parse KEY', result.KEY === 'value');
  check('dotenv.parse FOO', result.FOO === 'bar');
  check('dotenv.parse QUOTED', result.QUOTED === '"hello world"' || result.QUOTED === 'hello world');
} catch(e) { console.log('FAIL: dotenv load:', e.message); total += 4; }

// uuid v14 (ESM)
try {
  const uuid = require('uuid');
  check('uuid.v4 exists', typeof uuid.v4 === 'function');
  var id = uuid.v4();
  check('uuid.v4() format', typeof id === 'string' && id.length === 36);
  check('uuid.v4() version', id[14] === '4');
  check('uuid.v4() variant', '89ab'.indexOf(id[19]) >= 0);
  var id2 = uuid.v4();
  check('uuid.v4() unique', id !== id2);
} catch(e) { console.log('FAIL: uuid load:', e.message); total += 5; }

// which (CJS)
try {
  const which = require('which');
  check('which loads', typeof which === 'function' || typeof which.sync === 'function');
} catch(e) { console.log('FAIL: which load:', e.message); total += 1; }

// commander (CJS, class-based)
try {
  const { Command } = require('commander');
  check('commander.Command is function', typeof Command === 'function');
  var prog = new Command();
  prog.name('test').version('1.0.0');
  check('commander.parse exists', typeof prog.parse === 'function');
  check('commander.option exists', typeof prog.option === 'function');
} catch(e) { console.log('FAIL: commander load:', e.message); total += 3; }

// yargs-parser (ESM with createRequire + import.meta)
try {
  const parser = require('yargs-parser');
  check('yargs-parser is function', typeof parser === 'function');
  var result = parser(['--foo', 'bar', '--baz']);
  check('yargs-parser --foo', result.foo === 'bar');
  check('yargs-parser --baz', result.baz === true);
} catch(e) { console.log('FAIL: yargs-parser load:', e.message); total += 3; }

// depd (CJS, uses Error.captureStackTrace + CallSite API)
try {
  const depd = require('depd');
  check('depd is function', typeof depd === 'function');
  var deprecate = depd('test-namespace');
  check('depd() returns function', typeof deprecate === 'function');
  check('depd.function exists', typeof deprecate.function === 'function');
  check('depd.property exists', typeof deprecate.property === 'function');
} catch(e) { console.log('FAIL: depd load:', e.message); total += 4; }

// on-finished (CJS, HTTP utility)
try {
  const onFinished = require('on-finished');
  check('on-finished is function', typeof onFinished === 'function');
  check('on-finished.isFinished exists', typeof onFinished.isFinished === 'function');
} catch(e) { console.log('FAIL: on-finished load:', e.message); total += 2; }

// mime-types (CJS, content-type mapping)
try {
  const mime = require('mime-types');
  check('mime-types.lookup html', mime.lookup('file.html') === 'text/html');
  check('mime-types.lookup json', mime.lookup('file.json') === 'application/json');
  check('mime-types.lookup css', mime.lookup('file.css') === 'text/css');
  check('mime-types.contentType', typeof mime.contentType === 'function');
  check('mime-types.extension', typeof mime.extension === 'function');
} catch(e) { console.log('FAIL: mime-types load:', e.message); total += 5; }

// cookie (CJS, cookie parsing)
try {
  const cookie = require('cookie');
  check('cookie.parse exists', typeof cookie.parse === 'function');
  check('cookie.serialize exists', typeof cookie.serialize === 'function');
  var parsed = cookie.parse('foo=bar; baz=qux');
  check('cookie.parse foo', parsed.foo === 'bar');
  check('cookie.parse baz', parsed.baz === 'qux');
} catch(e) { console.log('FAIL: cookie load:', e.message); total += 4; }

// escape-html (CJS, XSS prevention)
try {
  const escapeHtml = require('escape-html');
  check('escape-html is function', typeof escapeHtml === 'function');
  check('escape-html <script>', escapeHtml('<script>') === '&lt;script&gt;');
  check('escape-html &', escapeHtml('a&b') === 'a&amp;b');
} catch(e) { console.log('FAIL: escape-html load:', e.message); total += 3; }

// lodash (CJS, complex utility library)
try {
  const _ = require('lodash');
  check('lodash loads', typeof _ === 'function');
  check('lodash.map', _.map([1,2,3], function(x){return x*2}).join(',') === '2,4,6');
  check('lodash.uniq', _.uniq([1,2,1,3,2]).join(',') === '1,2,3');
  check('lodash.groupBy', typeof _.groupBy([1,2,3], function(x){return x%2}) === 'object');
  check('lodash.cloneDeep', typeof _.cloneDeep === 'function');
} catch(e) { console.log('FAIL: lodash load:', e.message); total += 5; }

// safe-buffer (CJS, Buffer wrapper)
try {
  const safeBuf = require('safe-buffer');
  check('safe-buffer loads', safeBuf.Buffer !== undefined);
  check('safe-buffer.from', safeBuf.Buffer.from('hello').toString() === 'hello');
  check('safe-buffer.alloc', safeBuf.Buffer.alloc(10).length === 10);
} catch(e) { console.log('FAIL: safe-buffer load:', e.message); total += 3; }

// content-type (CJS, HTTP content-type parsing)
try {
  const contentType = require('content-type');
  check('content-type.parse', typeof contentType.parse === 'function');
  var ct = contentType.parse('text/html; charset=utf-8');
  check('content-type type', ct.type === 'text/html');
  check('content-type charset', ct.parameters.charset === 'utf-8');
} catch(e) { console.log('FAIL: content-type load:', e.message); total += 3; }

// accepts (CJS, HTTP content negotiation)
try {
  const Accepts = require('accepts');
  check('accepts loads', typeof Accepts === 'function');
  var req = { headers: { accept: 'text/html, application/json' } };
  var accept = Accepts(req);
  check('accepts.types exists', typeof accept.types === 'function');
} catch(e) { console.log('FAIL: accepts load:', e.message); total += 2; }

// type-is (CJS, content type checking)
try {
  const typeis = require('type-is');
  check('type-is loads', typeof typeis === 'function');
  check('type-is.is exists', typeof typeis.is === 'function');
} catch(e) { console.log('FAIL: type-is load:', e.message); total += 2; }

// bytes (CJS, byte size parsing)
try {
  const bytes = require('bytes');
  check('bytes.parse 1kb', bytes.parse('1kb') === 1024);
  check('bytes.format 1024', bytes.format(1024) === '1KB');
} catch(e) { console.log('FAIL: bytes load:', e.message); total += 2; }

// iconv-lite (CJS, encoding with lazy internal require)
try {
  const iconv = require('iconv-lite');
  check('iconv-lite loads', typeof iconv.decode === 'function');
  check('iconv-lite encode exists', typeof iconv.encode === 'function');
  check('iconv-lite encodingExists', iconv.encodingExists('utf8') === true);
} catch(e) { console.log('FAIL: iconv-lite load:', e.message); total += 3; }

console.log('npm_real_packages: ' + passed + '/' + total + ' checks passed');
if (passed === total) console.log('ALL CHECKS PASSED');
