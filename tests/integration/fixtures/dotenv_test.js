// .env auto-loading integration test
// This fixture is tested by the dotenv_loading block in run.sh,
// which sets up a temp directory with a .env file and runs dun from there.
// Requires: --allow-env flag

// Verify .env variables were loaded into process.env
console.log("FOO:" + process.env.DUN_TEST_FOO);
console.log("BAR:" + process.env.DUN_TEST_BAR);
console.log("BAZ:" + process.env.DUN_TEST_BAZ);
console.log("EMPTY:" + (process.env.DUN_TEST_EMPTY === "" ? "empty" : "missing"));
console.log("SPACES:" + process.env.DUN_TEST_SPACES);
console.log("PADDED:" + process.env.DUN_TEST_PADDED);
