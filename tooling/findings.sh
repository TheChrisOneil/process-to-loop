#!/usr/bin/env bash
# An audit verdict -> FINDINGS.md beside the design, and appended to the brief.
#
#   findings.sh <verdict.json> <design> [--brief <BRIEF.md>]
#
# The person who has to act on a finding should not have to know a file path or
# read JSON. Deterministic: no model.
set -uo pipefail
V=${1:-}; D=${2:-}; BRIEF=""
shift 2 2>/dev/null || true
while [ $# -gt 0 ]; do case "$1" in --brief) BRIEF=${2:-}; shift 2 ;; *) shift ;; esac; done
[ -n "$V" ] && [ -n "$D" ] || { echo "findings.sh <verdict.json> <design> [--brief <BRIEF.md>]" >&2; exit 64; }
[ -f "$V" ] || { echo "REFUSED: no verdict at $V." >&2; exit 75; }
[ -f "$D" ] || { echo "REFUSED: no design at $D." >&2; exit 75; }
command -v python3 >/dev/null || { echo "REFUSED: no python3 to read the verdict." >&2; exit 75; }
OUT="$(cd "$(dirname "$D")" && pwd)/FINDINGS.md"
[ -n "$BRIEF" ] || BRIEF="$(cd "$(dirname "$D")" && pwd)/BRIEF.md"

python3 - "$V" "$D" "$OUT" <<'PY'
import json, sys, pathlib, datetime
v, design, out = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(v))
defects = d.get("defects") or []
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
        L.append(f"## {i}. {x.get('severity','?').upper()} — {x.get('what','')}")
        L.append("")
        L.append(x.get("why", ""))
        L.append("")
        L.append("- [ ] fixed in the design")
        L.append("- [ ] accepted as it stands, because: ")
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
