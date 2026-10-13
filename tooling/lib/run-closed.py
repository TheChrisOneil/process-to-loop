"""Closed steps of ONE run, read from `gc bd list --status closed --json` on stdin.

env: ROOT_BEAD  the workflow to report on

Its own file for the same reason run-steps.py is: an inline program inside a
shell heredoc inside a command substitution is three levels of quoting, and the
test that exercises it needs a fourth.

The label it prints is the point. gc has no outcome for "could not run" — an exec
check exiting 75 consumes its attempts and closes `fail`, exactly as exit 1 does
(measured 2026-10-13). So an infrastructure failure is indistinguishable from a
refused rule unless something reads the REASON. gc records enough to tell them
apart; this is the only thing that does.
"""
import sys, json, os
ROOT = os.environ.get("ROOT_BEAD", "")
try: beads = json.load(sys.stdin)
except Exception: sys.exit(0)
seen = set()
for b in beads:
    t = b.get("title") or ""
    if t.startswith("Step spec") or not t: continue
    md = b.get("metadata") or {}
    # One rig can hold several runs at once. Without this filter another
    # workflow steps appear as this one: it once showed compile and finalize
    # as done when both belonged to a different design.
    if ROOT and md.get("gc.root_bead_id") != ROOT: continue
    # Each step has iteration beads and one logical bead. An iteration may fail
    # and a later one pass, which is the loop working; the logical bead carries
    # the outcome that stands. Show only that one, or a step reads as both done
    # and FAILED at once.
    ref = md.get("gc.step_ref") or ""
    if ".iteration." in ref: continue
    out = md.get("gc.outcome") or ""
    # gc has no outcome for "could not run": an exec check exiting 75 consumes
    # its attempts and closes fail, exactly as exit 1 does (measured 2026-10-13).
    # So a step that failed for an INFRASTRUCTURE reason is indistinguishable
    # from one that failed a rule — unless something reads the reason, which
    # nothing did. gc records enough to tell them apart; this is the wiring.
    infra = ""
    if out == "fail":
        blob = (str(md.get("gc.attempt_log") or "")
                + " " + str(md.get("gc.controller_error") or "")).lower()
        for marker, why in (
            ("login expired", "not logged in"),
            ("oauth", "not logged in"),
            ("authenticat", "not logged in"),
            ("could not run", "could not run"),
            ("escapes trusted roots", "check path refused"),
            ("no such file", "something was missing"),
            ("exit 75", "could not run"),
            ("timed out", "timed out"),
            ("timeout", "timed out"),
        ):
            if marker in blob:
                infra = why
                break
        if not infra and (md.get("gc.controller_error_class") or ""):
            infra = "controller: " + str(md.get("gc.controller_error_class"))
    if   out == "pass": label = "done   "
    elif out == "fail": label = "BLOCKED" if infra else "FAILED "
    elif out == "":     label = "closed "
    else:               label = (out[:6] + " ").ljust(7)
    # 8, not 7: BLOCKED is exactly seven characters, so padding to seven left
    # it welded to the step title.
    label = label.rstrip().ljust(8)
    key = (label, t)
    if key in seen: continue
    seen.add(key)
    print("    %s%s%s" % (label, t, ("   <- " + infra) if infra else ""))
