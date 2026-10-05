#!/usr/bin/env bash
# Close an acceptance gate in the ptl rig, and ONLY there.
#
#   close-acceptance.sh <gate-bead-id>
#
# Narrow on purpose. The harness refuses an agent closing a human-approval gate,
# which is correct: an acceptance register whose gate an agent can close on
# verbal say-so measures something other than what it claims. This exists so the
# permission granted is one command against one rig, not `gc bd close`.
#
# It refuses unless the design is already in the acceptance register, so the
# signature leads and the gate follows — never the reverse. It records that the
# close was made on standing instruction, not reviewed in person.
#
# Exit 0 closed · 1 refused · 64 wrong arguments
set -uo pipefail
RIG="$HOME/cities/ptl-rig"
GATE=${1:?usage: close-acceptance.sh <gate-bead-id>}
case "$GATE" in wk-*) ;; *) echo "refusing: $GATE is not a wk- bead in the ptl rig" >&2; exit 64 ;; esac

cd "$RIG" 2>/dev/null || { echo "no ptl rig at $RIG" >&2; exit 64; }

JSON=$(gc bd show "$GATE" --json 2>/dev/null) || { echo "no bead $GATE" >&2; exit 1; }
read -r TYPE STATUS ROOT <<<"$(printf '%s' "$JSON" | python3 -c '
import json,sys
b=json.load(sys.stdin); b=b[0] if isinstance(b,list) else b
md=b.get("metadata") or {}
print(b.get("issue_type",""), b.get("status",""), md.get("gc.root_bead_id",""))')"

[ "$TYPE" = "gate" ] || { echo "refusing: $GATE is a $TYPE, not a gate" >&2; exit 1; }
[ "$STATUS" = "open" ] || { echo "refusing: $GATE is already $STATUS" >&2; exit 1; }

DESIGN=$(gc bd show "$ROOT" --json 2>/dev/null | python3 -c '
import json,sys
b=json.load(sys.stdin); b=b[0] if isinstance(b,list) else b
print((b.get("metadata") or {}).get("gc.var.design_path",""))')
[ -f "$DESIGN" ] || { echo "refusing: the workflow names no design on disk" >&2; exit 1; }

# The signature must already exist. The gate follows the register, never leads it.
ST=$("$HOME/software/process-to-loop/tooling/accept.sh" --status "$DESIGN" 2>&1)
case "$ST" in
  ACCEPTED*) ;;
  *) echo "refusing: $DESIGN is not in the acceptance register." >&2
     echo "          Sign it first with accept.sh, then close the gate." >&2
     exit 1 ;;
esac
SHA=$(shasum -a 256 "$DESIGN" | cut -c1-16)

gc bd update "$GATE" --set-metadata 'gc.outcome=pass' >/dev/null 2>&1
gc bd close "$GATE" --reason "Acceptance gate closed for design $SHA. Signature is in the acceptance register; this close followed it. Closed by the assistant on Buzz's standing instruction — NOT reviewed in person at the gate." 2>&1 | tail -1
