#!/usr/bin/env bash
# Gate check: does the authored design pass the design rules?
#
# Exit 0   all rules pass
# Exit 1   a rule failed — the design is not buildable as written
# Exit 75  the design or the validator is not there to run
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
# Formula [vars] live on the workflow root, not in an exec check's environment.
. "$HERE/tooling/step-vars.sh" 2>/dev/null && load_workflow_vars || true
D=${DESIGN_PATH:-}
[ -n "$D" ] || { echo "DESIGN_PATH is not set — the authoring step did not record where it wrote." >&2; exit 75; }
[ -f "$D" ] || { echo "no design at $D — nothing was authored." >&2; exit 75; }
[ -x "$HERE/tooling/validate.sh" ] || { echo "the validator is not at $HERE/tooling/validate.sh." >&2; exit 75; }
# The question set goes in, or V32-V34 do not run and nothing says so. A rule
# that quietly does not run is the defect this pipeline exists to catch.
exec env ${QUESTIONS_PATH:+QUESTIONS="$QUESTIONS_PATH"} ${METHOD_PATH:+METHOD="$METHOD_PATH"} ${CATALOG:+CATALOG="$CATALOG"} \
     "$HERE/tooling/validate.sh" "$D"
