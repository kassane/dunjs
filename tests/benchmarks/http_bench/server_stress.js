// Stress benchmark server — simulates real-world microservice patterns
// Endpoints test: JSON serialization, CPU compute, data processing,
// middleware chains, transaction simulation, error handling
const http = require('http');

var PORT = 8080;
if (typeof process !== 'undefined' && process.argv && process.argv.length > 2)
    PORT = parseInt(process.argv[2], 10) || 8080;

// Pre-computed constants
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

const server = http.createServer(function(req, res) {
    var url = req.url;

    if (url === '/plaintext') {
        res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': TEXT_BODY.length.toString() });
        res.end(TEXT_BODY);
    }
    else if (url === '/json') {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': JSON_BODY.length.toString() });
        res.end(JSON_BODY);
    }
    else if (url === '/api/users') {
        var active = USERS_DB.filter(function(u) { return u.active; });
        var body = JSON.stringify({ users: active, total: active.length });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length.toString() });
        res.end(body);
    }
    else if (url.indexOf('/api/user/') === 0) {
        var uid = parseInt(url.slice(10), 10);
        if (uid >= 0 && uid < USERS_DB.length) {
            var body = JSON.stringify(USERS_DB[uid]);
            res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length.toString() });
            res.end(body);
        } else {
            var errBody = JSON.stringify({ error: 'Not Found' });
            res.writeHead(404, { 'Content-Type': 'application/json', 'Content-Length': errBody.length.toString() });
            res.end(errBody);
        }
    }
    else if (url === '/compute') {
        var body = JSON.stringify({ fib30: fibonacci(30), fib40: fibonacci(40) });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length.toString() });
        res.end(body);
    }
    else if (url === '/compute/heavy') {
        var results = [];
        for (var i = 20; i <= 35; i++) results.push(fibonacci(i));
        var body = JSON.stringify({ fibonacci: results, count: results.length });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length.toString() });
        res.end(body);
    }
    else if (url === '/transaction') {
        var txId = Math.floor(Math.random() * 100000);
        var amount = Math.floor(Math.random() * 10000) / 100;
        var tx = processTransaction(txId, amount);
        var body = JSON.stringify(tx);
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length.toString() });
        res.end(body);
    }
    else if (url === '/middleware') {
        // Simulate middleware chain: auth check → rate limit → validate → process → serialize
        var authOk = req.headers && (req.headers['authorization'] || true);
        var rateLimited = false;
        var validated = url.length < 1024;
        var result = { auth: !!authOk, rateLimited: rateLimited, validated: validated, processed: true };
        var body = JSON.stringify(result);
        res.writeHead(200, {
            'Content-Type': 'application/json',
            'Content-Length': body.length.toString(),
            'X-Request-Id': 'req-' + Date.now(),
            'X-RateLimit-Remaining': '99'
        });
        res.end(body);
    }
    else if (url === '/echo') {
        var headers = req.headers || {};
        var body = JSON.stringify({ method: req.method, url: req.url, headers: headers });
        res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': body.length.toString() });
        res.end(body);
    }
    else {
        res.writeHead(200, { 'Content-Type': 'text/plain', 'Content-Length': '2' });
        res.end('OK');
    }
});

server.listen(PORT, function() {
    console.log('READY:' + PORT);
});
