#!/usr/bin/env bash
# Run the check-authoring workflow without a city.
#
#   run-authoring.sh <design> <gate-number> [--out <dir>]
#
# Same steps, same prompts and the same deterministic gates as
# formulas/check-authoring.toml. For anyone who wants to exercise the two model
# lanes before standing up a city — and for proving the prompts work at all.
#
# The orchestrator is what this does not do: no beads, no retries, no human
# gate bead. It stops at the point a person would be asked.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
DESIGN=${1:-}; N=${2:-}; OUT="run"
shift 2 2>/dev/null || true
while [ $# -gt 0 ]; do case "$1" in --out) OUT=${2:-}; shift 2 ;; *) shift ;; esac; done
[ -n "$DESIGN" ] && [ -n "$N" ] || { echo "run-authoring.sh <design> <gate-number> [--out <dir>]" >&2; exit 64; }
[ -f "$DESIGN" ] || { echo "REFUSED: no design at $DESIGN." >&2; exit 1; }
command -v claude >/dev/null || { echo "REFUSED: the claude CLI is not installed." >&2; exit 1; }

AUTHOR_MODEL=${AUTHOR_MODEL:-claude-opus-5}
AUDIT_MODEL=${AUDIT_MODEL:-claude-sonnet-5}
[ "$AUTHOR_MODEL" != "$AUDIT_MODEL" ] || { echo "REFUSED: AUTHOR_MODEL and AUDIT_MODEL are the same." >&2
  echo "         Next human action: set AUDIT_MODEL to a different model. Two lanes on one model" >&2
  echo "         produce correlated blind spots, and the review then looks like agreement." >&2; exit 1; }

NN=$(printf '%02d' "$N")
mkdir -p "$OUT"
SCRIPT="$OUT/gate-$NN.sh"; FIX="$OUT/gate-$NN.fixtures.tsv"; VERDICT="$OUT/audit-verdict.json"
LEDGER="$OUT/usage.tsv"
[ -s "$LEDGER" ] || printf 'date\tstage\tmodel\tin\tout\tusd\n' > "$LEDGER"

say() { printf '\n  %s\n' "$*"; }
usage_row() {  # $1 raw json, $2 stage, $3 model
  printf '%s' "$1" | python3 -c '
import json,sys,datetime
d=json.load(sys.stdin); u=d.get("usage") or {}
print("\t".join([datetime.date.today().isoformat(), sys.argv[1], sys.argv[2],
  str(u.get("input_tokens","unknown")), str(u.get("output_tokens","unknown")),
  str(d.get("total_cost_usd","unknown"))]))' "$2" "$3" >> "$LEDGER" 2>/dev/null || true
}

# ---- 1. load-gate
ROW=$(awk -f "$HERE/tooling/lib/parse.awk" -f "$HERE/tooling/lib/gates.awk" "$DESIGN" | awk -F'\t' -v n="$N" '$1==n+0')
[ -n "$ROW" ] || { echo "REFUSED: $DESIGN has no gate $N." >&2; exit 1; }
COND=$(printf '%s' "$ROW" | cut -f2); REF=$(printf '%s' "$ROW" | cut -f3)
awk -f "$HERE/tooling/lib/fixtures.awk" -v N="$NN" -v COND="$COND" -v REFUSAL="$REF" /dev/null > "$FIX"
say "gate $NN"
printf '    condition: %s\n    refusal:   %s\n' "$COND" "$REF"
ROWS=$(awk -F'\t' '!/^#/ && $1!="name" && NF>2' "$FIX" | wc -l | tr -d ' ')
UND=$(awk -F'\t' '!/^#/ && $1!="name" && $3=="declare"' "$FIX" | wc -l | tr -d ' ')
printf '    fixtures:  %s rows, %s still undeclared\n' "$ROWS" "$UND"

# ---- 2. author-check
say "authoring with $AUTHOR_MODEL … (this spends tokens)"
cat > "$OUT/prompt-author.txt" <<EOF
Write a bash check script for one gate of a business process, and output ONLY the
script. No commentary, no markdown fences. It must start with #!/usr/bin/env bash.

THE CONDITION, which describes WHAT REFUSES:
  $COND

THE REFUSAL, which must name the next human action:
  $REF

The contract:
  the condition holds     -> exit non-zero, refusal on stderr
  the condition does not  -> exit 0
  the check cannot run    -> exit 75, and ONLY for that

The script's arguments are fixed:
  \$1  the unit id, for the message only
  \$2  the value the condition compares

A real check reads anything else it needs from the unit record or from
configuration. Never from model output, including your own.

It must satisfy this fixture table exactly. Rows marked declare are boundaries
nobody has decided; decide them, and be prepared to say which way and why in a
comment at the top of the script.

$(cat "$FIX")

Read every value from \$1 or from configuration, never from model output.
EOF
RAW=$(claude -p --model "$AUTHOR_MODEL" --output-format json < "$OUT/prompt-author.txt" 2>/dev/null)
usage_row "$RAW" author "$AUTHOR_MODEL"
printf '%s' "$RAW" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("result",""))' \
  | sed '/^```/d' > "$SCRIPT"
chmod +x "$SCRIPT"
printf '    wrote %s (%s lines)\n' "$SCRIPT" "$(wc -l < "$SCRIPT" | tr -d ' ')"

# ---- 3. selftest gate
say "selftest — deterministic, no model"
CHECK_SCRIPT="$SCRIPT" CHECK_FIXTURES="$FIX" "$HERE/checks/selftest-gate.sh"
SELFTEST=$?

# ---- 4. audit-check
say "auditing with $AUDIT_MODEL … (a different model, on purpose)"
cat > "$OUT/prompt-audit.txt" <<EOF
You did not write this script. Find what is wrong with it. A review that finds
nothing and says so in one line is worthless; if you genuinely find nothing, say
what you checked.

THE GATE CONDITION, which describes WHAT REFUSES:
  $COND
THE REFUSAL:
  $REF

THE SCRIPT:
$(cat "$SCRIPT")

THE FIXTURES it must satisfy:
$(cat "$FIX")

Cover all five of these by name:
  polarity         does it refuse when the condition HOLDS and proceed when it does not?
  boundary         at exactly the threshold, which way does it go, and is that right?
  source-of-truth  where does each value come from? A value taken from model output is a finding.
  exit-75          is 75 used ONLY for "the check could not run"?
  refusal-text     does the refusal name a next human action?

Output ONLY JSON, no fences:
{"author_model":"$AUTHOR_MODEL","audit_model":"$AUDIT_MODEL",
 "verdict":"sound"|"defective",
 "checked":["polarity","boundary","source-of-truth","exit-75","refusal-text"],
 "defects":[{"severity":"critical"|"major"|"minor","what":"...","why":"..."}],
 "confidence":"high"|"medium"|"low"}
EOF
RAW=$(claude -p --model "$AUDIT_MODEL" --output-format json < "$OUT/prompt-audit.txt" 2>/dev/null)
usage_row "$RAW" audit "$AUDIT_MODEL"
printf '%s' "$RAW" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("result",""))' \
  | sed '/^```/d' > "$VERDICT"

# ---- 5. audit-verdict gate
say "audit verdict — deterministic, the auditor does not grade itself"
AUDIT_VERDICT="$VERDICT" "$HERE/checks/audit-verdict.sh"
AUDITGATE=$?

say "what it cost"
column -t -s$'\t' "$LEDGER" 2>/dev/null | sed 's/^/    /' || cat "$LEDGER"

say "where it stops"
echo "    A person would now be asked to accept $SCRIPT."
echo "    In the formula that is a gate bead nothing passes until they close it."
[ "$SELFTEST" -eq 0 ] && [ "$AUDITGATE" -eq 0 ] || exit 1
