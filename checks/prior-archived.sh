#!/usr/bin/env bash
# Gate check: can anything downstream still read a previous run's conclusions?
#
# The archive step's job is not "a copy was made". It is that NO artifact which
# describes an earlier design is still sitting where a later step will read it as
# if it described this one. That is the stale-verdict failure, and it reached a
# person once already.
#
# Exit 0   the working directory holds nothing derived from an earlier design
# Exit 1   a verdict or a findings file is still there
# Exit 75  there is no artifact_root to look at
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/tooling/step-vars.sh" 2>/dev/null && load_workflow_vars || true

R=${ARTIFACT_ROOT:-}
[ -n "$R" ] || { echo "ARTIFACT_ROOT is not set, so there is nothing to check." >&2; exit 75; }
[ -d "$R" ] || { echo "no artifact_root at $R." >&2; exit 75; }

LEFT=""
for f in design-audit-verdict.json FINDINGS.md; do
  [ -e "$R/$f" ] && LEFT="$LEFT $f"
done

if [ -n "$LEFT" ]; then
  echo "REFUSED: a previous run's conclusions are still in the working directory:$LEFT" >&2
  echo "         A later step reads these by name and cannot tell which design they" >&2
  echo "         describe. On 2026-10-02 a run reached the findings step with an" >&2
  echo "         audit of a design that no longer existed." >&2
  echo "         Next human action: run tooling/archive-run.sh \"$R\" and try again." >&2
  exit 1
fi

# An archive is only evidence if it holds something. A first run legitimately has
# none, so its absence is reported and not refused.
if [ -d "$R/prior" ] && [ -n "$(ls -A "$R/prior" 2>/dev/null)" ]; then
  N=$(ls -1 "$R/prior" | wc -l | tr -d ' ')
  echo "clear: nothing derived is left in the working directory; $N archived run(s) kept."
else
  echo "clear: nothing derived is left in the working directory; no earlier run to keep."
fi
exit 0
