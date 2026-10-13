#!/usr/bin/env bash
# Gate check: were the diagrams drawn, and do they carry every control?
#
# A diagram that drops a gate is worse than no diagram — a reviewer reads it,
# sees a clean flow, and approves a design whose control is invisible.
#
# Exit 0   both views exist and show every gate the design declares
# Exit 1   a view is missing, stale, or shows fewer gates than the design has
# Exit 75  the design or the renderer is not there to check
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
[ -n "$D" ] || { echo "DESIGN_PATH is not set — the render step did not record where it wrote." >&2; exit 75; }
[ -f "$D" ] || { echo "no design at $D." >&2; exit 75; }
DIR=$(cd "$(dirname "$D")" && pwd)/diagrams
[ -f "$T/lib/parse.awk" ] || { echo "the parser is not at $T/lib." >&2; exit 75; }

WANT=$(awk -f "$T/lib/parse.awk" -f "$T/lib/gates.awk" "$D" 2>/dev/null | grep -c .)
fail=0
for v in sequence flow; do
  f="$DIR/$v.mmd"
  if [ ! -f "$f" ]; then
    echo "REFUSED: $v.mmd was not drawn." >&2; fail=1; continue
  fi
  if [ "$f" -ot "$D" ]; then
    echo "REFUSED: $v.mmd is older than the design — it shows a design that no longer exists." >&2
    fail=1; continue
  fi
  case "$v" in
    sequence) got=$(grep -c '^    alt ' "$f" 2>/dev/null || echo 0) ;;
    flow)     got=$(grep -c ':::gate' "$f" 2>/dev/null || echo 0) ;;
  esac
  if [ "$got" -lt "$WANT" ]; then
    echo "REFUSED: the design declares $WANT gate(s); $v.mmd shows $got." >&2
    echo "         A reviewer would approve a flow whose control is invisible." >&2
    fail=1
  fi
done
[ "$fail" -eq 0 ] || { echo "         Next human action: re-render, and if it still drops a control, report it." >&2; exit 1; }
echo "both views drawn, each showing all $WANT gate(s)"
