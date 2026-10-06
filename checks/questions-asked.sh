#!/usr/bin/env bash
# Gate check: were the questions actually asked, and asked properly?
#
# This runs between the interview and the answers. It does not ask whether the
# answers are good — nothing has been answered yet. It asks whether a person
# could answer this: that the set exists, that it names the use case it is about,
# that every block says what it asks and why that matters, and that nothing in it
# names a tool the organization does not have.
#
# Exit 0   the questions can be put to a person
# Exit 1   a rule failed — the set is not askable as written
# Exit 75  the questions file or the tool is not there to run
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/tooling/step-vars.sh" 2>/dev/null && load_workflow_vars || true
Q=${QUESTIONS_PATH:-}
[ -n "$Q" ] || { echo "QUESTIONS_PATH is not set — the interview step did not record where it wrote." >&2; exit 75; }
[ -f "$Q" ] || { echo "no questions at $Q — the interview wrote nothing." >&2
                 echo "A design authored with nothing asked is the thing this step replaces." >&2; exit 75; }
[ -x "$HERE/tooling/questions.sh" ] || { echo "the questions tool is not at $HERE/tooling/questions.sh." >&2; exit 75; }

# The use case the questions claim to be about must be the one this run read.
# A question set carried over from a different description is a set of questions
# about something else, and every answer to it is an answer about something else.
if [ -n "${USE_CASE_PATH:-}" ] && [ -f "$USE_CASE_PATH" ]; then
  WANT=$(shasum -a 256 "$USE_CASE_PATH" | cut -d' ' -f1)
  GOT=$(awk '/^use_case_sha256:/ { print $2; exit }' "$Q")
  if [ -n "$GOT" ] && [ "$GOT" != "$WANT" ]; then
    echo "REFUSED: the questions are about a different use case." >&2
    echo "         they name   $GOT" >&2
    echo "         this run read $WANT" >&2
    echo "         Next human action: re-run the interview against this description." >&2
    exit 1
  fi
fi

exec env ${CATALOG:+CATALOG="$CATALOG"} "$HERE/tooling/questions.sh" validate "$Q"
