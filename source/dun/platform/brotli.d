module dun.platform.brotli;

// Bindings for libbrotli (encoder + decoder).
//
// The vendor/brotli/brotli_api.c bridge `#include`s <brotli/encode.h> and
// <brotli/decode.h>. ImportC compiles that bridge with cImportPaths set to
// vendor/brotli, exposing every declaration as a D symbol. This replaces the
// hand-written extern(C) prototypes and keeps the bindings in sync with
// whatever libbrotli the build environment ships.

public import brotli_api;
