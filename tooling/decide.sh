#!/usr/bin/env bash
# Evaluate a decision table. The table is the logic; this just runs it.
#
#   decide.sh <design> --table <id> -- <input> [<input> ...]
#   decide.sh <table.tsv> -- <input> [<input> ...]
#   decide.sh <design> --list
#
# A gate backed by a table compiles to this. A gate backed by prose compiles to
# a stub somebody has to implement, which is the difference the tables are for.
#
# Exit 0  a rule matched; the outputs are on stdout, tab separated
# Exit 1  no rule matched — a fall-through is a refusal, never a default
# Exit 75 the table or the arity is wrong — could not run, never a business
#         failure, and the same code every gate check here uses
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
F=${1:-}; shift 2>/dev/null || true
TABLE=""; LIST=0; ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --table) TABLE=${2:-}; shift 2 ;;
    --list)  LIST=1; shift ;;
    --)      shift; while [ $# -gt 0 ]; do ARGS+=("$1"); shift; done ;;
    *)       ARGS+=("$1"); shift ;;
  esac
done
[ -n "$F" ] && [ -f "$F" ] || { echo "usage: decide.sh <design|table.tsv> [--table <id>] -- <input> ..." >&2; exit 75; }

# A design is compiled to a table here, once. A .tsv is already one.
TSV="$F"
case "$F" in
  *.tsv) : ;;
  *) TSV=$(mktemp)
     awk -v WANT="$TABLE" -f "$HERE/lib/parse.awk" -f "$HERE/lib/dt-cell.awk" \
         -f "$HERE/lib/decisions.awk" -f "$HERE/lib/emit-decision.awk" "$F" > "$TSV"
     trap 'rm -f "$TSV"' EXIT ;;
esac

if [ "$LIST" -eq 1 ]; then
  awk -F'\t' '/^#table/{t=$2;h=$3} /^#inputs/{ni=NF-1} /^#outputs/{no=NF-1}
              !/^#/ && NF{n[t]++}
              END{for (k in n) printf "%s  %s  %d rule(s)\n", k, h, n[k]}' "$TSV"
  exit 0
fi
[ -s "$TSV" ] || { echo "REFUSED: no decision table${TABLE:+ called $TABLE} in $F." >&2; exit 75; }
[ ${#ARGS[@]} -gt 0 ] || { echo "REFUSED: give the inputs after --." >&2
  awk -F'\t' '/^#inputs/{printf "         in order: "; for(i=2;i<=NF;i++) printf "%s%s", (i>2?", ":""), $i; print ""}' "$TSV" >&2
  exit 75; }

# \037 is the ASCII unit separator: an input value may legitimately contain a
# space, a comma or a pipe, and every one of those is already a cell delimiter
# somewhere in this format.
IN=$(printf '%s\037' "${ARGS[@]}"); IN=${IN%$'\037'}
awk -v IN="$IN" -f "$HERE/lib/dt-cell.awk" -f "$HERE/lib/decide.awk" "$TSV"
