// SQLite benchmark — compare with Bun's bun:sqlite and Deno's deno-sqlite
const sqlite = require("sqlite");

const db = sqlite.open(":memory:");

// Setup
db.exec("CREATE TABLE bench (id INTEGER PRIMARY KEY, name TEXT, value REAL)");

// Benchmark: bulk inserts
const INSERT_COUNT = 10000;
let start = Date.now();
db.exec("BEGIN");
for (let i = 0; i < INSERT_COUNT; i++) {
    db.run("INSERT INTO bench (name, value) VALUES (?, ?)", "item" + i, Math.random() * 1000);
}
db.exec("COMMIT");
let elapsed = Date.now() - start;
console.log("INSERT " + INSERT_COUNT + " rows: " + elapsed + "ms (" + Math.round(INSERT_COUNT / (elapsed / 1000)) + " ops/sec)");

// Benchmark: single-row reads
const READ_COUNT = 10000;
start = Date.now();
for (let i = 0; i < READ_COUNT; i++) {
    db.get("SELECT * FROM bench WHERE id = ?", (i % INSERT_COUNT) + 1);
}
elapsed = Date.now() - start;
console.log("GET " + READ_COUNT + " rows: " + elapsed + "ms (" + Math.round(READ_COUNT / (elapsed / 1000)) + " ops/sec)");

// Benchmark: bulk reads
start = Date.now();
const all = db.all("SELECT * FROM bench ORDER BY id");
elapsed = Date.now() - start;
console.log("ALL " + all.length + " rows: " + elapsed + "ms");

// Benchmark: count aggregation
start = Date.now();
for (let i = 0; i < 1000; i++) {
    db.get("SELECT COUNT(*) as cnt FROM bench WHERE value > ?", Math.random() * 500);
}
elapsed = Date.now() - start;
console.log("COUNT 1000 queries: " + elapsed + "ms (" + Math.round(1000 / (elapsed / 1000)) + " ops/sec)");

// Benchmark: update
start = Date.now();
db.exec("BEGIN");
for (let i = 1; i <= 1000; i++) {
    db.run("UPDATE bench SET value = ? WHERE id = ?", Math.random() * 1000, i);
}
db.exec("COMMIT");
elapsed = Date.now() - start;
console.log("UPDATE 1000 rows: " + elapsed + "ms");

db.close();
console.log("\nSQLite benchmark complete");
