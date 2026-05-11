// Real-world: process.env access with --allow-env
console.log(typeof process.env === 'object');
console.log(typeof process.env.PATH === 'string');
console.log(Object.keys(process.env).length > 0);
console.log('HOME' in process.env);
