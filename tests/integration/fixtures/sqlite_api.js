const sqlite = require("sqlite");

// Version check
const ver = sqlite.version_();
console.log("SQLite version:", typeof ver === "string" && ver.length > 0 ? "ok" : "FAIL");

// Open in-memory database
const db = sqlite.open(":memory:");
console.log("Database opened:", db.filename === ":memory:" ? "ok" : "FAIL");

// Create table
db.exec("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INTEGER)");
console.log("Table created");

// Insert rows
const r1 = db.run("INSERT INTO users (name, age) VALUES (?, ?)", "Alice", 30);
console.log("Insert 1: changes=" + r1.changes);

const r2 = db.run("INSERT INTO users (name, age) VALUES (?, ?)", "Bob", 25);
console.log("Insert 2: changes=" + r2.changes);

const r3 = db.run("INSERT INTO users (name, age) VALUES (?, ?)", "Charlie", 35);
console.log("Insert 3: changes=" + r3.changes);

// Get single row
const row = db.get("SELECT * FROM users WHERE id = ?", 1);
console.log("Get:", row.name, row.age);

// Get with no match returns null
const noRow = db.get("SELECT * FROM users WHERE id = ?", 999);
console.log("Get missing:", noRow);

// All rows
const all = db.all("SELECT * FROM users ORDER BY id");
console.log("All rows:", all.length);
for (const r of all) {
    console.log(" -", r.name, r.age);
}

// Update
const upd = db.run("UPDATE users SET age = ? WHERE name = ?", 31, "Alice");
console.log("Update changes:", upd.changes);

// Verify update
const updated = db.get("SELECT age FROM users WHERE name = ?", "Alice");
console.log("Updated age:", updated.age);

// Delete
const del = db.run("DELETE FROM users WHERE name = ?", "Charlie");
console.log("Delete changes:", del.changes);

// Count remaining
const remaining = db.all("SELECT * FROM users ORDER BY id");
console.log("Remaining:", remaining.length);

// NULL handling
db.exec("CREATE TABLE nullable (id INTEGER PRIMARY KEY, val TEXT)");
db.run("INSERT INTO nullable (val) VALUES (?)", null);
const nullRow = db.get("SELECT * FROM nullable WHERE id = 1");
console.log("Null value:", nullRow.val);

// Multiple columns and types
db.exec("CREATE TABLE types (i INTEGER, f REAL, t TEXT)");
db.run("INSERT INTO types VALUES (?, ?, ?)", 42, 3.14, "hello");
const typeRow = db.get("SELECT * FROM types");
console.log("Types:", typeof typeRow.i, typeof typeRow.f, typeof typeRow.t);
console.log("Values:", typeRow.i, typeRow.f, typeRow.t);

// Close
db.close();
console.log("Database closed");
console.log("PASS: 20 sqlite checks");
