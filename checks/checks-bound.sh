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
# The exec checks and the formula's steps resolved DIFFERENT copies of the
# tooling. A step follows {{tooling_root}}, which points at the repo. A check
# resolved HERE/tooling, the copy inside the rig, stale since whenever somebody
# last remembered to copy it. On 2026-10-13 the validate gate judged a design
# with a validator several commits behind the repo and said nothing, because
# both copies exist and neither knows about the other.
# bind-checks already exports TOOLING_ROOT. Prefer it; fall back for an unbound
# check so nothing that was working breaks.
T=${TOOLING_ROOT:-$HERE/tooling}
. "$T/step-vars.sh" 2>/dev/null && load_workflow_vars || true

R=${ARTIFACT_ROOT:-}
[ -n "$R" ] || { echo "ARTIFACT_ROOT is not set, so there is nothing to verify." >&2; exit 75; }
[ -d "$R/checks" ] || { echo "REFUSED: $R/checks does not exist — nothing was bound." >&2
  echo "         Next human action: run tooling/bind-checks.sh and try again." >&2; exit 1; }

# name:the one variable without which THAT check is running on nothing. Naming
# it per check, rather than testing DESIGN_PATH for all of them, is the
# difference between proving the binding and proving a binding happened: the
# question gates would pass a DESIGN_PATH test while carrying no questions.
# What bind-checks says it bound. Read from its manifest rather than carried
# here: two hardcoded lists drift, and the one that drifts silently is the
# verifier. A missing manifest means nothing was bound, which is itself the
# failure this gate exists to catch.
MANIFEST="$R/checks/.bound"
[ -f "$MANIFEST" ] || { echo "REFUSED: no $MANIFEST — bind-checks did not run, or ran an older version." >&2
  echo "         Next human action: run tooling/bind-checks.sh for $R and try again." >&2; exit 1; }

# The one variable without which a given check is running on nothing. A check not
# named here is still verified for existence and a target; naming it just makes
# the test sharper.
need_for() {
  case "$1" in
    bundle-records)   echo BUNDLE_PATH ;;
    prior-archived)   echo ARTIFACT_ROOT ;;
    questions-asked|questions-answered) echo QUESTIONS_PATH ;;
    selftest-gate)    echo CHECK_SCRIPT ;;
    audit-verdict)    echo AUDIT_VERDICT ;;
    *)                echo DESIGN_PATH ;;
  esac
}

BAD=""
NCHECK=0
while IFS= read -r n; do
  [ -n "$n" ] || continue
  need=$(need_for "$n")
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
done < "$MANIFEST"

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
