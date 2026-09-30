#!/usr/bin/env bash
# Is this city safe to develop formulas against?
#
#   city-preflight.sh [--city <dir>] [--offline]
#
# The pack spec defines no drift or staleness semantics — "it does not define
# when or how an operator discovers that a resolved pack directory no longer
# matches its upstream source." So this defines them, in six properties:
#
#   PINNED      every import declares an explicit version. A blank version
#               floats, which is worse than a stale pin: it changes between
#               installs and yesterday's behaviour cannot be reproduced.
#   COHERENT    declared, locked and resolved agree, per import.
#   UNIFIED     every import of one pack family resolves to one version.
#   CURRENT     the declared version matches upstream HEAD (or is knowingly
#               behind — see --offline and the BEHIND marker).
#   CAPABLE     the capabilities a formula depends on actually resolve here.
#   CONSISTENT  the claim command the role prompt MANDATES exists in this city.
#
# The last one is the point. A version number does not tell you whether a
# command exists; it tells you which number somebody wrote down. Assert the
# capability, not the number.
set -uo pipefail
CITY=""; OFFLINE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --city)    CITY=${2:-}; shift 2 ;;
    --offline) OFFLINE=1; shift ;;
    *) echo "city-preflight.sh [--city <dir>] [--offline]" >&2; exit 64 ;;
  esac
done
[ -n "$CITY" ] || CITY=$PWD
[ -f "$CITY/city.toml" ] || { echo "REFUSED: no city.toml at $CITY." >&2
  echo "         Next human action: pass --city <the city directory>." >&2; exit 1; }
command -v gc >/dev/null || { echo "REFUSED: gc is not installed, so nothing here can be checked." >&2; exit 75; }

G="\033[32m"; R="\033[31m"; Y="\033[33m"; Z="\033[0m"
pass=0; fail=0; warn=0
ok()  { pass=$((pass+1)); printf "  ${G}PASS${Z}  %-11s %s\n" "$1" "$2"; }
no()  { fail=$((fail+1)); printf "  ${R}FAIL${Z}  %-11s %s\n" "$1" "$2"
        [ -n "${3:-}" ] && printf "                    %s\n" "$3"; }
wa()  { warn=$((warn+1)); printf "  ${Y}WARN${Z}  %-11s %s\n" "$1" "$2"; }

cd "$CITY" || exit 1
STATUS=$(gc import status 2>/dev/null | grep -vE '^packs\.lock' \
         | awk -F'\t' 'BEGIN{OFS="\t"} {for(i=1;i<=6;i++) if($i=="") $i="-"; print}')
[ -n "$STATUS" ] || { echo "REFUSED: gc import status returned nothing." >&2; exit 75; }

echo "CITY  $CITY"
echo

# ---- PINNED ----------------------------------------------------------------
FLOAT=$(printf '%s\n' "$STATUS" | awk -F'\t' '$3=="-"{print $1}')
if [ -z "$FLOAT" ]; then ok PINNED "every import declares a version"
else no PINNED "$(printf '%s' "$FLOAT" | tr '\n' ' ')— declares no version, so it floats" \
      "a floating import changes between installs; pin it to the sha you tested"; fi

# ---- COHERENT --------------------------------------------------------------
INCO=$(printf '%s\n' "$STATUS" | awk -F'\t' '
  $3!="-" { d=$3; sub(/^sha:/,"",d); l=$5; sub(/^sha:/,"",l)
           if (l!="" && d!=l && index($6,d)!=1) print $1 }')
if [ -z "$INCO" ]; then ok COHERENT "declared, locked and resolved agree"
else no COHERENT "$(printf '%s' "$INCO" | tr '\n' ' ')declared and locked disagree" \
      "run gc import install, then check again"; fi

# ---- UNIFIED ---------------------------------------------------------------
FAMS=$(printf '%s\n' "$STATUS" | awk -F'\t' '{
  fam=$2; sub(/\/tree\/.*/,"",fam); print fam "\t" $6 }' | sort -u)
SPLIT=$(printf '%s\n' "$FAMS" | awk -F'\t' '{c[$1]++} END{for(f in c) if(c[f]>1) print f}')
if [ -z "$SPLIT" ]; then ok UNIFIED "each pack family resolves to one version"
else
  for f in $SPLIT; do
    vs=$(printf '%s\n' "$FAMS" | awk -F'\t' -v f="$f" '$1==f{printf "%s ", substr($2,1,10)}')
    no UNIFIED "$(basename "$f") resolves to $(printf '%s' "$vs" | wc -w | tr -d ' ') versions: $vs" \
       "one family, one version — prompts and commands ship together and must match"
  done
fi

# ---- CURRENT ---------------------------------------------------------------
if [ "$OFFLINE" = 1 ]; then wa CURRENT "skipped — offline"
elif ! command -v gh >/dev/null; then wa CURRENT "skipped — gh is not installed, so upstream cannot be read"
else
  behind=0
  while IFS=$'\t' read -r name src declared _ _ resolved; do
    case "$src" in *github.com/*) : ;; *) continue ;; esac
    # bd and core are builtin: gc init pins them to match the installed binary,
    # and doctor's builtin-pack-family check owns them. Comparing them to the
    # CLI repo's main branch is meaningless — that branch is the whole product.
    case "$src" in
      */gascity/tree/*/internal/bootstrap/packs/*|*/gascity/tree/*/examples/*)
        ok CURRENT "$name is a builtin, pinned by the installed gc"; continue ;;
    esac
    [ "$declared" = "-" ] && { no CURRENT "$name declares no version, so currency is undefined" \
        "pin it first; PINNED above says the same thing"; continue; }
    repo=$(printf '%s' "$src" | sed -E 's|https://github.com/([^/]+/[^/]+)/tree/.*|\1|')
    head=$(gh api "repos/$repo/commits/main" -q .sha 2>/dev/null)
    [ -n "$head" ] || { wa CURRENT "$name — upstream unreadable"; continue; }
    d=${declared#sha:}
    if [ "$d" = "$head" ]; then ok CURRENT "$name is at upstream main"
    else
      n=$(gh api "repos/$repo/compare/$d...$head" -q .ahead_by 2>/dev/null)
      behind=1
      no CURRENT "$name is ${n:-?} commit(s) behind upstream main" \
         "declared ${d:0:10}, upstream ${head:0:10} — bump it, or record why not"
    fi
  done <<< "$STATUS"
fi

# ---- CAPABLE ---------------------------------------------------------------
if gc hook --help 2>&1 | grep -q -- "--claim"; then ok CAPABLE "gc hook --claim is available"
else no CAPABLE "gc hook has no --claim flag" "the claim protocol is unavailable in this city"; fi

if gc agent list 2>/dev/null | grep -q "gc\.run-operator"; then ok CAPABLE "gc.run-operator resolves as an agent"
else no CAPABLE "no gc.run-operator agent" \
     "the rig's roles import is not named gc, or the rig has no roles import"; fi

# ---- CONSISTENT ------------------------------------------------------------
# Read what the role prompt tells the agent to run, and check it exists here.
PROMPT=$(find ~/.gc/cache/repos -path "*gascity/roles/agents/run-operator/prompt.template.md" 2>/dev/null | head -1)
FRAG=$(find ~/.gc/cache/repos -path "*gascity/template-fragments/gc-role-worker.template.md" 2>/dev/null | head -1)
MAND=""
for f in "$FRAG" "$PROMPT"; do
  [ -n "$f" ] && [ -f "$f" ] || continue
  m=$(grep -oE '^\s*gc [a-z][a-z -]*claim[a-z -]*' "$f" 2>/dev/null | head -1 | sed 's/^ *//')
  [ -n "$m" ] && { MAND=$m; break; }
done
if [ -z "$MAND" ]; then wa CONSISTENT "no claim command found in any installed role prompt"
else
  first=$(printf '%s' "$MAND" | awk '{print $2}')
  if [ "$first" = hook ]; then ok CONSISTENT "the prompt mandates '$MAND', which is a builtin"
  elif gc "$first" --help 2>&1 | grep -qi "Commands from"; then
    ok CONSISTENT "the prompt mandates '$MAND', and 'gc $first' resolves"
  else
    no CONSISTENT "the prompt mandates '$MAND', and 'gc $first' does not resolve" \
       "name the import '$first' in pack.toml, or pin a version whose prompt matches this city"
  fi
fi

echo
printf "  %d passed, %d failed, %d warning(s)\n" "$pass" "$fail" "$warn"
if [ "$fail" -gt 0 ]; then
  echo
  echo "  REFUSED: formulas developed against this city may be written for a capability"
  echo "           surface it does not have. Fix the failures above before building on it." >&2
  exit 1
fi
