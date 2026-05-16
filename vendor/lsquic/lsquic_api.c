/* ImportC bridge: lets D's ImportC processor pull in lsquic's public
 * declarations directly from the upstream header. Used by
 * `dun.platform.lsquic_c` as an alternative to the hand-maintained
 * extern(C) bindings in `dun.platform.lsquic`.
 *
 * Header-only: the runtime library (liblsquic.a + BoringSSL) is NOT
 * linked by default — see CLAUDE.md for the full build recipe.
 */
#pragma attribute(push, nothrow, nogc)
#include "include/lsquic_types.h"
#include "include/lsxpack_header.h"
#include "include/lsquic.h"
#pragma attribute(pop)
