#!/usr/bin/env bash
# An audit verdict -> FINDINGS.md beside the design, and appended to the brief.
#
#   findings.sh <verdict.json> <design> [--brief <BRIEF.md>] [--questions <QUESTIONS.md>]
#
# The person who has to act on a finding should not have to know a file path or
# read JSON. Deterministic: no model.
#
# With --questions, the interview contributes findings of its own, and they are
# not the auditor's:
#
#   a DELEGATED STRUCTURAL answer  -> major. The owner was asked for the highest
#                                     leverage decision in the design and told
#                                     the system to choose. They see what was
#                                     chosen before they sign, or delegation is
#                                     just a silent assumption with better
#                                     paperwork.
#   an UNANSWERED question         -> minor, naming who owes it.
#   a SYNTHETIC answer             -> major. Nobody confirmed it.
#
# Delegation defers a decision to the acceptance gate rather than removing it.
# This is the part that does the deferring.
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
V=${1:-}; D=${2:-}; BRIEF=""; QF=""
shift 2 2>/dev/null || true
while [ $# -gt 0 ]; do case "$1" in
  --brief) BRIEF=${2:-}; shift 2 ;;
  --questions) QF=${2:-}; shift 2 ;;
  *) shift ;;
esac; done
[ -n "$V" ] && [ -n "$D" ] || { echo "findings.sh <verdict.json> <design> [--brief <BRIEF.md>]" >&2; exit 64; }
[ -f "$V" ] || { echo "REFUSED: no verdict at $V." >&2; exit 75; }
[ -f "$D" ] || { echo "REFUSED: no design at $D." >&2; exit 75; }
command -v python3 >/dev/null || { echo "REFUSED: no python3 to read the verdict." >&2; exit 75; }
OUT="$(cd "$(dirname "$D")" && pwd)/FINDINGS.md"
[ -n "$BRIEF" ] || BRIEF="$(cd "$(dirname "$D")" && pwd)/BRIEF.md"

# The interview, flattened for python. The awk parser stays the one source of
# truth about what a question file says — this is a read of it, not a second one.
QTSV=""
if [ -n "$QF" ] && [ -f "$QF" ]; then
  QTSV=$(mktemp)
  "$HERE/questions.sh" tsv "$QF" > "$QTSV" 2>/dev/null || : > "$QTSV"
fi

python3 - "$V" "$D" "$OUT" "${QTSV:-}" <<'PY'
import json, sys, pathlib, datetime
v, design, out = sys.argv[1], sys.argv[2], sys.argv[3]
qtsv = sys.argv[4] if len(sys.argv) > 4 else ""
d = json.load(open(v))
defects = d.get("defects") or []

# What the interview contributes. These are findings about the DESIGN PROCESS,
# not about the design, and they are marked so nobody mistakes one for the
# other. They always need a person: that is the whole reason they are here.
interview = []
tally = {"stated": 0, "delegated": 0, "unanswered": 0, "synthetic": 0, "total": 0}
if qtsv:
    try:
        rows = [r.split("\t") for r in open(qtsv).read().splitlines() if r.strip()]
    except Exception:
        rows = []
    for r in rows:
        r = (r + [""] * 8)[:8]
        qid, qclass, qtype, qby, qdate, qvalue, qprov, qasks = r
        tally["total"] += 1
        if qtype in tally: tally[qtype] += 1
        if qprov == "synthetic": tally["synthetic"] += 1
        if qtype == "delegated" and qclass == "structural":
            interview.append({
                "severity": "major", "fixable": "needs_a_person", "source": "interview",
                "what": f"[{qid}] You delegated a structural choice: {qasks}",
                "why": (f"The design assumed **{qvalue.removeprefix('assumed:').strip()}**. "
                        f"A structural answer decides the shape of everything downstream, and this one "
                        f"was chosen on your behalf on {qdate}. Confirm it or replace it before signing — "
                        f"that is what delegating it deferred to this moment."),
            })
        elif qtype == "unanswered":
            interview.append({
                "severity": "minor", "fixable": "needs_a_person", "source": "interview",
                "what": f"[{qid}] Still unanswered: {qasks}",
                "why": (f"**{qby}** owes this answer, asked {qdate}. The design was written around the "
                        f"gap rather than over it. Nothing here is wrong; something here is unknown."),
            })
        if qprov == "synthetic" and qtype in ("stated", "delegated"):
            interview.append({
                "severity": "major", "fixable": "needs_a_person", "source": "interview",
                "what": f"[{qid}] Answered synthetically, not by {qby}: {qasks}",
                "why": (f"The answer recorded is **{qvalue or '(none)'}**, supplied on behalf of "
                        f"{qby} rather than by them. Nobody with domain knowledge confirmed it."),
            })
defects = defects + interview
order = {"critical": 0, "major": 1, "minor": 2}
defects.sort(key=lambda x: order.get(x.get("severity", "minor"), 3))
crit = sum(1 for x in defects if x.get("severity") == "critical")
maj  = sum(1 for x in defects if x.get("severity") == "major")

L = []
L.append(f"# Findings on {pathlib.Path(design).name}")
L.append("")
L.append(f"**{d.get('audit_model','an auditor')}** reviewed a design written by "
         f"**{d.get('author_model','the author')}** and returned **{d.get('verdict','?')}**, "
         f"confidence {d.get('confidence','unstated')}.")
L.append("")
if not defects:
    L.append("It found nothing. What it checked: " + ", ".join(d.get("checked") or []) + ".")
else:
    L.append(f"**{len(defects)} finding(s)** — {crit} critical, {maj} major, "
             f"{len(defects)-crit-maj} minor.")
    L.append("")
    L.append("Each one is a claim about the design, not about the writing. Decide on each:")
    L.append("fix the design, or record why it is acceptable as it stands.")
    L.append("")
    for i, x in enumerate(defects, 1):
        tag = " · from the interview" if x.get("source") == "interview" else ""
        L.append(f"## {i}. {x.get('severity','?').upper()}{tag} — {x.get('what','')}")
        L.append("")
        L.append(x.get("why", ""))
        L.append("")
        L.append("- [ ] fixed in the design")
        L.append("- [ ] accepted as it stands, because: ")
        L.append("")
if tally["total"]:
    L.append("---")
    L.append("")
    L.append("## How the questions were answered")
    L.append("")
    L.append(f"{tally['total']} question(s) were put to the owner: "
             f"**{tally['stated']} stated**, {tally['delegated']} delegated, "
             f"{tally['unanswered']} unanswered.")
    L.append("")
    if tally["synthetic"]:
        L.append(f"**{tally['synthetic']} of those answers are synthetic** — supplied on behalf of "
                 f"the named person rather than by them. This design has not been confirmed by "
                 f"anybody who owns the process.")
        L.append("")
    if tally["delegated"] > tally["stated"]:
        L.append("More answers were delegated than stated. Either the interview is not working, "
                 "or the person was not really available. Both are worth knowing before signing.")
        L.append("")
L.append("---")
L.append("")
L.append("## What to do next")
L.append("")
L.append("**To revise:** edit the design, or re-run the authoring workflow with this file as")
L.append("input so the author addresses each finding rather than starting again. A revision is")
L.append("a new run with its own record — the design is never edited in place after acceptance.")
L.append("")
L.append("**To proceed as it stands:** tick the second box on each finding with a reason. The")
L.append("reason is the record; an unexplained acceptance is indistinguishable from not reading it.")
L.append("")
L.append(f"_Verdict: {v}_")
L.append(f"_Written {datetime.datetime.now().isoformat(timespec='seconds')}_")
pathlib.Path(out).write_text("\n".join(L) + "\n")
print(f"{len(defects)} finding(s): {crit} critical, {maj} major")
PY
RC=$?
[ -z "$QTSV" ] || rm -f "$QTSV"
[ "$RC" -eq 0 ] || exit "$RC"

# fold a pointer into the brief, which is the page a person actually reads
if [ -f "$BRIEF" ] && ! grep -q "^## Findings" "$BRIEF" 2>/dev/null; then
  N=$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1])).get('defects') or []))" "$V" 2>/dev/null || echo "?")
  { echo; echo "## Findings"; echo
    echo "An independent audit returned **$N finding(s)** on this design. Read \`FINDINGS.md\`"
    echo "before accepting it — each finding needs a decision, and the reason is the record."
  } >> "$BRIEF"
  echo "pointer added to $(basename "$BRIEF")"
fi
echo "wrote $OUT"
