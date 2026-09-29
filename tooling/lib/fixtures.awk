# A gate condition -> a fixture table the check script must satisfy.
#
# V15 guarantees every condition carries a number, a comparison, or the word
# "never", so there is always something to build a boundary case from.
#
# -v N=<gate number> -v COND=<condition> -v REFUSAL=<refusal>
#
# Emits TSV: name <TAB> value <TAB> expect <TAB> why
# expect is one of:
#   refuse   the condition holds, so the gate fires and the script exits non-zero
#   proceed  the condition does not hold, so the script exits 0 and work continues
#   declare  the tool cannot settle this case; the author must change it to one
#            of the other two before the check is trusted
#
# The condition in a design describes WHAT REFUSES. Everything here follows from
# that one sentence, and getting it backwards is the most common gate defect.
function num(t,   s) { s=t; gsub(/,/,"",s); return s+0 }
# the step is one unit of the literal's own precision: 2000 -> 1, 0.01 -> 0.01
function step(lit,   s, d) { s=lit; gsub(/,/,"",s)
  if (index(s,".")==0) return 1
  d = length(s) - index(s,".")
  return 10 ^ -d }
function dec(lit,   s) { s=lit; gsub(/,/,"",s)
  if (index(s,".")==0) return 0
  return length(s) - index(s,".") }
function fmt(v, d) { return sprintf("%.*f", d, v) }
END {
  c = tolower(COND)
  print "# fixtures for gate " N
  print "# condition: " COND
  print "# refusal:   " REFUSAL
  print "#"
  print "# Every row must hold before this check is trusted. A row marked declare is a"
  print "# boundary the condition does not settle — decide it, and change declare to"
  print "# pass or refuse. Off by one at a threshold is the most common gate defect."
  printf "name\tvalue\texpect\twhy\n"

  found = 0
  # strictly-greater forms: over N, above N, more than N, greater than N, > N
  if (match(c, /(over|above|more than|greater than|exceeds|>)[ =]*\$?[0-9][0-9,.]*/)) {
    m = substr(c, RSTART, RLENGTH); v = m; sub(/^[^0-9]*/,"",v)
    t = num(v); e = step(v); d = dec(v)
    printf "below\t%s\tproceed\tunder the threshold, so the condition does not hold\n", fmt(t-e, d)
    printf "at\t%s\tdeclare\t\"%s\" — does the threshold itself trip it?\n", fmt(t, d), m
    printf "above\t%s\trefuse\tover the threshold, so the condition holds and the gate fires\n", fmt(t+e, d)
    found = 1
  }
  # strictly-less forms: under N, below N, less than N, fewer than N, < N
  else if (match(c, /(under|below|less than|fewer than|<)[ =]*\$?[0-9][0-9,.]*/)) {
    m = substr(c, RSTART, RLENGTH); v = m; sub(/^[^0-9]*/,"",v)
    t = num(v); e = step(v); d = dec(v)
    printf "above\t%s\tproceed\tover the threshold, so the condition does not hold\n", fmt(t+e, d)
    printf "at\t%s\tdeclare\t\"%s\" — does the threshold itself trip it?\n", fmt(t, d), m
    printf "below\t%s\trefuse\tunder the threshold, so the condition holds and the gate fires\n", fmt(t-e, d)
    found = 1
  }
  # any bare number, as a last resort
  else if (match(c, /[0-9][0-9,.]*/)) {
    v = substr(c, RSTART, RLENGTH); t = num(v); e = step(v); d = dec(v)
    printf "below\t%s\tdeclare\tthe condition names %s but not which way the comparison runs\n", fmt(t-e,d), v
    printf "at\t%s\tdeclare\tthe condition names %s but not which way the comparison runs\n", fmt(t,d), v
    printf "above\t%s\tdeclare\tthe condition names %s but not which way the comparison runs\n", fmt(t+e,d), v
    found = 1
  }
  # differs / does not match / is not equal — a comparison with no number in it
  if (!found && c ~ /(differs|does not match|not match|is not equal|mismatch|unequal|changed from)/) {
    printf "same\t<two identical values>\tproceed\tthey agree, so the condition does not hold\n"
    printf "different\t<two values that differ>\trefuse\tthey disagree, so the condition holds\n"
    printf "one-missing\t<one side absent>\tdeclare\tabsent is not the same as different — decide which it is\n"
    found = 1
  }
  if (c ~ /never/) {
    printf "any\t-\trefuse\tthe condition says never, so every unit trips this gate\n"
    found = 1
  }
  if (!found)
    printf "unknown\t-\tdeclare\tno number, comparison or \"never\" was found — write the fixtures by hand\n"

  # these two hold for every gate, whatever it checks
  printf "absent\t<none>\tdeclare\tthe field is missing entirely — refuse, or exit 75 if it means the source is unreachable\n"
  printf "unreadable\t-\tdeclare\tthe source cannot be read — this is the only case that may exit 75\n"
}
