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
S=${CHECK_SCRIPT:-}; F=${CHECK_FIXTURES:-}
[ -n "$S" ] && [ -n "$F" ] || { echo "CHECK_SCRIPT and CHECK_FIXTURES are not set — the authoring step did not record where it wrote." >&2; exit 75; }
[ -f "$S" ] || { echo "no check script at $S — nothing was authored." >&2; exit 75; }
[ -f "$F" ] || { echo "no fixtures at $F." >&2; exit 75; }
exec "$HERE/tooling/selftest.sh" "$S" "$F"
