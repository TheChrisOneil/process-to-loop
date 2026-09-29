# Shared parser for the design format. Read by validate.sh and render.sh, so the two
# cannot disagree about what a design says. The contract is schema/DESIGN-FORMAT.md.
#
# Populates: V["section.key"] · ASSUM[1..a] · SID/SNAME/STYPE/SACT/SDESC[1..s]
#            GAFT/GCOND/GREF[1..g] · KNAME/KKIND/KBASE[1..k]
/^[[:space:]]*#/ { next }
/^[[:space:]]*$/ { next }
/^@/ { sec=substr($1,2); next }
{
  line=$0; sub(/^[ \t]+/,"",line); sub(/[ \t]+$/,"",line)
  if (sec=="meta" || sec=="unit" || sec=="evidence") {
      i=index(line,":"); if (i==0) next
      k=substr(line,1,i-1); v=substr(line,i+1); sub(/^[ \t]+/,"",v); sub(/[ \t]+$/,"",v)
      V[sec"."k]=v; next
  }
  if (sec=="assumptions") { if (substr(line,1,1)=="-") { a++; ASSUM[a]=substr(line,3) } next }
  if (sec=="steps" || sec=="gates" || sec=="kpis") {
      cnt=split(line,F," *\\| *")
      if (sec=="steps") { s++; SID[s]=F[1]; SNAME[s]=F[2]; STYPE[s]=F[3]; SACT[s]=F[4]; SDESC[s]=F[5]; SSCOPE[s]=(cnt>=6 && F[6]!="" ? tolower(F[6]) : "unit"); SF[s]=cnt }
      if (sec=="gates") { g++; GAFT[g]=F[1]; GCOND[g]=F[2]; GREF[g]=F[3]; GF[g]=cnt }
      if (sec=="kpis")  { k++; KNAME[k]=F[1]; KKIND[k]=F[2]; KBASE[k]=F[3]; KF[k]=cnt }
      next
  }
  SEEN_UNKNOWN[sec]=1
}
