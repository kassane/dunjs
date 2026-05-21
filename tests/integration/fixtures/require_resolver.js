// Permanent regression for the CJS resolver bug surfaced by `hono`
// (and any module that ships both `foo.js` + `foo/` in the same dir):
// Node's LOAD_AS_FILE step must run BEFORE LOAD_AS_DIRECTORY. DunJS
// used to pick the directory first, fail to find `foo/index.js`, and
// give up — even though `foo.js` (the sibling file) was the correct
// answer.
//
// Also exercises `buffer.constants` (added at the same time, required
// by `thread-stream` → `pino`).

const fs = require("fs");
const path = require("path");
const os = require("os");

// Build a fixture tree:
//   <tmpdir>/foo.js               ← the file we want
//   <tmpdir>/foo/                 ← directory that LACKS index.js
//   <tmpdir>/foo/constants.js     ← just so the directory isn't empty
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "dun-resolver-"));
fs.writeFileSync(path.join(tmp, "foo.js"), `module.exports = "FILE_WINS";`);
fs.mkdirSync(path.join(tmp, "foo"));
fs.writeFileSync(path.join(tmp, "foo", "constants.js"), `module.exports = "DIR_CHILD";`);

// Pass absolute paths so `require()` doesn't try to resolve relative
// to this fixture's own directory.
const got = require(path.join(tmp, "foo"));
console.log(got === "FILE_WINS"
  ? "OK file-beats-dir resolution"
  : "FAIL file-beats-dir: got '" + got + "'");

const dirChild = require(path.join(tmp, "foo", "constants"));
console.log(dirChild === "DIR_CHILD"
  ? "OK explicit directory child resolution"
  : "FAIL explicit child: got '" + dirChild + "'");

// buffer.constants surface (Node parity)
const buf = require("buffer");
console.log(typeof buf.constants === "object" && buf.constants !== null
  ? "OK buffer.constants is an object"
  : "FAIL buffer.constants missing");
console.log(buf.constants.MAX_LENGTH > 1e9
  ? "OK buffer.constants.MAX_LENGTH > 1 GiB"
  : "FAIL MAX_LENGTH: " + buf.constants.MAX_LENGTH);
console.log(buf.constants.MAX_STRING_LENGTH > 1e6
  ? "OK buffer.constants.MAX_STRING_LENGTH > 1 MiB"
  : "FAIL MAX_STRING_LENGTH: " + buf.constants.MAX_STRING_LENGTH);

// Cleanup — leak prevention per the v1.1.19 tmpdir-cleanup pattern
try { fs.rmSync(tmp, { recursive: true, force: true }); } catch {}
