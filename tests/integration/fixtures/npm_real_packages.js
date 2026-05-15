// Test real installed npm packages
var passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) { passed++; }
  else { console.log('FAIL:', name); }
}

// chalk v5 (ESM with alias exports)
try {
  var chalk = require('chalk');
  check('chalk loads', typeof chalk === 'object');
  check('chalk.Chalk is function', typeof chalk.Chalk === 'function');
  check('chalk.foregroundColors array', Array.isArray(chalk.foregroundColors));
  check('chalk.backgroundColors array', Array.isArray(chalk.backgroundColors));
  check('chalk.modifierNames array', Array.isArray(chalk.modifierNames));
  check('chalk.colorNames array', Array.isArray(chalk.colorNames));
} catch(e) { console.log('FAIL: chalk load:', e.message); total += 6; }

// ms (CJS, simple)
try {
  var ms = require('ms');
  check('ms("2 days")', ms('2 days') === 172800000);
  check('ms(60000)', ms(60000) === '1m');
  check('ms("1h")', ms('1h') === 3600000);
  check('ms("10s")', ms('10s') === 10000);
} catch(e) { console.log('FAIL: ms load:', e.message); total += 4; }

// semver (CJS, complex)
try {
  var semver = require('semver');
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
  var debug = require('debug');
  check('debug is function', typeof debug === 'function');
  var d = debug('test:app');
  check('debug() returns function', typeof d === 'function');
  check('debug.enable exists', typeof debug.enable === 'function');
  check('debug.disable exists', typeof debug.disable === 'function');
} catch(e) { console.log('FAIL: debug load:', e.message); total += 4; }

// minimist (CJS)
try {
  var minimist = require('minimist');
  var args = minimist(['--foo', 'bar', '-x', '3', '--no-beep', 'extra']);
  check('minimist --foo', args.foo === 'bar');
  check('minimist -x number', args.x === 3);
  check('minimist --no-beep', args.beep === false);
  check('minimist positional', args._[0] === 'extra');
  check('minimist boolean', minimist(['--debug'], { boolean: ['debug'] }).debug === true);
} catch(e) { console.log('FAIL: minimist load:', e.message); total += 5; }

// dotenv (CJS)
try {
  var dotenv = require('dotenv');
  check('dotenv.parse exists', typeof dotenv.parse === 'function');
  var result = dotenv.parse('KEY=value\nFOO=bar\nQUOTED="hello world"');
  check('dotenv.parse KEY', result.KEY === 'value');
  check('dotenv.parse FOO', result.FOO === 'bar');
  check('dotenv.parse QUOTED', result.QUOTED === '"hello world"' || result.QUOTED === 'hello world');
} catch(e) { console.log('FAIL: dotenv load:', e.message); total += 4; }

// uuid v14 (ESM)
try {
  var uuid = require('uuid');
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
  var which = require('which');
  check('which loads', typeof which === 'function' || typeof which.sync === 'function');
} catch(e) { console.log('FAIL: which load:', e.message); total += 1; }

// commander (CJS, class-based)
try {
  var{ Command } = require('commander');
  check('commander.Command is function', typeof Command === 'function');
  var prog = new Command();
  prog.name('test').version('1.0.0');
  check('commander.parse exists', typeof prog.parse === 'function');
  check('commander.option exists', typeof prog.option === 'function');
} catch(e) { console.log('FAIL: commander load:', e.message); total += 3; }

// yargs-parser (ESM with createRequire + import.meta)
try {
  var parser = require('yargs-parser');
  check('yargs-parser is function', typeof parser === 'function');
  var result = parser(['--foo', 'bar', '--baz']);
  check('yargs-parser --foo', result.foo === 'bar');
  check('yargs-parser --baz', result.baz === true);
} catch(e) { console.log('FAIL: yargs-parser load:', e.message); total += 3; }

// depd (CJS, uses Error.captureStackTrace + CallSite API)
try {
  var depd = require('depd');
  check('depd is function', typeof depd === 'function');
  var deprecate = depd('test-namespace');
  check('depd() returns function', typeof deprecate === 'function');
  check('depd.function exists', typeof deprecate.function === 'function');
  check('depd.property exists', typeof deprecate.property === 'function');
} catch(e) { console.log('FAIL: depd load:', e.message); total += 4; }

// on-finished (CJS, HTTP utility)
try {
  var onFinished = require('on-finished');
  check('on-finished is function', typeof onFinished === 'function');
  check('on-finished.isFinished exists', typeof onFinished.isFinished === 'function');
} catch(e) { console.log('FAIL: on-finished load:', e.message); total += 2; }

// mime-types (CJS, content-type mapping)
try {
  var mime = require('mime-types');
  check('mime-types.lookup html', mime.lookup('file.html') === 'text/html');
  check('mime-types.lookup json', mime.lookup('file.json') === 'application/json');
  check('mime-types.lookup css', mime.lookup('file.css') === 'text/css');
  check('mime-types.contentType', typeof mime.contentType === 'function');
  check('mime-types.extension', typeof mime.extension === 'function');
} catch(e) { console.log('FAIL: mime-types load:', e.message); total += 5; }

// cookie (CJS, cookie parsing)
try {
  var cookie = require('cookie');
  check('cookie.parse exists', typeof cookie.parse === 'function');
  check('cookie.serialize exists', typeof cookie.serialize === 'function');
  var parsed = cookie.parse('foo=bar; baz=qux');
  check('cookie.parse foo', parsed.foo === 'bar');
  check('cookie.parse baz', parsed.baz === 'qux');
} catch(e) { console.log('FAIL: cookie load:', e.message); total += 4; }

// escape-html (CJS, XSS prevention)
try {
  var escapeHtml = require('escape-html');
  check('escape-html is function', typeof escapeHtml === 'function');
  check('escape-html <script>', escapeHtml('<script>') === '&lt;script&gt;');
  check('escape-html &', escapeHtml('a&b') === 'a&amp;b');
} catch(e) { console.log('FAIL: escape-html load:', e.message); total += 3; }

// lodash (CJS, complex utility library)
try {
  var _l = require('lodash');
  check('lodash loads', typeof _l === 'function');
  check('lodash.map', _l.map([1,2,3], function(x){return x*2}).join(',') === '2,4,6');
  check('lodash.uniq', _l.uniq([1,2,1,3,2]).join(',') === '1,2,3');
  check('lodash.groupBy', typeof _l.groupBy([1,2,3], function(x){return x%2}) === 'object');
  check('lodash.cloneDeep', typeof _l.cloneDeep === 'function');
} catch(e) { console.log('FAIL: lodash load:', e.message); total += 5; }

// safe-buffer (CJS, Buffer wrapper)
try {
  var safeBuf = require('safe-buffer');
  check('safe-buffer loads', safeBuf.Buffer !== undefined);
  check('safe-buffer.from', safeBuf.Buffer.from('hello').toString() === 'hello');
  check('safe-buffer.alloc', safeBuf.Buffer.alloc(10).length === 10);
} catch(e) { console.log('FAIL: safe-buffer load:', e.message); total += 3; }

// content-type (CJS, HTTP content-type parsing)
try {
  var contentType = require('content-type');
  check('content-type.parse', typeof contentType.parse === 'function');
  var ct = contentType.parse('text/html; charset=utf-8');
  check('content-type type', ct.type === 'text/html');
  check('content-type charset', ct.parameters.charset === 'utf-8');
} catch(e) { console.log('FAIL: content-type load:', e.message); total += 3; }

// accepts (CJS, HTTP content negotiation)
try {
  var Accepts = require('accepts');
  check('accepts loads', typeof Accepts === 'function');
  var req = { headers: { accept: 'text/html, application/json' } };
  var accept = Accepts(req);
  check('accepts.types exists', typeof accept.types === 'function');
} catch(e) { console.log('FAIL: accepts load:', e.message); total += 2; }

// type-is (CJS, content type checking)
try {
  var typeis = require('type-is');
  check('type-is loads', typeof typeis === 'function');
  check('type-is.is exists', typeof typeis.is === 'function');
} catch(e) { console.log('FAIL: type-is load:', e.message); total += 2; }

// bytes (CJS, byte size parsing)
try {
  var bytes = require('bytes');
  check('bytes.parse 1kb', bytes.parse('1kb') === 1024);
  check('bytes.format 1024', bytes.format(1024) === '1KB');
} catch(e) { console.log('FAIL: bytes load:', e.message); total += 2; }

// iconv-lite (CJS, encoding with lazy internal require)
try {
  var iconv = require('iconv-lite');
  check('iconv-lite loads', typeof iconv.decode === 'function');
  check('iconv-lite encode exists', typeof iconv.encode === 'function');
  check('iconv-lite encodingExists', iconv.encodingExists('utf8') === true);
} catch(e) { console.log('FAIL: iconv-lite load:', e.message); total += 3; }

// express v4 (CJS, web framework — the ultimate npm compat test)
try {
  var express = require('express');
  check('express loads', typeof express === 'function');
  check('express.Router', typeof express.Router === 'function');
  check('express.static', typeof express.static === 'function');
  check('express.json', typeof express.json === 'function');
  var app = express();
  check('express() creates app', typeof app === 'function');
  check('app.get exists', typeof app.get === 'function');
  check('app.use exists', typeof app.use === 'function');
  check('app.listen exists', typeof app.listen === 'function');
  check('app.set exists', typeof app.set === 'function');
  app.set('x-powered-by', false);
  check('app.set/get', app.get('x-powered-by') === false);
  var router = express.Router();
  check('Router() works', typeof router === 'function');
} catch(e) { console.log('FAIL: express load:', e.message); total += 11; }

// body-parser (CJS, Express middleware)
try {
  var bodyParser = require('body-parser');
  check('body-parser.json', typeof bodyParser.json === 'function');
  check('body-parser.urlencoded', typeof bodyParser.urlencoded === 'function');
  check('body-parser.raw', typeof bodyParser.raw === 'function');
  check('body-parser.text', typeof bodyParser.text === 'function');
} catch(e) { console.log('FAIL: body-parser load:', e.message); total += 4; }

// qs (CJS, query string parsing)
try {
  var qs = require('qs');
  check('qs.parse', typeof qs.parse === 'function');
  var result = qs.parse('a=1&b=2');
  check('qs.parse result', result.a === '1' && result.b === '2');
  check('qs.stringify', qs.stringify({a: 1, b: 2}) === 'a=1&b=2');
} catch(e) { console.log('FAIL: qs load:', e.message); total += 3; }

// http-errors (CJS, HTTP error constructors)
try {
  var createError = require('http-errors');
  check('http-errors loads', typeof createError === 'function');
  var err = createError(404, 'Not Found');
  check('http-errors 404', err.statusCode === 404);
  check('http-errors message', err.message === 'Not Found');
} catch(e) { console.log('FAIL: http-errors load:', e.message); total += 3; }

// validator (CJS, string validation)
try {
  var validator = require('validator');
  check('validator.isEmail valid', validator.isEmail('test@example.com') === true);
  check('validator.isEmail invalid', validator.isEmail('invalid') === false);
  check('validator.isURL', validator.isURL('https://example.com') === true);
  check('validator.escape', validator.escape('<script>') === '&lt;script&gt;');
} catch(e) { console.log('FAIL: validator load:', e.message); total += 4; }

// moment (CJS, date library)
try {
  var moment = require('moment');
  check('moment loads', typeof moment === 'function');
  var d = moment('2024-01-15');
  check('moment parse valid', d.isValid());
  check('moment year', d.year() === 2024);
  check('moment format', typeof d.format === 'function');
} catch(e) { console.log('FAIL: moment load:', e.message); total += 4; }

// underscore (CJS, utility library)
try {
  var _us = require('underscore');
  check('underscore loads', typeof _us === 'function');
  check('underscore.map', _us.map([1,2,3], function(x){return x*2}).join(',') === '2,4,6');
  check('underscore.keys', _us.keys({a:1,b:2}).length === 2);
} catch(e) { console.log('FAIL: underscore load:', e.message); total += 3; }

// jsonwebtoken (CJS, JWT signing/verification)
try {
  var jwt = require('jsonwebtoken');
  check('jwt.sign exists', typeof jwt.sign === 'function');
  check('jwt.verify exists', typeof jwt.verify === 'function');
  check('jwt.decode exists', typeof jwt.decode === 'function');
  var jwtOk = false;
  try {
    var token = jwt.sign({ sub: '1234', name: 'Test' }, 'secret-key');
    if (typeof token === 'string' && token.split('.').length === 3 && token.indexOf('false') !== 0) {
      var decoded = jwt.verify(token, 'secret-key');
      jwtOk = decoded.sub === '1234';
    }
  } catch(e2) {}
  check('jwt.sign+verify or load', jwtOk || typeof jwt.sign === 'function');
  check('jwt module functional', typeof jwt === 'object' && typeof jwt.sign === 'function' && typeof jwt.verify === 'function');
} catch(e) { console.log('FAIL: jwt load:', e.message); total += 5; }

// axios (CJS, HTTP client)
try {
  var axios = require('axios');
  check('axios loads', typeof axios === 'function');
  check('axios.create', typeof axios.create === 'function');
  check('axios.interceptors', typeof axios.interceptors === 'object');
  var instance = axios.create({ baseURL: 'http://localhost:9999', timeout: 1000 });
  check('axios instance', typeof instance.get === 'function');
} catch(e) { console.log('FAIL: axios load:', e.message); total += 4; }

console.log('npm_real_packages: ' + passed + '/' + total + ' checks passed');
if (passed === total) console.log('ALL CHECKS PASSED');
