#!/usr/bin/env bash
# Close a human gate as a REHEARSAL, in the ptl rig and nowhere else.
#
#   rehearse-gate.sh <gate-bead-id> --by <who> [--why <reason>]
#
# A pipeline has two questions in it and they are not the same question:
#
#   does the machinery work?        answerable without a person
#   is this design right?           answerable only by a person
#
# Blocking the first on the second is what left a run parked for four hours with
# every upstream step green. So a gate may be closed without a person — and the
# ARTIFACT carries the mark, permanently, exactly as a synthetic interview answer
# does. The run proceeds; nothing can later be mistaken for the real thing.
#
# What a rehearsal costs, and these are the whole of the design:
#
#   1. The bead records gc.rehearsed=true, by whom, when.
#   2. artifact_root/REHEARSAL lists every gate closed this way. It is append
#      only and no tool here removes it.
#   3. accept.sh records a rehearsed acceptance AS rehearsed, so the register
#      never claims a signature it did not get.
#   4. compile REFUSES to emit a bundle from a rehearsed acceptance. You may
#      rehearse the entire pipeline. You may not ship out of a rehearsal.
#
# Remove 4 and this becomes the thing this project exists to catch: a control
# that is declared, reported, and absent.
#
# Exit 0 closed as rehearsed · 1 refused · 64 wrong arguments
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RIG="$HOME/cities/ptl-rig"
GATE=${1:-}; shift 2>/dev/null || true
BY=""; WHY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --by)  BY=${2:-}; shift 2 ;;
    --why) WHY=${2:-}; shift 2 ;;
    *) echo "REFUSED: unknown option $1" >&2; exit 64 ;;
  esac
done
[ -n "$GATE" ] || { echo "usage: rehearse-gate.sh <gate-bead-id> --by <who> [--why <reason>]" >&2; exit 64; }
[ -n "$BY" ]   || { echo "REFUSED: --by is required. A rehearsal with no name is an unexplained pass." >&2; exit 64; }
case "$GATE" in wk-*) ;; *) echo "REFUSED: $GATE is not a wk- bead in the ptl rig" >&2; exit 64 ;; esac
cd "$RIG" 2>/dev/null || { echo "REFUSED: no ptl rig at $RIG" >&2; exit 64; }

JSON=$(gc bd show "$GATE" --json 2>/dev/null) || { echo "REFUSED: no bead $GATE" >&2; exit 1; }
read -r TYPE STATUS ROOT <<<"$(printf '%s' "$JSON" | python3 -c '
import json,sys
b=json.load(sys.stdin); b=b[0] if isinstance(b,list) else b
md=b.get("metadata") or {}
print(b.get("issue_type",""), b.get("status",""), md.get("gc.root_bead_id",""))')"
[ "$TYPE" = "gate" ] || { echo "REFUSED: $GATE is a $TYPE, not a gate." >&2; exit 1; }
[ "$STATUS" = "open" ] || { echo "REFUSED: $GATE is already $STATUS." >&2; exit 1; }

ART=$(gc bd show "$ROOT" --json 2>/dev/null | python3 -c '
import json,sys
b=json.load(sys.stdin); b=b[0] if isinstance(b,list) else b
print((b.get("metadata") or {}).get("gc.var.artifact_root",""))')
[ -n "$ART" ] && [ -d "$ART" ] || { echo "REFUSED: the workflow names no artifact_root on disk, so the mark has nowhere to live." >&2; exit 1; }

# The mark is written BEFORE the gate closes. A gate closed with no mark beside
# it is the failure this is built to avoid, and the order is what guarantees it.
WHEN=$(date -u +%FT%TZ)
{ printf '%s\t%s\t%s\t%s\t%s\n' "$WHEN" "$GATE" "${TITLE:-gate}" "$BY" "${WHY:-no reason given}"
} >> "$ART/REHEARSAL"
[ -s "$ART/REHEARSAL" ] || { echo "REFUSED: could not write $ART/REHEARSAL. Nothing was closed." >&2; exit 1; }

gc bd update "$GATE" --set-metadata 'gc.outcome=pass' >/dev/null 2>&1
gc bd update "$GATE" --set-metadata 'gc.rehearsed=true' >/dev/null 2>&1
gc bd update "$GATE" --set-metadata "gc.rehearsed_by=$BY" >/dev/null 2>&1
gc bd update "$GATE" --set-metadata "gc.rehearsed_at=$WHEN" >/dev/null 2>&1

OUT=$(gc bd close "$GATE" --reason "REHEARSED — closed without a person by $BY at $WHEN. ${WHY:-No reason given.} This run is a rehearsal of the machinery, not an approval of the design. See $ART/REHEARSAL. Nothing may be compiled or shipped from it." 2>&1)
RC=$?
printf '%s\n' "$OUT" | tail -1

# The mark is written BEFORE the close so a closed gate always has one. The
# failure that completes the invariant is this one: a close that did not happen,
# leaving a mark that says a rehearsal did. A record claiming something that
# never occurred is worse than no record — it is the defect this whole project
# exists to catch, inside the tool written to be honest about rehearsals.
#
# So the two are atomic: both present, or neither. On a failed close the line
# just appended is removed and this refuses.
if [ "$RC" -ne 0 ] || printf '%s' "$OUT" | grep -qi 'cannot close\|refus\|error'; then
  TMPR=$(mktemp)
  grep -vF "	$GATE	" "$ART/REHEARSAL" > "$TMPR" 2>/dev/null || :
  if [ -s "$TMPR" ]; then cat "$TMPR" > "$ART/REHEARSAL"; else rm -f "$ART/REHEARSAL"; fi
  rm -f "$TMPR"
  gc bd update "$GATE" --set-metadata 'gc.rehearsed=' >/dev/null 2>&1
  gc bd update "$GATE" --set-metadata 'gc.outcome=' >/dev/null 2>&1
  echo "REFUSED: the gate did not close, so the mark was removed." >&2
  echo "         A REHEARSAL record for a rehearsal that did not happen is a false" >&2
  echo "         record, and worse than none. Nothing was changed." >&2
  exit 1
fi

echo "marked: $ART/REHEARSAL"
echo "compile will refuse this run. That is the point."
