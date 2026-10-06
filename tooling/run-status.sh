#!/usr/bin/env bash
# Where is a design-authoring run, in one screen?
#
#   run-status.sh <artifact_root> [--follow [seconds]]
#
# Reads the rig's beads and the artifacts on disk. Changes nothing.
set -uo pipefail
Q=${1:?artifact_root}
FOLLOW=${2:-}
INT=${3:-30}
[ -d "$Q" ] || { echo "no artifact_root at $Q." >&2; exit 75; }
Q=$(cd "$Q" && pwd)

# gc resolves its city and rig from the CURRENT DIRECTORY. Run this from a repo
# checkout and gc answers about the city it defaults to, which holds none of
# these beads — and the report came back empty rather than wrong, which is the
# worse of the two. The artifact_root is inside the rig, so stand there.
cd "$Q" || { echo "cannot enter $Q." >&2; exit 75; }

# Which workflow owns this artifact_root? Resolved once, so a caller needs no
# bead id to get a truthful answer.
if [ -z "${ROOT_BEAD:-}" ]; then
  ROOT_BEAD=$(ARTQ="$Q" gc bd list --json 2>/dev/null | ARTQ="$Q" python3 -c "
import json, sys, os
q = os.environ.get('ARTQ', '')
try: bs = json.load(sys.stdin)
except Exception: raise SystemExit
for b in bs:
    md = b.get('metadata') or {}
    if md.get('gc.kind') == 'workflow' and md.get('gc.var.artifact_root') == q:
        print(b.get('id') or ''); break
" 2>/dev/null)
fi
# An empty answer here means "I found no run", and it must not be reported as
# "the run has done nothing". Those look identical on screen and they are not
# the same fact.
if [ -z "${ROOT_BEAD:-}" ]; then
  echo "No workflow in this rig names $Q as its artifact_root." >&2
  echo "Either nothing has been slung for it, or this is not the path the run was given." >&2
  echo "What this rig does hold:" >&2
  gc bd list --json 2>/dev/null | python3 -c "
import json, sys
try: bs = json.load(sys.stdin)
except Exception: raise SystemExit
n = 0
for b in bs:
    md = b.get('metadata') or {}
    if md.get('gc.kind') != 'workflow': continue
    n += 1
    print('   ', b.get('id'), '->', md.get('gc.var.artifact_root') or '(no artifact_root)')
if not n: print('    no workflows at all.')
" >&2
  exit 75
fi
export ROOT_BEAD

snapshot() {
  printf '\n%s\n' "$(date '+%H:%M:%S')"
  echo "  ── steps ─────────────────────────────────────────"
  # A closed bead is not a passed bead. Printing every closed step as "done"
  # showed two gates that had REFUSED as though they had passed, on 2026-10-05,
  # which is the failure this whole project exists to catch — in the tool
  # written to watch for it. Read gc.outcome.
  gc bd list --status closed --json 2>/dev/null | python3 -c '
import sys, json, os
ROOT = os.environ.get("ROOT_BEAD", "")
try: beads = json.load(sys.stdin)
except Exception: sys.exit(0)
seen = set()
for b in beads:
    t = b.get("title") or ""
    if t.startswith("Step spec") or not t: continue
    md = b.get("metadata") or {}
    # One rig can hold several runs at once. Without this filter another
    # workflow steps appear as this one: it once showed compile and finalize
    # as done when both belonged to a different design.
    if ROOT and md.get("gc.root_bead_id") != ROOT: continue
    # Each step has iteration beads and one logical bead. An iteration may fail
    # and a later one pass, which is the loop working; the logical bead carries
    # the outcome that stands. Show only that one, or a step reads as both done
    # and FAILED at once.
    ref = md.get("gc.step_ref") or ""
    if ".iteration." in ref: continue
    out = md.get("gc.outcome") or ""
    if   out == "pass": label = "done   "
    elif out == "fail": label = "FAILED "
    elif out == "":     label = "closed "
    else:               label = (out[:6] + " ").ljust(7)
    key = (label, t)
    if key in seen: continue
    seen.add(key)
    print("    %s%s" % (label, t))
' 
  gc bd list 2>/dev/null | grep '◐' | grep -vE 'design-authoring|^Status:|^Priority:' \
    | sed 's/^.*P2 /    NOW    /'
  gc bd ready 2>/dev/null | grep '○' | grep -vE 'Step spec|^Status:|^Priority:' \
    | sed 's/^.*P2 /    next   /' | head -3

  echo "  ── artifacts ─────────────────────────────────────"
  local d v f
  d=$(ls "$Q"/*.design 2>/dev/null | head -1)
  if [ -n "$d" ]; then
    printf '    design   %s  %s\n' "$(shasum -a 256 "$d" | cut -c1-12)" "$(basename "$d")"
  else
    printf '    design   not written yet\n'
  fi
  v="$Q/design-audit-verdict.json"
  if [ -f "$v" ]; then
    python3 - "$v" "$d" <<'PY'
import json, sys, hashlib
try: d = json.load(open(sys.argv[1]))
except Exception: print("    verdict  unreadable"); raise SystemExit
defects = d.get("defects") or []
fix = sum(1 for x in defects if x.get("fixable") == "by_revision")
hum = sum(1 for x in defects if x.get("fixable") == "needs_a_person")
subj = (d.get("subject_sha256") or "")[:12]
cur = ""
if len(sys.argv) > 2 and sys.argv[2]:
    try: cur = hashlib.sha256(open(sys.argv[2],"rb").read()).hexdigest()[:12]
    except Exception: pass
fresh = "about THIS design" if subj and subj == cur else f"about {subj or 'nothing'} — STALE"
print(f"    verdict  {d.get('verdict')} by {d.get('audit_model')}: "
      f"{len(defects)} findings, {fix} fixable, {hum} need a person")
print(f"             {fresh}")
PY
  else
    printf '    verdict  none yet — the design has not been audited\n'
  fi
  [ -f "$Q/FINDINGS.md" ] \
    && printf '    findings %s\n' "$Q/FINDINGS.md" \
    || printf '    findings not yet\n'
}

if [ "$FOLLOW" = "--follow" ]; then
  while :; do snapshot; sleep "$INT"; done
else
  snapshot
fi
