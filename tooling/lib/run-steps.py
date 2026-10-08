"""One line per step of ONE run, read from a `gc bd ... --json` stream on stdin.

env: ROOT_BEAD  the workflow this run belongs to. Without it every workflow in
                the rig is shown, which is how one run's screen came to carry
                another run's steps.
     LBL        the prefix, e.g. "    NOW    "

Its own file rather than inline, because an inline program inside a shell loop
inside a heredoc is three levels of quoting and the middle one broke twice.
"""
import json
import os
import sys

ROOT = os.environ.get("ROOT_BEAD", "")
LBL = os.environ.get("LBL", "    ")

try:
    beads = json.load(sys.stdin)
except Exception:
    sys.exit(0)

seen, shown = set(), 0
for b in beads:
    title = b.get("title") or ""
    if not title or title.startswith("Step spec") or title == "design-authoring":
        continue
    md = b.get("metadata") or {}
    if ROOT and md.get("gc.root_bead_id") != ROOT:
        continue
    # An iteration bead is one attempt; the logical bead carries what stands.
    if ".iteration." in (md.get("gc.step_ref") or ""):
        continue
    # Gates have their own section, and it says what closing one means.
    if b.get("issue_type") == "gate":
        continue
    if title in seen:
        continue
    seen.add(title)
    shown += 1
    if shown > 3:
        break
    print(LBL + title)
