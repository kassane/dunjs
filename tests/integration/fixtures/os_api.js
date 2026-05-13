// Test os module
const os = require('os');

console.log('platform: ' + os.platform());
console.log('arch: ' + os.arch());
console.log('type: ' + os.type());
console.log('endianness: ' + os.endianness());
console.log('EOL: ' + JSON.stringify(os.EOL));
console.log('devNull: ' + os.devNull);

const home = os.homedir();
console.log('homedir exists: ' + (typeof home === 'string'));

const tmp = os.tmpdir();
console.log('tmpdir exists: ' + (typeof tmp === 'string'));

const cpus = os.cpus();
console.log('cpus count: ' + (cpus.length > 0));

const total = os.totalmem();
console.log('totalmem > 0: ' + (total > 0));

const free = os.freemem();
console.log('freemem > 0: ' + (free > 0));

const up = os.uptime();
console.log('uptime > 0: ' + (up > 0));

const rel = os.release();
console.log('release exists: ' + (typeof rel === 'string' && rel.length > 0));

const host = os.hostname();
console.log('hostname exists: ' + (typeof host === 'string'));
