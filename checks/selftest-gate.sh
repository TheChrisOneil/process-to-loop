#!/usr/bin/env bash
# Gate check: does the authored script satisfy its fixtures?
#
# Exit 0   every fixture holds and none is undeclared
# Exit 1   a fixture failed, or a boundary is still undeclared
# Exit 75  the script or the fixtures are not there to test
#
# Reads CHECK_SCRIPT and CHECK_FIXTURES from the environment, which the
# authoring step writes into the workflow.
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
S=${CHECK_SCRIPT:-}; F=${CHECK_FIXTURES:-}
[ -n "$S" ] && [ -n "$F" ] || { echo "CHECK_SCRIPT and CHECK_FIXTURES are not set — the authoring step did not record where it wrote." >&2; exit 75; }
[ -f "$S" ] || { echo "no check script at $S — nothing was authored." >&2; exit 75; }
[ -f "$F" ] || { echo "no fixtures at $F." >&2; exit 75; }
exec "$T/selftest.sh" "$S" "$F"
