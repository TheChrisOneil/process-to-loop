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
for cp in sorted(set(re.findall(r'path\s*=\s*"([^"]+)"', resolved))):
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
for p in sorted({x.rstrip('.,;:').rstrip('/') for x in raw if x.rstrip('.,;:').rstrip('/')}):
    if p.startswith(("/bin", "/usr", "/dev", "/tmp", "/etc", "/var")): continue
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
