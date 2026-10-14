#!/usr/bin/env bash
# requires: DESIGN_PATH
# bind-checks.sh reads this line and refuses a binding that omits any of
# them. A check that discovers a missing value at run time reports it as
# "could not run", and gc has no outcome for that, so it surfaces as a
# failed check with a reason about the environment rather than the artifact.
# Gate check: does the authored design pass the design rules?
#
# Exit 0   all rules pass
# Exit 1   a rule failed — the design is not buildable as written
# Exit 75  the design or the validator is not there to run
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
# The exec checks and the formula's steps resolved DIFFERENT copies of the
# tooling. A step follows {{tooling_root}}, which points at the repo. A check
# resolved HERE/tooling, the copy inside the rig, stale since whenever somebody
# last remembered to copy it. On 2026-10-13 the validate gate judged a design
# with a validator several commits behind the repo and said nothing, because
# both copies exist and neither knows about the other.
# bind-checks already exports TOOLING_ROOT. Prefer it; fall back for an unbound
# check so nothing that was working breaks.
T=${TOOLING_ROOT:-$HERE/tooling}
# Formula [vars] live on the workflow root, not in an exec check's environment.
. "$T/step-vars.sh" 2>/dev/null && load_workflow_vars || true
D=${DESIGN_PATH:-}
[ -n "$D" ] || { echo "DESIGN_PATH is not set — the authoring step did not record where it wrote." >&2; exit 75; }
[ -f "$D" ] || { echo "no design at $D — nothing was authored." >&2; exit 75; }
[ -x "$T/validate.sh" ] || { echo "the validator is not at $T/validate.sh." >&2; exit 75; }
# The question set goes in, or V32-V34 do not run and nothing says so. A rule
# that quietly does not run is the defect this pipeline exists to catch.
exec env ${QUESTIONS_PATH:+QUESTIONS="$QUESTIONS_PATH"} ${METHOD_PATH:+METHOD="$METHOD_PATH"} ${CATALOG:+CATALOG="$CATALOG"} \
     "$T/validate.sh" "$D"
