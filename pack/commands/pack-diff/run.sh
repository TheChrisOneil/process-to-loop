#!/bin/sh
# gc <binding> pack-diff — classify the difference between two pack versions.
set -eu
[ -n "${GC_PACK_DIR:-}" ] || { echo "REFUSED: GC_PACK_DIR is not set; this must run as a projected command." >&2; exit 75; }
exec "$GC_PACK_DIR/lib/pack-diff.sh" "$@"
