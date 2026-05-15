// Test crypto cipher/decipher API
var crypto = require('crypto');

// 1. AES-256-CBC encrypt/decrypt (hex encoding)
var key256 = 'abcdefghijklmnopqrstuvwxyz012345'; // 32 bytes
var iv16 = '0123456789abcdef'; // 16 bytes

var cipher = crypto.createCipheriv('aes-256-cbc', key256, iv16);
var encrypted = cipher.update('Hello, World!', 'utf8', 'hex');
encrypted += cipher.final('hex');
console.log('1: encrypted is string: ' + (typeof encrypted === 'string'));
console.log('2: encrypted not empty: ' + (encrypted.length > 0));

var decipher = crypto.createDecipheriv('aes-256-cbc', key256, iv16);
var decrypted = decipher.update(encrypted, 'hex', 'utf8');
decrypted += decipher.final('utf8');
console.log('3: decrypted matches: ' + (decrypted === 'Hello, World!'));

// 2. AES-128-CBC
var key128 = '0123456789abcdef'; // 16 bytes
var cipher2 = crypto.createCipheriv('aes-128-cbc', key128, iv16);
var enc2 = cipher2.update('test data 12345', 'utf8', 'hex');
enc2 += cipher2.final('hex');

var decipher2 = crypto.createDecipheriv('aes-128-cbc', key128, iv16);
var dec2 = decipher2.update(enc2, 'hex', 'utf8');
dec2 += decipher2.final('utf8');
console.log('4: aes-128-cbc round-trip: ' + (dec2 === 'test data 12345'));

// 3. getCiphers
var ciphers = crypto.getCiphers();
console.log('5: getCiphers array: ' + Array.isArray(ciphers));
console.log('6: has aes-256-cbc: ' + ciphers.includes('aes-256-cbc'));
console.log('7: has aes-128-gcm: ' + ciphers.includes('aes-128-gcm'));

// 4. getHashes
var hashes = crypto.getHashes();
console.log('8: getHashes array: ' + Array.isArray(hashes));
console.log('9: has sha256: ' + hashes.includes('sha256'));

// 5. timingSafeEqual
console.log('10: timingSafeEqual same: ' + crypto.timingSafeEqual('abc', 'abc'));
console.log('11: timingSafeEqual diff: ' + !crypto.timingSafeEqual('abc', 'xyz'));

// 6. createHmac
var hmac = crypto.createHmac('sha256', 'secret');
hmac.update('message');
var hmacResult = hmac.digest('hex');
console.log('12: hmac result: ' + (hmacResult.length === 64));
