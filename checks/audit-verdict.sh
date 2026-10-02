#!/usr/bin/env bash
# Gate check: is the audit real, and did it come from a different model?
#
# Serves both lanes. AUDIT_DIMENSIONS names the dimensions the audit had to
# cover; it defaults to the gate-check set.
#
# This decides whether the audit passed. The auditor does not. A model that
# grades its own review is one opinion twice.
#
# Exit 0   the verdict is well formed, the lanes were genuinely different,
#          and either it found no defect or every defect is described
# Exit 1   the verdict is malformed, self-graded, empty of content, or is
#          about an artifact other than the one being gated
# Exit 75  the check could not run: no JSON parser, or AUDIT_SUBJECT unset
#          so freshness cannot be established
set -uo pipefail
V=${AUDIT_VERDICT:-}
[ -n "$V" ] || { echo "AUDIT_VERDICT is not set — the audit step recorded nothing." >&2; exit 75; }
[ -f "$V" ] || { echo "no verdict at $V — the audit step produced no output." >&2; exit 75; }

# FRESHNESS. A verdict is about one artifact. This gate used to check only that
# the audit was well formed and cross-model — both of which a verdict about a
# DIFFERENT design satisfies. On 2026-10-02 a run reached this gate with
# yesterday's verdict on disk and the gate had nothing to say about it.
S=${AUDIT_SUBJECT:-}
if [ -z "$S" ]; then
  echo "AUDIT_SUBJECT is not set, so this gate cannot tell whether the verdict at" >&2
  echo "$V describes the artifact being gated or some earlier one." >&2
  echo "This check cannot run. It is not a business failure." >&2
  echo "Next human action: set AUDIT_SUBJECT to the path of the audited file." >&2
  exit 75
fi
[ -f "$S" ] || { echo "AUDIT_SUBJECT points at $S, which is not there." >&2; exit 75; }
if ! command -v shasum >/dev/null 2>&1; then
  echo "no shasum on this host, so freshness cannot be verified." >&2; exit 75
fi
WANT=$(shasum -a 256 "$S" | awk '{print $1}')
GOT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("subject_sha256") or "")' "$V" 2>/dev/null)
if [ -z "$GOT" ]; then
  echo "REFUSED: the verdict at $V names no subject_sha256, so there is no way to" >&2
  echo "         tell what it audited. Treating it as not an audit of $S." >&2
  echo "         Next human action: re-run the audit against the current design." >&2
  exit 1
fi
if [ "$GOT" != "$WANT" ]; then
  echo "REFUSED: the verdict is about a different artifact than the one being gated." >&2
  echo "           gated:  $S" >&2
  echo "                   $WANT" >&2
  echo "           verdict describes:" >&2
  echo "                   $GOT" >&2
  echo "         A stale verdict passes every other test in this file: it is well" >&2
  echo "         formed, cross-model, and complete. It is simply about something else." >&2
  echo "         Next human action: re-run the audit against the current design." >&2
  exit 1
fi

if   command -v python3 >/dev/null 2>&1; then P=python3
elif command -v jq      >/dev/null 2>&1; then P=jq
else echo "no JSON parser on this host, so the verdict cannot be read. This is not a business failure." >&2; exit 75; fi

if [ "$P" = python3 ]; then
python3 - "$V" <<'PY'
import json, sys
import os
REQUIRED = set((os.environ.get("AUDIT_DIMENSIONS") or
                "polarity,boundary,source-of-truth,exit-75,refusal-text").split(","))
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"REFUSED: the verdict is not valid JSON ({e}).", file=sys.stderr)
    print("         Next human action: re-run the audit; its output did not conform.", file=sys.stderr)
    sys.exit(1)

def bad(msg, action):
    print(f"REFUSED: {msg}", file=sys.stderr)
    print(f"         Next human action: {action}", file=sys.stderr)
    sys.exit(1)

am, um = d.get("author_model"), d.get("audit_model")
if not am or not um:
    bad("the verdict does not say which models authored and audited.",
        "re-run the audit with author_model and audit_model recorded.")
if am == um:
    bad(f"the same model ({am}) authored and audited this check.",
        "set audit_model to a different model, and run the audit again. "
        "Two lanes on one model produce correlated blind spots, and the review then "
        "looks like agreement when it is one opinion twice.")

verdict = d.get("verdict")
if verdict not in ("sound", "defective"):
    bad(f"verdict is {verdict!r}, which is neither sound nor defective.",
        "re-run the audit; it must reach one of the two verdicts.")

checked = set(d.get("checked") or [])
missing = REQUIRED - checked
if missing:
    bad("the audit did not cover: " + ", ".join(sorted(missing)) + ".",
        "re-run the audit against every required dimension. A skipped dimension is "
        "a review that did not happen.")

defects = d.get("defects") or []
if verdict == "defective":
    # A defective verdict is NOT a reason to refuse. This gate asks whether the
    # audit was real — a different model, every dimension covered, each defect
    # described. What to DO about the findings is a person's decision, and the
    # findings step puts them in front of one.
    if not defects:
        bad("the verdict is defective but names no defect.",
            "re-run the audit; a defective verdict must say what is wrong.")
    for i, x in enumerate(defects):
        for key in ("severity", "what", "why"):
            if not x.get(key):
                bad(f"defect {i} has no {key}.",
                    "re-run the audit; every defect states its severity, what it is, and why it matters.")
    crit = [x for x in defects if x.get("severity") == "critical"]
    print(f"audit passed: {am} authored, {um} audited. "
          f"{len(defects)} defect(s) found, {len(crit)} critical — "
          f"the findings step takes these to a person.")
    sys.exit(0)

print(f"audit passed: {am} authored, {um} audited, {len(checked)} dimensions covered.")
PY
else
  jq -e '.author_model and .audit_model and (.author_model != .audit_model) and (.verdict == "sound")' "$V" >/dev/null 2>&1 || {
    echo "REFUSED: the verdict is malformed, self-graded, or not sound." >&2
    echo "         Next human action: read $V, fix the check, and run the workflow again." >&2; exit 1; }
  echo "audit passed (jq path — the python path reports more)."
fi
