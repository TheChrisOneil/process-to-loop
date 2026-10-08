# Which skills does one step apply? Read after parse.awk.
#   -v STEP=<step id>    prints one skill id per line
#
# Mirrors gates.awk and the tools lookup: one place that knows what the @skills
# table means, so the emitter and the validator cannot disagree about it.
END {
  for (z=1; z<=n_skill; z++) {
    nb = split(SKL_BY[z], B, / +/)
    for (y=1; y<=nb; y++) {
      sid = B[y]; gsub(/^ +| +$/, "", sid)
      if (sid != "" && sid == STEP) { print SKL_ID[z]; break }
    }
  }
}
