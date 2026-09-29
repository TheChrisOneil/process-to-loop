# Read after parse.awk. Prints one gate per line: n <TAB> condition <TAB> refusal
END { for (j=1;j<=g;j++) printf "%d\t%s\t%s\n", j, GCOND[j], GREF[j] }
