// Test import.meta support
let pass = 0, fail = 0;
function check(name, cond) {
  if (cond) { pass++; }
  else { fail++; console.log('FAIL: ' + name); }
}

check('import.meta exists', typeof import.meta === 'object');
check('import.meta.url', typeof import.meta.url === 'string');
check('import.meta.url starts with file://', import.meta.url.startsWith('file://'));
check('import.meta.filename', typeof import.meta.filename === 'string');
check('import.meta.dirname', typeof import.meta.dirname === 'string');
check('import.meta.main is boolean', typeof import.meta.main === 'boolean');

console.log(`\nimport.meta: ${pass}/${pass + fail} passed`);
if (fail > 0) console.log(`${fail} FAILED`);
