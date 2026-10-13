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

# A var the caller did not supply still has a DEFAULT, and the run will use it.
# Checking only what was passed meant this loop had never once examined a
# provider in a real preflight: every sling of design-authoring relies on
# author_provider and audit_provider defaulting, so the capability section
# silently examined nothing and printed nothing, which reads exactly like
# "no providers to check".
PROVIDERS=""
for kv in "$@"; do
  case "${kv%%=*}" in *_provider) PROVIDERS="$PROVIDERS $kv" ;; esac
done
# Anything the formula declares with a default, and the caller did not override.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  pname=${line%%=*}
  case " $PROVIDERS " in *" $pname="*) continue ;; esac
  PROVIDERS="$PROVIDERS $line"
done <<EOF
$(awk '/^\[vars\.[a-z_]*_provider\]/{ n=$0; sub(/^\[vars\./,"",n); sub(/\]$/,"",n); want=n; next }
       want!="" && /^default *=/ { v=$0; sub(/^default *= *"?/,"",v); sub(/"$/,"",v)
                                   if (v!="") print want "=" v; want="" }
       /^\[\[steps\]\]/{ want="" }' "$F")
EOF

for kv in $PROVIDERS; do
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
    claude)
      # "carries its own session auth" was an ASSUMPTION, and it cost two
      # incidents. On 2026-10-09 the OAuth session expired mid-run and seven
      # steps closed fail, reading as a broken design. On 2026-10-13 the same
      # expiry produced total silence: the run materialized, a step sat ready,
      # agents were up, and nothing moved. Both were knowable in under a second,
      # before the sling.
      if ! command -v python3 >/dev/null; then
        cap_ok "provider $prov installed; auth not verified (no python3 to read the status)"
      else
        AUTHJ=$(claude auth status 2>/dev/null)
        LOGGED=$(printf '%s' "$AUTHJ" | python3 -c '
import json, sys
try: print("yes" if json.load(sys.stdin).get("loggedIn") else "no")
except Exception: print("unknown")' 2>/dev/null)
        case "$LOGGED" in
          yes) cap_ok "provider $prov is logged in" ;;
          no)
            cap_no "provider $prov is NOT logged in — every agent attempt will fail in under a second"
            echo "           claude auth login" >&2
            echo "           then KILL the agent sessions: a session started before the login" >&2
            echo "           keeps the dead credential and claims work it cannot do." >&2 ;;
          *) cap_ok "provider $prov installed; auth status unreadable on this version" ;;
        esac
      fi ;;
    *)      cap_ok "provider $prov credential not verified by this tool" ;;
  esac
done

# The catalog, if this formula uses one. A tool that does not answer is a source
# a run will discover is unreachable on attempt one, having spent an attempt.
for kv in "$@"; do
  case "${kv%%=*}" in catalog_path) ;; *) continue ;; esac
  cat=${kv#*=}
  [ -n "$cat" ] || continue
  if [ ! -f "$cat" ]; then cap_no "catalog_path names no file: $cat"; continue; fi
  cap_ok "catalog at $cat"
  if out=$("$HERE_PF/catalog.sh" "$cat" health 2>&1); then
    printf '%s\n' "$out" | sed 's/^/  /'
  else
    printf '%s\n' "$out" | sed 's/^/  /' >&2
    cap_no "a catalogued tool does not answer; a design naming it would fail at run time"
  fi
  stale=$("$HERE_PF/catalog.sh" "$cat" stale 2>&1) || cap_no "the catalog has entries past their review date"
  case "$stale" in *"within its review date"*) cap_ok "every catalog entry is within its review date" ;; esac
done

# ---- the rig's copy of the tooling must match the one the run will be given.
#
# A formula step follows tooling_root. An exec check falls back to the copy
# inside the rig. When those differ, the gates judge the run with one version of
# the rules and the steps do the work with another, and nothing says so: both
# copies exist and neither knows about the other. On 2026-10-13 a validate gate
# passed a design using a validator 23 lines behind the repo, including the one
# rule that would have warned about it.
#
# This is the moment to notice, because after the sling there is no moment.
if [ -d "$RIG/tooling" ] && [ -d "$HERE_PF" ]; then
  RIGT=$(cd "$RIG/tooling" && pwd); REPOT=$(cd "$HERE_PF" && pwd)
  if [ "$RIGT" = "$REPOT" ]; then
    cap_ok "the rig's tooling IS the repo's — one copy, so it cannot drift"
  else
    REPOC=$(cd "$REPOT/../checks" 2>/dev/null && pwd)
    D1=$(diff -rq "$REPOT" "$RIGT" 2>/dev/null | grep -c . || true)
    D2=0
    [ -z "$REPOC" ] || [ ! -d "$RIG/checks" ] || \
      D2=$(diff -rq "$REPOC" "$RIG/checks" 2>/dev/null | grep -c . || true)
    DRIFT=$(( ${D1:-0} + ${D2:-0} ))
    if [ "$DRIFT" -eq 0 ]; then
      cap_ok "the rig's copies of tooling/ and checks/ match the repo"
    else
      cap_no "the rig's copies differ from the repo in $DRIFT place(s)"
      { diff -rq "$REPOT" "$RIGT" 2>/dev/null
        [ -z "$REPOC" ] || diff -rq "$REPOC" "$RIG/checks" 2>/dev/null; } \
        | head -12 | sed 's/^/           /' >&2
      echo "           The gates would judge this run with one version and the steps do the" >&2
      echo "           work with another. Next human action: rsync -a --delete the repo's" >&2
      echo "           tooling/ and checks/ over the rig's, then preflight again." >&2
    fi
  fi
fi

echo
if [ "$PATHS_RC" = 0 ] && [ "$CAP_RC" = 0 ]; then
  echo "ready to sling"; exit 0
fi
echo "NOT ready to sling"; exit 1

