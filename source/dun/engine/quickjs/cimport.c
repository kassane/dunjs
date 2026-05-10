// ImportC shim for QuickJS-NG.
//
// This file is compiled via ImportC (ldc2's built-in C compiler) to
// automatically import all types, enums, and function declarations
// from quickjs.h — eliminating manual extern(C) maintenance.
//
// Usage in D:
//   import dun.engine.quickjs.cimport;
//   auto rt = JS_NewRuntime();
//
// Build:
//   ldc2 uses this .c file as ImportC source when cImportPaths includes
//   the vendor/quickjs directory.
//
// The #pragma(attribute) directives suppress gcc/clang warnings and
// control symbol visibility for the D side.

#pragma(attribute, push("nothrow", "nogc"))

// Define JS_EXTERN as empty — we're linking against libqjs.a,
// not building a shared library.
#define JS_EXTERN

// Suppress unused function warnings for static inlines
#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-function"
#endif

#include "quickjs.h"

#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic pop
#endif

#pragma(attribute, pop)
