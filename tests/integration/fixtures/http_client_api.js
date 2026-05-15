// Test http.request, http.get, http.METHODS, http.STATUS_CODES, http.Agent
var http = require('http');
var checks = 0;
var passed = 0;

function check(name, condition) {
  checks++;
  if (condition) { passed++; console.log('PASS: ' + name); }
  else console.log('FAIL: ' + name);
}

// STATUS_CODES
check('STATUS_CODES is object', typeof http.STATUS_CODES === 'object');
check('STATUS_CODES 200', http.STATUS_CODES[200] === 'OK');
check('STATUS_CODES 404', http.STATUS_CODES[404] === 'Not Found');
check('STATUS_CODES 500', http.STATUS_CODES[500] === 'Internal Server Error');
check('STATUS_CODES 301', http.STATUS_CODES[301] === 'Moved Permanently');
check('STATUS_CODES 204', http.STATUS_CODES[204] === 'No Content');
check('STATUS_CODES 418', http.STATUS_CODES[418] === "I'm a Teapot");

// METHODS
check('METHODS is array', Array.isArray(http.METHODS));
check('METHODS has GET', http.METHODS.indexOf('GET') !== -1);
check('METHODS has POST', http.METHODS.indexOf('POST') !== -1);
check('METHODS has PUT', http.METHODS.indexOf('PUT') !== -1);
check('METHODS has DELETE', http.METHODS.indexOf('DELETE') !== -1);
check('METHODS has PATCH', http.METHODS.indexOf('PATCH') !== -1);
check('METHODS has HEAD', http.METHODS.indexOf('HEAD') !== -1);
check('METHODS has OPTIONS', http.METHODS.indexOf('OPTIONS') !== -1);

// Agent
check('Agent is function', typeof http.Agent === 'function');
check('globalAgent exists', typeof http.globalAgent === 'object');
check('globalAgent.maxSockets', http.globalAgent.maxSockets === Infinity);
check('globalAgent.keepAlive', http.globalAgent.keepAlive === false);
var agent = new http.Agent({ maxSockets: 10, keepAlive: true });
check('custom agent maxSockets', agent.maxSockets === 10);
check('custom agent keepAlive', agent.keepAlive === true);
check('agent.destroy', typeof agent.destroy === 'function');
check('agent.getName', typeof agent.getName === 'function');
check('agent getName result', agent.getName({ host: 'example.com', port: 443 }) === 'example.com:443');

// request function
check('request is function', typeof http.request === 'function');
check('get is function', typeof http.get === 'function');

// request returns ClientRequest-like object
var req = http.request({ hostname: 'localhost', port: 99999, path: '/' });
check('req has write', typeof req.write === 'function');
check('req has end', typeof req.end === 'function');
check('req has abort', typeof req.abort === 'function');
check('req has destroy', typeof req.destroy === 'function');
check('req has on', typeof req.on === 'function');
check('req has setTimeout', typeof req.setTimeout === 'function');
check('req has setHeader', typeof req.setHeader === 'function');
check('req has getHeader', typeof req.getHeader === 'function');
check('req has removeHeader', typeof req.removeHeader === 'function');
check('req method default GET', req.method === 'GET');
check('req path default /', req.path === '/');

// request with method option
var postReq = http.request({ method: 'POST', hostname: 'localhost', port: 99999, path: '/data' });
check('post req method', postReq.method === 'POST');
check('post req path', postReq.path === '/data');

// setHeader / getHeader / removeHeader
req.setHeader('x-test', 'hello');
check('getHeader after set', req.getHeader('x-test') === 'hello');
check('getHeader case insensitive', req.getHeader('X-Test') === 'hello');
req.removeHeader('x-test');
check('getHeader after remove', req.getHeader('x-test') === undefined);

console.log('---');
console.log('Total: ' + passed + '/' + checks + ' passed');
