#!/usr/bin/env bash
# Gate check: does the authored design pass the design rules?
#
# Exit 0   all rules pass
# Exit 1   a rule failed — the design is not buildable as written
# Exit 75  the design or the validator is not there to run
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
D=${DESIGN_PATH:-}
[ -n "$D" ] || { echo "DESIGN_PATH is not set — the authoring step did not record where it wrote." >&2; exit 75; }
[ -f "$D" ] || { echo "no design at $D — nothing was authored." >&2; exit 75; }
[ -x "$HERE/tooling/validate.sh" ] || { echo "the validator is not at $HERE/tooling/validate.sh." >&2; exit 75; }
exec "$HERE/tooling/validate.sh" "$D"
