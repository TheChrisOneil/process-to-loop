# Decision-table access over the parsed design. Read after parse.awk, and load
# lib/dt-cell.awk alongside it for what a cell means — that half is pure, and
# the emitted evaluator loads it too.
#
# A CELL is one of:
#   -            any value matches
#   "literal"    equal, case-folded
#   >n <n >=n <=n   numeric comparison
#   [a..b]       numeric range, inclusive
#   a,b,c        any one of these literals
#
# The reason the whole feature exists is that these three questions are
# answerable about a table and are not answerable about a bash conditional:
#   does any input fall through?        completeness
#   do two rules claim the same input?  overlap
#   is any output never produced?       dead branch

function dt_cells(id, r, OUT,   raw) {
  raw = DTR[id, r]
  return split(raw, OUT, / *\| */)
}

