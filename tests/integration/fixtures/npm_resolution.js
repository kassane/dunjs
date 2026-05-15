// Tests for enhanced npm/node_modules resolution
const fs = require('fs');
const path = require('path');
const os = require('os');

var tmpDir = os.tmpdir() + '/dun-npm-res-' + Date.now();
fs.mkdirSync(tmpDir, { recursive: true });

var checks = 0;
var passed = 0;
function check(label, cond) {
    checks++;
    if (cond) { passed++; console.log('PASS', label); }
    else console.log('FAIL', label);
}

// --- Setup mock node_modules structure ---

// 1. Simple package with main field
fs.mkdirSync(tmpDir + '/node_modules/simple-pkg', { recursive: true });
fs.writeFileSync(tmpDir + '/node_modules/simple-pkg/package.json',
    JSON.stringify({ name: 'simple-pkg', main: './lib/index.js' }));
fs.mkdirSync(tmpDir + '/node_modules/simple-pkg/lib', { recursive: true });
fs.writeFileSync(tmpDir + '/node_modules/simple-pkg/lib/index.js',
    'module.exports = { name: "simple-pkg", version: "1.0.0" };');

// 2. Package with exports field (conditional)
fs.mkdirSync(tmpDir + '/node_modules/exports-pkg', { recursive: true });
fs.writeFileSync(tmpDir + '/node_modules/exports-pkg/package.json',
    JSON.stringify({
        name: 'exports-pkg',
        exports: {
            '.': { require: './cjs/index.js', import: './esm/index.mjs', default: './cjs/index.js' },
            './utils': { require: './cjs/utils.js', default: './cjs/utils.js' }
        }
    }));
fs.mkdirSync(tmpDir + '/node_modules/exports-pkg/cjs', { recursive: true });
fs.writeFileSync(tmpDir + '/node_modules/exports-pkg/cjs/index.js',
    'module.exports = { type: "cjs", name: "exports-pkg" };');
fs.writeFileSync(tmpDir + '/node_modules/exports-pkg/cjs/utils.js',
    'module.exports = { helper: true };');

// 3. Scoped package
fs.mkdirSync(tmpDir + '/node_modules/@myorg/scoped-lib/src', { recursive: true });
fs.writeFileSync(tmpDir + '/node_modules/@myorg/scoped-lib/package.json',
    JSON.stringify({ name: '@myorg/scoped-lib', main: './src/index.js' }));
fs.writeFileSync(tmpDir + '/node_modules/@myorg/scoped-lib/src/index.js',
    'module.exports = { scoped: true, org: "myorg" };');

// 4. Scoped package with subpath
fs.writeFileSync(tmpDir + '/node_modules/@myorg/scoped-lib/src/extra.js',
    'module.exports = { extra: true };');

// 5. Package with wildcard exports: "./*" -> "./dist/*.js"
fs.mkdirSync(tmpDir + '/node_modules/wildcard-pkg/dist', { recursive: true });
fs.writeFileSync(tmpDir + '/node_modules/wildcard-pkg/package.json',
    JSON.stringify({
        name: 'wildcard-pkg',
        exports: { '.': './dist/index.js', './*': './dist/*.js' }
    }));
fs.writeFileSync(tmpDir + '/node_modules/wildcard-pkg/dist/index.js',
    'module.exports = { wild: true };');
fs.writeFileSync(tmpDir + '/node_modules/wildcard-pkg/dist/helpers.js',
    'module.exports = { helper: "wildcard" };');

// 6. Package with string exports (simple)
fs.mkdirSync(tmpDir + '/node_modules/string-exports', { recursive: true });
fs.writeFileSync(tmpDir + '/node_modules/string-exports/package.json',
    JSON.stringify({ name: 'string-exports', exports: './main.js' }));
fs.writeFileSync(tmpDir + '/node_modules/string-exports/main.js',
    'module.exports = { stringExport: true };');

// 7. Package with index.js fallback (no main, no exports)
fs.mkdirSync(tmpDir + '/node_modules/index-fallback', { recursive: true });
fs.writeFileSync(tmpDir + '/node_modules/index-fallback/package.json',
    JSON.stringify({ name: 'index-fallback' }));
fs.writeFileSync(tmpDir + '/node_modules/index-fallback/index.js',
    'module.exports = { fallback: true };');

// 8. Package.json imports field (self-referencing with #)
fs.writeFileSync(tmpDir + '/package.json', JSON.stringify({
    name: 'test-project',
    imports: { '#utils': './src/utils.js', '#lib/*': './lib/*.js' }
}));
fs.mkdirSync(tmpDir + '/src', { recursive: true });
fs.writeFileSync(tmpDir + '/src/utils.js', 'module.exports = { fromImports: true };');
fs.mkdirSync(tmpDir + '/lib', { recursive: true });
fs.writeFileSync(tmpDir + '/lib/math.js', 'module.exports = { add: function(a,b){return a+b;} };');

// --- Create test script that requires all the above ---
var testScript = `
var simplePkg = require('simple-pkg');
check('simple-pkg main', simplePkg.name === 'simple-pkg');

var exportsPkg = require('exports-pkg');
check('exports conditional', exportsPkg.type === 'cjs' && exportsPkg.name === 'exports-pkg');

var exportsUtils = require('exports-pkg/utils');
check('exports subpath', exportsUtils.helper === true);

var scoped = require('@myorg/scoped-lib');
check('scoped package', scoped.scoped === true && scoped.org === 'myorg');

var scopedSub = require('@myorg/scoped-lib/src/extra');
check('scoped subpath', scopedSub.extra === true);

var wildcardMain = require('wildcard-pkg');
check('wildcard main', wildcardMain.wild === true);

var wildcardSub = require('wildcard-pkg/helpers');
check('wildcard subpath', wildcardSub.helper === 'wildcard');

var strExports = require('string-exports');
check('string exports', strExports.stringExport === true);

var indexFb = require('index-fallback');
check('index.js fallback', indexFb.fallback === true);

var hashUtils = require('#utils');
check('#imports exact', hashUtils.fromImports === true);

var hashMath = require('#lib/math');
check('#imports wildcard', typeof hashMath.add === 'function' && hashMath.add(2,3) === 5);
`;

// Write and execute the test script from tmpDir
fs.writeFileSync(tmpDir + '/run_test.js', testScript);

// Write a runner script that requires all packages from inside tmpDir
var runner = [
    'var checks = 0, passed = 0;',
    'function check(l, c) { checks++; if(c){passed++;console.log("PASS",l)}else{console.log("FAIL",l)} }',
    '',
    'var simplePkg = require("simple-pkg");',
    'check("simple-pkg main", simplePkg.name === "simple-pkg");',
    '',
    'var exportsPkg = require("exports-pkg");',
    'check("exports conditional", exportsPkg.type === "cjs" && exportsPkg.name === "exports-pkg");',
    '',
    'var exportsUtils = require("exports-pkg/utils");',
    'check("exports subpath", exportsUtils.helper === true);',
    '',
    'var scoped = require("@myorg/scoped-lib");',
    'check("scoped package", scoped.scoped === true && scoped.org === "myorg");',
    '',
    'var scopedSub = require("@myorg/scoped-lib/src/extra");',
    'check("scoped subpath", scopedSub.extra === true);',
    '',
    'var wildcardMain = require("wildcard-pkg");',
    'check("wildcard main", wildcardMain.wild === true);',
    '',
    'var wildcardSub = require("wildcard-pkg/helpers");',
    'check("wildcard subpath", wildcardSub.helper === "wildcard");',
    '',
    'var strExports = require("string-exports");',
    'check("string exports", strExports.stringExport === true);',
    '',
    'var indexFb = require("index-fallback");',
    'check("index.js fallback", indexFb.fallback === true);',
    '',
    'var hashUtils = require("#utils");',
    'check("#imports exact", hashUtils.fromImports === true);',
    '',
    'var hashMath = require("#lib/math");',
    'check("#imports wildcard", typeof hashMath.add === "function" && hashMath.add(2,3) === 5);',
    '',
    'console.log(passed + "/" + checks + " npm resolution checks passed");',
].join('\n');

fs.writeFileSync(tmpDir + '/runner.js', runner);

// Now require the runner from tmpDir context by using a wrapper
// The trick: write a shim that sets __dirname context
var shim = 'require("./runner.js");';
fs.writeFileSync(tmpDir + '/entry.js', shim);

// Execute via child_process using the same dun binary
var cp = require('child_process');
var dunBin = process.execPath || process.argv[0];
var result = cp.execSync(dunBin + ' run ' + tmpDir + '/entry.js --allow-all', { encoding: 'utf8' });
process.stdout.write(result);

// Cleanup
fs.rmSync(tmpDir, { recursive: true });
