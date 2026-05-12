// npm Package Compatibility Test — simulates popular npm packages using only standard JS
// Tests the underlying patterns that real packages depend on, without installing anything
// Run: dun run tests/benchmarks/npm_compat_test.js
// Run: bun run tests/benchmarks/npm_compat_test.js
// Run: deno run tests/benchmarks/npm_compat_test.js
// Run: node tests/benchmarks/npm_compat_test.js

var passCount = 0;
var failCount = 0;
var totalChecks = 0;

function assert(condition, msg) {
    totalChecks++;
    if (condition) {
        passCount++;
    } else {
        failCount++;
        console.log("  FAIL: " + msg);
    }
}

function section(name) {
    console.log("\n=== " + name + " ===");
}

// ============================================================
// 1. LODASH SIMULATION
// ============================================================
section("lodash (utility belt)");

var _ = {
    map: function(arr, fn) {
        var result = [];
        for (var i = 0; i < arr.length; i++) result.push(fn(arr[i], i, arr));
        return result;
    },
    filter: function(arr, fn) {
        var result = [];
        for (var i = 0; i < arr.length; i++) {
            if (fn(arr[i], i, arr)) result.push(arr[i]);
        }
        return result;
    },
    reduce: function(arr, fn, init) {
        var acc = init;
        for (var i = 0; i < arr.length; i++) acc = fn(acc, arr[i], i, arr);
        return acc;
    },
    chunk: function(arr, size) {
        var result = [];
        for (var i = 0; i < arr.length; i += size) {
            result.push(arr.slice(i, i + size));
        }
        return result;
    },
    groupBy: function(arr, fn) {
        var result = {};
        for (var i = 0; i < arr.length; i++) {
            var key = typeof fn === "function" ? fn(arr[i]) : arr[i][fn];
            if (!result[key]) result[key] = [];
            result[key].push(arr[i]);
        }
        return result;
    },
    debounce: function(fn, wait) {
        var timeout = null;
        return function() {
            var args = arguments;
            var self = this;
            if (timeout !== null) clearTimeout(timeout);
            timeout = setTimeout(function() { fn.apply(self, args); }, wait);
        };
    },
    throttle: function(fn, limit) {
        var lastCall = 0;
        return function() {
            var now = Date.now();
            if (now - lastCall >= limit) {
                lastCall = now;
                return fn.apply(this, arguments);
            }
        };
    },
    uniq: function(arr) {
        var seen = new Set();
        var result = [];
        for (var i = 0; i < arr.length; i++) {
            if (!seen.has(arr[i])) { seen.add(arr[i]); result.push(arr[i]); }
        }
        return result;
    },
    flatten: function(arr) {
        var result = [];
        for (var i = 0; i < arr.length; i++) {
            if (Array.isArray(arr[i])) {
                var inner = arr[i];
                for (var j = 0; j < inner.length; j++) result.push(inner[j]);
            } else {
                result.push(arr[i]);
            }
        }
        return result;
    },
    get: function(obj, path, def) {
        var parts = typeof path === "string" ? path.split(".") : path;
        var cur = obj;
        for (var i = 0; i < parts.length; i++) {
            if (cur === undefined || cur === null) return def;
            cur = cur[parts[i]];
        }
        return cur === undefined ? def : cur;
    },
    set: function(obj, path, value) {
        var parts = typeof path === "string" ? path.split(".") : path;
        var cur = obj;
        for (var i = 0; i < parts.length - 1; i++) {
            if (cur[parts[i]] === undefined) cur[parts[i]] = {};
            cur = cur[parts[i]];
        }
        cur[parts[parts.length - 1]] = value;
        return obj;
    },
    cloneDeep: function(obj) {
        return JSON.parse(JSON.stringify(obj));
    },
    pick: function(obj, keys) {
        var result = {};
        for (var i = 0; i < keys.length; i++) {
            if (keys[i] in obj) result[keys[i]] = obj[keys[i]];
        }
        return result;
    },
    omit: function(obj, keys) {
        var result = {};
        var omitSet = new Set(keys);
        var allKeys = Object.keys(obj);
        for (var i = 0; i < allKeys.length; i++) {
            if (!omitSet.has(allKeys[i])) result[allKeys[i]] = obj[allKeys[i]];
        }
        return result;
    },
    keyBy: function(arr, key) {
        var result = {};
        for (var i = 0; i < arr.length; i++) {
            result[arr[i][key]] = arr[i];
        }
        return result;
    }
};

// Tests
assert(JSON.stringify(_.map([1, 2, 3], function(x) { return x * 2; })) === "[2,4,6]", "_.map doubles");
assert(JSON.stringify(_.filter([1, 2, 3, 4, 5], function(x) { return x % 2 === 0; })) === "[2,4]", "_.filter even");
assert(_.reduce([1, 2, 3, 4], function(a, b) { return a + b; }, 0) === 10, "_.reduce sum");
var chunks = _.chunk([1, 2, 3, 4, 5], 2);
assert(chunks.length === 3, "_.chunk count");
assert(chunks[0].length === 2 && chunks[2].length === 1, "_.chunk sizes");
var grouped = _.groupBy([{ type: "a", v: 1 }, { type: "b", v: 2 }, { type: "a", v: 3 }], "type");
assert(grouped.a.length === 2 && grouped.b.length === 1, "_.groupBy");
assert(JSON.stringify(_.uniq([1, 2, 2, 3, 3, 3])) === "[1,2,3]", "_.uniq");
assert(JSON.stringify(_.flatten([[1, 2], [3, 4], 5])) === "[1,2,3,4,5]", "_.flatten");
assert(_.get({ a: { b: { c: 42 } } }, "a.b.c") === 42, "_.get deep");
assert(_.get({ a: 1 }, "x.y.z", "default") === "default", "_.get default");
var setObj = {};
_.set(setObj, "a.b.c", 42);
assert(setObj.a.b.c === 42, "_.set deep");
var clone = _.cloneDeep({ a: [1, { b: 2 }] });
assert(clone.a[1].b === 2, "_.cloneDeep");
assert(JSON.stringify(_.pick({ a: 1, b: 2, c: 3 }, ["a", "c"])) === '{"a":1,"c":3}', "_.pick");
assert(JSON.stringify(_.omit({ a: 1, b: 2, c: 3 }, ["b"])) === '{"a":1,"c":3}', "_.omit");
var keyed = _.keyBy([{ id: 1, name: "a" }, { id: 2, name: "b" }], "id");
assert(keyed[1].name === "a" && keyed[2].name === "b", "_.keyBy");

// debounce returns a function
var debounced = _.debounce(function() {}, 100);
assert(typeof debounced === "function", "_.debounce returns function");

// throttle returns a function
var throttled = _.throttle(function() { return 42; }, 100);
assert(typeof throttled === "function", "_.throttle returns function");

console.log("  lodash: " + passCount + " checks passed");

// ============================================================
// 2. EXPRESS SIMULATION
// ============================================================
section("express (web framework)");
var prevPass = passCount;

function Router() {
    this.routes = [];
    this.middlewares = [];
}
Router.prototype.use = function(fn) {
    this.middlewares.push(fn);
    return this;
};
Router.prototype.get = function(path, handler) {
    this.routes.push({ method: "GET", path: path, handler: handler });
    return this;
};
Router.prototype.post = function(path, handler) {
    this.routes.push({ method: "POST", path: path, handler: handler });
    return this;
};
Router.prototype.put = function(path, handler) {
    this.routes.push({ method: "PUT", path: path, handler: handler });
    return this;
};
Router.prototype.delete = function(path, handler) {
    this.routes.push({ method: "DELETE", path: path, handler: handler });
    return this;
};
Router.prototype.handle = function(method, path) {
    var req = { method: method, url: path, params: {}, query: {} };
    var res = { statusCode: 200, headers: {}, body: null };
    res.status = function(code) { res.statusCode = code; return res; };
    res.json = function(data) { res.body = JSON.stringify(data); res.headers["content-type"] = "application/json"; return res; };
    res.send = function(data) { res.body = data; return res; };

    // Run middlewares
    var idx = 0;
    var self = this;
    function next(err) {
        if (err) { res.statusCode = 500; res.body = err.message; return; }
        if (idx < self.middlewares.length) {
            var mw = self.middlewares[idx++];
            try { mw(req, res, next); } catch (e) { next(e); }
            return;
        }
        // Match route
        for (var i = 0; i < self.routes.length; i++) {
            var route = self.routes[i];
            if (route.method === method) {
                // Simple param matching (:param)
                var routeParts = route.path.split("/");
                var pathParts = path.split("/");
                if (routeParts.length === pathParts.length) {
                    var match = true;
                    var params = {};
                    for (var j = 0; j < routeParts.length; j++) {
                        if (routeParts[j].startsWith(":")) {
                            params[routeParts[j].slice(1)] = pathParts[j];
                        } else if (routeParts[j] !== pathParts[j]) {
                            match = false;
                            break;
                        }
                    }
                    if (match) {
                        req.params = params;
                        route.handler(req, res);
                        return res;
                    }
                }
            }
        }
        res.statusCode = 404;
        res.body = "Not Found";
    }
    next();
    return res;
};

var app = new Router();
app.use(function(req, res, next) {
    req.timestamp = Date.now();
    next();
});
app.use(function(req, res, next) {
    res.headers["x-powered-by"] = "TestExpress";
    next();
});
app.get("/api/users", function(req, res) {
    res.json({ users: [{ id: 1, name: "Alice" }] });
});
app.get("/api/users/:id", function(req, res) {
    res.json({ user: { id: req.params.id } });
});
app.post("/api/users", function(req, res) {
    res.status(201).json({ created: true });
});
app.put("/api/users/:id", function(req, res) {
    res.json({ updated: req.params.id });
});
app.delete("/api/users/:id", function(req, res) {
    res.status(204).send("");
});

var r1 = app.handle("GET", "/api/users");
assert(r1.statusCode === 200, "express GET /api/users => 200");
assert(r1.headers["content-type"] === "application/json", "express content-type header");
assert(r1.headers["x-powered-by"] === "TestExpress", "express middleware header");
assert(JSON.parse(r1.body).users.length === 1, "express response body");

var r2 = app.handle("GET", "/api/users/42");
assert(JSON.parse(r2.body).user.id === "42", "express param extraction");

var r3 = app.handle("POST", "/api/users");
assert(r3.statusCode === 201, "express POST => 201");

var r4 = app.handle("DELETE", "/api/users/99");
assert(r4.statusCode === 204, "express DELETE => 204");

var r5 = app.handle("GET", "/nonexistent");
assert(r5.statusCode === 404, "express 404 for unknown route");

console.log("  express: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 3. MOMENT/DAYJS SIMULATION
// ============================================================
section("moment/dayjs (date utilities)");
prevPass = passCount;

var moment = {
    _months: ["January", "February", "March", "April", "May", "June",
              "July", "August", "September", "October", "November", "December"],
    _monthsShort: ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
    _days: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],

    parse: function(str) {
        // ISO 8601 parsing
        var m = str.match(/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(?:Z|([+-]\d{2}):?(\d{2}))?)?$/);
        if (!m) return null;
        return new Date(Date.UTC(
            parseInt(m[1]), parseInt(m[2]) - 1, parseInt(m[3]),
            parseInt(m[4] || 0), parseInt(m[5] || 0), parseInt(m[6] || 0),
            parseInt((m[7] || "0").substring(0, 3))
        ));
    },

    format: function(date, fmt) {
        if (typeof date === "string") date = this.parse(date);
        if (!date) return "";
        var pad = function(n, w) { w = w || 2; var s = "" + n; while (s.length < w) s = "0" + s; return s; };
        return fmt
            .replace("YYYY", date.getUTCFullYear())
            .replace("YY", ("" + date.getUTCFullYear()).slice(2))
            .replace("MMMM", this._months[date.getUTCMonth()])
            .replace("MMM", this._monthsShort[date.getUTCMonth()])
            .replace("MM", pad(date.getUTCMonth() + 1))
            .replace("DD", pad(date.getUTCDate()))
            .replace("HH", pad(date.getUTCHours()))
            .replace("mm", pad(date.getUTCMinutes()))
            .replace("ss", pad(date.getUTCSeconds()))
            .replace("dddd", this._days[date.getUTCDay()])
            .replace("ddd", this._days[date.getUTCDay()].substring(0, 3));
    },

    diff: function(a, b, unit) {
        if (typeof a === "string") a = this.parse(a);
        if (typeof b === "string") b = this.parse(b);
        var ms = a.getTime() - b.getTime();
        switch (unit) {
            case "seconds": return Math.floor(ms / 1000);
            case "minutes": return Math.floor(ms / 60000);
            case "hours": return Math.floor(ms / 3600000);
            case "days": return Math.floor(ms / 86400000);
            default: return ms;
        }
    },

    isValid: function(str) {
        var d = this.parse(str);
        return d !== null && !isNaN(d.getTime());
    },

    startOf: function(date, unit) {
        if (typeof date === "string") date = this.parse(date);
        var d = new Date(date.getTime());
        switch (unit) {
            case "day": d.setUTCHours(0, 0, 0, 0); break;
            case "month": d.setUTCDate(1); d.setUTCHours(0, 0, 0, 0); break;
            case "year": d.setUTCMonth(0, 1); d.setUTCHours(0, 0, 0, 0); break;
        }
        return d;
    },

    add: function(date, amount, unit) {
        if (typeof date === "string") date = this.parse(date);
        var d = new Date(date.getTime());
        switch (unit) {
            case "days": d.setUTCDate(d.getUTCDate() + amount); break;
            case "months": d.setUTCMonth(d.getUTCMonth() + amount); break;
            case "years": d.setUTCFullYear(d.getUTCFullYear() + amount); break;
            case "hours": d.setUTCHours(d.getUTCHours() + amount); break;
        }
        return d;
    },

    fromNow: function(date) {
        if (typeof date === "string") date = this.parse(date);
        var diff = Date.now() - date.getTime();
        var absDiff = Math.abs(diff);
        var suffix = diff > 0 ? " ago" : " from now";
        if (absDiff < 60000) return "a few seconds" + suffix;
        if (absDiff < 3600000) return Math.floor(absDiff / 60000) + " minutes" + suffix;
        if (absDiff < 86400000) return Math.floor(absDiff / 3600000) + " hours" + suffix;
        return Math.floor(absDiff / 86400000) + " days" + suffix;
    }
};

assert(moment.format("2024-03-15T10:30:45Z", "YYYY-MM-DD") === "2024-03-15", "moment format YYYY-MM-DD");
assert(moment.format("2024-03-15T10:30:45Z", "HH:mm:ss") === "10:30:45", "moment format HH:mm:ss");
assert(moment.format("2024-12-25T00:00:00Z", "MMMM DD, YYYY") === "December 25, 2024", "moment format long");
assert(moment.format("2024-01-01T00:00:00Z", "MMM DD") === "Jan 01", "moment format short month");
assert(moment.diff("2024-03-15T00:00:00Z", "2024-03-10T00:00:00Z", "days") === 5, "moment diff days");
assert(moment.diff("2024-03-15T12:00:00Z", "2024-03-15T10:00:00Z", "hours") === 2, "moment diff hours");
assert(moment.isValid("2024-03-15T10:30:45Z") === true, "moment isValid true");
assert(moment.isValid("not-a-date") === false, "moment isValid false");

var start = moment.startOf("2024-03-15T10:30:45Z", "day");
assert(start.getUTCHours() === 0 && start.getUTCMinutes() === 0, "moment startOf day");

var added = moment.add("2024-03-15T00:00:00Z", 10, "days");
assert(added.getUTCDate() === 25, "moment add days");

var fromNow = moment.fromNow("2020-01-01T00:00:00Z");
assert(fromNow.indexOf("ago") !== -1, "moment fromNow past");

console.log("  moment/dayjs: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 4. UUID SIMULATION
// ============================================================
section("uuid (ID generation)");
prevPass = passCount;

var uuid = {
    v4: function() {
        // RFC 4122 v4 UUID using Math.random
        var hex = "0123456789abcdef";
        var result = "";
        for (var i = 0; i < 36; i++) {
            if (i === 8 || i === 13 || i === 18 || i === 23) {
                result += "-";
            } else if (i === 14) {
                result += "4"; // version 4
            } else if (i === 19) {
                result += hex[(Math.random() * 4 | 0) + 8]; // variant 10xx
            } else {
                result += hex[Math.random() * 16 | 0];
            }
        }
        return result;
    },
    validate: function(str) {
        return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(str);
    },
    parse: function(str) {
        var hex = str.replace(/-/g, "");
        var bytes = new Uint8Array(16);
        for (var i = 0; i < 16; i++) {
            bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
        }
        return bytes;
    }
};

var id1 = uuid.v4();
var id2 = uuid.v4();
assert(id1.length === 36, "uuid v4 length");
assert(id1 !== id2, "uuid v4 uniqueness");
assert(uuid.validate(id1), "uuid v4 format valid");
assert(id1[14] === "4", "uuid v4 version nibble");
assert("89ab".indexOf(id1[19]) !== -1, "uuid v4 variant nibble");
assert(!uuid.validate("not-a-uuid"), "uuid validate rejects invalid");
var parsed = uuid.parse(id1);
assert(parsed.length === 16, "uuid parse to bytes");

console.log("  uuid: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 5. CHALK SIMULATION (ANSI colors)
// ============================================================
section("chalk (terminal colors)");
prevPass = passCount;

var chalk = {
    _wrap: function(code, closeCode, str) {
        return "\x1b[" + code + "m" + str + "\x1b[" + closeCode + "m";
    },
    red: function(s) { return chalk._wrap(31, 39, s); },
    green: function(s) { return chalk._wrap(32, 39, s); },
    blue: function(s) { return chalk._wrap(34, 39, s); },
    yellow: function(s) { return chalk._wrap(33, 39, s); },
    cyan: function(s) { return chalk._wrap(36, 39, s); },
    magenta: function(s) { return chalk._wrap(35, 39, s); },
    white: function(s) { return chalk._wrap(37, 39, s); },
    bold: function(s) { return chalk._wrap(1, 22, s); },
    dim: function(s) { return chalk._wrap(2, 22, s); },
    underline: function(s) { return chalk._wrap(4, 24, s); },
    italic: function(s) { return chalk._wrap(3, 23, s); },
    strikethrough: function(s) { return chalk._wrap(9, 29, s); },
    bgRed: function(s) { return chalk._wrap(41, 49, s); },
    bgGreen: function(s) { return chalk._wrap(42, 49, s); },
    bgBlue: function(s) { return chalk._wrap(44, 49, s); },
    rgb: function(r, g, b) {
        return function(s) { return "\x1b[38;2;" + r + ";" + g + ";" + b + "m" + s + "\x1b[39m"; };
    },
    hex: function(hexStr) {
        var r = parseInt(hexStr.slice(1, 3), 16);
        var g = parseInt(hexStr.slice(3, 5), 16);
        var b = parseInt(hexStr.slice(5, 7), 16);
        return chalk.rgb(r, g, b);
    },
    strip: function(s) {
        return s.replace(/\x1b\[[0-9;]*m/g, "");
    }
};

assert(chalk.red("hello") === "\x1b[31mhello\x1b[39m", "chalk red");
assert(chalk.green("ok") === "\x1b[32mok\x1b[39m", "chalk green");
assert(chalk.bold("text") === "\x1b[1mtext\x1b[22m", "chalk bold");
assert(chalk.underline("text") === "\x1b[4mtext\x1b[24m", "chalk underline");
assert(chalk.bgRed("alert") === "\x1b[41malert\x1b[49m", "chalk bgRed");
var nested = chalk.bold(chalk.red("error"));
assert(nested.indexOf("\x1b[1m") !== -1 && nested.indexOf("\x1b[31m") !== -1, "chalk nested styles");
assert(chalk.strip(chalk.red("hello")) === "hello", "chalk strip ANSI");
var custom = chalk.rgb(255, 128, 0);
assert(custom("test").indexOf("38;2;255;128;0") !== -1, "chalk rgb");
var hexColor = chalk.hex("#ff8000");
assert(hexColor("test").indexOf("38;2;255;128;0") !== -1, "chalk hex");

console.log("  chalk: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 6. DOTENV SIMULATION
// ============================================================
section("dotenv (env parser)");
prevPass = passCount;

var dotenv = {
    parse: function(src) {
        var result = {};
        var lines = src.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            // Skip comments and empty lines
            if (line === "" || line[0] === "#") continue;
            var eqIdx = line.indexOf("=");
            if (eqIdx === -1) continue;
            var key = line.substring(0, eqIdx).trim();
            var val = line.substring(eqIdx + 1).trim();
            // Remove surrounding quotes
            if ((val[0] === '"' && val[val.length - 1] === '"') ||
                (val[0] === "'" && val[val.length - 1] === "'")) {
                val = val.slice(1, -1);
            }
            // Handle escape sequences in double-quoted strings
            if (line.substring(eqIdx + 1).trim()[0] === '"') {
                val = val.replace(/\\n/g, "\n").replace(/\\t/g, "\t").replace(/\\\\/g, "\\");
            }
            result[key] = val;
        }
        return result;
    },
    stringify: function(obj) {
        var lines = [];
        var keys = Object.keys(obj);
        for (var i = 0; i < keys.length; i++) {
            var val = obj[keys[i]];
            if (typeof val === "string" && (val.indexOf(" ") !== -1 || val.indexOf("\n") !== -1)) {
                val = '"' + val.replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/"/g, '\\"') + '"';
            }
            lines.push(keys[i] + "=" + val);
        }
        return lines.join("\n");
    }
};

var envStr = [
    "# Database config",
    "DB_HOST=localhost",
    "DB_PORT=5432",
    "DB_NAME=myapp",
    'DB_PASSWORD="super secret"',
    "API_KEY='abc-123-def'",
    "",
    "# App settings",
    "DEBUG=true",
    "NODE_ENV=production",
    'MULTILINE="line1\\nline2"'
].join("\n");

var env = dotenv.parse(envStr);
assert(env.DB_HOST === "localhost", "dotenv parse host");
assert(env.DB_PORT === "5432", "dotenv parse port");
assert(env.DB_PASSWORD === "super secret", "dotenv parse quoted value");
assert(env.API_KEY === "abc-123-def", "dotenv parse single-quoted");
assert(env.DEBUG === "true", "dotenv parse boolean-like");
assert(env.NODE_ENV === "production", "dotenv parse env");
assert(env.MULTILINE === "line1\nline2", "dotenv parse escape sequences");
assert(Object.keys(env).length === 8, "dotenv parse count (skip comments)");

var serialized = dotenv.stringify({ KEY: "value", SPACED: "has spaces" });
assert(serialized.indexOf("KEY=value") !== -1, "dotenv stringify simple");
assert(serialized.indexOf('SPACED="has spaces"') !== -1, "dotenv stringify quoted");

console.log("  dotenv: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 7. MINIMIST SIMULATION (argv parsing)
// ============================================================
section("minimist (argument parsing)");
prevPass = passCount;

var minimist = {
    parse: function(args, opts) {
        opts = opts || {};
        var result = { _: [] };
        var booleans = new Set(opts.boolean || []);
        var strings = new Set(opts.string || []);
        var alias = opts.alias || {};
        var defaults = opts.default || {};

        // Apply defaults
        var defaultKeys = Object.keys(defaults);
        for (var d = 0; d < defaultKeys.length; d++) {
            result[defaultKeys[d]] = defaults[defaultKeys[d]];
        }

        for (var i = 0; i < args.length; i++) {
            var arg = args[i];
            if (arg === "--") {
                // Everything after -- goes to _
                for (var j = i + 1; j < args.length; j++) result._.push(args[j]);
                break;
            } else if (arg.startsWith("--no-")) {
                var noKey = arg.slice(5);
                result[noKey] = false;
            } else if (arg.startsWith("--")) {
                var eqPos = arg.indexOf("=");
                if (eqPos !== -1) {
                    var key = arg.slice(2, eqPos);
                    var val = arg.slice(eqPos + 1);
                    result[key] = booleans.has(key) ? val !== "false" : val;
                } else {
                    var key2 = arg.slice(2);
                    if (booleans.has(key2)) {
                        result[key2] = true;
                    } else if (i + 1 < args.length && !args[i + 1].startsWith("-")) {
                        result[key2] = args[++i];
                    } else {
                        result[key2] = true;
                    }
                }
            } else if (arg.startsWith("-") && arg.length > 1) {
                // Short flags: -abc means -a -b -c, -k value
                var chars = arg.slice(1);
                for (var c = 0; c < chars.length; c++) {
                    var ch = chars[c];
                    if (c === chars.length - 1 && i + 1 < args.length && !args[i + 1].startsWith("-") && !booleans.has(ch)) {
                        result[ch] = args[++i];
                    } else {
                        result[ch] = true;
                    }
                }
            } else {
                result._.push(arg);
            }
        }

        // Apply aliases
        var aliasKeys = Object.keys(alias);
        for (var a = 0; a < aliasKeys.length; a++) {
            var src = aliasKeys[a];
            var targets = Array.isArray(alias[src]) ? alias[src] : [alias[src]];
            if (result[src] !== undefined) {
                for (var t = 0; t < targets.length; t++) {
                    result[targets[t]] = result[src];
                }
            }
        }
        return result;
    }
};

var parsed = minimist.parse(["--name", "alice", "--verbose", "-p", "8080", "file.js"]);
assert(parsed.name === "alice", "minimist --name value");
assert(parsed.verbose === true, "minimist --verbose flag");
assert(parsed.p === "8080", "minimist -p value");
assert(parsed._[0] === "file.js", "minimist positional arg");

var parsed2 = minimist.parse(["--port=3000", "--no-color", "-abc"]);
assert(parsed2.port === "3000", "minimist --key=value");
assert(parsed2.color === false, "minimist --no-flag");
assert(parsed2.a === true && parsed2.b === true && parsed2.c === true, "minimist combined short flags");

var parsed3 = minimist.parse(["cmd", "--", "--not-a-flag", "extra"]);
assert(parsed3._[0] === "cmd", "minimist positional before --");
assert(parsed3._[1] === "--not-a-flag", "minimist -- stops parsing");
assert(parsed3._.length === 3, "minimist -- preserves rest");

var parsed4 = minimist.parse(["--debug"], { boolean: ["debug"], default: { port: 3000 } });
assert(parsed4.debug === true, "minimist boolean option");
assert(parsed4.port === 3000, "minimist default value");

console.log("  minimist: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 8. SEMVER SIMULATION
// ============================================================
section("semver (version parsing)");
prevPass = passCount;

var semver = {
    parse: function(str) {
        var m = str.match(/^v?(\d+)\.(\d+)\.(\d+)(?:-([a-zA-Z0-9.]+))?(?:\+([a-zA-Z0-9.]+))?$/);
        if (!m) return null;
        return { major: parseInt(m[1]), minor: parseInt(m[2]), patch: parseInt(m[3]),
                 prerelease: m[4] || "", build: m[5] || "" };
    },
    compare: function(a, b) {
        var va = typeof a === "string" ? this.parse(a) : a;
        var vb = typeof b === "string" ? this.parse(b) : b;
        if (va.major !== vb.major) return va.major - vb.major;
        if (va.minor !== vb.minor) return va.minor - vb.minor;
        if (va.patch !== vb.patch) return va.patch - vb.patch;
        if (va.prerelease && !vb.prerelease) return -1;
        if (!va.prerelease && vb.prerelease) return 1;
        if (va.prerelease < vb.prerelease) return -1;
        if (va.prerelease > vb.prerelease) return 1;
        return 0;
    },
    satisfies: function(version, range) {
        var v = typeof version === "string" ? this.parse(version) : version;
        // Handle ^major.minor.patch
        if (range[0] === "^") {
            var r = this.parse(range.slice(1));
            if (v.major !== r.major) return false;
            return this.compare(v, r) >= 0;
        }
        // Handle ~major.minor.patch
        if (range[0] === "~") {
            var r2 = this.parse(range.slice(1));
            if (v.major !== r2.major || v.minor !== r2.minor) return false;
            return v.patch >= r2.patch;
        }
        // Handle >=major.minor.patch
        if (range.startsWith(">=")) {
            return this.compare(v, range.slice(2)) >= 0;
        }
        // Exact match
        return this.compare(v, range) === 0;
    },
    valid: function(str) {
        return this.parse(str) !== null;
    },
    inc: function(version, type) {
        var v = typeof version === "string" ? this.parse(version) : { major: version.major, minor: version.minor, patch: version.patch, prerelease: "", build: "" };
        v = { major: v.major, minor: v.minor, patch: v.patch, prerelease: "", build: "" };
        switch (type) {
            case "major": v.major++; v.minor = 0; v.patch = 0; break;
            case "minor": v.minor++; v.patch = 0; break;
            case "patch": v.patch++; break;
        }
        return v.major + "." + v.minor + "." + v.patch;
    }
};

assert(semver.valid("1.2.3"), "semver valid basic");
assert(semver.valid("v1.0.0"), "semver valid with v prefix");
assert(semver.valid("1.0.0-beta.1"), "semver valid prerelease");
assert(!semver.valid("not-semver"), "semver invalid string");
assert(semver.compare("1.2.3", "1.2.2") > 0, "semver compare gt");
assert(semver.compare("1.2.3", "1.2.3") === 0, "semver compare eq");
assert(semver.compare("1.2.3", "2.0.0") < 0, "semver compare lt");
assert(semver.compare("1.0.0-alpha", "1.0.0") < 0, "semver prerelease < release");
assert(semver.satisfies("1.5.0", "^1.0.0"), "semver satisfies caret");
assert(!semver.satisfies("2.0.0", "^1.0.0"), "semver caret rejects major bump");
assert(semver.satisfies("1.2.5", "~1.2.0"), "semver satisfies tilde");
assert(!semver.satisfies("1.3.0", "~1.2.0"), "semver tilde rejects minor bump");
assert(semver.inc("1.2.3", "patch") === "1.2.4", "semver inc patch");
assert(semver.inc("1.2.3", "minor") === "1.3.0", "semver inc minor");
assert(semver.inc("1.2.3", "major") === "2.0.0", "semver inc major");

console.log("  semver: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 9. EVENTEMITTER SIMULATION
// ============================================================
section("eventemitter3 (event system)");
prevPass = passCount;

function EventEmitter() {
    this._events = {};
}
EventEmitter.prototype.on = function(event, fn) {
    if (!this._events[event]) this._events[event] = [];
    this._events[event].push({ fn: fn, once: false });
    return this;
};
EventEmitter.prototype.once = function(event, fn) {
    if (!this._events[event]) this._events[event] = [];
    this._events[event].push({ fn: fn, once: true });
    return this;
};
EventEmitter.prototype.emit = function(event) {
    var listeners = this._events[event];
    if (!listeners) return false;
    var args = [];
    for (var i = 1; i < arguments.length; i++) args.push(arguments[i]);
    var remaining = [];
    for (var i = 0; i < listeners.length; i++) {
        listeners[i].fn.apply(null, args);
        if (!listeners[i].once) remaining.push(listeners[i]);
    }
    this._events[event] = remaining;
    return true;
};
EventEmitter.prototype.off = function(event, fn) {
    var listeners = this._events[event];
    if (!listeners) return this;
    this._events[event] = listeners.filter(function(l) { return l.fn !== fn; });
    return this;
};
EventEmitter.prototype.listenerCount = function(event) {
    return this._events[event] ? this._events[event].length : 0;
};
EventEmitter.prototype.removeAllListeners = function(event) {
    if (event) delete this._events[event];
    else this._events = {};
    return this;
};

var ee = new EventEmitter();
var received = [];
ee.on("data", function(val) { received.push(val); });
ee.emit("data", 1);
ee.emit("data", 2);
assert(received.length === 2, "EventEmitter on receives events");
assert(received[0] === 1 && received[1] === 2, "EventEmitter on correct values");

var onceVal = 0;
ee.once("single", function(v) { onceVal = v; });
ee.emit("single", 42);
ee.emit("single", 99);
assert(onceVal === 42, "EventEmitter once fires once");
assert(ee.listenerCount("single") === 0, "EventEmitter once removes listener");

var handler = function() {};
ee.on("test", handler);
assert(ee.listenerCount("test") === 1, "EventEmitter listenerCount");
ee.off("test", handler);
assert(ee.listenerCount("test") === 0, "EventEmitter off removes");

ee.on("a", function() {});
ee.on("b", function() {});
ee.removeAllListeners();
assert(ee.listenerCount("a") === 0 && ee.listenerCount("b") === 0, "EventEmitter removeAllListeners");

console.log("  eventemitter3: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 10. DEEP-EQUAL / CLONE SIMULATION
// ============================================================
section("fast-deep-equal / rfdc (deep operations)");
prevPass = passCount;

function deepEqual(a, b) {
    if (a === b) return true;
    if (a === null || b === null || typeof a !== typeof b) return false;
    if (typeof a !== "object") return false;
    if (Array.isArray(a)) {
        if (!Array.isArray(b) || a.length !== b.length) return false;
        for (var i = 0; i < a.length; i++) {
            if (!deepEqual(a[i], b[i])) return false;
        }
        return true;
    }
    var keysA = Object.keys(a);
    var keysB = Object.keys(b);
    if (keysA.length !== keysB.length) return false;
    for (var i = 0; i < keysA.length; i++) {
        if (!deepEqual(a[keysA[i]], b[keysA[i]])) return false;
    }
    return true;
}

function deepClone(obj) {
    if (obj === null || typeof obj !== "object") return obj;
    if (Array.isArray(obj)) {
        var arr = [];
        for (var i = 0; i < obj.length; i++) arr.push(deepClone(obj[i]));
        return arr;
    }
    if (obj instanceof Date) return new Date(obj.getTime());
    if (obj instanceof RegExp) return new RegExp(obj.source, obj.flags);
    var clone = {};
    var keys = Object.keys(obj);
    for (var i = 0; i < keys.length; i++) {
        clone[keys[i]] = deepClone(obj[keys[i]]);
    }
    return clone;
}

assert(deepEqual({ a: 1, b: [2, 3] }, { a: 1, b: [2, 3] }), "deepEqual same");
assert(!deepEqual({ a: 1 }, { a: 2 }), "deepEqual different value");
assert(!deepEqual({ a: 1 }, { b: 1 }), "deepEqual different key");
assert(deepEqual([1, [2, [3]]], [1, [2, [3]]]), "deepEqual nested arrays");
assert(!deepEqual([1, 2], [1, 2, 3]), "deepEqual different length");

var original = { a: 1, b: { c: [1, 2, { d: 3 }] }, e: "hello" };
var cloned = deepClone(original);
assert(deepEqual(original, cloned), "deepClone produces equal object");
cloned.b.c[2].d = 99;
assert(original.b.c[2].d === 3, "deepClone is independent");

console.log("  fast-deep-equal/rfdc: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 11. LRU-CACHE SIMULATION
// ============================================================
section("lru-cache (caching)");
prevPass = passCount;

function LRUCache(capacity) {
    this.capacity = capacity;
    this.map = new Map();
}
LRUCache.prototype.get = function(key) {
    if (!this.map.has(key)) return undefined;
    var val = this.map.get(key);
    // Move to end (most recent)
    this.map.delete(key);
    this.map.set(key, val);
    return val;
};
LRUCache.prototype.set = function(key, val) {
    if (this.map.has(key)) this.map.delete(key);
    this.map.set(key, val);
    if (this.map.size > this.capacity) {
        // Delete oldest (first entry)
        var oldest = this.map.keys().next().value;
        this.map.delete(oldest);
    }
    return this;
};
LRUCache.prototype.has = function(key) { return this.map.has(key); };
LRUCache.prototype.delete = function(key) { return this.map.delete(key); };
LRUCache.prototype.clear = function() { this.map.clear(); };
LRUCache.prototype.size = function() { return this.map.size; };

var cache = new LRUCache(3);
cache.set("a", 1);
cache.set("b", 2);
cache.set("c", 3);
assert(cache.get("a") === 1, "LRU get existing");
cache.set("d", 4); // evicts "b" (least recently used, since "a" was accessed)
assert(!cache.has("b"), "LRU evicts LRU entry");
assert(cache.has("a"), "LRU keeps recently accessed");
assert(cache.has("c"), "LRU keeps recent");
assert(cache.has("d"), "LRU keeps newest");
assert(cache.size() === 3, "LRU respects capacity");
cache.delete("d");
assert(cache.size() === 2, "LRU delete works");
cache.clear();
assert(cache.size() === 0, "LRU clear works");

console.log("  lru-cache: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 12. PATH UTILITIES SIMULATION
// ============================================================
section("path (path utilities)");
prevPass = passCount;

var path = {
    join: function() {
        var parts = [];
        for (var i = 0; i < arguments.length; i++) {
            if (arguments[i]) parts.push(arguments[i]);
        }
        return this.normalize(parts.join("/"));
    },
    normalize: function(p) {
        var isAbsolute = p[0] === "/";
        var parts = p.split(/[/]+/).filter(function(s) { return s.length > 0; });
        var result = [];
        for (var i = 0; i < parts.length; i++) {
            if (parts[i] === ".") continue;
            if (parts[i] === "..") { if (result.length > 0 && result[result.length - 1] !== "..") result.pop(); }
            else result.push(parts[i]);
        }
        return (isAbsolute ? "/" : "") + result.join("/");
    },
    basename: function(p, ext) {
        var base = p.split("/").pop() || "";
        if (ext && base.endsWith(ext)) base = base.slice(0, -ext.length);
        return base;
    },
    dirname: function(p) {
        var parts = p.split("/");
        parts.pop();
        return parts.join("/") || (p[0] === "/" ? "/" : ".");
    },
    extname: function(p) {
        var base = p.split("/").pop() || "";
        var dotIdx = base.lastIndexOf(".");
        if (dotIdx <= 0) return "";
        return base.slice(dotIdx);
    },
    isAbsolute: function(p) {
        return p[0] === "/";
    }
};

assert(path.join("/usr", "local", "bin") === "/usr/local/bin", "path join absolute");
assert(path.join("a", "b", "c") === "a/b/c", "path join relative");
assert(path.join("a", "..", "b") === "b", "path join with ..");
assert(path.normalize("/usr//local/./bin/../lib") === "/usr/local/lib", "path normalize");
assert(path.basename("/home/user/file.js") === "file.js", "path basename");
assert(path.basename("/home/user/file.js", ".js") === "file", "path basename strip ext");
assert(path.dirname("/home/user/file.js") === "/home/user", "path dirname");
assert(path.extname("file.test.js") === ".js", "path extname");
assert(path.extname("noext") === "", "path extname none");
assert(path.isAbsolute("/usr/bin"), "path isAbsolute true");
assert(!path.isAbsolute("relative/path"), "path isAbsolute false");

console.log("  path: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 13. MIME-TYPES SIMULATION
// ============================================================
section("mime-types (content types)");
prevPass = passCount;

var mimeTypes = {
    _db: {
        ".html": "text/html", ".htm": "text/html", ".css": "text/css",
        ".js": "application/javascript", ".mjs": "application/javascript",
        ".json": "application/json", ".xml": "application/xml",
        ".txt": "text/plain", ".csv": "text/csv", ".md": "text/markdown",
        ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
        ".gif": "image/gif", ".svg": "image/svg+xml", ".webp": "image/webp",
        ".ico": "image/x-icon", ".pdf": "application/pdf",
        ".zip": "application/zip", ".gz": "application/gzip",
        ".tar": "application/x-tar", ".wasm": "application/wasm",
        ".mp3": "audio/mpeg", ".mp4": "video/mp4", ".webm": "video/webm",
        ".woff": "font/woff", ".woff2": "font/woff2", ".ttf": "font/ttf",
        ".ts": "application/typescript", ".tsx": "application/typescript",
        ".yaml": "text/yaml", ".yml": "text/yaml"
    },
    lookup: function(path) {
        var ext = path.lastIndexOf(".") !== -1 ? path.slice(path.lastIndexOf(".")).toLowerCase() : "";
        return this._db[ext] || false;
    },
    contentType: function(ext) {
        if (ext[0] !== ".") ext = "." + ext;
        var type = this._db[ext];
        if (!type) return false;
        if (type.startsWith("text/") || type === "application/json" || type === "application/javascript") {
            return type + "; charset=utf-8";
        }
        return type;
    }
};

assert(mimeTypes.lookup("file.html") === "text/html", "mime lookup .html");
assert(mimeTypes.lookup("app.js") === "application/javascript", "mime lookup .js");
assert(mimeTypes.lookup("data.json") === "application/json", "mime lookup .json");
assert(mimeTypes.lookup("photo.png") === "image/png", "mime lookup .png");
assert(mimeTypes.lookup("noext") === false, "mime lookup no extension");
assert(mimeTypes.contentType("json") === "application/json; charset=utf-8", "mime contentType with charset");
assert(mimeTypes.contentType(".png") === "image/png", "mime contentType binary no charset");

console.log("  mime-types: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 14. MS (MILLISECOND CONVERTER) SIMULATION
// ============================================================
section("ms (time conversion)");
prevPass = passCount;

var ms = {
    _units: { s: 1000, m: 60000, h: 3600000, d: 86400000, w: 604800000, y: 31536000000 },
    parse: function(str) {
        var m = str.match(/^(-?\d+(?:\.\d+)?)\s*(ms|s|m|h|d|w|y)?$/);
        if (!m) return null;
        var val = parseFloat(m[1]);
        var unit = m[2] || "ms";
        if (unit === "ms") return val;
        return val * (this._units[unit[0]] || 1);
    },
    format: function(val) {
        var abs = Math.abs(val);
        if (abs >= 86400000) return Math.round(val / 86400000) + "d";
        if (abs >= 3600000) return Math.round(val / 3600000) + "h";
        if (abs >= 60000) return Math.round(val / 60000) + "m";
        if (abs >= 1000) return Math.round(val / 1000) + "s";
        return val + "ms";
    }
};

assert(ms.parse("100ms") === 100, "ms parse 100ms");
assert(ms.parse("2s") === 2000, "ms parse 2s");
assert(ms.parse("5m") === 300000, "ms parse 5m");
assert(ms.parse("1h") === 3600000, "ms parse 1h");
assert(ms.parse("2d") === 172800000, "ms parse 2d");
assert(ms.format(500) === "500ms", "ms format ms");
assert(ms.format(5000) === "5s", "ms format s");
assert(ms.format(120000) === "2m", "ms format m");
assert(ms.format(7200000) === "2h", "ms format h");

console.log("  ms: " + (passCount - prevPass) + " checks passed");

// ============================================================
// 15. COOKIE PARSER SIMULATION
// ============================================================
section("cookie (HTTP cookies)");
prevPass = passCount;

var cookie = {
    parse: function(str) {
        var result = {};
        var pairs = str.split(";");
        for (var i = 0; i < pairs.length; i++) {
            var pair = pairs[i].trim();
            var eq = pair.indexOf("=");
            if (eq === -1) continue;
            var key = decodeURIComponent(pair.substring(0, eq).trim());
            var val = decodeURIComponent(pair.substring(eq + 1).trim());
            if (result[key] === undefined) result[key] = val;
        }
        return result;
    },
    serialize: function(name, val, opts) {
        opts = opts || {};
        var str = encodeURIComponent(name) + "=" + encodeURIComponent(val);
        if (opts.maxAge !== undefined) str += "; Max-Age=" + opts.maxAge;
        if (opts.domain) str += "; Domain=" + opts.domain;
        if (opts.path) str += "; Path=" + opts.path;
        if (opts.httpOnly) str += "; HttpOnly";
        if (opts.secure) str += "; Secure";
        if (opts.sameSite) str += "; SameSite=" + opts.sameSite;
        return str;
    }
};

var cookies = cookie.parse("session=abc123; theme=dark; lang=en-US");
assert(cookies.session === "abc123", "cookie parse session");
assert(cookies.theme === "dark", "cookie parse theme");
assert(cookies.lang === "en-US", "cookie parse lang");

var serialized = cookie.serialize("token", "xyz", { httpOnly: true, secure: true, path: "/", sameSite: "Strict" });
assert(serialized.indexOf("token=xyz") !== -1, "cookie serialize name=value");
assert(serialized.indexOf("HttpOnly") !== -1, "cookie serialize httpOnly");
assert(serialized.indexOf("Secure") !== -1, "cookie serialize secure");
assert(serialized.indexOf("SameSite=Strict") !== -1, "cookie serialize sameSite");

console.log("  cookie: " + (passCount - prevPass) + " checks passed");

// ============================================================
// SUMMARY
// ============================================================
console.log("\n=== Summary ===");
console.log(totalChecks + " checks completed");
console.log(passCount + " passed, " + failCount + " failed");

if (failCount > 0) {
    console.log("RESULT: PARTIAL (" + failCount + " failures)");
} else {
    console.log("RESULT: ALL PASSED");
}
