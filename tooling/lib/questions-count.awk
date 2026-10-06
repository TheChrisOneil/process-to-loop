# One line summarising a question set, for a status screen. Appended to
# questions.awk, so it counts what the gates count.
END {
  for (qx=1; qx<=nq; qx++) { qd=QID[qx]
    qt = Q[qd ".answer_type"]; if (qt=="") qt="open"
    CNT[qt]++
    if (Q[qd ".answer_prov"]=="synthetic") syn++
  }
  out = nq " asked: " CNT["stated"]+0 " stated, " CNT["delegated"]+0 " delegated, " CNT["unanswered"]+0 " unanswered"
  if (CNT["open"]+0 > 0) out = out ", " CNT["open"] " STILL OPEN"
  if (syn+0 > 0)         out = out "  (" syn " SYNTHETIC — a rehearsal, not a confirmation)"
  print out
}
