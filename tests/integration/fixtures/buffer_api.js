// Test Buffer API
const b1 = Buffer.from('hello');
console.log('from string: ' + b1.toString());
console.log('length: ' + b1.length);

const b2 = Buffer.alloc(5, 0x41);
console.log('alloc fill: ' + b2.toString());

const b3 = Buffer.from('aGVsbG8=', 'base64');
console.log('base64: ' + b3.toString());

const b4 = Buffer.from('68656c6c6f', 'hex');
console.log('hex decode: ' + b4.toString());
console.log('hex encode: ' + b1.toString('hex'));

console.log('isBuffer: ' + Buffer.isBuffer(b1));
console.log('isBuffer string: ' + Buffer.isBuffer('hello'));

const b5 = Buffer.concat([b1, Buffer.from(' world')]);
console.log('concat: ' + b5.toString());

console.log('byteLength: ' + Buffer.byteLength('hello'));

const b6 = b1.slice(1, 3);
console.log('slice: ' + b6.toString());

console.log('indexOf: ' + b1.indexOf('ll'));

const b7 = Buffer.alloc(3);
b7.writeUInt8(65, 0);
b7.writeUInt8(66, 1);
b7.writeUInt8(67, 2);
console.log('writeUInt8: ' + b7.toString());
console.log('readUInt8: ' + b7.readUInt8(1));

const b8 = Buffer.from('test');
const b9 = Buffer.from('test');
console.log('equals: ' + b8.equals(b9));
