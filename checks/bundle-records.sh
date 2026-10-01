#!/usr/bin/env bash
# Gate check: does the emitted bundle actually keep the records its design promised?
#
# A design declares @record. The bundle must have those records wired, not merely
# mentioned. A bundle that reports a ledger it never writes is the same class of
# defect as a gate whose check script does not exist.
#
# Exit 0   the record layer is wired and demonstrably written
# Exit 1   the design promised records the bundle does not keep
# Exit 75  the bundle or the design is not there to check
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
B=${BUNDLE_PATH:-}; D=${DESIGN_PATH:-}
[ -n "$B" ] && [ -n "$D" ] || { echo "BUNDLE_PATH and DESIGN_PATH are not set — the compile step did not record where it wrote." >&2; exit 75; }
[ -d "$B" ] || { echo "no bundle at $B." >&2; exit 75; }
[ -f "$D" ] || { echo "no design at $D." >&2; exit 75; }

fail=0
say() { echo "REFUSED: $1" >&2; fail=1; }

# the design said it records these; the bundle must have them
grep -q "^@record" "$D" || { say "the design declares no @record section."; exit 1; }

[ -f "$B/lib/ledger.sh" ] || say "no lib/ledger.sh — nothing in this bundle can append a transition."
grep -q "ledger()" "$B/lib/ledger.sh" 2>/dev/null || say "lib/ledger.sh defines no ledger() function."
grep -q "unit_row()" "$B/lib/ledger.sh" 2>/dev/null || say "lib/ledger.sh defines no unit_row() function."

# every step must actually call it — a ledger nobody writes to is decoration
for s in "$B"/steps/*.sh; do
  [ -e "$s" ] || continue
  # strip comments first: a commented-out call is not a call, and the obvious
  # pattern matches "#ledger" because # satisfies [^a-z_]
  sed 's/#.*//' "$s" | grep -qE '(^|[^a-z_])ledger[ "]' \
    || say "$(basename "$s") never writes a ledger line."
done

# and the loop must record outcomes per unit
sed 's/#.*//' "$B/run.sh" 2>/dev/null | grep -q "unit_row" \
  || { sed 's/#.*//' "$B"/steps/*.sh 2>/dev/null | grep -q "unit_row"; } \
  || say "nothing in this bundle writes a per-unit outcome."

# prove it by running one tick rather than trusting the greps
( cd "$B" && ./run.sh >/dev/null 2>&1 ) || true
[ -s "$B/memory/ledger.tsv" ] || say "a tick ran and memory/ledger.tsv is empty — the ledger is not wired."
[ -s "$B/memory/units.tsv" ]  || say "a tick ran and memory/units.tsv is empty — no unit outcome was recorded."

if [ "$fail" -ne 0 ]; then
  echo "         Next human action: the design promised these records. Fix the emitter, not the design." >&2
  exit 1
fi
printf 'records wired: %s ledger line(s), %s unit row(s) after one tick\n' \
  "$(( $(grep -c . "$B/memory/ledger.tsv") - 1 ))" "$(( $(grep -c . "$B/memory/units.tsv") - 1 ))"
