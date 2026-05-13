// Real-world: ESM pipeline combining all builtins — read CSV-like data, process, hash
import { readFileSync, writeFileSync, existsSync, unlinkSync } from 'dun:fs';
import { join, basename } from 'dun:path';
import { createHash } from 'dun:crypto';

// Step 1: Create test data (CSV-like)
const csvData = [
  'name,age,city',
  'alice,30,seattle',
  'bob,25,portland',
  'charlie,35,denver',
  'diana,28,austin'
].join('\n');

const tmpFile = '/tmp/dun_esm_pipeline_' + Date.now() + '.csv';
writeFileSync(tmpFile, csvData);

// Step 2: Read and parse
const raw = readFileSync(tmpFile);
const lines = raw.split('\n');
const headers = lines[0].split(',');
const rows = lines.slice(1).map(line => {
  const vals = line.split(',');
  const obj = {};
  headers.forEach((h, i) => { obj[h] = vals[i]; });
  return obj;
});

console.log('headers: ' + headers.join(', '));
console.log('rows: ' + rows.length);

// Step 3: Transform and aggregate
const avgAge = rows.reduce((sum, r) => sum + parseInt(r.age), 0) / rows.length;
console.log('avg age: ' + avgAge);

const sorted = rows.slice().sort((a, b) => a.name.localeCompare(b.name));
console.log('sorted: ' + sorted.map(r => r.name).join(', '));

const cities = rows.map(r => r.city).sort();
console.log('cities: ' + cities.join(', '));

// Step 4: Hash the processed data
const digest = createHash('sha256')
  .update(JSON.stringify(sorted))
  .digest('hex');
console.log('digest length: ' + digest.length);
console.log('digest type: ' + typeof digest);

// Step 5: Path operations on our temp file
console.log('basename: ' + basename(tmpFile).startsWith('dun_esm_pipeline_'));

// Step 6: Cleanup
unlinkSync(tmpFile);
console.log('cleaned: ' + !existsSync(tmpFile));
