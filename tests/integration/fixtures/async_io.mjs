// Real-world: async file I/O with Promise-based API
import { readFile } from 'dun:fs';

async function main() {
  const content = await readFile('tests/integration/fixtures/data/words.txt');
  const lines = content.trim().split('\n');
  console.log(lines.length);
  console.log(lines.slice().sort().join(','));
}

main();
