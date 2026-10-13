#!/usr/bin/env bash
# Gate check: does the authored step hold the properties its type promises?
#
# Exit 0   every property holds
# Exit 1   a property failed
# Exit 75  the step or its properties are not there to test
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
S=${STEP_SCRIPT:-}; P=${STEP_PROPERTIES:-}; B=${STEP_BUNDLE:-}
[ -n "$S" ] && [ -n "$P" ] || { echo "STEP_SCRIPT and STEP_PROPERTIES are not set — the authoring step did not record where it wrote." >&2; exit 75; }
[ -f "$S" ] || { echo "no step script at $S — nothing was authored." >&2; exit 75; }
[ -f "$P" ] || { echo "no properties at $P." >&2; exit 75; }
exec "$T/step-selftest.sh" "$S" "$P" ${B:+--bundle "$B"}
