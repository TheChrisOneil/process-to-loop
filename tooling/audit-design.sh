#!/usr/bin/env bash
# Run the adversarial audit of a design, on a provider other than the author's.
#
#   audit-design.sh <design> <use-case> <out-verdict.json>
#
# env: AUDIT_PROVIDER (default gemini), AUDIT_MODEL, AUTHOR_MODEL
#
# Deterministic about WHO audits; the audit itself is a model call. The caller
# decides what to do with the verdict — this only produces it.
set -uo pipefail
D=${1:?design}; U=${2:?use-case}; OUT=${3:?out}
AP=${AUDIT_PROVIDER:-gemini}; AM=${AUDIT_MODEL:-gemini-3.8-flash}; AUM=${AUTHOR_MODEL:-unknown}
[ -f "$D" ] && [ -f "$U" ] || { echo "no design or use case to audit." >&2; exit 75; }
[ "$AM" != "$AUM" ] || { echo "REFUSED: the audit model and the author model are both $AM." >&2
  echo "         Two lanes on one model produce correlated blind spots." >&2; exit 1; }
command -v "$AP" >/dev/null || { echo "REFUSED: the $AP CLI is not installed." >&2; exit 75; }

P=$(mktemp)
cat > "$P" <<EOF
You did not write this design, and it has already passed its rules. That tells
you it is well formed. It does not tell you it is right, and the difference is
your entire job. Find what is wrong with it.

THE DESCRIBED PROCESS:
$(cat "$U")

THE DESIGN:
$(cat "$D")

Cover all six by name: unit-of-work, judgment-isolated, gate-coverage,
refusal-quality, evidence-chain, exit-criterion.

For EVERY defect decide whether a revision of the design can fix it:
  "by_revision"     the author can fix this from what the description already
                    says — a wrong number, a missing gate, an unsummed value,
                    an ambiguity the description actually resolves
  "needs_a_person"  fixing it requires information or a decision that is not in
                    the description — a policy nobody has written, a business
                    rule only the owner knows, a genuine ambiguity in the
                    process itself

That classification routes the finding, so be strict: if you would be guessing
at the business, it needs a person.

Output ONLY JSON, no fences:
{"author_model":"$AUM","audit_model":"$AM","verdict":"sound"|"defective",
 "checked":["unit-of-work","judgment-isolated","gate-coverage","refusal-quality","evidence-chain","exit-criterion"],
 "defects":[{"severity":"critical"|"major"|"minor","fixable":"by_revision"|"needs_a_person","what":"...","why":"..."}],
 "confidence":"high"|"medium"|"low"}
EOF

case "$AP" in
  gemini) RAW=$(cd "$(dirname "$D")" && gemini -m "$AM" -p "$(cat "$P")" 2>/dev/null) ;;
  claude) RAW=$(claude -p --model "$AM" --output-format json < "$P" 2>/dev/null \
                | python3 -c 'import json,sys;print(json.load(sys.stdin).get("result",""))' 2>/dev/null) ;;
  *) echo "REFUSED: no invocation known for provider $AP." >&2; rm -f "$P"; exit 75 ;;
esac
rm -f "$P"
printf '%s' "$RAW" | sed '/^```/d' > "$OUT"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$OUT" 2>/dev/null || {
  echo "REFUSED: $AP did not return valid JSON; the verdict was not written." >&2
  echo "         Next human action: read $OUT and re-run the audit." >&2; exit 1; }
python3 - "$OUT" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1]))
defects = d.get("defects") or []
fixable = sum(1 for x in defects if x.get("fixable") == "by_revision")
print("audited by {}: {}, {} finding(s), {} fixable by revision".format(
    d.get("audit_model"), d.get("verdict"), len(defects), fixable))
PY2
