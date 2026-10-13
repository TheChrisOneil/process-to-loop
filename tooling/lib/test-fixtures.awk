# One TEST step -> the obligations its fixtures must cover. Read after parse.awk.
#   -v STEP=<step id>
#
# A gate's fixtures can be generated from its condition because a condition is a
# predicate over one value: "more than 0" mechanically yields below, at, above,
# absent. A test step's description is not a predicate, so its fixtures cannot be
# generated the same way — the data it recomputes over is not derivable from the
# sentence.
#
# What IS derivable is the list of CLAIMS, and the obligation each one creates.
# A test step says it recomputes "that X, that Y, and that Z". Each of those is a
# thing the step must be able to CATCH, and the table below forces a constructed
# case per claim in both directions.
#
# The failure mode this exists to catch: a test step that passes everything. That
# is the polarity bug, in the shape it takes for a test — a gate that never
# refuses is obvious, and a test that never fails looks like success.

function emit(n, claim, expect, why) {
  printf "%s\t%s\t%s\t%s\n", n, claim, expect, why
}

END {
  for (i=1; i<=s; i++) if (SID[i]==STEP) { found=i; break }
  if (!found) { print "no step " STEP " in this design" > "/dev/stderr"; exit 2 }
  if (tolower(STYPE[found]) != "test") {
    printf "step %s is type %s, not test\n", STEP, STYPE[found] > "/dev/stderr"
    print "Fixtures of this shape are for a test step: one that recomputes a claim." > "/dev/stderr"
    exit 2
  }

  d = SDESC[found]
  print "# fixtures for step " STEP " (" SNAME[found] "), a test step"
  print "# recomputes: " d
  print "#"
  print "# Every row must hold before this step is trusted. A test step's own"
  print "# failure mode is passing everything: a gate that never refuses is"
  print "# obvious, and a test that never fails looks like success."
  print "#"
  print "# Each claim below needs TWO constructed cases. The step must pass the"
  print "# satisfying one and FAIL the violating one. A claim with no violating"
  print "# case is a claim nothing verifies."
  print "#"
  print "claim\tcase\texpect\twhy"

  # Claims are the "that ..." clauses, and the separator needs the COMMA.
  # Splitting on a bare "that" tears a relative clause in half: "only names that
  # pass the screen of step 11" became two claims, one of them the fragment
  # "pass the screen of step 11". A new claim is introduced by ", that" or
  # ", and that"; a bare "that" mid-sentence is describing the thing before it.
  #
  # The first claim is different: it follows the only "that" with no comma, the
  # one that opens the list.
  head = d
  rest = ""
  if (match(d, / that /)) {
    head = substr(d, 1, RSTART - 1)
    rest = substr(d, RSTART + 6)
  }
  n = split(rest, P, /, *(and )?that /)
  k = 0
  for (j=1; j<=n; j++) {
    c = P[j]
    sub(/[,;.]+ *$/, "", c)
    gsub(/^ +| +$/, "", c)
    if (c == "") continue
    k++
    emit("claim-" k, c, "holds -> pass", "construct a record that satisfies this")
    emit("claim-" k, c, "violated -> FAIL", "construct one that breaks it; a step that passes this is not testing it")
  }

  if (k == 0) {
    emit("claim-1", d, "holds -> pass", "the description names no claims with that; treat the whole of it as one")
    emit("claim-1", d, "violated -> FAIL", "construct a case that breaks it")
  }

  # Obligations that hold for every test step, from its type rather than its text.
  print ""
  print "# From the type, not the description. These hold for any test step."
  emit("source", "recomputes from the RAW source, not from the output it checks", "must", "a test reading the claim it is checking proves only that a value equals itself")
  emit("no-model", "contains no provider call", "must", "a test that asks a model is not a recomputation")
  emit("determinism", "same record twice, same verdict", "must", "a test that varies cannot be relied on to catch anything")
  emit("exit-75", "exits 75 when the source cannot be read", "must", "never a business failure; the claim was not disproved, it was not evaluated")
}
