// HTTP server for Deno (native Deno.serve)
var PORT = 8080;
if (Deno.args.length > 0)
    PORT = parseInt(Deno.args[0], 10) || 8080;
else
    PORT = parseInt(Deno.env.get('BENCH_PORT') || '8080', 10);

const JSON_BODY = JSON.stringify({ message: 'Hello, World!', runtime: 'deno' });
const TEXT_BODY = 'Hello, World!';
const encoder = new TextEncoder();

Deno.serve({ port: PORT, onListen: () => console.log('READY:' + PORT) }, (req: Request): Response => {
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
        const headers: Record<string, string> = {};
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
});
