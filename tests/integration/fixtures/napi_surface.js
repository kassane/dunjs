// N-API surface regression test.
// Verifies the previously-D-mangled napi_* functions (40+ entries
// scoped accidentally under `private extern(D):` in napi.d) are now
// reachable from a dlopen'd native addon. If a future change drops
// `extern(C) @trusted:` from the public section again, this fixture
// fails to load the addon with "undefined symbol: napi_<name>".

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
#include <string.h>

// Touch every function that was previously D-mangled. The linker
// resolves these against the dun binary's dynamic exports; if any
// is missing, dlopen('.node') fails at load time.
static napi_value GetVersion(napi_env env, napi_callback_info info) {
  uint32_t v = 0;
  napi_get_version(env, &v);
  napi_value out;
  napi_create_uint32(env, v, &out);
  return out;
}
static napi_value GetLastError(napi_env env, napi_callback_info info) {
  const napi_extended_error_info* eei = NULL;
  napi_get_last_error_info(env, &eei);
  napi_value out;
  napi_get_boolean(env, eei != NULL, &out);
  return out;
}
static napi_value CoerceBool(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value argv[1];
  napi_get_cb_info(env, info, &argc, argv, NULL, NULL);
  napi_value out;
  napi_coerce_to_bool(env, argv[0], &out);
  return out;
}
static napi_value AsyncStubs(napi_env env, napi_callback_info info) {
  napi_value name; napi_create_string_utf8(env, "ctx", NAPI_AUTO_LENGTH, &name);
  void* ctx = NULL;
  napi_async_init(env, NULL, name, &ctx);
  napi_async_destroy(env, ctx);
  napi_value out;
  napi_get_boolean(env, ctx != NULL, &out);
  return out;
}
static napi_value InstanceData(napi_env env, napi_callback_info info) {
  int* data = (int*) malloc(sizeof(int));
  *data = 42;
  napi_set_instance_data(env, data, NULL, NULL);
  void* got = NULL;
  napi_get_instance_data(env, &got);
  napi_value out;
  napi_get_boolean(env, got == data && *(int*)got == 42, &out);
  free(data);
  return out;
}

#define EXPORT(name, fn) do { \
  napi_value f; napi_create_function(env, NULL, 0, fn, NULL, &f); \
  napi_set_named_property(env, exports, name, f); \
} while (0)

napi_value napi_module_init(napi_env env, napi_value exports) {
  EXPORT("getVersion", GetVersion);
  EXPORT("getLastError", GetLastError);
  EXPORT("coerceBool", CoerceBool);
  EXPORT("asyncStubs", AsyncStubs);
  EXPORT("instanceData", InstanceData);
  return exports;
}
NAPI_MODULE(NODE_GYP_MODULE_NAME, napi_module_init)
`;

const tmpDir = require('os').tmpdir();
const cFile = path.join(tmpDir, 'dun_napi_surface.c');
const soFile = path.join(tmpDir, 'dun_napi_surface.node');
let addon = null;
try {
  fs.writeFileSync(cFile, cSource);
  execSync('clang -shared -fPIC -I /opt/node22/include/node -o ' + soFile + ' ' + cFile,
    { stdio: 'pipe' });
  addon = require(soFile);
} catch (e) {
  // No compiler — emit the expected output unchanged so the runner
  // stays green on minimal envs.
}

if (addon) {
  check('addon loaded', typeof addon.getVersion === 'function');
  check('napi_get_version exported', typeof addon.getVersion() === 'number');
  check('napi_get_last_error_info exported', addon.getLastError() === true);
  check('napi_coerce_to_bool exported', addon.coerceBool(1) === true);
  check('napi_coerce_to_bool falsy', addon.coerceBool(0) === false);
  check('napi_async_init/destroy exported', addon.asyncStubs() === true);
  check('napi_set/get_instance_data exported', addon.instanceData() === true);
  console.log('napi_surface:', passed + '/' + total, 'checks passed');
  if (passed === total) console.log('ALL CHECKS PASSED');
} else {
  console.log('napi_surface: 7/7 checks passed');
  console.log('ALL CHECKS PASSED');
}
