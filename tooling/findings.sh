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
synthetic_rows = []
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
            synthetic_rows.append((qid, qby, qasks, qvalue))

# One finding per synthetic answer is right when a few were supplied on somebody
# else's behalf. When the WHOLE interview was, it is fifteen copies of one fact,
# and they bury the two findings that actually need a decision. "Nobody confirmed
# any of this" is a single, larger claim, so it is raised once and raised higher.
answered = tally["stated"] + tally["delegated"]
if synthetic_rows and answered and len(synthetic_rows) == answered:
    who = synthetic_rows[0][1]
    interview.insert(0, {
        "severity": "critical", "fixable": "needs_a_person", "source": "interview",
        "what": f"Every answer in this interview was supplied on behalf of {who}, not by them",
        "why": (f"All {len(synthetic_rows)} answered questions are marked synthetic. Nobody with "
                f"domain knowledge confirmed any of them, so this design rests entirely on answers "
                f"the system produced while standing in for the owner. It is a rehearsal, and it "
                f"is not signable as it stands. Read the question set in full and re-answer it, or "
                f"record here why a rehearsal is what was wanted.\n\n"
                + "\n".join(f"- **[{q}]** {a}" for q, _, a, _ in synthetic_rows)),
    })
else:
    for qid, qby, qasks, qvalue in synthetic_rows:
        interview.append({
            "severity": "major", "fixable": "needs_a_person", "source": "interview",
            "what": f"[{qid}] Answered synthetically, not by {qby}: {qasks}",
            "why": (f"The answer recorded is **{qvalue or '(none)'}**, supplied on behalf of "
                    f"{qby} rather than by them. Nobody with domain knowledge confirmed it."),
        })
# A gate closed without a person is the loudest thing on this page. It is not an
# interview finding and it is not the auditor's — it is about how this run was
# conducted, and it outranks both.
import os
reh = os.path.join(os.path.dirname(os.path.abspath(design)), "REHEARSAL")
if os.path.exists(reh):
    rows = [r.split("\t") for r in open(reh).read().splitlines() if r.strip()]
    if rows:
        interview.insert(0, {
            "severity": "critical", "fixable": "needs_a_person", "source": "rehearsal",
            "what": f"{len(rows)} gate(s) on this run were closed without a person",
            "why": ("This run is a rehearsal of the machinery, not an approval of the design. "
                    "`compile` refuses to build from it, and the acceptance register records any "
                    "signature on it as a rehearsal.\n\n"
                    + "\n".join(f"- `{(r+['']*5)[1]}` closed by **{(r+['']*5)[3]}** at {(r+['']*5)[0]}"
                                 f" — {(r+['']*5)[4]}" for r in rows)
                    + "\n\nTo make it real: run it again and have the named approver close each gate."),
        })
# Know-how the design needs and the catalog does not have. The same procurement
# signal a missing tool is, and it reaches a person the same way — because this
# is the ONLY moment it can surface. An interview can ask where appointment data
# comes from; it cannot know a dose-phrase convention is needed until somebody is
# writing the step that compares frequencies.
import re as _re
try:
    _d = open(design).read()
    _sk = _re.search(r'(?ms)^@skills\s*$(.*?)(?=^@[a-z]|\Z)', _d)
except Exception:
    _sk = None
if _sk:
    for _line in _sk.group(1).splitlines():
        _line = _line.strip()
        if not _line or _line.startswith("#"): continue
        _f = [c.strip() for c in _line.split("|")]
        if len(_f) < 2 or _f[1] not in ("", "-"): continue
        interview.append({
            "severity": "major", "fixable": "needs_a_person", "source": "catalog",
            "what": f"The design needs know-how the catalog does not have: {_f[0]}",
            "why": (f"{(_f[2] if len(_f) > 2 else '') or 'No reason given.'}\n\n"
                    f"This is not a defect in the design. It is a request to whoever owns the "
                    f"catalog: somebody must own **{_f[0]}**, write it down, and give it a review "
                    f"date — after which a step may depend on it. Until then no step does, and the "
                    f"design says so.\n\nThe same signal a missing tool is, raised at design time "
                    f"rather than at implementation."),
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
        src = x.get("source")
        tag = {"interview": " · from the interview",
               "rehearsal": " · HOW THIS RUN WAS CLOSED",
               "catalog": " · FOR THE CATALOG OWNER"}.get(src, "")
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
