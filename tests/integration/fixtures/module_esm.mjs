import { join, dirname, basename, extname, isAbsolute } from 'dun:path';

console.log(join('/foo', 'bar', 'baz.js'));
console.log(dirname('/foo/bar/baz.js'));
console.log(basename('/foo/bar/baz.js'));
console.log(extname('index.html'));
console.log(isAbsolute('/foo/bar'));
console.log(isAbsolute('foo/bar'));
