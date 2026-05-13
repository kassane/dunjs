#!/bin/sh
# DunJS backend-swappable wrapper
# Detects DUN_BACKEND env and delegates to the appropriate binary.
# Usage:
#   DUN_BACKEND=jsc dun run script.js
#   DUN_BACKEND=v8  dun eval "1+1"
#   dun run script.js    # defaults to quickjs

set -e

BACKEND="${DUN_BACKEND:-quickjs}"
BIN_DIR="${DUN_BIN_DIR:-/usr/local/bin}"

case "$BACKEND" in
    quickjs|jsc|v8)
        BINARY="$BIN_DIR/dun-$BACKEND"
        ;;
    *)
        echo "error: unknown backend '$BACKEND' (use quickjs, jsc, or v8)" >&2
        exit 1
        ;;
esac

if [ ! -x "$BINARY" ]; then
    echo "error: backend binary not found: $BINARY" >&2
    echo "Available backends:" >&2
    for b in quickjs jsc v8; do
        [ -x "$BIN_DIR/dun-$b" ] && echo "  $b" >&2
    done
    exit 1
fi

exec "$BINARY" "$@"
