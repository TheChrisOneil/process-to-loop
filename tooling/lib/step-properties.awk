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

  # Determinism is true of every code kind and is the ORACLE for none of them.
  # Running a script twice and comparing bytes says nothing about whether a tool
  # call read a field its catalog entry covers, or whether a decision table has
  # a row for every combination of its inputs. So the shared promises stay shared
  # and each kind then earns the property that actually checks it.
  if (t == "mechanical" || t == "coordination" || t == "test" \
      || t == "tool-call" || t == "decision") {
    printf "no-model\tcontains no provider call\tthis type is a rule; a rule that asks a model is not a rule\n"
    printf "determinism\tsame input twice, byte-identical output\tnecessary for every code step and sufficient for none\n"
  }
  if (t == "tool-call") {
    printf "catalogued\treads and writes only through tools named in @tools\ta call to something nobody sanctioned is a call nobody reviewed\n"
    printf "field-covered\tevery field it reads is one its catalog entry lists\tthe entry is the oracle; a field outside it was assumed\n"
    printf "logs-provenance\twrites a read row naming the source, the tool and the data class\tan auditor asking where a number came from reads this row\n"
  }
  if (t == "decision") {
    printf "table-backed\tevery outcome it returns comes from a named decision table\ta branch written in the script is a rule the validator never saw\n"
    printf "no-fallthrough\tno outcome is produced for input the table does not cover\tthe table is complete by construction; a default hides the gap it leaves\n"
    printf "shared-semantics\tevaluates cells through the bundled dt-cell.awk, not its own comparison\ttwo copies of what \">= 2000\" means are two dialects\n"
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
