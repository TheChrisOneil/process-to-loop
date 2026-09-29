# design -> a Gas City formulas v2 file.
#
# Deterministic: same design in, same bytes out. Read after lib/parse.awk, which
# is the workshop's parser — so this emitter and the loop emitter cannot disagree
# about what a design says.
#
# -v NAME=<formula name>   required
# -v CHECKDIR=<path>       where check scripts live, repo-relative

function slug(t,   s) { s=tolower(t); gsub(/[^a-z0-9]+/,"-",s); gsub(/^-+|-+$/,"",s)
                        if (length(s)>24) s=substr(s,1,24); gsub(/-+$/,"",s); return s }
function esc(t,   s)  { s=t; gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); return s }
function block(t,   s){ s=t; gsub(/"""/,"'''",s); return s }
function tt(t, n,   s){ s=t; gsub(/^[ \t]+|[ \t]+$/,"",s)
                        if (n>0 && length(s)>n) s=substr(s,1,n-1) "…"
                        return s }

END {
  if (NAME=="") { print "emit-formula: -v NAME= is required" > "/dev/stderr"; exit 64 }
  if (CHECKDIR=="") CHECKDIR=".gc/scripts/checks"

  approver = (V["meta.approver"]!="" ? V["meta.approver"] : "a named approver")

  # ---- which emitted step does each design step become, and where do gates sit
  # gates attach AFTER the design step they name, as their own step, so the gate
  # blocks everything downstream instead of being a promise inside a step.
  for (i=1;i<=s;i++) EID[i] = sprintf("s%02d-%s", i, slug(SNAME[i]))
  for (j=1;j<=g;j++) {
    for (i=1;i<=s;i++) if (SID[i]==GAFT[j]) GAFTNAME[j]=SNAME[i]
    GEID[j] = sprintf("g%02d-%s", j, slug(GAFTNAME[j]!="" ? GAFTNAME[j] : GCOND[j]))
    GSCRIPT[j] = CHECKDIR "/" NAME "-g" sprintf("%02d", j) ".sh"
    for (i=1;i<=s;i++) if (SID[i]==GAFT[j]) GPOS[j]=i
  }

  # ---- header
  print "# Generated from a design by the formula compiler. Do not edit by hand."
  print "# Edit the design and compile again. This file cannot disagree with it."
  print ""
  print "formula = \"" esc(NAME) "\""
  print ""
  print "description = \"\"\""
  print block(tt(V["meta.use_case"]))
  print ""
  if (a>0) { print "Assumptions this method rests on:"
             for (n=1;n<=a;n++) print "  - " block(tt(ASSUM[n]))
             print "" }
  print "Unit of work: " block(tt(V["unit.definition"]))
  if (V["unit.kind"]!="")     print "Kind: " V["unit.kind"]
  if (V["unit.checked_by"]!="") print "Checked by: " block(tt(V["unit.checked_by"]))
  print ""
  print "Approver: " block(approver)
  if (V["meta.exit_criterion"]!="") print "Exit criterion: " block(tt(V["meta.exit_criterion"]))
  if (k>0) { print ""
             print "Measures:"
             for (n=1;n<=k;n++) print "  - " block(tt(KNAME[n])) " (" KKIND[n] "), baseline " block(tt(KBASE[n])) }
  print "\"\"\""
  print ""
  print "[requires]"
  print "formula_compiler = \">=2.0.0\""
  print ""
  print "[catalog]"
  print "name = \"" esc(NAME) "\""
  print "description = \"" esc(tt(V["meta.use_case"], 110)) "\""
  print ""

  # ---- vars
  print "[vars]"
  print ""
  print "[vars.notify]"
  print "description = \"Who is told when this method needs a person. A named role.\""
  print "default = \"" esc(approver) "\""
  print ""
  print "[vars.artifact_root]"
  print "description = \"Absolute path where this run writes its evidence.\""
  print "required = true"
  print ""

  # ---- steps
  prev = ""
  for (i=1;i<=s;i++) {
    ty = tolower(STYPE[i]); ac = tolower(SACT[i])
    print "# ---------------------------------------------------------------- " ty " ----"
    print "[[steps]]"
    print "id = \"" EID[i] "\""
    print "title = \"" esc(tt(SNAME[i], 90)) "\""
    if (prev != "") print "needs = [\"" prev "\"]"
    print "description = \"\"\""
    print block(tt(SDESC[i]))
    print ""
    if (ty=="thinking" && ac=="model") {
      print "This is the judgment in this method. It is the only step that reasons."
      if (V["unit.checked_by"]!="") print "It is checked by: " block(tt(V["unit.checked_by"]))
      print "Quote the evidence you relied on. Do not assert anything you cannot point at."
    } else if (ty=="thinking" && ac=="human") {
      print "A person does this. The gate below holds the method here until they close it."
      print "Notify {{notify}}."
    } else {
      print "Deterministic work only. Do not infer, do not fill gaps, and do not"
      print "decide anything this step was not told to decide."
    }
    if (V["evidence.writer_step"]==SID[i]) {
      print ""
      print "Write the proof for this unit under {{artifact_root}}: " block(tt(V["evidence.artifact"]))
      print "Integrity: " block(tt(V["evidence.integrity"]))
    }
    print ""
    print "Close with `gc.outcome=pass`, or `gc.outcome=fail` and a reason. Closing"
    print "without an outcome is read as a failure."
    print "\"\"\""
    prov = "\"eb.design_step\" = \"" esc(SID[i]) "\", \"eb.design_type\" = \"" esc(ty) "\""
    if (ty=="thinking" && ac=="model")
      print "metadata = { \"gc.run_target\" = \"gc.run-operator\", \"gc.provider\" = \"claude\", " prov " }"
    else if (ty=="thinking" && ac=="human")
      print "metadata = { \"eb.seat\" = \"" esc(approver) "\", " prov " }"
    else
      print "metadata = { \"gc.run_target\" = \"gc.run-operator\", " prov " }"
    if (ty=="thinking" && ac=="human") {
      print ""
      print "[steps.gate]"
      print "id = \"" EID[i] "-approval\""
      print "# The gate bead blocks this step until a person closes it. The type"
      print "# vocabulary has no runtime consumer, so it is not set."
    }
    print ""
    prev = EID[i]

    # any gate that names this design step becomes the next emitted step
    for (j=1;j<=g;j++) if (GPOS[j]==i) {
      print "# ---------------------------------------------------------------- gate ----"
      print "[[steps]]"
      print "id = \"" GEID[j] "\""
      print "title = \"Gate: " esc(tt(GCOND[j], 80)) "\""
      print "needs = [\"" prev "\"]"
      print "description = \"\"\""
      print "This step exists to run one check. It decides nothing itself."
      print ""
      print "The condition, from the design:"
      print "  " block(tt(GCOND[j]))
      print ""
      print "If the check refuses, the refusal is:"
      print "  " block(tt(GREF[j]))
      print ""
      print "The check is " GSCRIPT[j] ". Exit 0 to pass. Any other non-zero exit"
      print "is \"not yet\" and consumes an attempt. Exit 75 only when the check could"
      print "not run at all — never for a business failure."
      print ""
      print "Close with `gc.outcome=pass` or `gc.outcome=fail`."
      print "\"\"\""
      print "metadata = { \"gc.run_target\" = \"gc.run-operator\", \"eb.gate_after\" = \"" esc(GAFT[j]) "\" }"
      print ""
      print "[steps.check]"
      print "max_attempts = 1"
      print ""
      print "[steps.check.check]"
      print "mode = \"exec\""
      print "path = \"" GSCRIPT[j] "\""
      print "timeout = \"2m\""
      print ""
      prev = GEID[j]
    }
  }
}
