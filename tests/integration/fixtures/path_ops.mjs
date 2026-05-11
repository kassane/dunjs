import { join, normalize, parse, format, relative, sep, delimiter } from 'dun:path';

// join
console.log(join('foo', 'bar', 'baz'));
console.log(join('/foo', '../bar'));

// normalize
console.log(normalize('/foo/./bar/../baz'));

// parse + format round-trip
const parsed = parse('/home/user/file.txt');
console.log(parsed.root);
console.log(parsed.base);
console.log(parsed.ext);
console.log(parsed.name);
console.log(format({ dir: '/home/user', base: 'file.txt' }));

// POSIX constants
console.log(sep);
console.log(delimiter);
