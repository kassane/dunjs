// npm compat: bare specifier node_modules resolution
const mylib = require('mylib');
const greet = require('greet');

console.log(mylib.greet('World'));
console.log(mylib.version);
console.log(greet('Dun'));
