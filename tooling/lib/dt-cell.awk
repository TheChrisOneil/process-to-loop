# What one CELL of a decision table admits. Pure functions, no parser state, so
# the validator and the emitted evaluator share one definition of what a rule
# means. Two copies of this would be two dialects of the same table.
#
#   -            any value matches
#   literal      equal, case-folded
#   >n <n >=n <=n !=n =n   numeric comparison
#   [a..b]       numeric range, inclusive
#   a,b,c        any one of these literals

# Does one cell admit one value?
function dt_cell_matches(cell, v,   lo, hi, n, P, i) {
  gsub(/^ +| +$/, "", cell)
  if (cell == "" || cell == "-") return 1
  if (cell ~ /^\[.*\.\..*\]$/) {
    lo = cell; sub(/^\[/, "", lo); sub(/\.\..*$/, "", lo)
    hi = cell; sub(/^.*\.\./, "", hi); sub(/\]$/, "", hi)
    if (v !~ /^-?[0-9.]+$/) return 0
    return (v + 0 >= lo + 0 && v + 0 <= hi + 0)
  }
  if (cell ~ /^(>=|<=|>|<|!=|=)/) {
    if (v !~ /^-?[0-9.]+$/) return 0
    if (cell ~ /^>=/) { sub(/^>=/, "", cell); return (v + 0 >= cell + 0) }
    if (cell ~ /^<=/) { sub(/^<=/, "", cell); return (v + 0 <= cell + 0) }
    if (cell ~ /^!=/) { sub(/^!=/, "", cell); return (v + 0 != cell + 0) }
    if (cell ~ /^>/)  { sub(/^>/,  "", cell); return (v + 0 >  cell + 0) }
    if (cell ~ /^</)  { sub(/^</,  "", cell); return (v + 0 <  cell + 0) }
    sub(/^=/, "", cell); return (v + 0 == cell + 0)
  }
  if (cell ~ /,/) {
    n = split(cell, P, / *, */)
    for (i = 1; i <= n; i++) { gsub(/^ +| +$/, "", P[i]); if (tolower(P[i]) == tolower(v)) return 1 }
    return 0
  }
  return (tolower(cell) == tolower(v))
}

# Two cells can both admit some value. Used for overlap, where the question is
# not "do these match an input" but "could they ever match the SAME input".
# Literal against literal is exact; anything numeric is treated as possibly
# overlapping, because proving two ranges disjoint is a different job and
# claiming a proof we did not do is worse than declining to.
function dt_cells_overlap(a, b,   la, lb) {
  gsub(/^ +| +$/, "", a); gsub(/^ +| +$/, "", b)
  if (a == "" || a == "-" || b == "" || b == "-") return 1
  la = (a ~ /^(>=|<=|>|<|!=|=|\[)/ || a ~ /,/)
  lb = (b ~ /^(>=|<=|>|<|!=|=|\[)/ || b ~ /,/)
  if (la || lb) return 1
  return (tolower(a) == tolower(b))
}
