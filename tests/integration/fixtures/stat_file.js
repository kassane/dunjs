// Real-world: statSync on known fixture files
const fs = require('fs');
const path = require('path');

const jsonFile = 'tests/integration/fixtures/data/sample.json';
const stat = fs.statSync(jsonFile);

console.log(stat.isFile());
console.log(stat.isDirectory());
console.log(stat.size > 0);
console.log(typeof stat.mtimeMs === 'number');

// Stat the data directory
const dirStat = fs.statSync('tests/integration/fixtures/data');
console.log(dirStat.isDirectory());
console.log(dirStat.isFile());

// existsSync
console.log(fs.existsSync(jsonFile));
console.log(fs.existsSync('tests/integration/fixtures/data/nonexistent.txt'));
