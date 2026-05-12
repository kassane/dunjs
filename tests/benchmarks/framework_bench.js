// Framework pattern benchmarks — cross-runtime comparison (DunJS / Bun / Deno / Node)
// Tests underlying operations used by Express, Fastify, Hono, Koa, and friends
// Run: dun run tests/benchmarks/framework_bench.js
// Run: bun run tests/benchmarks/framework_bench.js
// Run: deno run tests/benchmarks/framework_bench.js
// Run: node tests/benchmarks/framework_bench.js

const results = [];

function benchmark(name, fn, warmup, minMs) {
    warmup = warmup || 100;
    minMs = minMs || 200;
    try {
        // Warmup
        for (var i = 0; i < warmup; i++) fn();

        // Auto-calibrate: double iterations until we fill minMs
        var iters = 1000;
        var elapsed = 0;
        while (elapsed < minMs) {
            var start = Date.now();
            for (var j = 0; j < iters; j++) fn();
            elapsed = Date.now() - start;
            if (elapsed < minMs) {
                iters = Math.min(iters * 2, 100000);
                if (iters >= 100000 && elapsed < minMs) {
                    // Already at max iterations, measure what we have
                    break;
                }
            }
        }
        if (elapsed === 0) elapsed = 1;
        var nsPerOp = Math.round((elapsed * 1e6) / iters);
        var opsPerSec = Math.round((iters / elapsed) * 1000);
        results.push({ name: name, nsPerOp: nsPerOp, opsPerSec: opsPerSec, iters: iters });
        console.log("  " + name + ": " + nsPerOp + "ns/op (" + opsPerSec.toLocaleString() + " ops/sec)");
    } catch (e) {
        var msg = e && e.message ? e.message : String(e);
        results.push({ name: name, nsPerOp: 0, opsPerSec: 0, iters: 0, error: msg });
        console.log("  " + name + ": FAIL (" + msg.substring(0, 80) + ")");
    }
}

// ============================================================
// 1. HTTP ROUTING SIMULATION (Express/Fastify/Hono patterns)
// ============================================================
console.log("\n=== HTTP Routing ===");

// Build a route table with 100 routes
var routeTable = [];
var methods = ["GET", "POST", "PUT", "DELETE", "PATCH"];
var segments = ["users", "posts", "comments", "tags", "categories", "auth", "admin", "api", "v1", "v2"];
for (var i = 0; i < 100; i++) {
    var method = methods[i % methods.length];
    var seg1 = segments[i % segments.length];
    var seg2 = segments[(i + 3) % segments.length];
    routeTable.push({
        method: method,
        pattern: new RegExp("^/" + seg1 + "/" + seg2 + "(?:/([^/]+))?$"),
        path: "/" + seg1 + "/" + seg2,
        handler: function() { return { status: 200 }; }
    });
}

benchmark("path matching (100 routes)", function() {
    var path = "/users/comments/42";
    var matched = null;
    for (var i = 0; i < routeTable.length; i++) {
        var m = path.match(routeTable[i].pattern);
        if (m) { matched = routeTable[i]; break; }
    }
    return matched;
});

// URL parameter extraction like /users/:id/posts/:postId
var paramPattern = /^\/users\/([^/]+)\/posts\/([^/]+)$/;
benchmark("parameter extraction", function() {
    var m = "/users/abc-123/posts/post-456".match(paramPattern);
    return { userId: m[1], postId: m[2] };
});

benchmark("query string parsing (URLSearchParams)", function() {
    var params = new URLSearchParams("page=1&limit=20&sort=created_at&order=desc&filter=active&q=search+term");
    return {
        page: params.get("page"),
        limit: params.get("limit"),
        sort: params.get("sort"),
        order: params.get("order"),
        filter: params.get("filter"),
        q: params.get("q")
    };
});

// Radix tree simulation — trie-based route lookup
var trieRoot = { children: {}, handler: null };
function trieInsert(path, handler) {
    var parts = path.split("/").filter(function(p) { return p.length > 0; });
    var node = trieRoot;
    for (var i = 0; i < parts.length; i++) {
        var key = parts[i].startsWith(":") ? ":param" : parts[i];
        if (!node.children[key]) node.children[key] = { children: {}, handler: null, paramName: parts[i].startsWith(":") ? parts[i].slice(1) : null };
        node = node.children[key];
    }
    node.handler = handler;
}
function trieLookup(path) {
    var parts = path.split("/").filter(function(p) { return p.length > 0; });
    var node = trieRoot;
    var params = {};
    for (var i = 0; i < parts.length; i++) {
        if (node.children[parts[i]]) {
            node = node.children[parts[i]];
        } else if (node.children[":param"]) {
            node = node.children[":param"];
            if (node.paramName) params[node.paramName] = parts[i];
        } else {
            return null;
        }
    }
    return { handler: node.handler, params: params };
}
var routePaths = [
    "/api/v1/users", "/api/v1/users/:id", "/api/v1/users/:id/posts",
    "/api/v1/posts", "/api/v1/posts/:id", "/api/v1/posts/:id/comments",
    "/api/v2/auth/login", "/api/v2/auth/register", "/api/v2/auth/refresh",
    "/api/v2/admin/dashboard", "/api/v2/admin/users", "/api/v2/admin/settings",
    "/health", "/metrics", "/ready", "/api/v1/tags", "/api/v1/categories",
    "/api/v1/search", "/api/v1/upload", "/api/v1/download/:id"
];
for (var i = 0; i < routePaths.length; i++) {
    trieInsert(routePaths[i], function() { return 200; });
}

benchmark("radix trie lookup (20 routes)", function() {
    trieLookup("/api/v1/users/abc-123/posts");
    trieLookup("/api/v2/auth/login");
    trieLookup("/health");
    trieLookup("/api/v1/download/file-99");
    return trieLookup("/api/v2/admin/dashboard");
});

benchmark("URL constructor + pathname", function() {
    var u = new URL("https://api.example.com:8080/v2/users/123/posts?page=5&limit=20&sort=date#comments");
    return u.pathname + u.search + u.hash;
});

// ============================================================
// 2. MIDDLEWARE PIPELINE (Express/Koa patterns)
// ============================================================
console.log("\n=== Middleware Pipeline ===");

// Synchronous middleware chain (like Express)
function composeSync(middlewares) {
    return function(ctx) {
        var idx = 0;
        function next() {
            if (idx >= middlewares.length) return;
            var fn = middlewares[idx++];
            fn(ctx, next);
        }
        next();
        return ctx;
    };
}

var syncMiddlewares = [];
for (var i = 0; i < 10; i++) {
    (function(n) {
        syncMiddlewares.push(function(ctx, next) {
            ctx.steps.push(n);
            ctx.count++;
            next();
        });
    })(i);
}
var syncPipeline = composeSync(syncMiddlewares);

benchmark("sync middleware chain (10 layers)", function() {
    return syncPipeline({ steps: [], count: 0, body: null, status: 200 });
});

// Async middleware (like Koa)
function composeAsync(middlewares) {
    return function(ctx) {
        var idx = 0;
        function next() {
            if (idx >= middlewares.length) return Promise.resolve();
            var fn = middlewares[idx++];
            return Promise.resolve(fn(ctx, next));
        }
        return next().then(function() { return ctx; });
    };
}

var asyncMiddlewares = [];
for (var i = 0; i < 10; i++) {
    (function(n) {
        asyncMiddlewares.push(function(ctx, next) {
            ctx.steps.push(n);
            return next();
        });
    })(i);
}
var asyncPipeline = composeAsync(asyncMiddlewares);

benchmark("async middleware chain (10 layers)", function() {
    return asyncPipeline({ steps: [], body: null, status: 200 });
});

// Error-handling middleware pattern
function composeWithError(middlewares) {
    return function(ctx) {
        var idx = 0;
        function next() {
            if (idx >= middlewares.length) return ctx;
            var fn = middlewares[idx++];
            try {
                fn(ctx, next);
            } catch (err) {
                ctx.error = err.message;
                ctx.status = 500;
            }
        }
        next();
        return ctx;
    };
}

var errorMiddlewares = [
    function(ctx, next) { ctx.requestId = "req-" + Math.random().toString(36).slice(2, 10); next(); },
    function(ctx, next) { ctx.startTime = Date.now(); next(); },
    function(ctx, next) { if (!ctx.authorized) { throw new Error("Unauthorized"); } next(); },
    function(ctx, next) { ctx.body = { data: "response" }; next(); },
    function(ctx, next) { ctx.endTime = Date.now(); next(); }
];
var errorPipeline = composeWithError(errorMiddlewares);

benchmark("error handling middleware", function() {
    return errorPipeline({ authorized: false, status: 200 });
});

// Context object passing — accumulating headers, cookies, state
benchmark("context object building", function() {
    var ctx = {
        req: { method: "GET", url: "/api/users", headers: {} },
        res: { status: 200, headers: {}, body: null },
        state: {}
    };
    ctx.state.user = { id: 1, role: "admin" };
    ctx.res.headers["content-type"] = "application/json";
    ctx.res.headers["x-request-id"] = "abc-123";
    ctx.res.headers["cache-control"] = "no-cache";
    ctx.res.headers["x-powered-by"] = "DunJS";
    ctx.res.body = JSON.stringify({ users: [{ id: 1 }] });
    return ctx;
});

// ============================================================
// 3. JSON API PATTERNS
// ============================================================
console.log("\n=== JSON API ===");

// Generate payloads of various sizes
var smallPayload = JSON.stringify({ id: 1, name: "Alice", email: "alice@example.com", age: 30, active: true });
var mediumObj = { users: [] };
for (var i = 0; i < 50; i++) {
    mediumObj.users.push({
        id: i, name: "User " + i, email: "user" + i + "@example.com",
        age: 20 + (i % 50), active: i % 3 !== 0,
        tags: ["tag1", "tag2", "tag3"],
        address: { street: i + " Main St", city: "Testville", zip: "" + (10000 + i) }
    });
}
var mediumPayload = JSON.stringify(mediumObj);
var largeObj = { data: [] };
for (var i = 0; i < 500; i++) {
    largeObj.data.push({
        id: i, timestamp: "2024-01-" + ((i % 28) + 1) + "T10:30:00Z",
        metrics: { cpu: Math.random() * 100, mem: Math.random() * 16384, disk: Math.random() * 1024 },
        labels: { env: "production", region: "us-east-1", service: "api-" + (i % 10) },
        message: "Log entry number " + i + " with some payload data for testing purposes"
    });
}
var largePayload = JSON.stringify(largeObj);

benchmark("JSON.parse ~200B (small)", function() {
    return JSON.parse(smallPayload);
});

benchmark("JSON.parse ~10KB (medium)", function() {
    return JSON.parse(mediumPayload);
});

benchmark("JSON.parse ~100KB (large)", function() {
    return JSON.parse(largePayload);
}, 50, 300);

benchmark("JSON.stringify nested objects", function() {
    return JSON.stringify(mediumObj);
});

// Request body validation pattern (like express-validator/joi)
benchmark("request body validation", function() {
    var body = { name: "Alice", email: "alice@example.com", age: 30, role: "admin" };
    var errors = [];
    if (typeof body.name !== "string" || body.name.length < 1 || body.name.length > 100) errors.push("name");
    if (typeof body.email !== "string" || !/^[^@]+@[^@]+\.[^@]+$/.test(body.email)) errors.push("email");
    if (typeof body.age !== "number" || body.age < 0 || body.age > 150) errors.push("age");
    if (["admin", "user", "guest"].indexOf(body.role) === -1) errors.push("role");
    return errors.length === 0;
});

// Response serialization with replacer
benchmark("JSON.stringify with replacer", function() {
    return JSON.stringify(mediumObj, function(key, val) {
        if (key === "email") return undefined; // redact emails
        if (key === "age" && typeof val === "number") return val > 100 ? 100 : val;
        return val;
    });
});

// ============================================================
// 4. TEMPLATE ENGINE SIMULATION (EJS/Handlebars patterns)
// ============================================================
console.log("\n=== Template Engine ===");

benchmark("string interpolation (template literal sim)", function() {
    var user = { name: "Alice", age: 30, email: "alice@example.com" };
    var items = ["Home", "About", "Contact", "Blog", "FAQ"];
    var html = "<html><head><title>Profile</title></head><body>";
    html += "<h1>Welcome, " + user.name + "!</h1>";
    html += "<p>Age: " + user.age + ", Email: " + user.email + "</p>";
    html += "<ul>";
    for (var i = 0; i < items.length; i++) {
        html += "<li>" + items[i] + "</li>";
    }
    html += "</ul></body></html>";
    return html;
});

var htmlEscapeMap = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
var htmlEscapeRe = /[&<>"']/g;
function escapeHtml(str) {
    return str.replace(htmlEscapeRe, function(ch) { return htmlEscapeMap[ch]; });
}

benchmark("HTML escaping", function() {
    escapeHtml('<script>alert("XSS & injection")</script>');
    escapeHtml('Tom & Jerry\'s "adventure" <2024>');
    escapeHtml("Normal text without special characters here");
    return escapeHtml('<a href="test.html?a=1&b=2">link</a>');
});

// Simple template compiler — replaces {{key}} with values
function compileTemplate(tmpl) {
    var parts = tmpl.split(/\{\{(\w+)\}\}/);
    return function(data) {
        var out = "";
        for (var i = 0; i < parts.length; i++) {
            if (i % 2 === 0) out += parts[i];
            else out += data[parts[i]] !== undefined ? String(data[parts[i]]) : "";
        }
        return out;
    };
}
var compiled = compileTemplate(
    "<div class='card'><h2>{{name}}</h2><p>{{bio}}</p><span>Age: {{age}}</span><a href='mailto:{{email}}'>{{email}}</a></div>"
);

benchmark("compiled template render", function() {
    return compiled({ name: "Alice", bio: "Software engineer", age: 30, email: "alice@example.com" });
});

// Conditional rendering pattern
benchmark("conditional template rendering", function() {
    var user = { name: "Alice", isAdmin: true, notifications: 5, isPremium: false };
    var html = "<div>";
    html += "<h1>" + user.name + "</h1>";
    if (user.isAdmin) html += '<span class="badge">Admin</span>';
    if (user.notifications > 0) html += '<span class="notif">' + user.notifications + " new</span>";
    if (user.isPremium) html += '<span class="premium">Premium</span>';
    else html += '<span class="free">Free tier</span>';
    html += "</div>";
    return html;
});

// ============================================================
// 5. DATABASE QUERY BUILDING (Knex/Prisma patterns)
// ============================================================
console.log("\n=== Query Building ===");

function buildSelect(table, columns, where, orderBy, limit, offset) {
    var sql = "SELECT " + columns.join(", ") + " FROM " + table;
    var params = [];
    if (where && Object.keys(where).length > 0) {
        var clauses = [];
        var keys = Object.keys(where);
        for (var i = 0; i < keys.length; i++) {
            clauses.push(keys[i] + " = ?");
            params.push(where[keys[i]]);
        }
        sql += " WHERE " + clauses.join(" AND ");
    }
    if (orderBy) sql += " ORDER BY " + orderBy;
    if (limit) { sql += " LIMIT ?"; params.push(limit); }
    if (offset) { sql += " OFFSET ?"; params.push(offset); }
    return { sql: sql, params: params };
}

benchmark("SQL SELECT builder", function() {
    return buildSelect("users", ["id", "name", "email", "created_at"],
        { active: true, role: "admin", org_id: 42 }, "created_at DESC", 20, 0);
});

function buildInsert(table, rows) {
    if (rows.length === 0) return { sql: "", params: [] };
    var keys = Object.keys(rows[0]);
    var placeholders = [];
    var params = [];
    for (var i = 0; i < rows.length; i++) {
        var vals = [];
        for (var j = 0; j < keys.length; j++) {
            vals.push("?");
            params.push(rows[i][keys[j]]);
        }
        placeholders.push("(" + vals.join(", ") + ")");
    }
    return { sql: "INSERT INTO " + table + " (" + keys.join(", ") + ") VALUES " + placeholders.join(", "), params: params };
}

benchmark("SQL INSERT builder (10 rows)", function() {
    var rows = [];
    for (var i = 0; i < 10; i++) {
        rows.push({ name: "User " + i, email: "user" + i + "@test.com", age: 20 + i, active: true });
    }
    return buildInsert("users", rows);
});

benchmark("Object-to-WHERE clause", function() {
    var filters = {
        status: "active",
        role: "admin",
        age_gte: 18,
        age_lte: 65,
        org_id: 42,
        verified: true
    };
    var clauses = [];
    var params = [];
    var keys = Object.keys(filters);
    for (var i = 0; i < keys.length; i++) {
        var k = keys[i];
        if (k.endsWith("_gte")) {
            clauses.push(k.slice(0, -4) + " >= ?");
        } else if (k.endsWith("_lte")) {
            clauses.push(k.slice(0, -4) + " <= ?");
        } else {
            clauses.push(k + " = ?");
        }
        params.push(filters[k]);
    }
    return { where: clauses.join(" AND "), params: params };
});

// Result set transformation (like ORM hydration)
var rawRows = [];
for (var i = 0; i < 100; i++) {
    rawRows.push({
        user_id: i, user_name: "User " + i, user_email: "u" + i + "@test.com",
        post_id: i * 10, post_title: "Post " + i, post_body: "Content " + i,
        comment_count: i % 20
    });
}

benchmark("result set transformation (100 rows)", function() {
    return rawRows
        .filter(function(r) { return r.comment_count > 5; })
        .map(function(r) {
            return {
                user: { id: r.user_id, name: r.user_name, email: r.user_email },
                post: { id: r.post_id, title: r.post_title, body: r.post_body },
                commentCount: r.comment_count
            };
        })
        .sort(function(a, b) { return b.commentCount - a.commentCount; });
});

// ============================================================
// 6. VALIDATION (Joi/Zod patterns)
// ============================================================
console.log("\n=== Validation ===");

function createValidator(schema) {
    return function(obj) {
        var errors = [];
        var keys = Object.keys(schema);
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i];
            var rule = schema[key];
            var val = obj[key];
            if (rule.required && (val === undefined || val === null)) {
                errors.push(key + " is required");
                continue;
            }
            if (val === undefined || val === null) continue;
            if (rule.type && typeof val !== rule.type) {
                errors.push(key + " must be " + rule.type);
            }
            if (rule.min !== undefined && typeof val === "number" && val < rule.min) {
                errors.push(key + " must be >= " + rule.min);
            }
            if (rule.max !== undefined && typeof val === "number" && val > rule.max) {
                errors.push(key + " must be <= " + rule.max);
            }
            if (rule.minLength !== undefined && typeof val === "string" && val.length < rule.minLength) {
                errors.push(key + " too short");
            }
            if (rule.maxLength !== undefined && typeof val === "string" && val.length > rule.maxLength) {
                errors.push(key + " too long");
            }
            if (rule.pattern && typeof val === "string" && !rule.pattern.test(val)) {
                errors.push(key + " invalid format");
            }
            if (rule.enum && rule.enum.indexOf(val) === -1) {
                errors.push(key + " must be one of: " + rule.enum.join(", "));
            }
        }
        return { valid: errors.length === 0, errors: errors };
    };
}

var userValidator = createValidator({
    name: { required: true, type: "string", minLength: 1, maxLength: 100 },
    email: { required: true, type: "string", pattern: /^[^@\s]+@[^@\s]+\.[^@\s]+$/ },
    age: { required: false, type: "number", min: 0, max: 150 },
    role: { required: true, type: "string", enum: ["admin", "user", "guest", "moderator"] },
    bio: { required: false, type: "string", maxLength: 500 }
});

benchmark("schema validation (5 fields)", function() {
    return userValidator({ name: "Alice", email: "alice@example.com", age: 30, role: "admin", bio: "Hello!" });
});

benchmark("schema validation (invalid)", function() {
    return userValidator({ name: "", email: "invalid", age: -5, role: "superadmin" });
});

// Nested object validation
function validateNested(obj, schema, path) {
    path = path || "";
    var errors = [];
    var keys = Object.keys(schema);
    for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        var rule = schema[key];
        var val = obj ? obj[key] : undefined;
        var fullPath = path ? path + "." + key : key;
        if (rule.type === "object" && rule.properties) {
            errors = errors.concat(validateNested(val || {}, rule.properties, fullPath));
        } else if (rule.required && (val === undefined || val === null)) {
            errors.push(fullPath + " is required");
        } else if (val !== undefined && rule.type && typeof val !== rule.type) {
            errors.push(fullPath + " must be " + rule.type);
        }
    }
    return errors;
}

var nestedSchema = {
    user: {
        type: "object",
        properties: {
            name: { required: true, type: "string" },
            email: { required: true, type: "string" },
            profile: {
                type: "object",
                properties: {
                    bio: { required: false, type: "string" },
                    avatar: { required: false, type: "string" },
                    settings: {
                        type: "object",
                        properties: {
                            theme: { required: false, type: "string" },
                            notifications: { required: false, type: "boolean" }
                        }
                    }
                }
            }
        }
    }
};

benchmark("nested object validation (3 levels)", function() {
    return validateNested({
        user: {
            name: "Alice", email: "alice@example.com",
            profile: { bio: "Hello", avatar: "pic.jpg", settings: { theme: "dark", notifications: true } }
        }
    }, nestedSchema);
});

// Array item validation
benchmark("array validation (20 items)", function() {
    var items = [];
    for (var i = 0; i < 20; i++) {
        items.push({ id: i, name: "Item " + i, price: 9.99 + i, inStock: i % 3 !== 0 });
    }
    var errors = [];
    for (var i = 0; i < items.length; i++) {
        if (typeof items[i].id !== "number") errors.push("items[" + i + "].id");
        if (typeof items[i].name !== "string") errors.push("items[" + i + "].name");
        if (typeof items[i].price !== "number" || items[i].price < 0) errors.push("items[" + i + "].price");
        if (typeof items[i].inStock !== "boolean") errors.push("items[" + i + "].inStock");
    }
    return { valid: errors.length === 0, errors: errors };
});

// Error accumulation pattern
benchmark("error accumulation (aggregate)", function() {
    var data = {
        username: "ab", // too short
        password: "123", // too short, no special char
        email: "not-an-email",
        age: 200, // out of range
        terms: false // must be true
    };
    var errors = {};
    if (data.username.length < 3) (errors.username = errors.username || []).push("min 3 chars");
    if (data.username.length > 30) (errors.username = errors.username || []).push("max 30 chars");
    if (data.password.length < 8) (errors.password = errors.password || []).push("min 8 chars");
    if (!/[!@#$%]/.test(data.password)) (errors.password = errors.password || []).push("needs special char");
    if (!/^[^@]+@[^@]+\.[^@]+$/.test(data.email)) (errors.email = errors.email || []).push("invalid email");
    if (data.age < 0 || data.age > 150) (errors.age = errors.age || []).push("must be 0-150");
    if (data.terms !== true) (errors.terms = errors.terms || []).push("must accept terms");
    return { valid: Object.keys(errors).length === 0, errors: errors };
});

// ============================================================
// 7. CONCURRENCY PATTERNS (async framework patterns)
// ============================================================
console.log("\n=== Concurrency Patterns ===");

benchmark("Promise.all (50 tasks)", function() {
    var tasks = [];
    for (var i = 0; i < 50; i++) {
        tasks.push(Promise.resolve(i * i));
    }
    return Promise.all(tasks);
});

benchmark("Promise.allSettled (50 tasks, 10 fail)", function() {
    var tasks = [];
    for (var i = 0; i < 50; i++) {
        if (i % 5 === 0) tasks.push(Promise.reject(new Error("fail-" + i)));
        else tasks.push(Promise.resolve(i));
    }
    return Promise.allSettled(tasks);
});

// Token bucket rate limiter simulation
function TokenBucket(capacity, refillRate) {
    this.capacity = capacity;
    this.tokens = capacity;
    this.refillRate = refillRate;
    this.lastRefill = Date.now();
}
TokenBucket.prototype.tryConsume = function(n) {
    var now = Date.now();
    var elapsed = now - this.lastRefill;
    this.tokens = Math.min(this.capacity, this.tokens + (elapsed * this.refillRate / 1000));
    this.lastRefill = now;
    if (this.tokens >= n) {
        this.tokens -= n;
        return true;
    }
    return false;
};

var limiter = new TokenBucket(100, 50);

benchmark("rate limiter (token bucket)", function() {
    limiter.tokens = 100; // reset for consistent benchmarking
    var accepted = 0;
    for (var i = 0; i < 200; i++) {
        if (limiter.tryConsume(1)) accepted++;
    }
    return accepted;
});

// Connection pool simulation (semaphore pattern)
function Pool(maxSize) {
    this.maxSize = maxSize;
    this.active = 0;
    this.queue = [];
}
Pool.prototype.acquire = function() {
    var self = this;
    if (self.active < self.maxSize) {
        self.active++;
        return Promise.resolve({ id: self.active, release: function() { self.release(); } });
    }
    return new Promise(function(resolve) {
        self.queue.push(resolve);
    });
};
Pool.prototype.release = function() {
    if (this.queue.length > 0) {
        var next = this.queue.shift();
        next({ id: this.active, release: function() { } });
    } else {
        this.active--;
    }
};

benchmark("connection pool acquire/release", function() {
    var pool = new Pool(5);
    var ops = [];
    for (var i = 0; i < 20; i++) {
        ops.push(pool.acquire().then(function(conn) {
            conn.release();
        }));
    }
    return Promise.all(ops);
});

// Promise chain pipeline (like async request processing)
benchmark("promise chain (5 stages)", function() {
    return Promise.resolve({ raw: "input" })
        .then(function(ctx) { ctx.parsed = true; return ctx; })
        .then(function(ctx) { ctx.validated = true; return ctx; })
        .then(function(ctx) { ctx.transformed = JSON.stringify(ctx); return ctx; })
        .then(function(ctx) { ctx.logged = true; return ctx; })
        .then(function(ctx) { ctx.complete = true; return ctx; });
});

// ============================================================
// 8. BUFFER/ENCODING (body-parser patterns)
// ============================================================
console.log("\n=== Buffer/Encoding ===");

// Base64 encode/decode
var b64Input = "Hello, World! This is a test of base64 encoding. It should handle binary data properly.";

benchmark("btoa/atob round-trip", function() {
    var encoded = btoa(b64Input);
    return atob(encoded);
});

// TextEncoder/TextDecoder throughput
var textInput = "The quick brown fox jumps over the lazy dog. Unicode: éàüñ 你好世界";
var encoder = new TextEncoder();
var decoder = new TextDecoder();

benchmark("TextEncoder.encode", function() {
    return encoder.encode(textInput);
});

benchmark("TextDecoder.decode", function() {
    var bytes = encoder.encode(textInput);
    return decoder.decode(bytes);
});

benchmark("TextEncoder/Decoder round-trip (1KB)", function() {
    var longText = textInput;
    while (longText.length < 1024) longText += textInput;
    longText = longText.substring(0, 1024);
    var bytes = encoder.encode(longText);
    return decoder.decode(bytes);
});

// Hex encode/decode
function hexEncode(str) {
    var hex = "";
    for (var i = 0; i < str.length; i++) {
        var code = str.charCodeAt(i);
        hex += (code < 16 ? "0" : "") + code.toString(16);
    }
    return hex;
}
function hexDecode(hex) {
    var str = "";
    for (var i = 0; i < hex.length; i += 2) {
        str += String.fromCharCode(parseInt(hex.substring(i, i + 2), 16));
    }
    return str;
}

benchmark("hex encode/decode round-trip", function() {
    var encoded = hexEncode("Hello, World! Testing hex encoding 0123456789");
    return hexDecode(encoded);
});

// Simulated Buffer.from patterns (works on all runtimes via Uint8Array)
benchmark("Uint8Array from string (manual)", function() {
    var str = "Hello World benchmark string for encoding test!";
    var arr = new Uint8Array(str.length);
    for (var i = 0; i < str.length; i++) {
        arr[i] = str.charCodeAt(i);
    }
    return arr;
});

// ============================================================
// SUMMARY
// ============================================================
console.log("\n=== Summary ===");
var totalOps = 0;
var benchCount = 0;
var failCount = 0;
for (var i = 0; i < results.length; i++) {
    if (results[i].error) {
        failCount++;
    } else {
        totalOps += results[i].opsPerSec;
        benchCount++;
    }
}
console.log(results.length + " benchmarks completed" + (failCount > 0 ? " (" + failCount + " failed)" : ""));
console.log("Total throughput: " + totalOps.toLocaleString() + " ops/sec");
