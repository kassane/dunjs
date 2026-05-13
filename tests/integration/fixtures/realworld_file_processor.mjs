// Real-world: File processing pipeline — read, parse, transform, checksum, write results
import { readFileSync, writeFileSync, existsSync, unlinkSync, statSync } from 'dun:fs';
import { join, basename, extname, dirname, resolve } from 'dun:path';
import { createHash, randomUUID } from 'dun:crypto';

const INPUT = 'tests/integration/fixtures/data/sample.json';
const OUTPUT = '/tmp/dun_realworld_' + randomUUID() + '.json';

// Step 1: Read and parse input
const raw = readFileSync(INPUT);
const data = JSON.parse(raw);
console.log('read bytes: ' + (raw.length > 0));

// Step 2: Transform — uppercase names, add computed fields
const transformed = data.items.map(function(item) {
  return {
    id: item.id,
    name: item.name.toUpperCase(),
    nameHash: createHash('md5').update(item.name).digest('hex').slice(0, 8)
  };
});
console.log('transformed ' + transformed.length + ' items');

// Step 3: Build output with metadata
const output = {
  source: basename(INPUT),
  sourceDir: dirname(INPUT),
  sourceExt: extname(INPUT),
  processedAt: typeof Date.now() === 'number' ? 'ok' : 'fail',
  items: transformed,
  checksum: createHash('sha256').update(JSON.stringify(transformed)).digest('hex')
};

// Step 4: Write output
writeFileSync(OUTPUT, JSON.stringify(output, null, 2));

// Step 5: Verify output exists and has content
console.log('output exists: ' + existsSync(OUTPUT));
const stat = statSync(OUTPUT);
console.log('output is file: ' + stat.isFile());
console.log('output size > 0: ' + (stat.size > 0));

// Step 6: Read back and verify round-trip
const readBack = JSON.parse(readFileSync(OUTPUT));
console.log('round-trip items: ' + readBack.items.length);
console.log('first item: ' + readBack.items[0].name);
console.log('source: ' + readBack.source);
console.log('sourceExt: ' + readBack.sourceExt);
console.log('checksum length: ' + readBack.checksum.length);
console.log('processedAt: ' + readBack.processedAt);

// Step 7: Cleanup
unlinkSync(OUTPUT);
console.log('cleaned up: ' + !existsSync(OUTPUT));
