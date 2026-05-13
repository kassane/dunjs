// Real npm package test: ms@2.1.3 (pure CJS, no native addons)
const ms = require('ms');

console.log(ms('2 days'));           // 172800000
console.log(ms('1h'));               // 3600000
console.log(ms('30m'));              // 1800000
console.log(ms(60000));              // 1m
console.log(ms(86400000));           // 1d
console.log(ms(86400000, { long: true })); // 1 day
