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

snapshot() {
  printf '\n%s\n' "$(date '+%H:%M:%S')"
  echo "  ── steps ─────────────────────────────────────────"
  gc bd list --status closed 2>/dev/null | grep '✓' | grep -vE 'Step spec|^Status:|^Priority:' \
    | sed 's/^.*task /    done   /' | sort -u
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
