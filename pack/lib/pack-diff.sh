#!/usr/bin/env bash
# Two pack versions -> what actually changed between them.
#
#   pack-diff.sh <pack-dir-a> <pack-dir-b>
#
# This is public-API diffing applied to a pack: cargo public-api, japicmp and
# go apidiff exist because semver is a human promise about a surface and humans
# get it wrong. Here the promise is worse than wrong — every version of this
# pack declares 0.1.0, and 0.x.y formally permits breaking changes in any
# release. So the version field is unusable, not stale, and the surface is
# computed.
#
# Verdicts:
#   BREAKING      a commitment was removed or changed
#   ADDITIVE      a commitment was added, nothing removed
#   UNCLASSIFIED  prose moved and no commitment did. NOT the same as NONE
#   NONE          the manifests are byte-identical
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
A=${1:-}; B=${2:-}
[ -n "$A" ] && [ -n "$B" ] || { echo "pack-diff.sh <pack-dir-a> <pack-dir-b>" >&2; exit 64; }
for d in "$A" "$B"; do [ -d "$d" ] || { echo "REFUSED: no pack directory at $d." >&2; exit 1; }; done

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
"$HERE/pack-capability.sh" "$A" > "$T/a" || exit 1
"$HERE/pack-capability.sh" "$B" > "$T/b" || exit 1

R="\033[31m"; G="\033[32m"; Y="\033[33m"; Z="\033[0m"
breaking=0; additive=0; opaque=0

prop() { grep "^$1	" "$2" | cut -f2- | sort -u; }
report() { # $1 label  $2 colour  $3 lines
  [ -z "$3" ] && return
  n=$(printf '%s\n' "$3" | grep -c .)
  printf "  ${2}%-9s${Z} %s (%d)\n" "$1" "$4" "$n"
  printf '%s\n' "$3" | head -6 | sed 's/^/                /'
  [ "$n" -gt 6 ] && printf '                … %d more\n' "$((n-6))"
}

echo "A  $A"
echo "B  $B"
echo

for p in PROVIDES MANDATES DEMANDS USES NORMS; do
  gone=$(comm -23 <(prop "$p" "$T/a") <(prop "$p" "$T/b"))
  new=$(comm -13 <(prop "$p" "$T/a") <(prop "$p" "$T/b"))
  case "$p" in
    PROVIDES|USES)
      [ -n "$gone" ] && { breaking=1; report BREAKING "$R" "$gone" "$p removed"; }
      [ -n "$new" ]  && { additive=1; report ADDITIVE "$G" "$new" "$p added"; } ;;
    MANDATES|NORMS)
      # a rule stated in prose is still a rule. Changing one changes behaviour
      # with no structural change anywhere, which is the case semver cannot see.
      [ -n "$gone" ] && { breaking=1; report BREAKING "$R" "$gone" "$p no longer stated"; }
      [ -n "$new" ]  && { breaking=1; report BREAKING "$R" "$new" "$p newly stated"; } ;;
    DEMANDS)
      [ -n "$new" ]  && { breaking=1; report BREAKING "$R" "$new" "$p added — a new requirement on callers"; }
      [ -n "$gone" ] && { additive=1; report ADDITIVE "$G" "$gone" "$p dropped"; } ;;
  esac
done

moved=$(comm -3 <(prop OPAQUE "$T/a") <(prop OPAQUE "$T/b") | awk '{print $1}' | sort -u)
[ -n "$moved" ] && { opaque=1; report UNCLASS "$Y" "$moved" "prose moved; no commitment did"; }

echo
if [ "$breaking" = 1 ];      then echo -e "  VERDICT  ${R}BREAKING${Z}"; rc=2
elif [ "$additive" = 1 ];    then echo -e "  VERDICT  ${G}ADDITIVE${Z}"; rc=0
elif [ "$opaque" = 1 ];      then echo -e "  VERDICT  ${Y}UNCLASSIFIED${Z} — prose changed and nothing computable did"; rc=1
else                              echo -e "  VERDICT  NONE — the manifests are identical"; rc=0; fi

if [ "$opaque" = 1 ] && [ "$breaking" = 0 ]; then
cat <<'NOTE'

  UNCLASSIFIED is not NONE. A prompt rewritten to give different judgment with
  the same surface lands here, and nothing above can tell you which it was.

  DRIFT, the embedding distance per prose file, would rank these by how far the
  text moved — but it is not configured, and it would not be a verdict if it
  were. Embeddings are weak at negation, and judgment prose is made of
  negations: "never claim through gc bd ready" and "always claim through
  gc bd ready" sit close together in vector space and are opposites. NORMS
  above is the negation-safe half and must not be replaced by a distance.
NOTE
fi
exit "$rc"
