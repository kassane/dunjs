// fd-based fs ops: ftruncateSync + futimesSync round-trip.
// Previously these were stubs that threw "not yet implemented".
const fs = require("fs");

let pass = 0, fail = 0;
function ok(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }

const tmp = `/tmp/dun_fd_test_${process.pid}.bin`;
fs.writeFileSync(tmp, "hello world, this is some content");
ok("setup", fs.statSync(tmp).size === 33);

// ftruncateSync — shrink by fd
const fd1 = fs.openSync(tmp, "r+");
fs.ftruncateSync(fd1, 5);
fs.closeSync(fd1);
ok("ftruncateSync shrink length", fs.statSync(tmp).size === 5);
ok("ftruncateSync shrink content", fs.readFileSync(tmp, "utf8") === "hello");

// ftruncateSync — grow by fd (POSIX zero-fills)
const fd2 = fs.openSync(tmp, "r+");
fs.ftruncateSync(fd2, 10);
fs.closeSync(fd2);
ok("ftruncateSync grow", fs.statSync(tmp).size === 10);

// futimesSync — set atime/mtime by fd
const fd3 = fs.openSync(tmp, "r+");
const atime = 1700000000;
const mtime = 1600000000;
fs.futimesSync(fd3, atime, mtime);
fs.closeSync(fd3);
const st = fs.statSync(tmp);
ok("futimesSync atime", Math.floor(st.atimeMs / 1000) === atime);
ok("futimesSync mtime", Math.floor(st.mtimeMs / 1000) === mtime);

fs.unlinkSync(tmp);
console.log(`Score: ${pass}/${pass + fail}`);
process.exit(fail > 0 ? 1 : 0);
