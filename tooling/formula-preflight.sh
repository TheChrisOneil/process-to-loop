#!/usr/bin/env bash
# Resolve a formula the way a run will, and check that everything it names is
# actually there — BEFORE slinging it.
#
#   formula-preflight.sh <formula.toml> <rig-dir> [key=value ...]
#
# A run that names a path nothing can resolve does not fail fast. The check is
# quarantined, the step closes anyway, and the author spends twenty-five minutes
# reading the city to work out what it was supposed to have been handed. This
# costs a second and reads the same files the run will.
#
# Exit 0  everything the formula names resolves
# Exit 1  something it names is missing or unresolved
# Exit 64 wrong arguments
set -uo pipefail
F=${1:-}; RIG=${2:-}
[ -f "$F" ] && [ -d "$RIG" ] || {
  echo "usage: formula-preflight.sh <formula.toml> <rig-dir> [key=value ...]" >&2; exit 64; }
shift 2

python3 - "$F" "$RIG" "$@" <<'PY'
import os, re, sys

formula, rig = sys.argv[1], sys.argv[2]
given = dict(a.split("=", 1) for a in sys.argv[3:] if "=" in a)
src = open(formula).read()

# Declared vars and their defaults, so we substitute exactly what a run would.
defaults, required = {}, set()
for block in re.findall(r'\[vars\.([a-z_]+)\]((?:\n(?!\[).*)*)', src):
    name, body = block
    d = re.search(r'^default\s*=\s*"(.*)"', body, re.M)
    if d: defaults[name] = d.group(1)
    if re.search(r'^required\s*=\s*true', body, re.M): required.add(name)

values = dict(defaults); values.update(given)
problems, notes = [], []

for r in sorted(required):
    if r not in given:
        problems.append(f"required var not supplied: {r}")

# Substitute, then see what is left. A surviving {{x}} is a value no run has.
body = re.sub(r'\[vars\.[a-z_]+\]((?:\n(?!\[).*)*)', '', src)   # var docs are not steps
resolved = body
for k, v in values.items():
    resolved = resolved.replace("{{" + k + "}}", v)
left = sorted(set(re.findall(r'\{\{([a-z_][a-z0-9_]*)\}\}', resolved)))
for v in left:
    problems.append(f"unresolved in step text: {{{{{v}}}}} — no value and no default")

# Check paths resolve against the RIG. This is where a formula's check paths are
# looked up, not against the city, and getting it wrong quarantines every check.
checks_root = values.get("checks_root", os.path.join(rig, "checks"))
art = values.get("artifact_root", "")
for cp in sorted(set(re.findall(r'path\s*=\s*"([^"]+)"', resolved))):
    # Bound at run time: it will not exist yet, but what gets bound must.
    if art and cp.startswith(os.path.join(art, "checks") + os.sep):
        src = os.path.join(checks_root, os.path.basename(cp))
        if os.path.exists(src):
            notes.append(f"check bound at run time: {os.path.basename(cp)} <- {src}")
        else:
            problems.append(f"check bound at run time has no source: {src}")
        continue
    full = cp if os.path.isabs(cp) else os.path.join(rig, cp)
    if not os.path.exists(full):
        problems.append(f"check path does not resolve: {cp}  ->  {full}")
    elif not os.access(full, os.X_OK):
        problems.append(f"check is not executable: {full}")
    else:
        notes.append(f"check ok: {cp}")

# Any absolute path the substituted text now names. An input that is not there is
# the run's first surprise; an output whose directory is missing is its last.
raw = set(re.findall(r'(/(?:[\w.\-]+/)+[\w.\-]+)', resolved))
# Prose puts a path at the end of a sentence, so strip sentence punctuation —
# and the trailing slash a directory is written with, or ".../prior/." becomes
# ".../prior/" and never matches anything on disk.
bound_dir = os.path.join(art, "checks") + os.sep if art else None
for p in sorted({x.rstrip('.,;:').rstrip('/') for x in raw if x.rstrip('.,;:').rstrip('/')}):
    if p.startswith(("/bin", "/usr", "/dev", "/tmp", "/etc", "/var")): continue
    # Written by the bind step at the start of the run; the check-path section
    # above already verified that what will be bound exists.
    if bound_dir and p.startswith(bound_dir): continue
    if os.path.exists(p):
        notes.append(f"path ok: {p}")
    elif os.path.isdir(os.path.dirname(p)):
        notes.append(f"path will be written: {p}")
    else:
        problems.append(f"path names a missing directory: {p}")

for n in notes:    print(f"  ok   {n}")
for p in problems: print(f"  MISSING  {p}")
print()
print(f"{len(notes)} resolved, {len(problems)} unresolved")
sys.exit(1 if problems else 0)
PY
PATHS_RC=$?

# ---- CAN IT ACTUALLY RUN? --------------------------------------------------
# Paths resolving says the formula names real things. It says nothing about
# whether the run can do its work. On 2026-10-05 every path resolved, preflight
# passed, and authoring burned all three attempts because the audit provider had
# no credential — a fact knowable in a second, before the run started.
#
# Convention: a var named *_provider names a CLI the run will invoke.
HERE_PF=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CAP_RC=0
cap_no() { echo "  MISSING  $1" >&2; CAP_RC=1; }
cap_ok() { echo "  ok   $1"; }

for kv in "$@"; do
  case "${kv%%=*}" in *_provider) ;; *) continue ;; esac
  prov=${kv#*=}
  [ -n "$prov" ] || continue
  if ! command -v "$prov" >/dev/null 2>&1; then
    cap_no "provider \"$prov\" is named by ${kv%%=*} and is not on PATH"
    continue
  fi
  cap_ok "provider $prov is installed"
  case "$prov" in
    gemini)
      if ( . "$HERE_PF/credential.sh" 2>/dev/null
           load_credential GEMINI_API_KEY process-to-loop-gemini >/dev/null 2>&1 ); then
        cap_ok "provider $prov has a credential"
      else
        cap_no "provider $prov has NO credential — the audit lane cannot run"
        echo "           store one: security add-generic-password -a \"\$USER\" -s process-to-loop-gemini -w" >&2
      fi ;;
    claude) cap_ok "provider $prov carries its own session auth" ;;
    *)      cap_ok "provider $prov credential not verified by this tool" ;;
  esac
done

echo
if [ "$PATHS_RC" = 0 ] && [ "$CAP_RC" = 0 ]; then
  echo "ready to sling"; exit 0
fi
echo "NOT ready to sling"; exit 1

