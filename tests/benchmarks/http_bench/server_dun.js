// HTTP server for DunJS (QuickJS/JSC/V8 backends)
// Uses dun:http createServer API
const http = require('http');

// Port from argv[2] (dun run server.js PORT) or env or default
var PORT = 8080;
if (typeof process !== 'undefined' && process.argv && process.argv.length > 2)
    PORT = parseInt(process.argv[2], 10) || 8080;
else if (typeof process !== 'undefined' && process.env && process.env.BENCH_PORT)
    PORT = parseInt(process.env.BENCH_PORT, 10) || 8080;

const JSON_BODY = JSON.stringify({ message: 'Hello, World!', runtime: 'dunjs' });
const TEXT_BODY = 'Hello, World!';

const server = http.createServer(function(req, res) {
    const url = req.url;
    if (url === '/json') {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': JSON_BODY.length.toString() });
        res.end(JSON_BODY);
    } else if (url === '/plaintext') {
        res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': TEXT_BODY.length.toString() });
        res.end(TEXT_BODY);
    } else if (url === '/echo') {
        // Echo back request info as JSON
        const body = JSON.stringify({
            method: req.method,
            url: req.url,
            headers: req.headers
        });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length.toString() });
        res.end(body);
    } else if (url === '/compute') {
        // CPU-bound: compute fibonacci
        let a = 0, b = 1;
        for (let i = 0; i < 30; i++) { const t = a + b; a = b; b = t; }
        const body = JSON.stringify({ fib30: b });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length.toString() });
        res.end(body);
    } else {
        res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': '2' });
        res.end('OK');
    }
});

server.listen(PORT, function() {
    console.log('READY:' + PORT);
});
