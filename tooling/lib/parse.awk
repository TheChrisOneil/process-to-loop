# Shared parser for the design format. Read by validate.sh and render.sh, so the two
# cannot disagree about what a design says. The contract is schema/DESIGN-FORMAT.md.
#
# Populates: V["section.key"] · ASSUM[1..a] · SID/SNAME/STYPE/SACT/SDESC[1..s]
#            GAFT/GCOND/GREF[1..g] · KNAME/KKIND/KBASE[1..k]
#            SRCID/SRCFROM/SRCPROV/SRCCON[1..n_src] · TLID/TLBY/TLPURP[1..n_tool]
#            DTID[1..n_dt] · DTHIT/DTIN/DTOUT/DTNIN/DTNOUT[id] · DTR[id,1..DTNR[id]]
#            SKL_ID/SKL_BY/SKL_WHY[1..n_skill]
# Counter names are spelled out — n_src, n_tool — because a short one collides.
# k was reused once for a keyed-section key and hung the validator forever.
/^[[:space:]]*#/ { next }
/^[[:space:]]*$/ { next }
/^@/ { sec=substr($1,2); next }
{
  line=$0; sub(/^[ \t]+/,"",line); sub(/[ \t]+$/,"",line)
  if (sec=="meta" || sec=="unit" || sec=="evidence" || sec=="record") {
      i=index(line,":"); if (i==0) next
      # ky, NOT k: k is the KPI counter below, and every variable in this file is
      # global to every rule that reads it. Assigning a key name to k left it
      # holding a string like "approver", so a later `for (i=1;i<=k;i++)` became
      # a string comparison that is always true — the validator hung forever on
      # any design with no @kpis section. Never reuse a, s, g, k or i here.
      ky=substr(line,1,i-1); v=substr(line,i+1); sub(/^[ \t]+/,"",v); sub(/[ \t]+$/,"",v)
      V[sec"."ky]=v; next
  }
  if (sec=="assumptions") { if (substr(line,1,1)=="-") { a++; ASSUM[a]=substr(line,3) } next }
  if (sec=="decisions") {
      # A rule row starts with a dash, like a list item. Everything else in the
      # section is a keyed line, and `table:` opens a new table — so a design may
      # carry several, and a row can never be attached to no table.
      if (substr(line,1,1)=="-") {
          if (dcur=="") next
          DTNR[dcur]++; DTR[dcur, DTNR[dcur]] = substr(line,3)
          next
      }
      di=index(line,":"); if (di==0) next
      dk=substr(line,1,di-1); dv=substr(line,di+1)
      sub(/^[ \t]+/,"",dv); sub(/[ \t]+$/,"",dv)
      if (dk=="table") {
          dn=split(dv,DF," *\\| *")
          n_dt++; DTID[n_dt]=DF[1]; dcur=DF[1]
          DTHIT[dcur]=(dn>=2 ? tolower(DF[2]) : "")
          next
      }
      if (dcur=="") next
      if (dk=="inputs")  { DTIN[dcur]=dv;  DTNIN[dcur]=split(dv,DX," *\\| *") }
      if (dk=="outputs") { DTOUT[dcur]=dv; DTNOUT[dcur]=split(dv,DY," *\\| *") }
      next
  }
  if (sec=="skills") {
      cnt=split(line,F," *\\| *")
      n_skill++; SKL_ID[n_skill]=F[1]; SKL_BY[n_skill]=F[2]; SKL_WHY[n_skill]=F[3]; SKL_F[n_skill]=cnt
      next
  }
  if (sec=="sources" || sec=="tools") {
      cnt=split(line,F," *\\| *")
      if (sec=="sources") { n_src++; SRCID[n_src]=F[1]; SRCFROM[n_src]=F[2]; SRCPROV[n_src]=F[3]; SRCCON[n_src]=F[4]; SRCF[n_src]=cnt }
      if (sec=="tools")   { n_tool++; TLID[n_tool]=F[1]; TLBY[n_tool]=F[2]; TLPURP[n_tool]=F[3]; TLF[n_tool]=cnt }
      next
  }
  if (sec=="steps" || sec=="gates" || sec=="kpis") {
      cnt=split(line,F," *\\| *")
      if (sec=="steps") { s++; SID[s]=F[1]; SNAME[s]=F[2]; STYPE[s]=F[3]; SACT[s]=F[4]; SDESC[s]=F[5]; SSCOPE[s]=(cnt>=6 && F[6]!="" ? tolower(F[6]) : "unit"); SF[s]=cnt }
      if (sec=="gates") { g++; GAFT[g]=F[1]; GCOND[g]=F[2]; GREF[g]=F[3]; GF[g]=cnt }
      if (sec=="kpis")  { k++; KNAME[k]=F[1]; KKIND[k]=F[2]; KBASE[k]=F[3]; KF[k]=cnt }
      next
  }
  SEEN_UNKNOWN[sec]=1
}
