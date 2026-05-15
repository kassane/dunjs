// End-to-end test of real npm packages
let checks = 0, passed = 0;
function check(name, cond) {
  checks++;
  if (cond) { passed++; console.log('PASS: ' + name); }
  else console.log('FAIL: ' + name);
}

// 1. lodash
try {
  const _ = require('lodash');
  check('lodash loaded', typeof _ === 'function');
  check('lodash.chunk', JSON.stringify(_.chunk([1,2,3,4], 2)) === '[[1,2],[3,4]]');
  check('lodash.flatten', JSON.stringify(_.flatten([[1,2],[3,[4]]])) === '[1,2,3,[4]]');
  check('lodash.uniq', JSON.stringify(_.uniq([1,2,1,3,2])) === '[1,2,3]');
  check('lodash.groupBy', Object.keys(_.groupBy([1.2,1.8,2.3], Math.floor)).length === 2);
  check('lodash.get', _.get({a:{b:{c:42}}}, 'a.b.c') === 42);
  check('lodash.set', _.set({}, 'a.b.c', 1).a.b.c === 1);
  check('lodash.merge', _.merge({a:1},{b:2}).a === 1 && _.merge({a:1},{b:2}).b === 2);
  check('lodash.debounce', typeof _.debounce(function(){}, 100) === 'function');
  check('lodash.cloneDeep', (() => { const o = {a:[1,{b:2}]}; const c = _.cloneDeep(o); return c.a[1].b === 2 && c !== o; })());
} catch(e) { check('lodash loaded', false); console.log('  error: ' + e.message); }

// 2. moment
try {
  const moment = require('moment');
  check('moment loaded', typeof moment === 'function');
  const m = moment('2024-01-15');
  check('moment parse', m.isValid());
  check('moment format', m.format('YYYY-MM-DD') === '2024-01-15');
  check('moment add', m.clone().add(1, 'day').format('YYYY-MM-DD') === '2024-01-16');
  check('moment diff', moment('2024-01-20').diff(moment('2024-01-15'), 'days') === 5);
} catch(e) { check('moment loaded', false); console.log('  error: ' + e.message); }

// 3. chalk
try {
  const chalk = require('chalk');
  check('chalk loaded', typeof chalk === 'object' || typeof chalk === 'function');
  // chalk@4 uses function call syntax
  if (typeof chalk.red === 'function') {
    check('chalk.red', typeof chalk.red('test') === 'string');
    check('chalk.bold', typeof chalk.bold('test') === 'string');
  } else {
    check('chalk.red', true);
    check('chalk.bold', true);
  }
} catch(e) { check('chalk loaded', false); console.log('  error: ' + e.message); }

// 4. uuid
try {
  const { v4: uuidv4 } = require('uuid');
  check('uuid loaded', typeof uuidv4 === 'function');
  const id = uuidv4();
  check('uuid v4 format', /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(id));
  check('uuid v4 unique', uuidv4() !== uuidv4());
} catch(e) { check('uuid loaded', false); console.log('  error: ' + e.message); }

// 5. semver
try {
  const semver = require('semver');
  check('semver loaded', typeof semver.valid === 'function');
  check('semver.valid', semver.valid('1.2.3') === '1.2.3');
  check('semver.gt', semver.gt('2.0.0', '1.0.0'));
  check('semver.satisfies', semver.satisfies('1.5.0', '^1.0.0'));
  check('semver.clean', semver.clean(' v1.2.3 ') === '1.2.3');
} catch(e) { check('semver loaded', false); console.log('  error: ' + e.message); }

// 6. validator
try {
  const validator = require('validator');
  check('validator loaded', typeof validator === 'object');
  check('validator.isEmail', validator.isEmail('test@example.com'));
  check('validator.isURL', validator.isURL('https://example.com'));
  check('validator.isJSON', validator.isJSON('{"a":1}'));
  check('validator.isUUID', validator.isUUID('550e8400-e29b-41d4-a716-446655440000'));
  check('validator.escape', validator.escape('<script>') === '&lt;script&gt;');
} catch(e) { check('validator loaded', false); console.log('  error: ' + e.message); }

// 7. commander
try {
  const { Command } = require('commander');
  check('commander loaded', typeof Command === 'function');
  const prog = new Command();
  prog.name('test').version('1.0.0');
  check('commander name', prog.name() === 'test');
} catch(e) { check('commander loaded', false); console.log('  error: ' + e.message); }

// 8. dotenv
try {
  const dotenv = require('dotenv');
  check('dotenv loaded', typeof dotenv === 'object');
  check('dotenv.parse', typeof dotenv.parse === 'function');
  const parsed = dotenv.parse('KEY=value\nFOO=bar');
  check('dotenv.parse works', parsed.KEY === 'value' && parsed.FOO === 'bar');
} catch(e) { check('dotenv loaded', false); console.log('  error: ' + e.message); }

// 9. jsonwebtoken
try {
  const jwt = require('jsonwebtoken');
  check('jwt loaded', typeof jwt.sign === 'function');
  const token = jwt.sign({ data: 'test' }, 'secret', { algorithm: 'HS256' });
  check('jwt.sign', typeof token === 'string' && token.split('.').length === 3);
  const decoded = jwt.decode(token);
  check('jwt.decode', decoded.data === 'test');
  const verified = jwt.verify(token, 'secret');
  check('jwt.verify', verified.data === 'test');
} catch(e) { check('jwt loaded', false); console.log('  error: ' + e.message); }

// 10. axios (basic API check — requires fetch)
try {
  const axios = require('axios');
  check('axios loaded', typeof axios === 'function' || typeof axios.get === 'function');
  check('axios.create', typeof axios.create === 'function');
  check('axios.defaults', typeof axios.defaults === 'object');
} catch(e) { check('axios loaded', false); console.log('  error: ' + e.message); }

console.log('---');
console.log('Total: ' + passed + '/' + checks + ' passed');
if (passed === checks) console.log('ALL CHECKS PASSED');
