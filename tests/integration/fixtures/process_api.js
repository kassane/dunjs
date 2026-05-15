// process object integration test

// process.stdout/stderr
process.stdout.write('stdout: ok\n');
process.stderr.write('');

// process.hrtime
var hr = process.hrtime();
console.log('hrtime array:', Array.isArray(hr) && hr.length === 2);
console.log('hrtime sec:', typeof hr[0] === 'number');

// process.hrtime.bigint
var ns = process.hrtime.bigint();
console.log('hrtime.bigint:', typeof ns === 'bigint' && ns > 0n);

// process.uptime
var up = process.uptime();
console.log('uptime:', typeof up === 'number' && up >= 0);

// process.memoryUsage
var mem = process.memoryUsage();
console.log('memoryUsage rss:', typeof mem.rss === 'number');
console.log('memoryUsage heapTotal:', typeof mem.heapTotal === 'number');

// process.cpuUsage
var cpu = process.cpuUsage();
console.log('cpuUsage user:', typeof cpu.user === 'number');
console.log('cpuUsage system:', typeof cpu.system === 'number');

// process.execPath
console.log('execPath:', typeof process.execPath === 'string' && process.execPath.length > 0);

// process.title
console.log('title:', process.title === 'dun');

// process.versions
console.log('versions dun:', typeof process.versions.dun === 'string');

// process.chdir / cwd
var orig = process.cwd();
process.chdir('/tmp');
console.log('chdir:', process.cwd() === '/tmp');
process.chdir(orig);

console.log('All process tests passed');
