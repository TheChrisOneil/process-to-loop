#!/usr/bin/env bash
# Gate check: was THIS design audited, by a different model, against the six
# dimensions the rules cannot reach?
#
# The design lane's wrapper around audit-verdict.sh, which serves three lanes and
# so cannot know this one's dimensions or where its verdict lives. This resolves
# both from the workflow and delegates the judgment.
#
# It exists because folding this gate into the authoring loop removed the only
# bead that said the audit happened. On 2026-10-02 the authoring step closed
# pass three times having written no verdict at all, and the run went on.
#
# Exit 0   the audit is real, cross-model, complete, and about this design
# Exit 1   it is not
# Exit 75  the check could not run
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/tooling/step-vars.sh" 2>/dev/null && load_workflow_vars || true

D=${DESIGN_PATH:-}
[ -n "$D" ] || { echo "DESIGN_PATH is not set, so there is no design to check an audit against." >&2; exit 75; }
[ -f "$D" ] || { echo "no design at $D." >&2; exit 75; }

# The audit is OF the design, so the design is the subject whose sha the verdict
# must name. Freshness is the whole point of this gate.
export AUDIT_SUBJECT="$D"
export AUDIT_VERDICT="${AUDIT_VERDICT:-$(cd "$(dirname "$D")" && pwd)/design-audit-verdict.json}"
export AUDIT_DIMENSIONS="unit-of-work,judgment-isolated,gate-coverage,refusal-quality,evidence-chain,exit-criterion"

[ -x "$HERE/checks/audit-verdict.sh" ] || { echo "audit-verdict.sh is not at $HERE/checks/." >&2; exit 75; }
exec "$HERE/checks/audit-verdict.sh"
