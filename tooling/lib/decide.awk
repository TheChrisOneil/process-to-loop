# Evaluate a decision table TSV against one set of inputs. Read after dt-cell.awk.
# -v IN="v1\x1fv2\x1f..."   the input values, unit-separator delimited
#
# Exit 0 and print the outputs, tab separated.
# Exit 1 when no rule matches — a fall-through is a refusal, never a default.
# Exit 75 when the table or the arity is wrong — the same 75 every gate check in
# this project uses for could-not-run, so a gate may pass this code straight
# through without translating it into a business failure.
BEGIN { FS="\t"; nvals = split(IN, VAL, "\037") }
/^#table/   { TID=$2; HIT=$3; next }
/^#inputs/  { NIN=NF-1;  for (i=2;i<=NF;i++) INAME[i-1]=$i; next }
/^#outputs/ { NOUT=NF-1; for (i=2;i<=NF;i++) ONAME[i-1]=$i; next }
/^#/        { next }
/^[[:space:]]*$/ { next }
{
  nrules++
  if (matched && HIT == "first") next
  for (i=1; i<=NIN; i++) if (!dt_cell_matches($i, VAL[i])) next
  if (matched && HIT == "unique") {
    printf "REFUSED: two rules in %s match the same input. The table said unique.\n", TID > "/dev/stderr"
    exit 75
  }
  matched = 1
  out = ""
  for (i=1; i<=NOUT; i++) out = out (i>1 ? "\t" : "") $(NIN+i)
  RESULT = out
}
END {
  if (NIN == 0) { print "REFUSED: no #inputs line — this is not a decision table." > "/dev/stderr"; exit 75 }
  if (nvals != NIN) {
    printf "REFUSED: %s takes %d input(s) and got %d.\n", TID, NIN, nvals > "/dev/stderr"
    printf "         in order: " > "/dev/stderr"
    for (i=1;i<=NIN;i++) printf "%s%s", (i>1?", ":""), INAME[i] > "/dev/stderr"
    printf "\n" > "/dev/stderr"
    exit 75
  }
  if (!matched) {
    printf "REFUSED: no rule in %s matches" , TID > "/dev/stderr"
    for (i=1;i<=NIN;i++) printf " %s=%s", INAME[i], VAL[i] > "/dev/stderr"
    printf "\n         A table that falls through has a case nobody decided. That is a\n" > "/dev/stderr"
    printf "         refusal, never a default.\n" > "/dev/stderr"
    exit 1
  }
  print RESULT
}
