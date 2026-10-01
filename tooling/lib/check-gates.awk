# Every gate must attach to a real step. A diagram that quietly drops a control is the exact
# failure this course teaches, so the render refuses before it prints anything.
END {
  miss=""
  for (j=1;j<=g;j++) { found=0
    for (i=1;i<=s;i++) if (SID[i]==GAFT[j]) { found=1; break }
    if (!found) miss=miss " " j }
  if (miss!="") { print "gate(s)" miss " name a step id that does not exist" > "/dev/stderr"; exit 1 }
}
