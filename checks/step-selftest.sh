#!/usr/bin/env bash
# Gate check: does the authored step hold the properties its type promises?
#
# Exit 0   every property holds
# Exit 1   a property failed
# Exit 75  the step or its properties are not there to test
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
S=${STEP_SCRIPT:-}; P=${STEP_PROPERTIES:-}; B=${STEP_BUNDLE:-}
[ -n "$S" ] && [ -n "$P" ] || { echo "STEP_SCRIPT and STEP_PROPERTIES are not set — the authoring step did not record where it wrote." >&2; exit 75; }
[ -f "$S" ] || { echo "no step script at $S — nothing was authored." >&2; exit 75; }
[ -f "$P" ] || { echo "no properties at $P." >&2; exit 75; }
exec "$HERE/tooling/step-selftest.sh" "$S" "$P" ${B:+--bundle "$B"}
