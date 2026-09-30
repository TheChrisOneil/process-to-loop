#!/bin/sh
# gc <binding> preflight — check this city before building formulas against it.
set -eu
[ -n "${GC_PACK_DIR:-}" ] || { echo "REFUSED: GC_PACK_DIR is not set; this must run as a projected command." >&2; exit 75; }
exec "$GC_PACK_DIR/lib/city-preflight.sh" --city "${GC_CITY_DIR:-$PWD}" "$@"
