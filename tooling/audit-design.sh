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

# The credential, before the model call, so a missing key is reported as a
# missing key rather than as an empty answer from the provider.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$HERE/credential.sh"
case "$AP" in
  gemini) load_credential GEMINI_API_KEY    process-to-loop-gemini || exit 75 ;;
  claude) : ;;   # the claude CLI carries its own session auth
esac

P=$(mktemp)
cat > "$P" <<EOF
You did not write this design, and it has already passed its rules. That tells
you it is well formed. It does not tell you it is right, and the difference is
your entire job. Find what is wrong with it.

THE DESCRIBED PROCESS:
$(cat "$U")

THE DESIGN:
$(cat "$D")

Cover all seven by name: unit-of-work, judgment-isolated, gate-coverage,
refusal-quality, evidence-chain, exit-criterion, source-integrity.

On source-integrity, the rules already check that every source is catalogued and
that no PHI tool is used by a model step. They cannot check these, so you must:
does every value a gate compares actually come from a declared source, or does
the design compare something it never obtained? Is any stated constraint
unverifiable as written — a sentence that reads like a control and could never
be evaluated? Does a redaction step actually stand between a PHI source and any
model step, or is the model merely trusted not to look?

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
 "checked":["unit-of-work","judgment-isolated","gate-coverage","refusal-quality","evidence-chain","exit-criterion","source-integrity"],
 "defects":[{"severity":"critical"|"major"|"minor","fixable":"by_revision"|"needs_a_person","what":"...","why":"..."}],
 "confidence":"high"|"medium"|"low"}
EOF

ERR=$(mktemp)
case "$AP" in
  # GEMINI_CLI_TRUST_WORKSPACE: the CLI refuses to run in an untrusted directory
  # and exits 55 with no output. The documented route for headless use. The audit
  # prompt is self-contained — the design and use case are read by this script and
  # passed as text — so the CLI needs nothing from the workspace it starts in.
  gemini)
    # The CLI is a node script with `#!/usr/bin/env node`. Installed under nvm it
    # sits beside the node it was built for, and whichever node happens to be
    # first on PATH may be older: v18 cannot parse the `v` regex flag the bundle
    # uses and dies with SyntaxError before printing anything. Put the CLI's own
    # bin directory first so it gets its own runtime.
    GEM_BIN=$(dirname "$(command -v gemini)")
    RAW=$(cd "$(dirname "$D")" && PATH="$GEM_BIN:$PATH" GEMINI_CLI_TRUST_WORKSPACE=true \
          gemini -m "$AM" -p "$(cat "$P")" 2>"$ERR") ;;
  claude) RAW=$(claude -p --model "$AM" --output-format json < "$P" 2>"$ERR" \
                | python3 -c 'import json,sys;print(json.load(sys.stdin).get("result",""))' 2>>"$ERR") ;;
  *) echo "REFUSED: no invocation known for provider $AP." >&2; rm -f "$P" "$ERR"; exit 75 ;;
esac
RC=$?
rm -f "$P"

# A provider that failed or said nothing is an audit that did not happen. That is
# infrastructure (75), not a defective design, and it must not cost an attempt.
# Report what the provider actually said: this gate used to close silently.
if [ "$RC" -ne 0 ] || [ -z "${RAW//[[:space:]]/}" ]; then
  echo "REFUSED: the audit did not run. $AP exited $RC and returned ${#RAW} bytes." >&2
  if [ -s "$ERR" ]; then
    echo "         $AP said:" >&2
    head -20 "$ERR" | sed 's/^/           /' >&2
  else
    echo "         $AP said nothing on stderr either." >&2
  fi
  echo "         The verdict was NOT written. $OUT is unchanged." >&2
  echo "         Next human action: run \`$AP -m $AM -p hello\` by hand and read the error." >&2
  rm -f "$ERR"
  exit 75
fi
rm -f "$ERR"
# Validate BEFORE replacing the verdict on disk. Writing first and checking
# second leaves a malformed verdict where a stale-but-wellformed one was, and
# makes the refusal below a lie. A later step reads this file and trusts it.
TMPV=$(mktemp)
printf '%s' "$RAW" | sed '/^```/d' > "$TMPV"
if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMPV" 2>/dev/null; then
  echo "REFUSED: $AP returned $(wc -c <"$TMPV" | tr -d ' ') bytes that are not JSON." >&2
  echo "         The audit ran; its answer is unusable. $OUT is UNCHANGED." >&2
  echo "         What it returned, first 20 lines:" >&2
  head -20 "$TMPV" | sed 's/^/           /' >&2
  rm -f "$TMPV"
  exit 1
fi
# Stamp what was audited. A verdict that cannot be tied to a specific design is
# a verdict about nothing: today a run found a well-formed verdict on disk that
# described a DIFFERENT design, and only the findings step noticed.
SUBJ_SHA=$(shasum -a 256 "$D" | awk '{print $1}')
python3 - "$TMPV" "$SUBJ_SHA" "$D" <<'PY3'
import json, sys, datetime
f, sha, path = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(f))
d["subject_sha256"] = sha
d["subject_path"]   = path
d["audited_at"]     = datetime.datetime.now(datetime.timezone.utc).isoformat()
json.dump(d, open(f, "w"), indent=1)
PY3
mv "$TMPV" "$OUT"
python3 - "$OUT" <<'PY2'
import json, sys
d = json.load(open(sys.argv[1]))
defects = d.get("defects") or []
fixable = sum(1 for x in defects if x.get("fixable") == "by_revision")
print("audited by {}: {}, {} finding(s), {} fixable by revision".format(
    d.get("audit_model"), d.get("verdict"), len(defects), fixable))
PY2
