# Shared parser for QUESTIONS.md. Read by the questions tool, the two gates and
# the findings writer, so none of them can disagree about what was asked or what
# came back. The contract is schema/QUESTIONS-FORMAT.md.
#
# Populates: H["<key>"]                         the header, before the first question
#            QID[1..nq] · QTITLE[1..nq]
#            Q["<id>.<key>"]                    every keyed line in a question block
#            Q["<id>.answer_type"]  one of stated, unanswered, delegated, or "" when open
#            Q["<id>.answer_by"] · answer_date · answer_value · answer_prov
#
# Counter is nq and the scratch names are qk/qv/qi, spelled distinctly on purpose:
# a short counter reused by a query program appended to this file hung the design
# validator for hours once. Never introduce a, s, g, k or i here.

/^##[ \t]+Q[0-9]+/ {
  nq++
  qline = $0
  sub(/^##[ \t]+/, "", qline)
  qi = index(qline, " ")
  if (qi == 0) { QID[nq] = qline; QTITLE[nq] = "" }
  else {
    QID[nq] = substr(qline, 1, qi - 1)
    QTITLE[nq] = substr(qline, qi + 1)
    sub(/^[ \t]*[-—–][ \t]*/, "", QTITLE[nq])
  }
  qcur = QID[nq]
  next
}
/^#/ { next }

# A keyed line starts lowercase, carries only lowercase, digits and underscores,
# sits hard against the left margin, then a colon. Prose almost never looks like
# that, and a question's own text — which does contain colons — is the VALUE of
# asks:, never a line of its own. The digits matter: use_case_sha256 is a key,
# and a pattern of letters alone silently dropped it into the prose.
/^[a-z_][a-z0-9_]*:/ {
  qi = index($0, ":")
  qk = substr($0, 1, qi - 1)
  qv = substr($0, qi + 1)
  sub(/^[ \t]+/, "", qv); sub(/[ \t]+$/, "", qv)
  if (qcur == "") { H[qk] = qv; next }
  Q[qcur "." qk] = qv
  if (qk == "answer") {
    if (qv == "") next
    qn = split(qv, QF, / *\| */)
    Q[qcur ".answer_type"]  = tolower(QF[1])
    Q[qcur ".answer_by"]    = (qn >= 2 ? QF[2] : "")
    Q[qcur ".answer_date"]  = (qn >= 3 ? QF[3] : "")
    Q[qcur ".answer_value"] = (qn >= 4 ? QF[4] : "")
    Q[qcur ".answer_prov"]  = (qn >= 5 ? tolower(QF[5]) : "real")
    Q[qcur ".answer_nf"]    = qn
  }
  next
}
