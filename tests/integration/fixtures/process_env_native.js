// Test that process.env set/delete propagates to native environment
let pass = 0;
let total = 0;

function check(label, cond) {
    total++;
    if (cond) { pass++; console.log("PASS: " + label); }
    else { console.log("FAIL: " + label); }
}

// Test 1: Set env var
process.env.DUN_TEST_VAR = "hello123";
check("set env var", process.env.DUN_TEST_VAR === "hello123");

// Test 2: Overwrite env var
process.env.DUN_TEST_VAR = "updated";
check("overwrite env var", process.env.DUN_TEST_VAR === "updated");

// Test 3: Delete env var
delete process.env.DUN_TEST_VAR;
check("delete env var", process.env.DUN_TEST_VAR === undefined);

// Test 4: Set and read back multiple vars
process.env.DUN_A = "aaa";
process.env.DUN_B = "bbb";
check("multiple vars A", process.env.DUN_A === "aaa");
check("multiple vars B", process.env.DUN_B === "bbb");

// Test 5: Numeric value coercion
process.env.DUN_NUM = 42;
check("numeric coercion", process.env.DUN_NUM === "42");

// Test 6: 'in' operator
process.env.DUN_EXISTS = "yes";
check("in operator true", "DUN_EXISTS" in process.env);
delete process.env.DUN_EXISTS;
check("in operator false after delete", !("DUN_EXISTS" in process.env));

// Test 7: Object.keys includes set vars
process.env.DUN_KEY_TEST = "val";
const keys = Object.keys(process.env);
check("Object.keys includes var", keys.indexOf("DUN_KEY_TEST") !== -1);
delete process.env.DUN_KEY_TEST;

// Test 8: Verify child process inherits env (via execSync)
process.env.DUN_CHILD_TEST = "from_parent";
try {
    const { execSync } = require("child_process");
    const output = execSync("echo $DUN_CHILD_TEST").toString().trim();
    check("child process inherits env", output === "from_parent");
} catch(e) {
    check("child process inherits env", false);
}

// Test 9: Delete propagates to child
delete process.env.DUN_CHILD_TEST;
try {
    const { execSync } = require("child_process");
    const output = execSync("echo ${DUN_CHILD_TEST:-EMPTY}").toString().trim();
    check("child process sees deleted env", output === "EMPTY");
} catch(e) {
    check("child process sees deleted env", false);
}

console.log("---");
console.log("Total: " + pass + "/" + total + " passed");
if (pass === total) console.log("ALL CHECKS PASSED");
else console.log("SOME CHECKS FAILED");
