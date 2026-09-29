# The design, flattened into one record per line for the scaffolder to read in bash.
function slug(t,   s) { s=tolower(t); gsub(/[^a-z0-9]+/,"-",s); gsub(/^-+|-+$/,"",s); return s }
END {
  printf "meta\tuse_case\t%s\n", V["meta.use_case"]
  printf "meta\tauthor\t%s\n",   V["meta.author"]
  printf "meta\tapprover\t%s\n", V["meta.approver"]
  printf "meta\texit\t%s\n",     V["meta.exit_criterion"]
  printf "meta\tunit\t%s\n",     V["unit.definition"]
  printf "meta\tfanout\t%s\n",   (V["unit.fanout"]=="" ? "1" : V["unit.fanout"])
  printf "meta\tevidence_step\t%s\n", V["evidence.writer_step"]
  printf "meta\tintegrity\t%s\n",     V["evidence.integrity"]
  for (i=1;i<=s;i++)
    printf "step\t%s\t%s\t%s\t%s\t%s\t%s\n", SID[i], slug(SNAME[i]), tolower(STYPE[i]), tolower(SACT[i]), SDESC[i], SSCOPE[i]
  for (j=1;j<=g;j++)
    printf "gate\t%s\t%s\t%s\n", GAFT[j], GCOND[j], GREF[j]
  for (i=1;i<=a;i++) printf "assumption\t%s\n", ASSUM[i]
  for (i=1;i<=k;i++) printf "kpi\t%s\t%s\t%s\n", KNAME[i], KKIND[i], KBASE[i]
}
