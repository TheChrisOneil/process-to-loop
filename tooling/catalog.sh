#!/usr/bin/env bash
# Ask the tool catalog things. Read-only.
#
#   catalog.sh <catalog> list
#   catalog.sh <catalog> health            every tool, does it answer?
#   catalog.sh <catalog> schema <id>       what the TOOL says it provides
#   catalog.sh <catalog> verify <id>       does the tool provide what the catalog claims?
#   catalog.sh <catalog> stale [today]     entries past their review date
#
# A catalog nothing verifies is a comment. These are the four questions that
# stop it becoming one.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
C=${1:?usage: catalog.sh <catalog> list|health|schema <id>|verify <id>|stale}
CMD=${2:?usage: catalog.sh <catalog> list|health|schema <id>|verify <id>|stale}
ARG=${3:-}
[ -f "$C" ] || { echo "no catalog at $C" >&2; exit 64; }

field() { awk -f "$HERE/lib/catalog.awk" -v id="$1" -v k="$2" \
          -e 'END{ print T[id "." k] }' "$C" 2>/dev/null \
          || awk -f "$HERE/lib/catalog.awk" "$C" >/dev/null; }

# mawk/BSD awk have no -e; use a second script file instead.
ask() { # ask <id> <key>
  printf 'END{ print T["%s.%s"] }\n' "$1" "$2" > "$TMPQ"
  awk -f "$HERE/lib/catalog.awk" -f "$TMPQ" "$C"
}
ids() { printf 'END{ for(i=1;i<=t;i++) print TID[i] }\n' > "$TMPQ"
        awk -f "$HERE/lib/catalog.awk" -f "$TMPQ" "$C"; }
TMPQ=$(mktemp); trap 'rm -f "$TMPQ"' EXIT

resolve() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s' "$(cd "$HERE/.." && pwd)/$1" ;; esac; }

case "$CMD" in
  list)
    printf '%-26s %-32s %-12s %s\n' TOOL VIA CLASS REVIEW
    for id in $(ids); do
      printf '%-26s %-32s %-12s %s\n' "$id" "$(ask "$id" via)" "$(ask "$id" data_class)" "$(ask "$id" review_by)"
    done ;;
  health)
    rc=0
    for id in $(ids); do
      via=$(ask "$id" via); cmd=$(resolve "$via")
      if [ -x "$cmd" ]; then
        if out=$("$cmd" health 2>&1); then printf '  ok       %-26s %s\n' "$id" "$out"
        else printf '  NO       %-26s %s\n' "$id" "$out"; rc=1; fi
      elif command -v "$via" >/dev/null 2>&1; then
        printf '  ok       %-26s %s on PATH (no health subcommand)\n' "$id" "$via"
      else
        printf '  MISSING  %-26s %s is neither executable nor on PATH\n' "$id" "$via"; rc=1
      fi
    done
    exit $rc ;;
  schema)
    [ -n "$ARG" ] || { echo "usage: catalog.sh <catalog> schema <id>" >&2; exit 64; }
    cmd=$(resolve "$(ask "$ARG" via)")
    [ -x "$cmd" ] || { echo "$ARG is not an executable tool, so it reports no schema" >&2; exit 75; }
    "$cmd" schema ;;
  verify)
    [ -n "$ARG" ] || { echo "usage: catalog.sh <catalog> verify <id>" >&2; exit 64; }
    cmd=$(resolve "$(ask "$ARG" via)")
    [ -x "$cmd" ] || { echo "$ARG is not an executable tool; its claims cannot be verified" >&2; exit 75; }
    claimed=$(ask "$ARG" provides | tr ',' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$' | sort)
    actual=$("$cmd" schema 2>/dev/null | cut -f1 | sort)
    missing=$(comm -23 <(printf '%s\n' "$claimed") <(printf '%s\n' "$actual"))
    if [ -n "$missing" ]; then
      echo "REFUSED: $ARG claims fields the tool does not report:" >&2
      printf '%s\n' "$missing" | sed 's/^/           /' >&2
      echo "         The catalog is describing something the tool will not return." >&2
      exit 1
    fi
    extra=$(comm -13 <(printf '%s\n' "$claimed") <(printf '%s\n' "$actual"))
    echo "$ARG: every claimed field is reported by the tool$([ -n "$extra" ] && printf '; it also reports %s' "$(printf '%s' "$extra" | tr '\n' ' ')")" ;;
  stale)
    today=${ARG:-$(date +%Y-%m)}
    rc=0
    for id in $(ids); do
      r=$(ask "$id" review_by)
      [ -n "$r" ] || { printf '  NO REVIEW DATE  %s\n' "$id"; rc=1; continue; }
      if [ "$(printf '%s\n%s\n' "$r" "$today" | sort | head -1)" = "$r" ] && [ "$r" != "$today" ]; then
        printf '  STALE  %-26s review_by %s, today %s\n' "$id" "$r" "$today"; rc=1
      fi
    done
    [ "$rc" = 0 ] && echo "every entry is within its review date"
    exit $rc ;;
  *) echo "unknown command: $CMD" >&2; exit 64 ;;
esac
