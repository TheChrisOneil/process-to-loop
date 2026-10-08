
function rec(sev,id,msg,fix) { n++; SEV[n]=sev; ID[n]=id; MSG[n]=msg; FIX[n]=fix
                               if (sev=="ERROR") errs++; if (sev=="WARN") warns++ }
function ok(id,msg) { n++; SEV[n]="PASS"; ID[n]=id; MSG[n]=msg; passes++ }
# A gate condition of the form "<table> yields <output> <value>" is checkable by
# construction: the table is executable, and V35-V38 already checked it. It is
# MORE checkable than prose, which is why it does not have to look like prose.
function decision_ref(c,   s) { s=tolower(c); return (s ~ /^[a-z0-9_-]+ +yields +[a-z0-9_-]+ +/) }
function decision_table(c,   P) { split(c, P, / +/); return P[1] }
function decision_out(c,   P)   { split(c, P, / +/); return P[3] }
function decision_val(c,   P, n, i, v) { n=split(c, P, / +/); v=""
  for (i=4; i<=n; i++) v = v (i>4 ? " " : "") P[i]; return v }
function checkable(c,   s) { if (decision_ref(c)) return 1
  s=tolower(c)
  # A condition is checkable when a script could evaluate it with no judgment: a figure, a
  # comparison, an absolute, or a stated equality or absence test.
  return (s ~ /[0-9]/ || s ~ /never/ || s ~ /[<>=]/ || s ~ /at least|at most/ ||
          s ~ /more than|less than|over |under |outside|not in/ ||
          s ~ /differs|mismatch|does not match|is missing|is absent|is empty|is not |fails|failed/) }

BEGIN {
  # The catalog, as toolid -> data_class and provides. Read once; every source
  # rule below leans on it, and a design naming a tool nobody catalogued is a
  # design pointing at something the organization has not sanctioned.
  CATN = 0
  if (CATFILE != "") {
    while ((getline cl < CATFILE) > 0) {
      n = split(cl, cf, "\t")
      if (n >= 1 && cf[1] == "#catalog") { CPOL[cf[2]] = cf[3]; continue }
      if (n >= 1 && cf[1] == "#skill")   { CSKILL[cf[2]] = 1; CSKREV[cf[2]] = cf[3]; CSKOWN[cf[2]] = cf[4]; CSKN++; continue }
      if (n >= 1 && cf[1] != "") { CATN++; CTOOL[cf[1]] = 1; CCLASS[cf[1]] = cf[2]; CPROV[cf[1]] = cf[3] }
    }
    close(CATFILE)
  }
  # The question set: id -> class, answer type. Loaded here for the same reason
  # the catalog is — one read, and every rule below leans on the same arrays.
  QN = 0
  if (QFILE != "") {
    while ((getline ql < QFILE) > 0) {
      nq2 = split(ql, qf, "\t")
      if (nq2 >= 1 && qf[1] != "") { QN++; QORD[QN] = qf[1]; QCLASS[qf[1]] = qf[2]; QTYPE[qf[1]] = qf[3] }
    }
    close(QFILE)
  }
}

END {
  # V1 sections
  missing=""
  if (!("meta.use_case" in V) && !("meta.author" in V)) missing=missing " @meta"
  if (a==0) missing=missing " @assumptions"
  if (!("unit.definition" in V)) missing=missing " @unit"
  if (s==0) missing=missing " @steps"
  if (g==0) missing=missing " @gates"
  if (!("evidence.writer_step" in V)) missing=missing " @evidence"
  if (k==0) missing=missing " @kpis"
  if (missing=="") ok("V1","every required section is present")
  else rec("ERROR","V1","sections missing or empty:" missing,"add them — see schema/DESIGN-FORMAT.md")

  # V2 meta completeness
  miss=""
  split("use_case author date approver exit_criterion",MK," ")
  for (i=1;i<=5;i++) if (!("meta." MK[i] in V) || V["meta." MK[i]]=="") miss=miss " " MK[i]
  if (miss=="") ok("V2","every @meta key is set")
  else rec("ERROR","V2","@meta is missing:" miss,"every key in @meta is required")
  if (length(V["meta.use_case"])>0 && length(V["meta.use_case"])<20)
      rec("ERROR","V2","use_case is " length(V["meta.use_case"]) " characters","state the business process in a full sentence")

  # V3 approver is human
  ap=tolower(V["meta.approver"])
  if (ap ~ /system|agent|automatic|the loop|n\/a|tbd|none/)
      rec("ERROR","V3","approver is \"" V["meta.approver"] "\"","name a role or a person — the machine never approves its own work")
  else if (ap!="") ok("V3","the approver is a named role or person")

  # V4 exit criterion has a figure
  if (V["meta.exit_criterion"]!="") {
      if (V["meta.exit_criterion"] ~ /[0-9]/) ok("V4","the exit criterion contains a figure")
      else rec("ERROR","V4","exit_criterion has no number","name the number on which you shut this down")
  }

  # V5 assumptions
  if (a>0) ok("V5",a " assumption(s) declared")
  else rec("ERROR","V5","no assumptions declared","a design that declares none is hiding them")

  # V6 / V7 unit
  ukind=tolower(V["unit.kind"])
  if (V["unit.definition"]=="") rec("ERROR","V6","the unit is not defined","name the smallest thing that gets one decision")
  else if (ukind!="rule" && ukind!="judgment") rec("ERROR","V6","unit kind is \"" V["unit.kind"] "\"","must be rule or judgment")
  else ok("V6","the unit is defined and its kind is " ukind)
  if (ukind=="judgment") {
      if (V["unit.checked_by"]=="" ) rec("ERROR","V7","the decomposition is a judgment and nothing checks it","a model deciding what work exists is an unchecked step — say what checks it")
      else ok("V7","the judgment decomposition names what checks it")
  } else if (ukind=="rule") ok("V7","the decomposition is a rule — nothing to check")

  # V8 fanout
  if (V["unit.fanout"] ~ /^[0-9]+$/ && V["unit.fanout_reason"]!="") ok("V8","fan-out is " V["unit.fanout"] " with a stated reason")
  else rec("ERROR","V8","fanout must be a number and fanout_reason must be set","width is bounded by contention, blast radius, or review capacity")

  # V9 step ids
  bad=0; for (i=1;i<=s;i++) if (SID[i]+0 != i) bad=1
  if (!bad && s>0) ok("V9","step ids run 1.." s)
  else rec("ERROR","V9","step ids are not sequential from 1","renumber them")

  # V10 / V11 step fields
  terr=""; aerr=""; derr=""; xerr=""
  for (i=1;i<=s;i++) {
      t=tolower(STYPE[i]); ac=tolower(SACT[i])
      if (t!="coordination" && t!="mechanical" && t!="thinking" && t!="test" && t!="gate") terr=terr " " SID[i]
      if (ac!="code" && ac!="model" && ac!="human") aerr=aerr " " SID[i]
      if (length(SDESC[i])<15) derr=derr " " SID[i]
      if (t!="thinking" && ac!="code") xerr=xerr " " SID[i]
      if (t=="thinking" && ac=="code") xerr=xerr " " SID[i]
      if (t=="thinking") { th++; THI[th]=i }
  }
  if (terr=="") ok("V10","every step has a known type"); else rec("ERROR","V10","unknown step type at step(s)" terr,"use coordination, mechanical, thinking, test or gate")
  if (aerr=="" && derr=="") ok("V10","every step has a known actor and a description of substance")
  else { if (aerr!="") rec("ERROR","V10","unknown actor at step(s)" aerr,"use code, model or human")
         if (derr!="") rec("ERROR","V10","description too short at step(s)" derr,"say what the step does, 15 characters minimum") }
  if (xerr=="") ok("V11","type and actor agree on every step")
  else rec("ERROR","V11","type and actor disagree at step(s)" xerr,"only a thinking step is performed by a model or a human")

  # V12 one thinking step
  if (th==1) ok("V12","exactly one thinking step")
  else if (th==0) rec("WARN","V12","no thinking step","a loop with no judgment is ordinary automation — correct, and cheaper")
  else if (V["unit.thinking_justification"]!="") rec("WARN","V12",th " thinking steps, with a justification","two of three are usually rules — check again")
  else rec("ERROR","V12",th " thinking steps and no justification","isolate one, or set thinking_justification in @unit")

  # V13 judgment is surrounded
  unsurrounded=""
  for (j=1;j<=th;j++) { i=THI[j]; found=0
      for (m=i+1;m<=s;m++) { t=tolower(STYPE[m]); if (t=="test" || t=="gate") { found=1; break } }
      if (!found) unsurrounded=unsurrounded " " SID[i] }
  if (th>0 && unsurrounded=="") ok("V13","every thinking step is followed by a test or a gate")
  else if (unsurrounded!="") rec("ERROR","V13","nothing checks the judgment at step(s)" unsurrounded,"a thinking step is surrounded, or it is unverified")

  # V14 gates
  if (g>=2) ok("V14",g " gates")
  else rec("ERROR","V14","only " g " gate(s)","at least two: one before the work, one before delivery")

  # V15 / V16 gate quality
  cerr=""; rerr=""; perr=""
  for (i=1;i<=g;i++) {
      if (!checkable(GCOND[i])) cerr=cerr " " i
      if (length(GREF[i])<25) rerr=rerr " " i
      r=tolower(GREF[i])
      if (r ~ /needs review|cannot proceed|escalate|tbd|for review|review required|see above/) perr=perr " " i
  }
  if (cerr=="") ok("V15","every gate condition is checkable")
  else rec("ERROR","V15","gate condition is not checkable at gate(s)" cerr,"state a number, a comparison, or the word never")
  if (rerr=="" && perr=="") ok("V16","every refusal names a next human action")
  else { if (rerr!="") rec("ERROR","V16","refusal too short at gate(s)" rerr,"name the next human action, 25 characters minimum")
         if (perr!="") rec("ERROR","V16","refusal is a placeholder at gate(s)" perr,"\"needs review\" is a state — name the action and who takes it") }

  # V21 scope
  serr=""; order_err=""; seen_unit=0
  for (i=1;i<=s;i++) {
      sc=SSCOPE[i]
      if (sc!="batch" && sc!="unit") serr=serr " " SID[i]
      if (sc=="unit") seen_unit=1
      else if (sc=="batch" && seen_unit) order_err=order_err " " SID[i]
  }
  if (serr=="" && order_err=="") ok("V21","step scopes are valid and batch steps come first")
  else { if (serr!="") rec("ERROR","V21","scope must be batch or unit at step(s)" serr,"leave the field off for unit, or write batch")
         if (order_err!="") rec("ERROR","V21","batch step(s)" order_err " come after a unit step","everything that runs once happens before the units exist") }

  # V26 the design declares its record layer
  # NOTE: never reuse k, s, g or a here — the shared parser counts with them.
  rmiss=""
  split("transitions units retention acceptance", RKEYS, " ")
  for (rk=1; rk<=4; rk++) if (V["record." RKEYS[rk]]=="") rmiss = rmiss " " RKEYS[rk]
  if (rmiss=="") ok("V26","the record layer is declared: transitions, units, retention, acceptance")
  else rec("ERROR","V26","@record is missing:" rmiss,"a loop that does not say what it records cannot be audited, and an RPA with no ledger cannot answer what it did or who allowed it")

  # V25 every step typed gate is named by a gate
  orphan=""
  for (i=1;i<=s;i++) if (tolower(STYPE[i])=="gate") {
    hit=0; for (j=1;j<=g;j++) if (GAFT[j]==SID[i]) hit=1
    if (!hit) orphan = orphan " " SID[i]
  }
  if (orphan=="") ok("V25","every step typed gate is named by a gate")
  else rec("ERROR","V25","step(s)" orphan " are typed gate but no gate names them","a step that looks like a control and enforces nothing is worse than no step — it reads as a gate in every diagram and refuses nothing")

  # V22 every gate attaches to a real step
  ghost=""
  for (i=1;i<=g;i++) { found=0
    for (j=1;j<=s;j++) if (SID[j]==GAFT[i]) { found=1; break }
    if (!found) ghost=ghost " " GAFT[i] }
  if (g>0 && ghost=="") ok("V22","every gate attaches to a real step")
  else if (ghost!="") rec("ERROR","V22","gate(s) name step id(s)" ghost ", which do not exist","a gate nobody can place is a control that silently disappears from the diagram and the build")

  # V17 proof writer is mechanical
  ws=V["evidence.writer_step"]; wt=""
  for (i=1;i<=s;i++) if (SID[i]==ws) wt=tolower(STYPE[i])
  if (wt=="mechanical") ok("V17","the proof is written by a mechanical step")
  else if (wt=="") rec("ERROR","V17","evidence.writer_step " (ws==""?"is unset":"names no step: " ws),"point it at a mechanical step")
  else rec("ERROR","V17","the proof is written by a " wt " step","evidence a model can edit is not evidence")

  # V18 integrity
  if (V["evidence.integrity"]!="") ok("V18","evidence declares an integrity check")
  else rec("ERROR","V18","no integrity check on the evidence","say how tampering is detected")

  # V19 / V20 kpis
  for (i=1;i<=k+0;i++) { kk=tolower(KKIND[i]); KIND[kk]++
                       if (tolower(KBASE[i])=="unmeasured") unmeas++ }
  if (k>=3 && KIND["cost"]>0 && KIND["quality"]>0) ok("V19",k " KPIs, including cost and quality")
  else rec("ERROR","V19","need at least 3 KPIs including one cost and one quality; have " k,"cost funds it, quality stops it")
  if (unmeas>0) rec("WARN","V20",unmeas " KPI baseline(s) unmeasured","measure the manual process first, or you can never claim an improvement")
  else if (k>0) ok("V20","every KPI carries a baseline")

  # V23 total value realized
  tvr=KIND["tvr-velocity"]+KIND["tvr-throughput"]+KIND["tvr-speed"]+KIND["tvr-margin"]
  if (tvr>0) ok("V23",tvr " KPI(s) measure total value realized")
  else rec("ERROR","V23","no KPI measures total value realized","add a tvr-velocity, tvr-throughput, tvr-speed or tvr-margin KPI; cost says what it spends, TVR says what it returns")

  # V24 every kind is one of the eight
  badkind=""
  for (i=1;i<=k+0;i++) { kk=tolower(KKIND[i])
    if (kk !~ /^(cost|quality|throughput|control|tvr-velocity|tvr-throughput|tvr-speed|tvr-margin)$/)
      badkind=badkind " \"" KKIND[i] "\"" }
  if (badkind=="") { if (k>0) ok("V24","every KPI kind is a known kind") }
  else rec("ERROR","V24","unknown KPI kind(s):" badkind,"use cost, quality, throughput, control, tvr-velocity, tvr-throughput, tvr-speed or tvr-margin")

  # ---- V27..V31 the data contract ------------------------------------------
  # A design that names a tool nobody catalogued points at something the
  # organization has not sanctioned. A design that cannot be checked against a
  # catalog has a data contract nobody verified.
  if (n_src > 0 || n_tool > 0) {
    if (CATN == 0)
      rec("ERROR","V27","the design names sources or tools and no catalog was readable","pass CATALOG=<file>; an unverified data contract is not a data contract")
    else {
      bad=""
      for (i=1;i<=n_src;i++) if (!(SRCFROM[i] in CTOOL)) bad = bad " " SRCID[i] "->" SRCFROM[i]
      for (i=1;i<=n_tool;i++) if (!(TLID[i] in CTOOL)) bad = bad " " TLID[i]
      if (bad=="") ok("V27", n_src " source(s) and " n_tool " tool(s), all catalogued")
      else rec("ERROR","V27","not in the catalog:" bad,"add it to the catalog with a rationale, or use a tool that is there")

      # V28 narrowing only. A design may take fewer fields than a tool provides,
      # never more: a field the tool does not return will not exist at run time.
      inv=""
      for (i=1;i<=n_src;i++) {
        if (!(SRCFROM[i] in CTOOL)) continue
        np=split(SRCPROV[i], PF, / *, */)
        for (j=1;j<=np;j++) {
          f=PF[j]; gsub(/^ +| +$/,"",f)
          if (f=="" || f=="-") continue
          if (index("," CPROV[SRCFROM[i]] ",", f)==0 && CPROV[SRCFROM[i]] !~ ("(^|, )" f "(,|$)"))
            inv = inv " " SRCID[i] "." f
        }
      }
      if (inv=="") { if (n_src>0) ok("V28","every field taken is one the tool provides") }
      else rec("ERROR","V28","fields the tool does not provide:" inv,"a design may narrow what a tool returns, never invent it")

      # V29 a tool is used by steps that exist.
      nos=""
      for (i=1;i<=n_tool;i++) {
        ns=split(TLBY[i], SB, / +/)
        for (j=1;j<=ns;j++) {
          sid=SB[j]; gsub(/^ +| +$/,"",sid)
          if (sid=="" || sid=="-") continue
          found=0
          for (m=1;m<=s;m++) if (SID[m]==sid) { found=1; break }
          if (!found) nos = nos " " TLID[i] "@" sid
        }
      }
      if (nos=="") { if (n_tool>0) ok("V29","every tool is used by a step that exists") }
      else rec("ERROR","V29","tools used by steps that do not exist:" nos,"name a real step id in used_by")

      # V30 a constraint is checkable or structural, and says which by its shape.
      # A checkable constraint nothing can evaluate is a constraint in name only.
      vague=""
      for (i=1;i<=n_src;i++) {
        c=tolower(SRCCON[i]); gsub(/^ +| +$/,"",c)
        if (c=="" || c=="-") continue
        if (c ~ /^(never|only)[ \t]/) continue   # BSD awk has no \b
        if (c ~ /[0-9]/ || c ~ /(^| )(is|in|equals|matches|one|at|over|under|above|below)( |$)/) continue
        vague = vague " " SRCID[i]
      }
      if (vague=="") { if (n_src>0) ok("V30","every source constraint is structural or evaluable") }
      else rec("ERROR","V30","constraints that cannot be evaluated or recognised as structural:" vague,"begin a structural constraint with never or only; give a checkable one a comparison")

      # V31 the permission the catalog withheld cannot be granted here.
      #
      # Whether PHI may reach a model is a BUSINESS AGREEMENT, not a property of
      # the data, so the answer is read from the catalog rather than written
      # here. Without a covering agreement a model call is outside the boundary
      # and the design is refused. With one it is inside, and the rule becomes
      # about the agreement instead: an attestation nobody has renewed is worse
      # than no catalog, because designs will cite it.
      leak=""
      for (i=1;i<=n_tool;i++) {
        if (CCLASS[TLID[i]] != "phi") continue
        ns=split(TLBY[i], SB, / +/)
        for (j=1;j<=ns;j++) {
          sid=SB[j]; gsub(/^ +| +$/,"",sid)
          for (m=1;m<=s;m++) if (SID[m]==sid && tolower(SACT[m])=="model") leak = leak " " TLID[i] "@step" sid
        }
      }
      covered = (tolower(CPOL["phi_may_reach_models"]) == "yes")
      byw = CPOL["phi_model_review_by"]
      if (leak=="") { if (n_tool>0) ok("V31","no PHI tool is used by a model step") }
      else if (!covered)
        rec("ERROR","V31","PHI reaches a model and the catalog does not permit it:" leak,
            "redact in a mechanical step and give the model only that output — or record the covering agreement in the catalog, which is a business decision and not a rule change")
      else if (byw == "")
        rec("ERROR","V31","the catalog permits PHI to reach a model and names no review date:" leak,
            "set phi_model_review_by — a permission nobody has to renew is a permission nobody will revisit")
      else if (TODAY != "" && byw < TODAY)
        rec("ERROR","V31","the agreement permitting PHI to reach a model lapsed on " byw ":" leak,
            "reattest it in the catalog, or stop sending PHI to a model — a stale catalog asserting a tool is safe is worse than no catalog, because designs cite it")
      else
        ok("V31","PHI reaches a model under " (CPOL["phi_model_basis"] != "" ? CPOL["phi_model_basis"] : "a catalogued agreement") ", attested to " byw)
    }
  }

  # V44 which method wrote this design. INTERVIEW.md is versioned because two
  # interviews from different scripts produce use cases nobody can compare; the
  # same is true of two designs from different authoring methods, and nothing
  # else records which one ran.
  if (MSHA != "") {
    if (V["meta.method_sha256"] == "")
      rec("WARN","V44","@meta.method_sha256 is not set","record the digest of the method that wrote this design, as it already records the question set")
    else if (V["meta.method_sha256"] != MSHA)
      rec("ERROR","V44","@meta.method_sha256 is " substr(V["meta.method_sha256"],1,12) "... and the method is " substr(MSHA,1,12) "...","this design was written by a different version of the method than the one in front of you")
    else ok("V44","the design names the method that wrote it, by digest")
  }

  # ---- skills, V40-V43 ----
  #
  # A SKILL is know-how a step applies. It reaches nothing, and crucially it
  # DECIDES nothing: know-how that decides is a decision table, where
  # completeness and overlap are provable and a fall-through refuses.
  #
  # V42 is the load-bearing one and it shipped before @skills existed. You cannot
  # prove a model read a document, so a gate resting on a skill is a control that
  # is declared, reported and absent — and a skills section is exactly where
  # unprovable things get put to look official. The constraint arrives first so
  # the section can never be born loose.
  #
  # A THINKING step may be informed by a skill. That is the evaluator-optimizer
  # shape: the skill frames the draft, and the gate checks the OUTPUT.
  if (CSKN+0 > 0) {
    cited=""
    for (sg=1; sg<=g+0; sg++) {
      for (sk in CSKILL) if (index(GCOND[sg], sk) > 0) cited = cited " gate" sg "(" sk ")"
    }
    if (cited=="") ok("V42","no gate condition depends on a skill")
    else rec("ERROR","V42","gate condition(s) resting on a skill:" cited,
             "nothing can prove a document was read, so a gate on a skill is a control that is declared, reported and absent — move the deciding part into a @decisions table, which is checkable")
  }

  if (n_skill+0 > 0) {
    unc=""; nostep=""; ongate=""; stale=""
    for (sz=1; sz<=n_skill; sz++) {
      sid = SKL_ID[sz]
      if (!(sid in CSKILL)) { unc = unc " " sid; continue }
      byw = CSKREV[sid]
      if (byw != "" && TODAY != "" && byw < TODAY) stale = stale " " sid "(" byw ")"
      nsb = split(SKL_BY[sz], SKB, / +/)
      for (sj=1; sj<=nsb; sj++) {
        ssid = SKB[sj]; gsub(/^ +| +$/,"",ssid)
        if (ssid=="" || ssid=="-") continue
        found=0
        for (sm=1; sm<=s; sm++) if (SID[sm]==ssid) {
          found=1
          if (tolower(STYPE[sm])=="gate") ongate = ongate " " sid "@step" ssid
        }
        if (!found) nostep = nostep " " sid "@" ssid
      }
    }
    if (unc=="") ok("V40","every skill the design names is in the catalog")
    else rec("ERROR","V40","skills nothing catalogued:" unc,"a design does not invent know-how — catalogue it, with an owner and a review date, or do not name it")
    if (nostep=="" && ongate=="") ok("V41","every skill is used by a real step, and none by a gate step")
    else { if (nostep!="") rec("ERROR","V41","skills used by steps that do not exist:" nostep,"name a real step id in used_by")
           if (ongate!="") rec("ERROR","V41","skills used by GATE steps:" ongate,"a gate decides; a skill informs. Put the deciding part in a @decisions table") }
    if (stale=="") ok("V43","every skill named is within its review date")
    else rec("ERROR","V43","skills whose review date has passed:" stale,
             "re-attest it in the catalog or stop naming it — a lapsed clinical lookup table is as dangerous as a lapsed agreement, because designs cite it and nothing at run time notices")
  }

  # ---- the interview, V32-V34 ----
  # A design is bound to the question set that produced it the same way
  # acceptance is bound to the design: by content. Without that, an answered
  # question and a model's guess are the same sentence in the same list, and the
  # whole point of asking was to make them distinguishable.
  if (QN == 0) {
    rec("WARN","V32","no question set was supplied, so V32-V34 did not run",
        "pass QUESTIONS=<QUESTIONS.md>. A design authored without an interview carries assumptions nobody was asked about")
  } else {
    if (V["meta.questions_sha256"] == "")
      rec("ERROR","V32","@meta.questions_sha256 is not set","name the question set this design was authored from, by digest — a filename is not a binding")
    else if (V["meta.questions_sha256"] != QSHA)
      rec("ERROR","V32","@meta.questions_sha256 is " substr(V["meta.questions_sha256"],1,12) "... and the question set is " substr(QSHA,1,12) "...",
          "the design was authored from a different set of answers than the one in front of you — re-author, or point at the right file")
    else ok("V32","the design is bound to its question set by digest")

    uncited=""; wrongprov=""
    for (vq=1; vq<=QN; vq++) {
      vqid = QORD[vq]; vqt = QTYPE[vqid]
      cited = 0; provok = 0
      for (vqa=1; vqa<=a+0; vqa++) {
        if (index(ASSUM[vqa], "[" vqid "]") == 0) continue
        cited = 1
        if (vqt == "" || index(tolower(ASSUM[vqa]), vqt) > 0) provok = 1
      }
      if (!cited) uncited = uncited " " vqid
      else if (!provok) wrongprov = wrongprov " " vqid "(" vqt ")"
    }
    if (uncited=="") ok("V33","every one of the " QN " questions is cited by an assumption")
    else rec("ERROR","V33","asked and never carried into the design:" uncited,
             "declare an assumption citing [Qn] for each — a question answered and then dropped is worse than one never asked")
    if (wrongprov=="") { if (uncited=="") ok("V34","every citing assumption carries how the answer was given") }
    else rec("ERROR","V34","the assumption does not say how the answer was given:" wrongprov,
             "write stated, unanswered or delegated in the assumption — an auditor reading this list must be able to tell a confirmed fact from a surviving guess")
  }

  # ---- decision tables, V35-V38 ----
  # A gate whose condition is prose compiles to a STUB somebody must implement.
  # A gate backed by a table compiles to working logic — and the table can be
  # asked three questions a bash conditional cannot answer: does any input fall
  # through, do two rules claim the same input, is any output never produced.
  # Those three rules are the entire reason for the feature.
  if (n_dt > 0) {
    bad=""; badhit=""; badw=""
    for (dz=1; dz<=n_dt; dz++) {
      did=DTID[dz]
      if (DTNIN[did]+0 == 0 || DTNOUT[did]+0 == 0) bad = bad " " did
      if (DTHIT[did] != "unique" && DTHIT[did] != "first") badhit = badhit " " did "(" (DTHIT[did]=="" ? "none" : DTHIT[did]) ")"
      if (DTNR[did]+0 == 0) bad = bad " " did "(no rules)"
      want = DTNIN[did] + DTNOUT[did]
      for (dr=1; dr<=DTNR[did]+0; dr++) {
        got = dt_cells(did, dr, DC)
        if (got != want) badw = badw " " did "#" dr "(" got " of " want ")"
      }
    }
    if (bad=="") ok("V35", n_dt " decision table(s), each with inputs, outputs and rules")
    else rec("ERROR","V35","incomplete decision table(s):" bad,"a table declares inputs, outputs and at least one rule")
    if (badhit=="") ok("V36","every table names a hit policy")
    else rec("ERROR","V36","unknown hit policy at:" badhit,"write unique or first after the table name — unique is the one a reviewer can check, and first hides an overlap behind an ordering")
    if (badw=="") ok("V37","every rule has one cell per input and per output")
    else rec("ERROR","V37","wrong cell count at:" badw,"a short row silently shifts every output one column left")

    # overlap, under unique only: two rules claiming the same input is a defect
    # the table format can detect and prose cannot.
    ov=""
    for (dz=1; dz<=n_dt; dz++) {
      did=DTID[dz]
      if (DTHIT[did] != "unique") continue
      for (dr=1; dr<=DTNR[did]+0; dr++) {
        dt_cells(did, dr, DA)
        for (dr2=dr+1; dr2<=DTNR[did]+0; dr2++) {
          dt_cells(did, dr2, DB)
          clash=1
          for (dc=1; dc<=DTNIN[did]+0; dc++)
            if (!dt_cells_overlap(DA[dc], DB[dc])) { clash=0; break }
          if (clash) ov = ov " " did "#" dr "/#" dr2
        }
      }
    }
    if (ov=="") ok("V38","no two rules under a unique policy claim the same input")
    else rec("ERROR","V38","overlapping rules:" ov,"under unique exactly one rule may match — narrow one of them, or say first and accept that the order is the logic")
  }

  # V39 a gate naming a decision table names one that exists, and an output it has.
  # Without this a typo compiles to a check that evaluates nothing and refuses
  # everything, which reads in the log exactly like a design that is working.
  dghost=""
  for (dg=1; dg<=g+0; dg++) {
    if (!decision_ref(GCOND[dg])) continue
    dtab = decision_table(GCOND[dg]); dout = decision_out(GCOND[dg])
    dfound = 0
    for (dz=1; dz<=n_dt; dz++) if (DTID[dz] == dtab) { dfound = 1; break }
    if (!dfound) { dghost = dghost " gate" dg "(no table " dtab ")"; continue }
    don = split(DTOUT[dtab], DO2, / *\| */); dok = 0
    for (dc=1; dc<=don; dc++) { gsub(/^ +| +$/, "", DO2[dc]); if (DO2[dc] == dout) { dok = 1; break } }
    if (!dok) dghost = dghost " gate" dg "(" dtab " has no output " dout ")"
    if (decision_val(GCOND[dg]) == "") dghost = dghost " gate" dg "(no value to compare)"
  }
  if (dghost=="") { if (n_dt > 0) ok("V39","every gate naming a decision table names a real one") }
  else rec("ERROR","V39","gate(s) naming a table or output that does not exist:" dghost,"write <table> yields <output> <value>, naming a table in @decisions and one of its outputs")

  # ---- output ----
  if (mode=="tsv") {
      for (i=1;i<=n;i++) printf "%s\t%s\t%s\t%s\n", SEV[i], ID[i], MSG[i], FIX[i]
      exit (errs>0 ? 1 : 0)
  }
  for (i=1;i<=n;i++) {
      if (SEV[i]=="PASS") printf "  \033[32mPASS\033[0m  %-4s %s\n", ID[i], MSG[i]
      else if (SEV[i]=="WARN") printf "  \033[33mWARN\033[0m  %-4s %s\n            %s\n", ID[i], MSG[i], FIX[i]
      else printf "  \033[31mFAIL\033[0m  %-4s %s\n            fix: %s\n", ID[i], MSG[i], FIX[i]
  }
  printf "\n  %d passed, %d failed, %d warning(s)\n", passes+0, errs+0, warns+0
  if (errs>0) printf "\n  This design is not ready to be shown. Every failure above is a rule,\n  not an opinion, and the fix is named.\n"
  exit (errs>0 ? 1 : 0)
}
