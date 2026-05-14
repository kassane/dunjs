// Test readline module
var readline = require('readline');

// 1. createInterface exists
console.log('1: createInterface exists: ' + (typeof readline.createInterface === 'function'));

// 2. Interface exists
console.log('2: Interface exists: ' + (typeof readline.Interface === 'function'));

// 3. Create interface
var rl = readline.createInterface({ input: process.stdin, output: process.stdout });
console.log('3: rl created: ' + (typeof rl === 'object'));

// 4. Methods exist
console.log('4: on method: ' + (typeof rl.on === 'function'));
console.log('5: close method: ' + (typeof rl.close === 'function'));
console.log('6: setPrompt: ' + (typeof rl.setPrompt === 'function'));
console.log('7: prompt: ' + (typeof rl.prompt === 'function'));
console.log('8: pause: ' + (typeof rl.pause === 'function'));
console.log('9: resume: ' + (typeof rl.resume === 'function'));
console.log('10: write: ' + (typeof rl.write === 'function'));

// 5. Event handling
var lineReceived = false;
rl.on('line', function(line) { lineReceived = true; });
rl.write('test line\n');
console.log('11: line event fired: ' + lineReceived);

// 6. Close event
var closeFired = false;
rl.on('close', function() { closeFired = true; });
rl.close();
console.log('12: close event fired: ' + closeFired);

// 7. Stub modules work
var punycode = require('punycode');
console.log('13: punycode loaded: ' + (typeof punycode === 'object'));
console.log('14: punycode.toASCII: ' + (typeof punycode.toASCII === 'function'));

var domain = require('domain');
console.log('15: domain loaded: ' + (typeof domain === 'object'));
console.log('16: domain.create: ' + (typeof domain.create === 'function'));

var dc = require('diagnostics_channel');
console.log('17: diagnostics_channel loaded: ' + (typeof dc === 'object'));
console.log('18: dc.channel: ' + (typeof dc.channel === 'function'));
