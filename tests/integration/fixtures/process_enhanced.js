// Test enhanced process APIs

// 1. process.nextTick with extra args
var result1 = '';
process.nextTick(function(a, b, c) {
  result1 = a + '-' + b + '-' + c;
  console.log('1: nextTick args: ' + result1);
}, 'hello', 'world', '42');

// 2. process.emitWarning
process.emitWarning('test warning', 'CustomWarning');
console.log('2: emitWarning exists: ' + (typeof process.emitWarning === 'function'));

// 3. process.kill exists
console.log('3: kill exists: ' + (typeof process.kill === 'function'));

// 4. process.ppid
console.log('4: ppid is number: ' + (typeof process.ppid === 'number'));

// 5. process.abort exists
console.log('5: abort exists: ' + (typeof process.abort === 'function'));

// 6. process.umask
var mask = process.umask();
console.log('6: umask is number: ' + (typeof mask === 'number'));

// 7. process.exitCode
console.log('7: exitCode default: ' + (process.exitCode === undefined));

// 8. process.hrtime returns array
var hr = process.hrtime();
console.log('8: hrtime is array: ' + Array.isArray(hr));
console.log('9: hrtime has 2 elements: ' + (hr.length === 2));

// 10. process.hrtime diff
var hr2 = process.hrtime(hr);
console.log('10: hrtime diff works: ' + (hr2[0] >= 0));

// 11. process.uptime
console.log('11: uptime is number: ' + (typeof process.uptime() === 'number'));

// 12. process.memoryUsage
var mem = process.memoryUsage();
console.log('12: memoryUsage has rss: ' + ('rss' in mem));
console.log('13: memoryUsage has external: ' + ('external' in mem));
console.log('14: memoryUsage has arrayBuffers: ' + ('arrayBuffers' in mem));

// 15. process.cpuUsage
var cpu = process.cpuUsage();
console.log('15: cpuUsage has user: ' + ('user' in cpu));

// 16. process.release
console.log('16: release.name: ' + process.release.name);

// 17. process.features
console.log('17: features.tls: ' + process.features.tls);

// 18. process.title
console.log('18: title is string: ' + (typeof process.title === 'string'));
