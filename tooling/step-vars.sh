#!/usr/bin/env bash
# Fill a check's inputs from the workflow it belongs to. SOURCE this.
#
#   . tooling/step-vars.sh
#   load_workflow_vars            # sets DESIGN_PATH etc. if they are not already set
#
# A formula declares [vars] and the controller stores them on the workflow ROOT
# bead as gc.var.<name>. It does NOT export them to an exec check's environment.
# A check that reads only its environment therefore finds nothing and exits 75
# forever, which is how a run on 2026-10-02 burned four authoring attempts: the
# design was written correctly every time and the check could not find it.
#
# The environment still wins, so a check stays runnable by hand.
set -uo pipefail 2>/dev/null || true

# load_workflow_vars
# Sets, for each gc.var.<name> on the workflow root, the variable <NAME> —
# design_path becomes DESIGN_PATH — unless it already has a value.
load_workflow_vars() {
  local bead=${GC_BEAD_ID:-${GC_BEAD:-}}
  [ -n "$bead" ] || return 0
  command -v gc >/dev/null 2>&1 || return 0

  local root
  root=$(gc bd show "$bead" --json 2>/dev/null | python3 -c '
import json,sys
try: b=json.load(sys.stdin)
except Exception: sys.exit(0)
b=b[0] if isinstance(b,list) and b else b
if not isinstance(b,dict): sys.exit(0)
md=b.get("metadata") or {}
print(md.get("gc.root_bead_id") or b.get("id") or "")
' 2>/dev/null)
  [ -n "$root" ] || return 0

  local assignments
  assignments=$(gc bd show "$root" --json 2>/dev/null | python3 -c '
import json,sys,shlex
try: b=json.load(sys.stdin)
except Exception: sys.exit(0)
b=b[0] if isinstance(b,list) and b else b
if not isinstance(b,dict): sys.exit(0)
for k,v in (b.get("metadata") or {}).items():
    if not k.startswith("gc.var."): continue
    name=k[len("gc.var."):].upper()
    if not name.replace("_","").isalnum(): continue
    print("%s=%s" % (name, shlex.quote(str(v))))
' 2>/dev/null)

  local line name
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name=${line%%=*}
    # Already set and non-empty: the caller meant it, so leave it alone.
    [ -n "$(eval "printf '%s' \"\${$name-}\"")" ] && continue
    eval "export $line"
  done <<< "$assignments"
}
