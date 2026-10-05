# The compiler's own rules, over an emitted formula. These are the rules gc does
# NOT enforce — gc checks that the graph is well formed, not that the method is.
# -v CHECKROOT=<dir the check paths are relative to>  -v FILE=<the formula path>
function fail(id, msg) { F[++nf] = id "  " msg }
function warn(id, msg) { W[++nw] = id "  " msg }
function trim(t,  s) { s=t; gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
function strval(l,   v) { v=l; sub(/^[^=]*=[ \t]*/,"",v); gsub(/^"|"[ \t]*$/,"",v); return v }

BEGIN { tbl=""; inblock=0; si=0 }
{
  line=$0
  # multi-line strings: collect the body, but keep scanning for {{vars}}
  if (inblock) { body = body "\n" line; if (line ~ /"""/) { inblock=0; BODY[si]=BODY[si] body }
                 scanvars(line); next }
  if (line ~ /"""[ \t]*$/ && line ~ /=/) { inblock=1; body=""; scanvars(line); next }

  t=trim(line)
  if (t ~ /^\[\[steps\]\]/) { si++; tbl="step"; next }
  if (t ~ /^\[steps\.check\.check\]/)  { tbl="checkcheck"; HASCHECK[si]=1; next }
  if (t ~ /^\[steps\.check\]/)  { tbl="check"; HASCHECK[si]=1; next }
  if (t ~ /^\[steps\.retry\]/)  { tbl="retry"; HASRETRY[si]=1; next }
  if (t ~ /^\[steps\.drain\]/)  { tbl="drain"; HASDRAIN[si]=1; next }
  if (t ~ /^\[steps\.gate\]/)   { tbl="gate";  HASGATE[si]=1;  next }
  if (t ~ /^\[steps\.loop\]/)   { tbl="loop";  next }
  if (t ~ /^\[vars\./) { tbl="var"; vn=t; sub(/^\[vars\./,"",vn); sub(/\].*$/,"",vn); DECL[vn]=1; next }
  if (t ~ /^\[vars\]/)     { tbl="vars"; next }
  if (t ~ /^\[catalog\]/)  { tbl="catalog"; next }
  if (t ~ /^\[requires\]/) { tbl="requires"; next }
  if (t ~ /^\[/) { tbl="other"; next }
  if (t ~ /^#/ || t=="") next

  scanvars(t)
  if (t ~ /^formula[ \t]*=/ && tbl=="")        FORMULA=strval(t)
  if (t ~ /^contract[ \t]*=/ && tbl=="")       BARECONTRACT=1
  if (t ~ /^formula_compiler[ \t]*=/ && tbl=="requires") REQ=strval(t)
  if (t ~ /^name[ \t]*=/ && tbl=="catalog")    CATNAME=strval(t)
  if (tbl=="var"  && t ~ /^type[ \t]*=/)       VTYPE[vn]=1
  if (tbl=="loop" && t ~ /^until[ \t]*=/)      UNTIL=1
  if (tbl=="step" && t ~ /^id[ \t]*=/)         { SID[si]=strval(t); SEEN[SID[si]]++ }
  if (tbl=="step" && t ~ /^needs[ \t]*=/)      NEEDS[si]=t
  if (tbl=="step" && t ~ /^metadata[ \t]*=/)   { META[si]=t
    if (t ~ /"eb\.design_type" *= *"gate"/) ISGATESTEP[SID[si]]=1
    if (match(t, /"eb\.gate_after" *= *"[^"]*"/)) { v=substr(t,RSTART,RLENGTH); sub(/.*= *"/,"",v); sub(/"$/,"",v); GUARDED[v]=1 } }
  if (tbl=="checkcheck" && t ~ /^path[ \t]*=/) CPATH[si]=strval(t)
}
function scanvars(l,   rest, v) {
  rest=l
  while (match(rest, /\{\{[A-Za-z0-9_]+\}\}/)) {
    v=substr(rest, RSTART+2, RLENGTH-4); USED[v]=1
    rest=substr(rest, RSTART+RLENGTH)
  }
}
END {
  base=FILE; sub(/.*\//,"",base)
  stem=base; sub(/\.toml$/,"",stem)

  # F1 canonical filename
  if (base ~ /\.formula\.toml$/)
    fail("F1", "the file is " base " — .formula.toml is deprecated; emit <name>.toml")
  # F2 the three names agree
  if (FORMULA=="") fail("F2", "no top-level formula = key")
  else if (FORMULA != stem) fail("F2", "formula = \"" FORMULA "\" but the file is " base)
  if (CATNAME!="" && CATNAME != FORMULA) fail("F2", "[catalog].name \"" CATNAME "\" does not match formula \"" FORMULA "\"")
  # F3/F4 the opt-in
  if (REQ=="") fail("F3", "no [requires] formula_compiler — graph-only constructs will be refused")
  if (BARECONTRACT) fail("F4", "contract = is the deprecated opt-in; use [requires] formula_compiler")
  # F5 every check script exists and is executable
  ng=0
  for (i=1;i<=si;i++) if (CPATH[i]!="") {
    ng++
    # A path carrying a {{var}} is bound at run time and cannot be on disk now.
    # The dropped-gate protection still applies: whatever will be bound has to
    # exist here, so check the basename against this repo's checks.
    if (CPATH[i] ~ /\{\{/) {
      base = CPATH[i]; sub(/.*\//, "", base)
      p = (CHECKROOT!="" ? CHECKROOT "/checks/" base : "checks/" base)
      if ((getline junk < p) < 0)
        fail("F5", "step " SID[i] ": check " base " is bound at run time and does not exist at checks/" base)
      else close(p)
      continue
    }
    p = (CHECKROOT!="" ? CHECKROOT "/" CPATH[i] : CPATH[i])
    if ((getline junk < p) < 0) fail("F5", "step " SID[i] ": check script " CPATH[i] " does not exist")
    else { close(p); cmd="test -x \"" p "\""; if (system(cmd)!=0) fail("F5", "step " SID[i] ": check script " CPATH[i] " is not executable") }
  }
  # F6 the incompatibility matrix
  for (i=1;i<=si;i++) {
    n = HASCHECK[i] + HASRETRY[i] + HASDRAIN[i]
    if (n>1) fail("F6", "step " SID[i] " carries more than one of check, retry, drain")
    if (HASCHECK[i] && HASGATE[i]) fail("F6", "step " SID[i] " carries both check and gate")
  }
  # F7 variables
  for (v in USED) {
    if (v=="convoy_id" || v=="bead_id") fail("F7", "{{" v "}} is a reserved v2 variable")
    else if (!DECL[v]) fail("F7", "{{" v "}} is used but not declared in [vars]")
  }
  # F8 inert constructs
  for (v in VTYPE) fail("F8", "vars." v ".type is parsed and never enforced; use enum or pattern")
  if (UNTIL) fail("F8", "an until loop runs exactly once in this release; use check")
  # F9 at least two gates
  if (ng < 2) fail("F9", "the method declares " ng " check(s); a method with fewer than two controls is not governed")
  # F10 unique ids
  for (v in SEEN) if (SEEN[v]>1) fail("F10", "duplicate step id \"" v "\"")
  # F11 needs resolve
  for (i=1;i<=si;i++) if (NEEDS[i]!="") {
    rest=NEEDS[i]
    while (match(rest, /"[^"]+"/)) {
      dep=substr(rest, RSTART+1, RLENGTH-2)
      if (!SEEN[dep]) fail("F11", "step " SID[i] ": needs \"" dep "\", which is not a step here")
      if (dep==SID[i]) fail("F12", "step " SID[i] " needs itself")
      rest=substr(rest, RSTART+RLENGTH)
    }
  }
  # F13 every step closes with an outcome
  for (i=1;i<=si;i++) if (BODY[i] !~ /gc\.outcome/)
    fail("F13", "step " SID[i] " never tells the worker to close with gc.outcome — silence reads as failure")
  # F14 gc.kind is compiler-owned
  for (i=1;i<=si;i++) if (META[i] ~ /gc\.kind/ && META[i] !~ /"(scope|cleanup)"/)
    fail("F14", "step " SID[i] " authors gc.kind; only scope and cleanup may be set")
  # F17 a step that came from a gate-typed design step is actually guarded
  for (i=1;i<=si;i++) if (ISGATESTEP[SID[i]]) {
    ds=META[i]; sub(/.*"eb\.design_step" *= *"/,"",ds); sub(/".*/,"",ds)
    if (!GUARDED[ds]) fail("F17", "step " SID[i] " came from a gate-typed design step, but no check step guards it")
  }
  # F16 no step both reasons and writes its own proof
  for (i=1;i<=si;i++) if (META[i] ~ /gc\.provider/ && BODY[i] ~ /Write the proof/)
    fail("F16", "step " SID[i] " both runs a model and writes its own proof")
  # F15 a human hold
  hg=0; for (i=1;i<=si;i++) hg += HASGATE[i]
  if (hg==0) warn("F15", "no [steps.gate] — nothing in this method waits for a person")

  for (i=1;i<=nf;i++) print "  FAIL  " F[i]
  for (i=1;i<=nw;i++) print "  WARN  " W[i]
  printf "  %d rule(s) passed, %d failed, %d warning(s)\n", 17-nf, nf, nw
  exit (nf>0 ? 1 : 0)
}
