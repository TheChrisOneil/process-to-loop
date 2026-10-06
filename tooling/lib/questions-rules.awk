# The rules over a question set. Appended to questions.awk, so it reads that
# parser's arrays and no second parser can disagree with it.
#
#   mode=validate   form only: can this set of questions be asked?
#   mode=answered   form, and has every block come back with an answer?
#
# I-rules are about the questions. A-rules are about the answers.

function rec(sev, rid, msg, fix) { nr++; SEV[nr]=sev; RID[nr]=rid; MSG[nr]=msg; FIX[nr]=fix
                                   if (sev=="ERROR") errs++ }
function ok(rid, msg) { nr++; SEV[nr]="PASS"; RID[nr]=rid; MSG[nr]=msg; passes++ }
BEGIN {
  if (CATFILE != "") { while ((getline cl < CATFILE) > 0) if (cl != "") CTOOL[cl]=1; close(CATFILE) }
}
END {
  # ---- form ----
  hm=""
  split("interview asked catalog use_case_sha256", HK, " ")
  for (hx=1; hx<=4; hx++) if (!(HK[hx] in H) || H[HK[hx]]=="") hm = hm " " HK[hx]
  if (hm=="") ok("I1","the header names the interview, the date, the catalog and the use case")
  else rec("ERROR","I1","the header is missing:" hm,"a question set that does not say which use case it is about is a question set about nothing")

  if (nq>0) ok("I2", nq " question(s)")
  else rec("ERROR","I2","no questions","a design written with nothing asked is the thing this step replaces")

  badid=""
  for (qx=1; qx<=nq; qx++) if (QID[qx] != "Q" qx) badid = badid " " QID[qx]
  if (badid=="") { if (nq>0) ok("I3","question ids run Q1..Q" nq) }
  else rec("ERROR","I3","ids are not sequential from Q1:" badid,"renumber them — a finding cites a question by id")

  miss=""; vague=""; badclass=""; nstruct=0
  for (qx=1; qx<=nq; qx++) { qd=QID[qx]
    if (Q[qd ".class"]=="" || Q[qd ".asks"]=="" || Q[qd ".why"]=="") miss = miss " " qd
    qc = Q[qd ".class"]
    if (qc != "structural" && qc != "parametric" && qc != "") badclass = badclass " " qd
    if (qc == "structural") nstruct++
    if (length(Q[qd ".asks"]) > 0 && (length(Q[qd ".asks"]) < 20 || Q[qd ".asks"] !~ /\?/)) vague = vague " " qd
  }
  if (miss=="") { if (nq>0) ok("I4","every question carries a class, what it asks and why it matters") }
  else rec("ERROR","I4","missing class, asks or why at:" miss,"all three are required — why it matters is what makes an answer worth giving")
  if (badclass=="") { if (nq>0) ok("I5","every class is structural or parametric") }
  else rec("ERROR","I5","unknown class at:" badclass,"structural blocks, parametric defers — there is no third kind")
  if (vague=="") { if (nq>0) ok("I6","every question is asked as a question") }
  else rec("ERROR","I6","not asked as a question at:" vague,"write the sentence you would say out loud, ending in a question mark")

  if (nstruct>0) ok("I7", nstruct " structural question(s)")
  else rec("ERROR","I7","no structural question","the unit, the judgment and the sources are structural, and no design can be written without them")

  # A catalog: line that names something the organization does not have is
  # the interview inventing a tool, which is exactly what the catalog exists
  # to stop. The word none is the honest answer, and it is a finding later.
  ghost=""
  for (qx=1; qx<=nq; qx++) { qd=QID[qx]; qct=Q[qd ".catalog"]
    if (qct=="" || tolower(qct)=="none") continue
    qn2=split(qct, CF, / /); qtool=CF[1]; sub(/[,:].*$/,"",qtool)
    if (!(qtool in CTOOL)) ghost = ghost " " qd "(" qtool ")"
  }
  if (ghost=="") ok("I8","every catalog reference names a tool the organization has")
  else rec("ERROR","I8","catalog references nothing has:" ghost,"name a catalogued tool or write none — a need the catalog cannot meet is a finding, not an invention")

  # ---- completeness, only in answered mode ----
  if (mode=="answered") {
    op=""; badtype=""; novalue=""; noassume=""; noowner=""; baddate=""; badprov=""; thin=""; nans=0
    for (qx=1; qx<=nq; qx++) { qd=QID[qx]; qt=Q[qd ".answer_type"]
      if (qt=="") { op = op " " qd; continue }
      nans++
      if (qt!="stated" && qt!="unanswered" && qt!="delegated") { badtype = badtype " " qd "(" qt ")"; continue }
      if (Q[qd ".answer_nf"]+0 < 4) thin = thin " " qd
      if (Q[qd ".answer_by"]=="") noowner = noowner " " qd
      if (Q[qd ".answer_date"] !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) baddate = baddate " " qd
      qp = Q[qd ".answer_prov"]
      if (qp!="real" && qp!="synthetic" && qp!="") badprov = badprov " " qd
      if (qt=="stated" && Q[qd ".answer_value"]=="") novalue = novalue " " qd
      if (qt=="delegated" && Q[qd ".answer_value"] !~ /^assumed:/) noassume = noassume " " qd
    }
    if (op=="") ok("A1","every question has an answer")
    else rec("ERROR","A1","no answer at:" op,"stated, unanswered or delegated — all three are legal, and silence is not one of them")
    if (badtype=="") { if (nans>0) ok("A2","every answer type is one of the three") }
    else rec("ERROR","A2","unknown answer type at:" badtype,"stated, unanswered or delegated")
    if (thin=="" && noowner=="") { if (nans>0) ok("A3","every answer names who gave it, and when") }
    else { if (thin!="") rec("ERROR","A3","answer has fewer than four fields at:" thin,"type | by | date | value")
           if (noowner!="") rec("ERROR","A3","no author at:" noowner,"an unanswered question still names who owes the answer") }
    if (baddate=="") { if (nans>0) ok("A4","every answer carries an ISO date") }
    else rec("ERROR","A4","the date is not YYYY-MM-DD at:" baddate,"an answer with no date cannot be told from a later one")
    if (novalue!="") rec("ERROR","A5","stated with no value at:" novalue,"that is an unanswered question wearing the wrong label")
    else if (nans>0) ok("A5","every stated answer carries a value")
    if (noassume!="") rec("ERROR","A6","delegated without assumed: at:" noassume,"record the value chosen on their behalf, so they can disagree with it at the gate")
    else if (nans>0) ok("A6","every delegated answer says what was assumed")
    if (badprov!="") rec("ERROR","A7","unknown provenance at:" badprov,"real or synthetic")
    else if (nans>0) ok("A7","every answer declares whether it is real or synthetic")
  }

  for (rx=1; rx<=nr; rx++) {
    if (SEV[rx]=="PASS") printf "  \033[32mPASS\033[0m  %-4s %s\n", RID[rx], MSG[rx]
    else printf "  \033[31mFAIL\033[0m  %-4s %s\n            fix: %s\n", RID[rx], MSG[rx], FIX[rx]
  }
  printf "\n  %d passed, %d failed\n", passes+0, errs+0
  exit (errs>0 ? 1 : 0)
}
