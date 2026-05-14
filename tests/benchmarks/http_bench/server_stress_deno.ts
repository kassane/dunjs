// Stress benchmark server for Deno — identical logic, Deno.serve API
var PORT = 8080;
if (Deno.args.length > 0)
    PORT = parseInt(Deno.args[0], 10) || 8080;

const USERS_DB: {id: number; name: string; email: string; active: boolean}[] = [];
for (let i = 0; i < 100; i++) {
    USERS_DB.push({ id: i, name: 'User_' + i, email: 'user' + i + '@example.com', active: i % 3 !== 0 });
}
const TEXT_BODY = 'Hello, World!';
const JSON_BODY = JSON.stringify({ message: 'Hello, World!' });

function fibonacci(n: number): number {
    let a = 0, b = 1;
    for (let i = 0; i < n; i++) { const t = a + b; a = b; b = t; }
    return b;
}

function processTransaction(id: number, amount: number) {
    let hash = 0;
    const data = id + ':' + amount + ':' + Date.now();
    for (let i = 0; i < data.length; i++) {
        hash = ((hash << 5) - hash + data.charCodeAt(i)) | 0;
    }
    return {
        txId: 'TX-' + Math.abs(hash).toString(16).toUpperCase(),
        status: amount > 0 ? 'completed' : 'rejected',
        amount, timestamp: Date.now()
    };
}

Deno.serve({ port: PORT, onListen: () => console.log('READY:' + PORT) }, (req: Request): Response => {
    const url = new URL(req.url);
    const path = url.pathname;

    if (path === '/plaintext') {
        return new Response(TEXT_BODY, { headers: { 'Content-Type': 'text/plain' } });
    } else if (path === '/json') {
        return new Response(JSON_BODY, { headers: { 'Content-Type': 'application/json' } });
    } else if (path === '/api/users') {
        const active = USERS_DB.filter(u => u.active);
        return new Response(JSON.stringify({ users: active, total: active.length }),
            { headers: { 'Content-Type': 'application/json' } });
    } else if (path.startsWith('/api/user/')) {
        const uid = parseInt(path.slice(10), 10);
        if (uid >= 0 && uid < USERS_DB.length) {
            return new Response(JSON.stringify(USERS_DB[uid]),
                { headers: { 'Content-Type': 'application/json' } });
        }
        return new Response(JSON.stringify({ error: 'Not Found' }),
            { status: 404, headers: { 'Content-Type': 'application/json' } });
    } else if (path === '/compute') {
        return new Response(JSON.stringify({ fib30: fibonacci(30), fib40: fibonacci(40) }),
            { headers: { 'Content-Type': 'application/json' } });
    } else if (path === '/compute/heavy') {
        const results: number[] = [];
        for (let i = 20; i <= 35; i++) results.push(fibonacci(i));
        return new Response(JSON.stringify({ fibonacci: results, count: results.length }),
            { headers: { 'Content-Type': 'application/json' } });
    } else if (path === '/transaction') {
        const txId = Math.floor(Math.random() * 100000);
        const amount = Math.floor(Math.random() * 10000) / 100;
        return new Response(JSON.stringify(processTransaction(txId, amount)),
            { headers: { 'Content-Type': 'application/json' } });
    } else if (path === '/middleware') {
        const result = { auth: true, rateLimited: false, validated: true, processed: true };
        return new Response(JSON.stringify(result), {
            headers: { 'Content-Type': 'application/json',
                'X-Request-Id': 'req-' + Date.now(), 'X-RateLimit-Remaining': '99' }
        });
    } else if (path === '/echo') {
        const headers: Record<string, string> = {};
        req.headers.forEach((v, k) => { headers[k] = v; });
        return new Response(JSON.stringify({ method: req.method, url: req.url, headers }),
            { headers: { 'Content-Type': 'application/json' } });
    } else {
        return new Response('OK', { headers: { 'Content-Type': 'text/plain' } });
    }
});
