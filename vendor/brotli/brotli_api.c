// ImportC bridge: processes brotli/encode.h and brotli/decode.h declarations for D import.
// libbrotli is a system dependency (libbrotli-dev on Debian/Ubuntu, brotli on macOS via brew).
//
// `#pragma attribute(push, nothrow, nogc)` instructs the D compiler to mark
// every brotli function as `nothrow @nogc`. Without this, ImportC defaults to
// throw/may-allocate, which forces D-side landing-pad and GC-root setup that
// libbrotli will never use.
#pragma attribute(push, nothrow, nogc)
#include <brotli/encode.h>
#include <brotli/decode.h>
#pragma attribute(pop)
