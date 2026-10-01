#!/usr/bin/env bash
# Gate check: is this design finished with the model, or can the model still fix it?
#
# This is the revision loop. It sits on the authoring step, so a non-zero exit
# re-runs the AUTHOR, not the audit — the orchestrator's own bounded loop, which
# is what [steps.check] is for.
#
# Exit 0   nothing left for the model: either sound, or every remaining finding
#          needs a person. Proceed, and the findings step surfaces what is left.
# Exit 1   findings the author can fix. "Not yet" — consumes an attempt and
#          re-runs authoring with the findings in hand.
# Exit 75  the design, the verdict or a tool is not there to judge.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
D=${DESIGN_PATH:-}; V=${AUDIT_VERDICT:-}
[ -n "$D" ] || { echo "DESIGN_PATH is not set — the authoring step did not record where it wrote." >&2; exit 75; }
[ -f "$D" ] || { echo "no design at $D — nothing was authored." >&2; exit 75; }
command -v python3 >/dev/null || { echo "no python3 to read the verdict." >&2; exit 75; }

# 1. form first. A design that fails its rules is not worth auditing.
if ! "$HERE/tooling/validate.sh" "$D" >/tmp/dr-val.$$ 2>&1; then
  sed 's/^/  /' /tmp/dr-val.$$ | grep -E "FAIL" | head -6 >&2
  rm -f /tmp/dr-val.$$
  echo "NOT YET: the design does not pass its own rules." >&2
  echo "         Fix what the validator named and write it again." >&2
  exit 1
fi
rm -f /tmp/dr-val.$$

# 2. audit THIS revision. A verdict older than the design describes a revision
#    that no longer exists, so it is re-run rather than reused.
[ -n "$V" ] || V="$(cd "$(dirname "$D")" && pwd)/design-audit-verdict.json"
if [ ! -f "$V" ] || [ "$V" -ot "$D" ]; then
  U=${USE_CASE_PATH:-}
  [ -n "$U" ] && [ -f "$U" ] || { echo "USE_CASE_PATH is not set, so the audit has nothing to judge the design against." >&2; exit 75; }
  "$HERE/tooling/audit-design.sh" "$D" "$U" "$V" || exit $?
fi

# 3. classify what the audit found
python3 - "$V" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
defects = d.get("defects") or []
if not defects:
    print("sound: the audit found nothing. Nothing left for the model.")
    sys.exit(0)

unknown = [x for x in defects if x.get("fixable") not in ("by_revision", "needs_a_person")]
if unknown:
    print(f"NOT YET: {len(unknown)} finding(s) do not say whether a revision can fix them.",
          file=sys.stderr)
    print("         Every defect carries fixable: by_revision or needs_a_person.", file=sys.stderr)
    print("         An unclassified finding cannot be routed, so nothing can act on it.", file=sys.stderr)
    sys.exit(1)

fixable = [x for x in defects if x["fixable"] == "by_revision"]
human   = [x for x in defects if x["fixable"] == "needs_a_person"]

if fixable:
    print(f"NOT YET: {len(fixable)} finding(s) the author can fix, {len(human)} for a person.",
          file=sys.stderr)
    for x in fixable[:6]:
        print(f"           [{x.get('severity','?')}] {x.get('what','')[:150]}", file=sys.stderr)
    print("         Revise the design against these and write it again. The findings that", file=sys.stderr)
    print("         need a person are carried forward untouched.", file=sys.stderr)
    sys.exit(1)

print(f"done with the model: {len(human)} finding(s) remain, every one needing a person. "
      f"The findings step takes them to one.")
sys.exit(0)
PY
