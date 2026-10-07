#!/usr/bin/env bash
# Append one discovery to docs/DISCOVERIES.md.
#
#   discovery.sh add --title "..." --believed "..." --happened "..." \
#                    --changed "..." --generalizes "..." [--cost "..."] [--date YYYY-MM-DD]
#   discovery.sh list                     ids, dates and titles
#   discovery.sh show <Dn>                one entry
#   discovery.sh check                    is the log well formed?
#
# Written by this tool, never by hand, for the same reason every other artifact
# here is: a format a person types is a format that drifts, and the first entry
# missing its cost is the entry that reads as a tidy lesson instead of a scar.
#
# A discovery is not a decision and not a runbook step. It is what SURPRISED us.
# Decisions leave a diff; runbooks leave a procedure; a surprise leaves nothing
# unless somebody writes it down the day it happens.
#
# Exit 0 appended · 1 refused · 64 wrong arguments
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LOG=${DISCOVERIES:-$HERE/../docs/DISCOVERIES.md}
CMD=${1:-}; shift 2>/dev/null || true
[ -n "$CMD" ] || { sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }
[ -f "$LOG" ] || { echo "REFUSED: no discoveries log at $LOG." >&2; exit 1; }

next_id() { awk '/^## D[0-9]+ /{ sub(/^## D/,""); sub(/ .*$/,""); if ($0+0>m) m=$0+0 } END{ print m+1 }' "$LOG"; }

case "$CMD" in

list)
  awk '/^## D[0-9]+ /{ line=$0; sub(/^## /,"",line); print line }' "$LOG"
  printf '\n%s entr(ies)\n' "$(grep -c '^## D[0-9]* ' "$LOG")"
  ;;

show)
  WANT=${1:?usage: discovery.sh show <Dn>}
  awk -v w="$WANT" '
    $0 ~ "^## " w " " { p=1 }
    p && /^---$/ { exit }
    p { print }' "$LOG"
  ;;

check)
  # Every entry carries all five fields. An entry missing `cost` is the one that
  # reads as a tidy lesson rather than something that hurt, so it is checked
  # like any other field.
  awk '
    /^## D[0-9]+ /{ if (id != "") report(); id=$2; title=$0; b=h=c=g=0 }
    /^\*\*believed\*\*/    { b=1 }
    /^\*\*happened\*\*/    { h=1 }
    /^\*\*changed\*\*/     { c=1 }
    /^\*\*generalizes\*\*/ { g=1 }
    END { if (id != "") report()
          printf "\n  %d entr(ies), %d incomplete\n", n, bad+0
          exit (bad>0 ? 1 : 0) }
    function report(  miss) { n++
      miss=""
      if (!b) miss=miss " believed"
      if (!h) miss=miss " happened"
      if (!c) miss=miss " changed"
      if (!g) miss=miss " generalizes"
      if (miss=="") printf "  ok      %s\n", id
      else { bad++; printf "  MISSING %s:%s\n", id, miss }
    }' "$LOG"
  ;;

add)
  T=""; B=""; H=""; C=""; G=""; COST=""; D=$(date +%F)
  while [ $# -gt 0 ]; do
    case "$1" in
      --title)       T=${2:-}; shift 2 ;;
      --believed)    B=${2:-}; shift 2 ;;
      --happened)    H=${2:-}; shift 2 ;;
      --cost)        COST=${2:-}; shift 2 ;;
      --changed)     C=${2:-}; shift 2 ;;
      --generalizes) G=${2:-}; shift 2 ;;
      --date)        D=${2:-}; shift 2 ;;
      *) echo "REFUSED: unknown option $1" >&2; exit 64 ;;
    esac
  done
  MISS=""
  [ -n "$T" ] || MISS="$MISS --title"
  [ -n "$B" ] || MISS="$MISS --believed"
  [ -n "$H" ] || MISS="$MISS --happened"
  [ -n "$C" ] || MISS="$MISS --changed"
  [ -n "$G" ] || MISS="$MISS --generalizes"
  if [ -n "$MISS" ]; then
    echo "REFUSED: missing$MISS" >&2
    echo "         An entry without what you BELIEVED is a changelog line. The" >&2
    echo "         belief is the part that makes it transferable: somebody else" >&2
    echo "         holds it right now." >&2
    exit 64
  fi
  case "$D" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) echo "REFUSED: --date must be YYYY-MM-DD." >&2; exit 64 ;; esac

  ID="D$(next_id)"
  {
    printf '\n---\n\n## %s · %s · %s\n\n' "$ID" "$D" "$T"
    printf '**believed** %s\n' "$B"
    printf '**happened** %s\n' "$H"
    [ -z "$COST" ] || printf '**cost** %s\n' "$COST"
    printf '**changed** %s\n' "$C"
    printf '**generalizes** %s\n' "$G"
  } >> "$LOG"
  echo "$ID appended to $LOG"
  [ -n "$COST" ] || echo "note: no --cost given. An entry with no cost reads as a tidy lesson." >&2
  ;;

*) echo "REFUSED: no subcommand \"$CMD\"." >&2; exit 64 ;;
esac
