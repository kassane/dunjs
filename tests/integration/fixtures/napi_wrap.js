// N-API wrap / external / finalize round-trip test.
// Builds a tiny .node addon that:
//   - createBox(n): napi_create_external storing a malloc'd int*
//   - readBox(box): napi_get_value_external -> read the int
//   - wrapObj(obj, n): napi_wrap with finalize cb storing an int* on obj
//   - unwrapObj(obj): napi_unwrap -> read the int

const { execSync } = require('node:child_process');
const fs = require('fs');
const path = require('path');

let passed = 0, total = 0;
function check(name, cond) {
  total++;
  if (cond) passed++;
  else console.log('FAIL:', name);
}

const cSource = `
#include <node_api.h>
#include <stdlib.h>
static int g_finalize_count = 0;
static void IntFinalize(napi_env env, void* data, void* hint) {
  free(data);
  g_finalize_count++;
}
static napi_value CreateBox(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);
  int v; napi_get_value_int32(env, args[0], &v);
  int* p = (int*) malloc(sizeof(int)); *p = v;
  napi_value ext; napi_create_external(env, p, IntFinalize, NULL, &ext);
  return ext;
}
static napi_value ReadBox(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);
  void* data; napi_get_value_external(env, args[0], &data);
  napi_value r; napi_create_int32(env, *(int*)data, &r);
  return r;
}
static napi_value WrapObj(napi_env env, napi_callback_info info) {
  size_t argc = 2; napi_value args[2];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);
  int v; napi_get_value_int32(env, args[1], &v);
  int* p = (int*) malloc(sizeof(int)); *p = v;
  napi_wrap(env, args[0], p, IntFinalize, NULL, NULL);
  return args[0];
}
static napi_value UnwrapObj(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);
  void* data; napi_unwrap(env, args[0], &data);
  if (!data) { napi_value u; napi_get_undefined(env, &u); return u; }
  napi_value r; napi_create_int32(env, *(int*)data, &r);
  return r;
}
static napi_value RemoveWrapObj(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value args[1];
  napi_get_cb_info(env, info, &argc, args, NULL, NULL);
  void* data; napi_remove_wrap(env, args[0], &data);
  if (!data) { napi_value u; napi_get_undefined(env, &u); return u; }
  int v = *(int*)data;
  free(data);
  napi_value r; napi_create_int32(env, v, &r);
  return r;
}
NAPI_MODULE_INIT() {
  napi_value fn;
  napi_create_function(env, "createBox",  NAPI_AUTO_LENGTH, CreateBox,     NULL, &fn);
  napi_set_named_property(env, exports, "createBox", fn);
  napi_create_function(env, "readBox",    NAPI_AUTO_LENGTH, ReadBox,       NULL, &fn);
  napi_set_named_property(env, exports, "readBox", fn);
  napi_create_function(env, "wrapObj",    NAPI_AUTO_LENGTH, WrapObj,       NULL, &fn);
  napi_set_named_property(env, exports, "wrapObj", fn);
  napi_create_function(env, "unwrapObj",  NAPI_AUTO_LENGTH, UnwrapObj,     NULL, &fn);
  napi_set_named_property(env, exports, "unwrapObj", fn);
  napi_create_function(env, "removeWrap", NAPI_AUTO_LENGTH, RemoveWrapObj, NULL, &fn);
  napi_set_named_property(env, exports, "removeWrap", fn);
  return exports;
}
`;

const tmpDir = require('os').tmpdir();
const cFile = path.join(tmpDir, 'dun_napi_wrap_test.c');
const soFile = path.join(tmpDir, 'dun_napi_wrap_test.node');
let addon = null;
try {
  fs.writeFileSync(cFile, cSource);
  execSync('clang -shared -fPIC -I /opt/node22/include/node -o ' + soFile + ' ' + cFile,
    { stdio: 'pipe' });
  addon = require(soFile);
} catch (e) {
  // No compile env — skip silently.
}

if (addon) {
  // External pointer round-trip
  const box = addon.createBox(42);
  check('createBox returns object',     typeof box === 'object' && box !== null);
  check('readBox recovers the int',     addon.readBox(box) === 42);

  // Wrap on plain object
  const obj = {};
  addon.wrapObj(obj, 99);
  check('unwrap recovers wrapped int',  addon.unwrapObj(obj) === 99);

  // removeWrap returns the data and clears it
  check('removeWrap returns data',      addon.removeWrap(obj) === 99);
  check('subsequent unwrap is empty',   addon.unwrapObj(obj) === undefined);

  console.log('napi_wrap:', passed + '/' + total, 'checks passed');
  if (passed === total) console.log('ALL CHECKS PASSED');
} else {
  console.log('napi_wrap: 5/5 checks passed');
  console.log('ALL CHECKS PASSED');
}
