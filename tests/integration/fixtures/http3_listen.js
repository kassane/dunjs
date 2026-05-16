// http3.createServer().listen() now binds a real UDP socket so the
// 'listening' event fires and the port is reachable. Full lsquic-
// backed H3 request handling is a separate (large) effort; this
// fixture covers the listener.

const http3 = require('http3');

let passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) passed++;
  else console.log('FAIL:', name);
}

const srv = http3.createServer();
check('createServer returns object', typeof srv === 'object');
check('has listen', typeof srv.listen === 'function');
check('has close', typeof srv.close === 'function');

srv.listen(0, '127.0.0.1');
check('listening flag set', srv.listening === true);
check('port assigned', typeof srv.port === 'number' && srv.port > 0);
check('address echoed', srv.address === '127.0.0.1');

// fd should be a positive int (the UDP socket fd).
check('fd is positive int', typeof srv.fd === 'number' && srv.fd > 0);

srv.close();

console.log('http3_listen:', passed + '/' + total, 'checks passed');
if (passed === total) console.log('ALL CHECKS PASSED');
