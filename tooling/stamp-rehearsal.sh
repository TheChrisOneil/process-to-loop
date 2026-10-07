#!/usr/bin/env bash
# Record on the BEADS whether a design is a rehearsal.
#
#   stamp-rehearsal.sh <artifact_root>
#
# The files already say it: QUESTIONS.md marks each synthetic answer, FINDINGS.md
# opens with it, REHEARSAL lists any gate closed without a person. The beads said
# nothing, and the beads are the system of record — the thing that outlives a
# working directory, that a dashboard reads, and that somebody queries a year
# later asking which designs were ever confirmed by a person.
#
# A design can be a rehearsal two different ways, and they are recorded apart
# because they are different claims:
#
#   synthetic answers   the interview was answered on somebody's behalf
#   rehearsed gates     a gate was closed without a person
#
# Deterministic: reads files, writes metadata, decides nothing.
#
# Exit 0 stamped · 1 refused · 75 could not run
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
R=${1:?usage: stamp-rehearsal.sh <artifact_root>}
[ -d "$R" ] || { echo "no artifact_root at $R" >&2; exit 75; }
R=$(cd "$R" && pwd)
command -v gc >/dev/null || { echo "REFUSED: gc is not on PATH, so nothing can be stamped." >&2; exit 75; }
cd "$R" || exit 75

Q="$R/QUESTIONS.md"
SYN=0; TOT=0
if [ -f "$Q" ] && [ -x "$HERE/questions.sh" ]; then
  TSV=$("$HERE/questions.sh" tsv "$Q" 2>/dev/null)
  TOT=$(printf '%s\n' "$TSV" | grep -c . || true)
  SYN=$(printf '%s\n' "$TSV" | awk -F'\t' '$7=="synthetic"{n++} END{print n+0}')
fi
GATES=0
[ ! -f "$R/REHEARSAL" ] || GATES=$(grep -c . "$R/REHEARSAL" || true)

REH=false
[ "$SYN" -eq 0 ] && [ "$GATES" -eq 0 ] || REH=true

# Which workflow owns this artifact_root? Same resolution run-status uses, so the
# stamp lands on the bead the status screen reports from.
ROOT=$(ARTQ="$R" gc bd list --json 2>/dev/null | ARTQ="$R" python3 -c "
import json, sys, os
q = os.environ.get('ARTQ','')
try: bs = json.load(sys.stdin)
except Exception: raise SystemExit
for b in bs:
    md = b.get('metadata') or {}
    if md.get('gc.kind') == 'workflow' and md.get('gc.var.artifact_root') == q:
        print(b.get('id') or ''); break
" 2>/dev/null)
[ -n "$ROOT" ] || { echo "REFUSED: no workflow names $R as its artifact_root." >&2; exit 75; }

BASIS=""
[ "$SYN" -eq 0 ]   || BASIS="$SYN of $TOT interview answer(s) supplied on the approver's behalf"
if [ "$GATES" -gt 0 ]; then
  [ -z "$BASIS" ] || BASIS="$BASIS; "
  BASIS="$BASIS$GATES gate(s) closed without a person"
fi
[ -n "$BASIS" ] || BASIS="a person answered the interview and closed every gate"

DSHA=""
D=$(ls "$R"/*.design 2>/dev/null | head -1)
[ -z "$D" ] || DSHA=$(shasum -a 256 "$D" | cut -d' ' -f1)

set -- \
  "eb.rehearsal=$REH" \
  "eb.rehearsal.synthetic_answers=$SYN of $TOT" \
  "eb.rehearsal.rehearsed_gates=$GATES" \
  "eb.rehearsal.basis=$BASIS" \
  "eb.rehearsal.design_sha256=$DSHA" \
  "eb.rehearsal.stamped_at=$(date -u +%FT%TZ)"

# The stamp goes on the workflow root AND on every open gate bead for this run.
# A person lands on the gate they are being asked to close, not on the root, and
# a mark they have to go looking for is a mark that does its job for nobody.
TARGETS="$ROOT"
for g in $(gc bd gate list 2>/dev/null | awk '/^○ /{print $2}'); do
  owner=$(gc bd show "$g" --json 2>/dev/null | python3 -c '
import json,sys
try: b=json.load(sys.stdin)
except Exception: raise SystemExit
b=b[0] if isinstance(b,list) else b
print((b.get("metadata") or {}).get("gc.root_bead_id",""))' 2>/dev/null)
  [ "$owner" = "$ROOT" ] && TARGETS="$TARGETS $g"
done

N=0
for t in $TARGETS; do
  for kv in "$@"; do gc bd update "$t" --set-metadata "$kv" >/dev/null 2>&1 || true; done
  N=$((N+1))
done

echo "stamped $N bead(s) for $ROOT: eb.rehearsal=$REH"
echo "  $BASIS"
[ "$REH" = "false" ] || echo "  This design is a REHEARSAL. The beads now say so, and will after the files are gone."
