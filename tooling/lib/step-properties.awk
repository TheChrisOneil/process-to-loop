# A step's declared type -> the properties its script must hold.
#
# A gate has a condition, so its fixtures are values. A step has no condition —
# it has a TYPE, and the type is a promise about what the code may do. These are
# that promise, made checkable.
#
# -v ID= -v SLUG= -v TYPE= -v ACTOR= -v SCOPE= -v EVIDENCE_STEP=
#
# Emits TSV: property <TAB> rule <TAB> why
END {
  t = tolower(TYPE); a = tolower(ACTOR); s = tolower(SCOPE)
  print "# properties for step " ID " (" SLUG ")"
  print "# type: " TYPE "   actor: " ACTOR "   scope: " SCOPE
  print "#"
  print "# Every property must hold before this step is trusted. They come from the"
  print "# step's declared type, which is a promise about what the code may do."
  printf "property\trule\twhy\n"

  printf "contract\ttakes $1 as the unit id and $2 as the value\tevery step in a bundle is called the same way\n"
  printf "ledger\twrites a ledger line on every exit path\ta step that returns silently cannot be costed or audited\n"
  printf "confinement\twrites only under memory/, proof/ and outbox/\ta step that writes elsewhere is a side effect nobody recorded\n"

  if (t == "mechanical" || t == "coordination" || t == "test") {
    printf "no-model\tcontains no provider call\tthis type is a rule; a rule that asks a model is not a rule\n"
    printf "determinism\tsame input twice, byte-identical output\tthe definition of this type, and it is runnable\n"
  }
  if (t == "thinking" && a == "model") {
    printf "is-model\tcalls exactly one provider, once per unit\tthe design names one judgment; two is a design change\n"
    printf "records-cost\twrites a usage row for the call\ta call nobody metered cannot appear in a budget\n"
    printf "quotes-evidence\tthe output points at what it relied on\tan assertion with nothing behind it cannot be checked\n"
  }
  if (t == "thinking" && a == "human") {
    printf "is-human\tblocks for a person; does not decide on their behalf\tthe design puts a person in this seat\n"
  }
  if (t == "test") {
    printf "before-state\tchecks against the state before the step it verifies\ta test that reads the after-state proves nothing\n"
  }
  if (s == "batch") {
    printf "batch-scope\truns once per tick and assumes no unit\tbatch steps run before any unit exists\n"
  } else {
    printf "unit-scope\truns once per unit and assumes exactly one\ta unit step that loops is doing the runner's job\n"
  }
  if (ID == EVIDENCE_STEP) {
    printf "writes-proof\twrites the proof and its checksum\tthe design names this step as the writer\n"
  } else {
    printf "no-proof\tdoes not write into proof/\tonly the step the design names may write evidence\n"
  }
}
