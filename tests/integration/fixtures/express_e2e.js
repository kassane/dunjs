// Express.js end-to-end integration test
const http = require('http');
let checks = 0, passed = 0;
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

try {
  const express = require('express');
  check('express loaded', typeof express === 'function');

  const app = express();
  check('app created', typeof app === 'function');

  // Middleware
  app.use((req, res, next) => {
    res.setHeader('x-powered-by', 'DunJS');
    next();
  });

  // JSON body parser
  app.use(express.json());

  // Routes
  app.get('/', (req, res) => {
    res.json({ hello: 'world' });
  });

  app.get('/status', (req, res) => {
    res.status(201).json({ created: true });
  });

  app.post('/echo', (req, res) => {
    res.json({ received: req.body });
  });

  app.get('/params/:id', (req, res) => {
    res.json({ id: req.params.id });
  });

  // app.listen should return the server
  const server = app.listen(0, () => {
    const addr = server.address();
    check('server.listen returns server', server !== undefined && server !== null);
    check('server.address() works', typeof addr === 'object' && typeof addr.port === 'number');
    const port = addr.port;

    // Test GET /
    http.get('http://127.0.0.1:' + port + '/', (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => {
        try {
          const j = JSON.parse(body);
          check('GET / json body', j.hello === 'world');
        } catch(e) { check('GET / json body', false); }

        // Test GET /status (201)
        http.get('http://127.0.0.1:' + port + '/status', (res2) => {
          check('GET /status code 201', res2.statusCode === 201);
          let b2 = '';
          res2.on('data', (c) => b2 += c);
          res2.on('end', () => {
            try {
              const j2 = JSON.parse(b2);
              check('GET /status body', j2.created === true);
            } catch(e) { check('GET /status body', false); }

            // Test POST /echo with JSON body
            const postData = JSON.stringify({ msg: 'test' });
            const postReq = http.request({
              hostname: '127.0.0.1', port: port, path: '/echo',
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'Content-Length': postData.length }
            }, (res3) => {
              let b3 = '';
              res3.on('data', (c) => b3 += c);
              res3.on('end', () => {
                try {
                  const j3 = JSON.parse(b3);
                  check('POST /echo body parsed', j3.received && j3.received.msg === 'test');
                } catch(e) { check('POST /echo body parsed', false); }

                // Test route params
                http.get('http://127.0.0.1:' + port + '/params/42', (res4) => {
                  let b4 = '';
                  res4.on('data', (c) => b4 += c);
                  res4.on('end', () => {
                    try {
                      const j4 = JSON.parse(b4);
                      check('GET /params/:id', j4.id === '42');
                    } catch(e) { check('GET /params/:id', false); }

                    server.close(() => {
                      check('server closed', true);
                      finish();
                    });
                  });
                });
              });
            });
            postReq.end(postData);
          });
        });
      });
    });
  });
} catch(e) {
  console.log('FAIL: express error - ' + e.message);
  check('express loaded', false);
  finish();
}

setTimeout(() => { finish(); }, 10000);
