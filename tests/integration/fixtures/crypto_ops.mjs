import { randomBytes, randomUUID, createHash } from 'dun:crypto';

// randomBytes: check length and type
const bytes = randomBytes(16);
console.log(bytes.length === 16);
console.log(typeof bytes[0] === 'number');

// randomUUID: check format (xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx)
const uuid = randomUUID();
console.log(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(uuid));

// createHash: known sha256 digest
const h = createHash('sha256');
h.update('hello');
h.update(' world');
console.log(h.digest('hex'));

// md5
const md5 = createHash('md5').update('abc').digest('hex');
console.log(md5);
