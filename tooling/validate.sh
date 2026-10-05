#!/usr/bin/env bash
# THE VALIDATOR — a gate over a design, before anybody is shown it.
#
# Every check below is deterministic, costs nothing, and cannot be argued with. That is the
# point: the tool that teaches "a gate's condition lives in code" is itself governed by one.
#
#   ./validate.sh <design file>          human-readable findings; exit 1 on any ERROR
#   ./validate.sh --tsv <design file>    machine-readable, for a later step to gate on
#   ./validate.sh --rules                print the rule list and exit
set -uo pipefail

MODE=human
case "${1:-}" in
  --rules)
    awk '/^# RULES$/,/^# END RULES$/' "$0" | sed '1d;$d;s/^# \{0,1\}//'
    exit 0 ;;
  --tsv) MODE=tsv; shift ;;
esac
FILE="${1:?usage: validate.sh [--tsv] <design file> | --rules}"
[ -f "$FILE" ] || { echo "no such design file: $FILE" >&2; exit 2; }

# RULES
# V1   every required section is present
# V2   use_case, author, date, approver and exit_criterion are all set
# V3   approver is a named role or person, never the machine
# V4   exit_criterion contains a figure
# V5   at least one assumption is declared
# V6   the unit is defined, and its kind is rule or judgment
# V7   a judgment decomposition says what checks it
# V8   fan-out is a number and carries a reason
# V9   step ids run 1..N with no gaps
# V10  every step has a known type and actor, and a description of substance
# V11  type and actor agree: only thinking is performed by a model or a human
# V12  exactly one thinking step, or a written justification for more
# V13  every thinking step is followed by a test or a gate
# V14  at least two gates
# V15  every gate condition contains a number, a comparison or the word never
# V16  every refusal names a next human action, and is not a placeholder
# V17  the proof is written by a mechanical step
# V18  evidence declares an integrity check
# V19  at least three KPIs, including one cost and one quality
# V20  an unmeasured baseline is allowed, and warned about
# V21  step scope is batch or unit, and every batch step comes first
# V22  every gate attaches to a step that exists
# V23  at least one KPI measures Total Value Realized: tvr-velocity, tvr-throughput, tvr-speed or tvr-margin
# V24  every KPI kind is one of the eight: cost, quality, throughput, control or a tvr-* kind
# V25  every step typed gate is named by a gate
# V26  the design declares its record layer: transitions, units, retention, acceptance
# V27  every source and tool it names is in the catalog
# V28  it takes only fields the catalogued tool actually provides — narrow, never invent
# V29  every tool is used by a step that exists
# V30  every source constraint is structural (never/only) or evaluable
# V31  no tool carrying PHI is used by a step whose actor is a model
# END RULES

# The catalog, flattened so validate.awk can read it without a second parser.
# A design that names sources and cannot be checked against a catalog is a design
# whose data contract nobody verified, so this is passed deliberately or the
# source rules refuse.
HERE=$(cd "$(dirname "$0")" && pwd)
CATALOG=${CATALOG:-$HERE/../catalog/eb-tools.catalog}
CATFILE=""
if [ -f "$CATALOG" ]; then
  CATFILE=$(mktemp)
  # A quoted heredoc, not printf: printf turns the \n into a real newline
  # inside the awk string literal and the query file stops parsing.
  cat > "$CATFILE.q" <<'CATQ'
END{ for(i=1;i<=t;i++) printf "%s\t%s\t%s\n", TID[i], T[TID[i] ".data_class"], T[TID[i] ".provides"] }
CATQ
  awk -f "$HERE/lib/catalog.awk" -f "$CATFILE.q" "$CATALOG" > "$CATFILE" 2>/dev/null
  rm -f "$CATFILE.q"
fi
trap '[ -n "$CATFILE" ] && rm -f "$CATFILE"' EXIT

awk -v mode="$MODE" -v CATFILE="$CATFILE" -f "$(dirname "$0")/lib/parse.awk" -f "$(dirname "$0")/lib/validate.awk" "$FILE"
