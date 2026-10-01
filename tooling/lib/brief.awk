# design -> a readable brief, rendered by rule. The prose is the design's own words,
# arranged; nothing here is written by a model, so the brief cannot flatter the design.
function esc(t,   s) { s=t; gsub(/\|/,"\\|",s); return s }
END {
  print "# " V["meta.use_case"]
  print ""
  print "A proposed design. **Nothing here is decided.** Read the assumptions first — they are"
  print "the gaps that were filled to produce this, and each one is a question for you."
  print ""
  print "## Assumptions made to produce this design"
  print ""
  for (i=1;i<=a;i++) print "- " ASSUM[i]
  print ""
  print "## The unit of work"
  print ""
  print "**" V["unit.definition"] "**"
  print ""
  print "| | |"
  print "|---|---|"
  print "| Rule or judgment | " V["unit.kind"] " |"
  print "| The two-people test | " esc(V["unit.two_people_test"]) " |"
  if (V["unit.checked_by"]!="") print "| What checks the decomposition | " esc(V["unit.checked_by"]) " |"
  print "| How many run at once | " V["unit.fanout"] " — " esc(V["unit.fanout_reason"]) " |"
  print ""
  print "## The steps"
  print ""
  print "| # | Step | Type | Who | Runs | What it does |"
  print "|---|---|---|---|---|---|"
  for (i=1;i<=s;i++)
    printf "| %s | %s | %s | %s | %s | %s |\n", SID[i], SNAME[i], STYPE[i], SACT[i], SSCOPE[i], esc(SDESC[i])
  print ""
  for (i=1;i<=s;i++) if (tolower(STYPE[i])=="thinking") th=i
  if (th) {
    print "**One judgment, and this is it:** step " SID[th] ", " SNAME[th] " — " SDESC[th]
    print ""
    print "Everything else is a rule. If that step were removed entirely, the rest of this loop"
    print "still partitions the work, refuses what it should refuse, and proves what it did."
    print ""
  }
  print "## Where it refuses"
  print ""
  print "| After step | The condition | The next human action |"
  print "|---|---|---|"
  for (j=1;j<=g;j++) printf "| %s | %s | %s |\n", GAFT[j], esc(GCOND[j]), esc(GREF[j])
  print ""
  print "## What a human approves from"
  print ""
  print "Written by step " V["evidence.writer_step"] ", which is a mechanical step — a model never"
  print "writes the evidence it will be judged on."
  print ""
  print "- **Contains:** " V["evidence.artifact"]
  print "- **Integrity:** " V["evidence.integrity"]
  print "- **Approver:** " V["meta.approver"]
  print "- **Exit criterion:** " V["meta.exit_criterion"]
  print ""
  print "## How it is governed"
  print ""
  print "| KPI | Kind | Baseline today |"
  print "|---|---|---|"
  for (i=1;i<=k;i++) printf "| %s | %s | %s |\n", KNAME[i], KKIND[i], KBASE[i]
  print ""
  print "## What happens next"
  print ""
  print "1. **Discuss it.** Every assumption above is a question, and the unit boundary is the"
  print "   one worth arguing about — everything downstream inherits it."
  print "2. **Change it.** Edit the design file and re-run the validator. That is cheap now and"
  print "   expensive later."
  print "3. **Accept it**, by name, when it is right: `make accept DESIGN=<design> BY=\"Name, Role\"`"
  print "4. **Build it:** `make scaffold DESIGN=<design> NAME=<name>` — it runs the same day."
}
