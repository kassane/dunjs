// Advanced HTTP server tests: res.end callback, server.close, error handling, res.on
const http = require('http');
let checks = 0;
let passed = 0;

function check(name, cond) {
  checks++;
  if (cond) { passed++; console.log('PASS: ' + name); }
  else console.log('FAIL: ' + name);
}

let done = false;
function finish() {
  if (done) return;
  done = true;
  console.log('---');
  console.log('Total: ' + passed + '/' + checks + ' passed');
  if (passed === checks) console.log('ALL CHECKS PASSED');
}

const server = http.createServer((req, res) => {
  if (req.url === '/callback') {
    // Test res.end with callback
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('callback-body', () => {
      endCallbackFired = true;
    });
  } else if (req.url === '/finish-event') {
    // Test res.on('finish')
    let finishFired = false;
    res.on('finish', () => { finishFired = true; });
    res.writeHead(200);
    res.end('ok');
    // finish fires synchronously in our impl
    check('res finish event fires', finishFired === true);
  } else if (req.url === '/status-custom') {
    res.statusCode = 201;
    res.setHeader('Content-Type', 'text/plain');
    res.end('created');
  } else if (req.url === '/error') {
    throw new Error('intentional error');
  } else if (req.url === '/close-test') {
    res.end('closing');
    // Signal to close the server after this request
    setTimeout(() => {
      server.close(() => {
        check('server.close callback fires', true);
        finish();
      });
    }, 50);
  }
});

let endCallbackFired = false;

server.listen(0, () => {
  const addr = server.address();
  const port = addr.port;

  check('server listening', server.listening === true);
  check('server.address() returns object', typeof addr === 'object');
  check('server.address().port is number', typeof port === 'number');

  // Test res.end callback
  http.get('http://127.0.0.1:' + port + '/callback', (res) => {
    let body = '';
    res.on('data', (chunk) => { body += chunk; });
    res.on('end', () => {
      check('res.end callback body received', body === 'callback-body');
      check('res.end callback fired', endCallbackFired === true);

      // Test finish event
      http.get('http://127.0.0.1:' + port + '/finish-event', (res2) => {
        let b2 = '';
        res2.on('data', (c) => b2 += c);
        res2.on('end', () => {
          check('finish event response ok', b2 === 'ok');

          // Test custom status code
          http.get('http://127.0.0.1:' + port + '/status-custom', (res3) => {
            check('custom status code 201', res3.statusCode === 201);
            let b3 = '';
            res3.on('data', (c) => b3 += c);
            res3.on('end', () => {
              check('custom status body', b3 === 'created');

              // Test error handling - server should send 500 and not crash
              http.get('http://127.0.0.1:' + port + '/error', (res4) => {
                check('error returns 500', res4.statusCode === 500);
                let b4 = '';
                res4.on('data', (c) => b4 += c);
                res4.on('end', () => {
                  check('error body', b4 === 'Internal Server Error');

                  // Test server.close
                  http.get('http://127.0.0.1:' + port + '/close-test', (res5) => {
                    let b5 = '';
                    res5.on('data', (c) => b5 += c);
                    res5.on('end', () => {
                      check('close test body', b5 === 'closing');
                      // server.close callback will fire and call finish()
                    });
                  });
                });
              });
            });
          });
        });
      });
    });
  });
});

// Safety timeout
setTimeout(() => { finish(); }, 5000);
