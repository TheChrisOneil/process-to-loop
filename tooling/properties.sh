#!/usr/bin/env bash
# design + step id -> the properties that step's declared type promises.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
D=${1:-}; ID=${2:-}
[ -n "$D" ] && [ -n "$ID" ] || { echo "properties.sh <design> <step-id>" >&2; exit 64; }
[ -f "$D" ] || { echo "REFUSED: no design at $D." >&2; exit 1; }
PLAN=$(awk -f "$HERE/lib/parse.awk" -f "$HERE/lib/emit-plan.awk" "$D")
EVID=$(printf '%s\n' "$PLAN" | awk -F'\t' '$1=="meta" && $2=="evidence_step"{print $3}')
ROW=$(printf '%s\n' "$PLAN" | awk -F'\t' -v i="$ID" '$1=="step" && $2==i')
[ -n "$ROW" ] || { echo "REFUSED: $D has no step $ID." >&2
                   echo "         Next human action: run make design DESIGN=$D to see the steps." >&2; exit 1; }
IFS=$'\t' read -r _ SID SLUG TYPE ACTOR DESC SCOPE <<<"$ROW"
awk -f "$HERE/lib/step-properties.awk" -v ID="$SID" -v SLUG="$SLUG" -v TYPE="$TYPE" \
    -v ACTOR="$ACTOR" -v SCOPE="$SCOPE" -v EVIDENCE_STEP="$EVID" /dev/null
