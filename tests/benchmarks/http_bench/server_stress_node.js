// Stress benchmark server for Node.js — identical logic to server_stress.js
const http = require('http');

var PORT = 8080;
if (process.argv.length > 2)
    PORT = parseInt(process.argv[2], 10) || 8080;

const USERS_DB = [];
for (var i = 0; i < 100; i++) {
    USERS_DB.push({ id: i, name: 'User_' + i, email: 'user' + i + '@example.com', active: i % 3 !== 0 });
}
const TEXT_BODY = 'Hello, World!';
const JSON_BODY = JSON.stringify({ message: 'Hello, World!' });

function fibonacci(n) {
    var a = 0, b = 1;
    for (var i = 0; i < n; i++) { var t = a + b; a = b; b = t; }
    return b;
}

function processTransaction(id, amount) {
    var hash = 0;
    var data = id + ':' + amount + ':' + Date.now();
    for (var i = 0; i < data.length; i++) {
        hash = ((hash << 5) - hash + data.charCodeAt(i)) | 0;
    }
    return {
        txId: 'TX-' + Math.abs(hash).toString(16).toUpperCase(),
        status: amount > 0 ? 'completed' : 'rejected',
        amount: amount,
        timestamp: Date.now()
    };
}

const server = http.createServer((req, res) => {
    const url = req.url;
    if (url === '/plaintext') {
        res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': TEXT_BODY.length });
        res.end(TEXT_BODY);
    } else if (url === '/json') {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': JSON_BODY.length });
        res.end(JSON_BODY);
    } else if (url === '/api/users') {
        const active = USERS_DB.filter(u => u.active);
        const body = JSON.stringify({ users: active, total: active.length });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length });
        res.end(body);
    } else if (url.startsWith('/api/user/')) {
        const uid = parseInt(url.slice(10), 10);
        if (uid >= 0 && uid < USERS_DB.length) {
            const body = JSON.stringify(USERS_DB[uid]);
            res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length });
            res.end(body);
        } else {
            const errBody = JSON.stringify({ error: 'Not Found' });
            res.writeHead(404, { 'Content-Type': 'application/json', 'Content-Length': errBody.length });
            res.end(errBody);
        }
    } else if (url === '/compute') {
        const body = JSON.stringify({ fib30: fibonacci(30), fib40: fibonacci(40) });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length });
        res.end(body);
    } else if (url === '/compute/heavy') {
        const results = [];
        for (let i = 20; i <= 35; i++) results.push(fibonacci(i));
        const body = JSON.stringify({ fibonacci: results, count: results.length });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length });
        res.end(body);
    } else if (url === '/transaction') {
        const txId = Math.floor(Math.random() * 100000);
        const amount = Math.floor(Math.random() * 10000) / 100;
        const tx = processTransaction(txId, amount);
        const body = JSON.stringify(tx);
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length });
        res.end(body);
    } else if (url === '/middleware') {
        const authOk = req.headers && (req.headers['authorization'] || true);
        const rateLimited = false;
        const validated = url.length < 1024;
        const result = { auth: !!authOk, rateLimited, validated, processed: true };
        const body = JSON.stringify(result);
        res.writeHead(200, {
            'Content-Type': 'application/json', 'Content-Length': body.length,
            'X-Request-Id': 'req-' + Date.now(), 'X-RateLimit-Remaining': '99'
        });
        res.end(body);
    } else if (url === '/echo') {
        const body = JSON.stringify({ method: req.method, url: req.url, headers: req.headers });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length });
        res.end(body);
    } else {
        res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': 2 });
        res.end('OK');
    }
});

server.listen(PORT, () => console.log('READY:' + PORT));
