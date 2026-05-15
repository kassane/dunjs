// Real-world: Config file loader that reads JSON, validates schema, merges defaults
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const CONFIG_DIR = 'tests/integration/fixtures/data';

function loadConfig(filename) {
  const fullPath = path.resolve(path.join(CONFIG_DIR, filename));
  const raw = fs.readFileSync(fullPath, 'utf8');
  const parsed = JSON.parse(raw);
  return parsed;
}

function mergeDefaults(config, defaults) {
  const result = {};
  const keys = Object.keys(defaults);
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    result[k] = config[k] !== undefined ? config[k] : defaults[k];
  }
  const configKeys = Object.keys(config);
  for (let i = 0; i < configKeys.length; i++) {
    const k = configKeys[i];
    if (result[k] === undefined) result[k] = config[k];
  }
  return result;
}

function configChecksum(obj) {
  const json = JSON.stringify(obj, Object.keys(obj).sort());
  return crypto.createHash('sha256').update(json).digest('hex').slice(0, 16);
}

// Load sample.json and treat it as a config
const config = loadConfig('sample.json');
const defaults = { version: '0.0.0', debug: false, items: [] };
const merged = mergeDefaults(config, defaults);

console.log('version: ' + merged.version);
console.log('debug: ' + merged.debug);
console.log('items: ' + merged.items.length);

// Verify path operations on config path
const configPath = path.join(CONFIG_DIR, 'sample.json');
console.log('ext: ' + path.extname(configPath));
console.log('base: ' + path.basename(configPath));
console.log('dir: ' + path.dirname(configPath));

// Checksum of merged config for integrity
const checksum = configChecksum(merged);
console.log('checksum length: ' + checksum.length);
console.log('checksum type: ' + typeof checksum);
