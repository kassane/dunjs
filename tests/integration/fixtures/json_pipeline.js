// Real-world: read JSON, transform, hash, path ops
const fs = require('fs');
const crypto = require('crypto');
const path = require('path');

const raw = fs.readFileSync('tests/integration/fixtures/data/sample.json');
const parsed = JSON.parse(raw);

// Sort item names
const names = parsed.items.map(function(x) { return x.name; }).sort();
console.log(names.join(','));

// Version field
console.log(parsed.version);

// MD5 of raw content — just verify length (32 hex chars)
const hash = crypto.createHash('md5').update(raw).digest('hex');
console.log(hash.length === 32);

// Path dirname of the data file
console.log(path.dirname('tests/integration/fixtures/data/sample.json'));
