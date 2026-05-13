const path = require('node:path');

console.log(path.join('/foo', 'bar', 'baz.js'));
console.log(path.dirname('/foo/bar/baz.js'));
console.log(path.basename('/foo/bar/baz.js'));
console.log(path.extname('index.html'));
console.log(path.isAbsolute('/foo/bar'));
console.log(path.sep);
