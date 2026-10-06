#!/usr/bin/env bash
# Gate check: has every question come back with an answer?
#
# Three answers are legal — stated, unanswered, delegated — and that is the
# point: the run never stalls on the first thing nobody knows. What is refused
# is silence. A blank block reaches the author as nothing at all, and the author
# does what it did before any of this existed: assumes, and declares it among
# forty-three others nobody reads.
#
# Exit 0   every question has an answer
# Exit 1   a block is open, or an answer is malformed
# Exit 75  the questions file or the tool is not there to run
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/tooling/step-vars.sh" 2>/dev/null && load_workflow_vars || true
Q=${QUESTIONS_PATH:-}
[ -n "$Q" ] || { echo "QUESTIONS_PATH is not set — the interview step did not record where it wrote." >&2; exit 75; }
[ -f "$Q" ] || { echo "no questions at $Q." >&2; exit 75; }
[ -x "$HERE/tooling/questions.sh" ] || { echo "the questions tool is not at $HERE/tooling/questions.sh." >&2; exit 75; }

RC=0
env ${CATALOG:+CATALOG="$CATALOG"} "$HERE/tooling/questions.sh" answered "$Q" || RC=$?
echo
"$HERE/tooling/questions.sh" status "$Q" || true
[ "$RC" -eq 0 ] || {
  echo
  echo "Next human action: answer each open block with" >&2
  echo "    tooling/questions.sh answer $Q <Qn> stated|unanswered|delegated --by <who> [--value <v>]" >&2
}
exit "$RC"
