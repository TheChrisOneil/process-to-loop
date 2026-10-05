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
# The controller does not export a formula's [vars] to an exec check. Recover
# them from the workflow root before reading anything from the environment.
. "$HERE/tooling/step-vars.sh" 2>/dev/null && load_workflow_vars || true
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

# 2. audit THIS revision. A verdict about any other revision describes a design
#    that no longer exists, so it is re-run rather than reused.
[ -n "$V" ] || V="$(cd "$(dirname "$D")" && pwd)/design-audit-verdict.json"
# Staleness is decided by CONTENT, not by mtime. A timestamp says when a file was
# touched, not what it describes: a verdict can be newer than the design and
# still be about an earlier revision, and any copy, checkout or restore rewrites
# mtime without changing a byte. The verdict records the sha of what it audited.
NEEDS_AUDIT=0
if [ ! -f "$V" ]; then
  NEEDS_AUDIT=1
else
  WANT_SHA=$(shasum -a 256 "$D" | awk '{print $1}')
  GOT_SHA=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("subject_sha256") or "")' "$V" 2>/dev/null)
  [ "$GOT_SHA" = "$WANT_SHA" ] || NEEDS_AUDIT=1
fi
if [ "$NEEDS_AUDIT" -eq 1 ]; then
  U=${USE_CASE_PATH:-}
  [ -n "$U" ] && [ -f "$U" ] || { echo "USE_CASE_PATH is not set, so the audit has nothing to judge the design against." >&2; exit 75; }
  "$HERE/tooling/audit-design.sh" "$D" "$U" "$V" || exit $?
fi

# 3. classify what the audit found
python3 - "$V" <<'PY'
import json, os, sys
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

# Stop retrying when a revision is not reducing the fixable count. On
# appointment-chase the loop went 9 findings to 7 and then spent its last
# attempt on one fixable item, and the whole run died holding six findings a
# person needed to see. A revision that does not make progress should surface
# what it has, not consume another attempt and then fail.
prev_path = os.environ.get("AUDIT_VERDICT", "") + ".fixable"
prev = None
try:
    with open(prev_path) as fh: prev = int(fh.read().strip())
except Exception:
    pass
try:
    with open(prev_path, "w") as fh: fh.write(str(len(fixable)))
except Exception:
    pass

if fixable and prev is not None and len(fixable) >= prev:
    print(f"no progress: {len(fixable)} finding(s) the author could fix, "
          f"and the last revision left {prev}. Surfacing instead of revising again.",
          file=sys.stderr)
    for x in fixable[:6]:
        print(f"           [{x.get('severity','?')}] {x.get('what','')[:150]}", file=sys.stderr)
    print(f"         {len(human)} finding(s) need a person regardless.", file=sys.stderr)
    sys.exit(0)

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
