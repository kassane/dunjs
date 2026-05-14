// HTTP server for Bun (native Bun.serve)
var PORT = 8080;
if (process.argv.length > 2)
    PORT = parseInt(process.argv[2], 10) || 8080;
else if (process.env.BENCH_PORT)
    PORT = parseInt(process.env.BENCH_PORT, 10) || 8080;

const JSON_BODY = JSON.stringify({ message: 'Hello, World!', runtime: 'bun' });
const TEXT_BODY = 'Hello, World!';

Bun.serve({
    port: PORT,
    fetch(req) {
        const url = new URL(req.url);
        const path = url.pathname;

        if (path === '/json') {
            return new Response(JSON_BODY, {
                headers: { 'Content-Type': 'application/json' },
            });
        } else if (path === '/plaintext') {
            return new Response(TEXT_BODY, {
                headers: { 'Content-Type': 'text/plain' },
            });
        } else if (path === '/echo') {
            const headers = {};
            req.headers.forEach((v, k) => { headers[k] = v; });
            const body = JSON.stringify({
                method: req.method,
                url: req.url,
                headers,
            });
            return new Response(body, {
                headers: { 'Content-Type': 'application/json' },
            });
        } else if (path === '/compute') {
            let a = 0, b = 1;
            for (let i = 0; i < 30; i++) { const t = a + b; a = b; b = t; }
            const body = JSON.stringify({ fib30: b });
            return new Response(body, {
                headers: { 'Content-Type': 'application/json' },
            });
        } else {
            return new Response('OK', {
                headers: { 'Content-Type': 'text/plain' },
            });
        }
    },
});
console.log('READY:' + PORT);
