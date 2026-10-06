# One decision table -> one TSV the runtime matcher reads. Deterministic.
# -v WANT=<table id>
#
# TSV, because the emitted bundle must run with nothing but a filesystem and awk.
# A generated bash if-chain would put the cell semantics in a second place, and
# two definitions of what ">= 2000" means is how a table starts disagreeing with
# the rules that validated it.
END {
  for (ez=1; ez<=n_dt; ez++) {
    eid = DTID[ez]
    if (WANT != "" && eid != WANT) continue
    printf "#table\t%s\t%s\n", eid, DTHIT[eid]
    en = split(DTIN[eid], EI, / *\| */);  printf "#inputs"
    for (ec=1; ec<=en; ec++) printf "\t%s", EI[ec]; printf "\n"
    eo = split(DTOUT[eid], EO, / *\| */); printf "#outputs"
    for (ec=1; ec<=eo; ec++) printf "\t%s", EO[ec]; printf "\n"
    for (er=1; er<=DTNR[eid]+0; er++) {
      ecn = dt_cells(eid, er, EC)
      for (ec=1; ec<=ecn; ec++) { gsub(/^ +| +$/, "", EC[ec]); printf "%s%s", (ec>1 ? "\t" : ""), EC[ec] }
      printf "\n"
    }
  }
}
