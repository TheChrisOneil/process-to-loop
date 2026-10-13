#!/usr/bin/env bash
# The obligations a TEST step's fixtures must cover.
#
#   test-fixtures.sh <design> <step-id>
#
# A gate's fixtures are generated from its condition, because a condition is a
# predicate over one value. A test step's are not generatable the same way: the
# data it recomputes over is not derivable from its description.
#
# What is derivable is the list of CLAIMS, and the obligation each creates — a
# satisfying case and a violating one. The violating case is the point. A test
# step's failure mode is passing everything.
#
# Exit 0 printed · 2 no such step, or not a test step · 64 wrong arguments
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
D=${1:-}; STEP=${2:-}
[ -n "$D" ] && [ -n "$STEP" ] || { echo "usage: test-fixtures.sh <design> <step-id>" >&2; exit 64; }
[ -f "$D" ] || { echo "no design at $D" >&2; exit 2; }
exec awk -v STEP="$STEP" -f "$HERE/lib/parse.awk" -f "$HERE/lib/test-fixtures.awk" "$D"
