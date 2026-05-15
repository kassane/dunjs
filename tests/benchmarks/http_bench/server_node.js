// HTTP server for Node.js
const http = require('http');

var PORT = 8080;
if (process.argv.length > 2)
    PORT = parseInt(process.argv[2], 10) || 8080;
else if (process.env.BENCH_PORT)
    PORT = parseInt(process.env.BENCH_PORT, 10) || 8080;

const JSON_BODY = JSON.stringify({ message: 'Hello, World!', runtime: 'node' });
const TEXT_BODY = 'Hello, World!';

const server = http.createServer((req, res) => {
    const url = req.url;
    if (url === '/json') {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': JSON_BODY.length });
        res.end(JSON_BODY);
    } else if (url === '/plaintext') {
        res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': TEXT_BODY.length });
        res.end(TEXT_BODY);
    } else if (url === '/echo') {
        const body = JSON.stringify({
            method: req.method,
            url: req.url,
            headers: req.headers
        });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length });
        res.end(body);
    } else if (url === '/compute') {
        let a = 0, b = 1;
        for (let i = 0; i < 30; i++) { const t = a + b; a = b; b = t; }
        const body = JSON.stringify({ fib30: b });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length });
        res.end(body);
    } else {
        res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': 2 });
        res.end('OK');
    }
});

server.listen(PORT, () => {
    console.log('READY:' + PORT);
});
