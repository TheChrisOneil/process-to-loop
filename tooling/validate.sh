#!/usr/bin/env bash
# THE VALIDATOR — a gate over a design, before anybody is shown it.
#
# Every check below is deterministic, costs nothing, and cannot be argued with. That is the
# point: the tool that teaches "a gate's condition lives in code" is itself governed by one.
#
#   ./validate.sh <design file>          human-readable findings; exit 1 on any ERROR
#   ./validate.sh --tsv <design file>    machine-readable, for a later step to gate on
#   ./validate.sh --rules                print the rule list and exit
#
# env: CATALOG    the tool catalog the design is checked against
#      METHOD     the authoring method (GENERATE.md) this design was written
#                 from. Versioned for the same reason INTERVIEW.md is: two
#                 designs written by different methods are not comparable, and
#                 nothing else records which one ran.
#      QUESTIONS  the QUESTIONS.md this design was authored from. Supplying it
#                 turns on V32-V34, which are what make an answered question
#                 traceable into the design. Omitting it is reported, not silent.
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
# V31  PHI reaches a model only where the catalog says it may, under a current attestation
# V32  the design names the question set it was authored from, by digest
# V33  every question asked is cited by an assumption, as [Qn]
# V34  the citing assumption carries the answer's provenance: stated, unanswered or delegated
# V35  every decision table declares inputs, outputs and at least one rule
# V36  every decision table names a hit policy: unique or first
# V37  every rule has one cell per input and per output
# V38  under a unique policy, no two rules claim the same input
# V39  a gate naming a decision table names a real table and a real output
# V40  every skill a step DEPENDS on is in the catalog; a proposal needs nobody
# V41  every skill is used by a step that exists, and never by a gate step
# V42  no gate condition depends on a skill — know-how that decides is a decision table
# V43  no design names a skill whose review date has passed
# V44  the design names the authoring method that wrote it, by digest
# V45  know-how the design needs and the catalog lacks is reported, not refused
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
END{ for (k in CAT) { ck=k; sub(/^catalog\./,"",ck); printf "#catalog\t%s\t%s\n", ck, CAT[k] }
     for(i=1;i<=ns;i++) printf "#skill\t%s\t%s\t%s\n", SKID[i], SK[SKID[i] ".review_by"], SK[SKID[i] ".owner"]
     for(i=1;i<=t;i++) printf "%s\t%s\t%s\n", TID[i], T[TID[i] ".data_class"], T[TID[i] ".provides"] }
CATQ
  awk -f "$HERE/lib/catalog.awk" -f "$CATFILE.q" "$CATALOG" > "$CATFILE" 2>/dev/null
  rm -f "$CATFILE.q"
fi
# The question set, flattened the same way, plus its digest. A design is bound to
# the interview that produced it exactly as acceptance is bound to the design: by
# content, never by filename. Supplying no question set is legal and is WARNED
# about rather than passed over — a rule that quietly does not run is the defect
# this whole project is about.
METHOD=${METHOD:-}
MSHA=""
[ -z "$METHOD" ] || [ ! -f "$METHOD" ] || MSHA=$(shasum -a 256 "$METHOD" | cut -d' ' -f1)
QUESTIONS=${QUESTIONS:-}
QFILE=""; QSHA=""
if [ -n "$QUESTIONS" ] && [ -f "$QUESTIONS" ]; then
  QSHA=$(shasum -a 256 "$QUESTIONS" | cut -d' ' -f1)
  QFILE=$(mktemp)
  cat > "$QFILE.q" <<'QQ'
END { for (qx=1; qx<=nq; qx++) { qd=QID[qx]
  printf "%s\t%s\t%s\n", qd, Q[qd ".class"], Q[qd ".answer_type"] } }
QQ
  awk -f "$HERE/lib/questions.awk" -f "$QFILE.q" "$QUESTIONS" > "$QFILE" 2>/dev/null
  rm -f "$QFILE.q"
fi
trap '[ -n "$CATFILE" ] && rm -f "$CATFILE"; [ -n "$QFILE" ] && rm -f "$QFILE"' EXIT

awk -v mode="$MODE" -v CATFILE="$CATFILE" -v QFILE="$QFILE" -v QSHA="$QSHA" -v MSHA="$MSHA" -v TODAY="$(date +%F)" \
    -f "$(dirname "$0")/lib/parse.awk" -f "$(dirname "$0")/lib/dt-cell.awk" \
    -f "$(dirname "$0")/lib/decisions.awk" \
    -f "$(dirname "$0")/lib/validate.awk" "$FILE"
