#!/usr/bin/env bash
# Gate check: can every later gate in this run find its own inputs?
#
# This is the one check that cannot be bound — it is what proves the binding
# happened — so it still recovers its inputs the old way.
#
# It does not ask "were files written". It asks whether a bound wrapper actually
# carries a value and points at a check that exists, because a wrapper that
# exports nothing is a gate that will run on whatever the environment carried.
#
# Exit 0   every expected wrapper is present, executable, valued and targeted
# Exit 1   one is missing, empty, or points at nothing
# Exit 75  the check could not run
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/tooling/step-vars.sh" 2>/dev/null && load_workflow_vars || true

R=${ARTIFACT_ROOT:-}
[ -n "$R" ] || { echo "ARTIFACT_ROOT is not set, so there is nothing to verify." >&2; exit 75; }
[ -d "$R/checks" ] || { echo "REFUSED: $R/checks does not exist — nothing was bound." >&2
  echo "         Next human action: run tooling/bind-checks.sh and try again." >&2; exit 1; }

# name:the one variable without which THAT check is running on nothing. Naming
# it per check, rather than testing DESIGN_PATH for all of them, is the
# difference between proving the binding and proving a binding happened: the
# question gates would pass a DESIGN_PATH test while carrying no questions.
EXPECT="design-reviewed:DESIGN_PATH design-validate:DESIGN_PATH design-audited:DESIGN_PATH
        diagrams-complete:DESIGN_PATH bundle-records:BUNDLE_PATH prior-archived:ARTIFACT_ROOT
        questions-asked:QUESTIONS_PATH questions-answered:QUESTIONS_PATH"
BAD=""
NCHECK=0
for spec in $EXPECT; do
  n=${spec%%:*}; need=${spec#*:}
  NCHECK=$((NCHECK+1))
  W="$R/checks/$n.sh"
  if   [ ! -f "$W" ];            then BAD="$BAD $n(absent)"
  elif [ ! -x "$W" ];            then BAD="$BAD $n(not-executable)"
  else
    # A wrapper with no value bound is worse than no wrapper: it runs, and it
    # runs on whatever the environment happened to carry.
    v=$(sed -n "s/^export $need='\(.*\)'$/\1/p" "$W" | head -1)
    t=$(sed -n "s/^exec '\(.*\)' .*/\1/p" "$W" | head -1)
    if   [ -z "$v" ];            then BAD="$BAD $n(no-$need)"
    elif [ -z "$t" ];            then BAD="$BAD $n(no-target)"
    elif [ ! -f "$t" ];          then BAD="$BAD $n(target-missing)"
    fi
  fi
done

if [ -n "$BAD" ]; then
  echo "REFUSED: these bound checks are not usable:$BAD" >&2
  echo "         A gate whose wrapper carries no value runs on whatever the" >&2
  echo "         environment happened to carry, which is the failure this" >&2
  echo "         binding exists to remove." >&2
  echo "         Next human action: re-run tooling/bind-checks.sh for $R." >&2
  exit 1
fi

echo "bound and usable: $NCHECK check(s) in $R/checks"
exit 0
