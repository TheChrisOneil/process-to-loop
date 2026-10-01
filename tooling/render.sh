#!/usr/bin/env bash
# THE RENDERER — a design becomes a diagram by a rule, never by a model.
#
# Same design in, same bytes out. The diagram therefore cannot disagree with the design it
# depicts, which is the whole reason it is not written by the thing that proposed the design.
#
#   ./render.sh <design>              a Mermaid sequence diagram
#   ./render.sh --flow <design>       a Mermaid flowchart, colored by step type
#   ./render.sh --md <design>         wrapped in a fenced block, ready to paste
#   ./render.sh --force <design>      render a design the validator refused
#
# It runs the validator first. A design that fails a rule is not shown to anybody.
# Students reach this through:  make diagram DESIGN=<design>  /  make flow DESIGN=<design>
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"          # the tooling
ROOT="$(cd "$HERE/.." && pwd)"                 # the workshop: jobs, loops, memory, examples
VIEW=seq; MD=0; FORCE=0
while [ $# -gt 1 ]; do
  case "$1" in
    --flow) VIEW=flow ;; --seq) VIEW=seq ;; --md) MD=1 ;; --force) FORCE=1 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac; shift
done
FILE="${1:?usage: render.sh [--flow] [--md] [--force] <design file>}"
[ -f "$FILE" ] || { echo "no such design file: $FILE" >&2; exit 2; }

if ! "$HERE/validate.sh" "$FILE" >/dev/null 2>&1; then
  if [ "$FORCE" -eq 0 ]; then
    echo "REFUSED: this design does not pass the validator, so it is not rendered." >&2
    echo "         A picture of a design nobody checked is worse than no picture." >&2
    echo "         Run:  make check DESIGN=$FILE   (or pass --force to see it anyway)" >&2
    exit 1
  fi
  echo "%% WARNING: rendered with --force. This design fails the validator." 
fi

if ! awk -f "$HERE/lib/parse.awk" -f "$HERE/lib/check-gates.awk" "$FILE"; then
  echo "REFUSED: nothing rendered. A diagram that drops a control is worse than no diagram." >&2
  exit 1
fi

[ "$MD" -eq 1 ] && echo '```mermaid'
awk -f "$HERE/lib/parse.awk" -f "$HERE/lib/render-$VIEW.awk" "$FILE"
STATUS=$?
[ "$MD" -eq 1 ] && echo '```'
exit $STATUS
