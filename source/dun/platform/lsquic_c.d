module dun.platform.lsquic_c;

// ImportC re-export of litespeedtech/lsquic's public API.
//
// `vendor/lsquic/lsquic_api.c` `#include`s the upstream `include/lsquic.h`,
// which the D compiler's ImportC mode parses into D symbols. This module
// re-exports them so callers can write `import dun.platform.lsquic_c` and
// get the same declarations as the hand-maintained
// `dun.platform.lsquic` -- with the advantage that struct layouts,
// constants, and signatures track the upstream header automatically.
//
// Header-only: no liblsquic.a / BoringSSL is linked by default. Building a
// runtime requires a separate lsquic + BoringSSL build (see lsquic's
// `BUILD-WINDOWS.md` / `README.md`); this binding only validates types.

public import lsquic_api;
