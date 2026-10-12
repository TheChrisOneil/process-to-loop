# Renders the skills review: `list`, `show` and the HTML page, from two flat
# files skills.sh writes. One program for all three, so the terminal and the
# page cannot disagree about what a skill's state is or where it is used.
#
#   -v MODE=list|show|html   -v TODAY=YYYY-MM-DD   [-v WANT=<id>]
#   files: <catalog.tsv> <uses.tsv>   (CATTSV names the first)
#
# catalog.tsv   S  id status owner review_by        one per skill, in file order
#               F  id key value                     every field, in file order
# uses.tsv      U  design path skill step name type text why
#               P  design path skill source owner_named text
#
# The lapse rule is V43's, copied exactly rather than approximated: V43 compares
# review_by (YYYY-MM) with today (YYYY-MM-DD) as strings, so "2027-04" is lapsed
# from 2027-04-01. A review page that called a skill "in force" on a day the
# validator refuses designs naming it would be the page lying for the rule.

BEGIN { FS = "\t"; nsk = 0; nu = 0; np = 0 }

FILENAME == CATTSV && $1 == "S" {
  nsk++; SKI[nsk] = $2; SST[$2] = $3; SOW[$2] = $4; SRB[$2] = $5; KNOWN[$2] = 1; next
}
FILENAME == CATTSV && $1 == "F" { NF_[$2]++; FK[$2, NF_[$2]] = $3; FV[$2, NF_[$2]] = $4; next }
FILENAME == CATTSV && $1 == "D" { DCOUNT++; next }

$1 == "U" {
  nu++; UD[nu] = $2; UP[nu] = $3; US[nu] = $4; UST[nu] = $5; UN[nu] = $6; UT[nu] = $7; UX[nu] = $8; UW[nu] = $9
  NUSE[$4]++
  if (!(($4, $2) in UDES)) { UDES[$4, $2] = 1; NDES[$4]++ }
  next
}
$1 == "P" {
  # A FINDINGS.md row repeats the design's own proposal. Keep the design's: it
  # is the source, and the finding is the routing of it.
  if ((($2, $4) in PSEEN)) next
  PSEEN[$2, $4] = 1
  np++; PD[np] = $2; PP[np] = $3; PS[np] = $4; PSRC[np] = $5; PO[np] = $6; PX[np] = $7
  next
}

# ---- dates ------------------------------------------------------------------
function civil(y, m, d) {   # days since 1970-01-01, proleptic Gregorian
  y -= (m <= 2); era = int((y >= 0 ? y : y - 399) / 400); yoe = y - era * 400
  doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}
function isym(s) { return s ~ /^[0-9][0-9][0-9][0-9]-(0[1-9]|1[0-2])$/ }
function state(id,   rb, d) {
  if (SST[id] == "proposed") return "proposed"
  rb = SRB[id]
  if (!isym(rb)) return "no valid review date"
  if (rb < TODAY) return "lapsed"
  d = civil(substr(rb,1,4)+0, substr(rb,6,2)+0, 1) - civil(substr(TODAY,1,4)+0, substr(TODAY,6,2)+0, substr(TODAY,9,2)+0)
  if (d <= 60) return "due within 60 days"
  return "in force"
}
function stclass(st) {
  if (st == "in force") return "ok"
  if (st == "due within 60 days") return "due"
  if (st == "proposed") return "prop"
  return "bad"
}

# ---- escaping ---------------------------------------------------------------
# Text nodes need only & < >. Attributes need the quotes too. A single quote is
# deliberately NOT escaped in text, so a command in a <pre> reads, copies and
# greps exactly as it will be pasted into a shell.
function ht(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
function ha(s) { s = ht(s); gsub(/"/, "\\&quot;", s); gsub(/'/, "\\&#39;", s); return s }
# POSIX single quoting: the only character that needs care is ' itself, written
# as '\'' . Split-and-join rather than gsub, because what awk does with a
# backslash in a gsub replacement differs between implementations.
function sq(s,   n, P, i, o) {
  n = split(s, P, "'"); o = P[1]
  for (i = 2; i <= n; i++) o = o "'\\''" P[i]
  return "'" o "'"
}
function fval(id, key,   j, v) { v = ""; for (j = 1; j <= NF_[id]; j++) if (FK[id, j] == key) v = FV[id, j]; return v }
function cmdset(id, f, v) { return "tooling/skills.sh set " id " " f " " sq(v) " --by " sq("<your name>") CATARG }

# ---- list -------------------------------------------------------------------
function do_list(   i, id) {
  printf "%-26s %-22s %-10s %-20s %7s %5s\n", "SKILL", "OWNER", "REVIEW_BY", "STATE", "DESIGNS", "STEPS"
  for (i = 1; i <= nsk; i++) {
    id = SKI[i]
    printf "%-26s %-22s %-10s %-20s %7d %5d\n", id, SOW[id], (SRB[id] == "" ? "-" : SRB[id]), state(id), NDES[id] + 0, NUSE[id] + 0
  }
  printf "\n%d skill(s) catalogued; %d design(s) read from %s; %d proposal(s) not catalogued\n", nsk, DCOUNT + 0, DESIGNS, uncat()
}
function uncat(   i, c) { c = 0; for (i = 1; i <= np; i++) if (!(PS[i] in KNOWN)) c++; return c }

# ---- show -------------------------------------------------------------------
function do_show(   j, i, any, id) {
  id = WANT
  if (!(id in KNOWN)) {
    printf "REFUSED: the catalog has no skill %s.\n", id > "/dev/stderr"
    for (i = 1; i <= np; i++) if (PS[i] == id)
      printf "         %s proposes it (%s): %s\n", PD[i], PSRC[i], PX[i] > "/dev/stderr"
    exit 1
  }
  printf "%s   %s\n", id, toupper(state(id))
  for (j = 1; j <= NF_[id]; j++) printf "  %-12s %s\n", FK[id, j] ":", FV[id, j]
  printf "\nWHERE IT IS USED   (designs under %s)\n", DESIGNS
  any = 0
  for (i = 1; i <= nu; i++) if (US[i] == id) {
    any = 1
    printf "  %s  step %s %s (%s)\n", UD[i], UST[i], UN[i], UT[i]
    printf "      step: %s\n", UX[i]
    printf "      why:  %s\n", UW[i]
  }
  if (!any) print "  no step in any design names it"
  if (SST[id] != "proposed")
    printf "\n  The ledger records it as: in force, not verified as applied.\n"
  print "\nPROPOSALS   (know-how a design asked for that the catalog does not hold in force)"
  any = 0
  for (i = 1; i <= np; i++) if (!(PS[i] in KNOWN) || SST[PS[i]] == "proposed") {
    any = 1
    printf "  %s  proposed by %s (%s); owner named: %s\n", PS[i], PD[i], PSRC[i], (PO[i] == "" ? "none — routes to the catalog owner" : PO[i])
    printf "      %s\n", PX[i]
  }
  for (i = 1; i <= nsk; i++) if (SST[SKI[i]] == "proposed") {
    any = 1
    printf "  %s  catalogued as proposed, waiting for %s to accept it\n", SKI[i], SOW[SKI[i]]
  }
  if (!any) print "  none"
}

# ---- html -------------------------------------------------------------------
function svg(id,   i, n, nd, y, h, D, DY, k, sy, o) {
  n = 0; nd = 0
  for (i = 1; i <= nu; i++) if (US[i] == id) { n++; if (!((UD[i]) in DY)) { nd++; D[nd] = UD[i]; DY[UD[i]] = 0 } }
  if (n == 0) return "<p class=\"muted\">No step in any design names it yet.</p>"
  h = (n > nd ? n : nd) * 40 + 16
  o = "<svg class=\"map\" viewBox=\"0 0 660 " h "\" role=\"img\" aria-label=\"" ha(id) " is applied by " n " step(s) in " nd " design(s)\">"
  sy = h / 2
  for (k = 1; k <= nd; k++) DY[D[k]] = 8 + (k - 1) * ((h - 16) / nd) + ((h - 16) / nd) / 2
  k = 0
  for (i = 1; i <= nu; i++) if (US[i] == id) {
    k++; y = 8 + (k - 1) * ((h - 16) / n) + ((h - 16) / n) / 2
    o = o "<path class=\"edge\" d=\"M180 " sy " C205 " sy " 205 " y " 230 " y "\"/>"
    o = o "<path class=\"edge\" d=\"M430 " y " C455 " y " 455 " DY[UD[i]] " 480 " DY[UD[i]] "\"/>"
    o = o "<rect class=\"n step\" x=\"230\" y=\"" (y - 14) "\" width=\"200\" height=\"28\" rx=\"6\"/>"
    o = o "<text x=\"330\" y=\"" (y + 4) "\" text-anchor=\"middle\">step " ht(UST[i]) " · " ht(substr(UN[i], 1, 20)) "</text>"
  }
  o = o "<rect class=\"n skill\" x=\"10\" y=\"" (sy - 16) "\" width=\"170\" height=\"32\" rx=\"6\"/>"
  o = o "<text x=\"95\" y=\"" (sy + 4) "\" text-anchor=\"middle\" class=\"b\">" ht(substr(id, 1, 24)) "</text>"
  for (k = 1; k <= nd; k++) {
    o = o "<rect class=\"n design\" x=\"480\" y=\"" (DY[D[k]] - 14) "\" width=\"170\" height=\"28\" rx=\"6\"/>"
    o = o "<text x=\"565\" y=\"" (DY[D[k]] + 4) "\" text-anchor=\"middle\">" ht(substr(D[k], 1, 22)) ".design</text>"
  }
  return o "</svg>"
}
function refine_row(id, f, v, multi) {
  printf "<div class=\"fld\" data-skill=\"%s\" data-field=\"%s\">\n", ha(id), f
  printf "<label for=\"%s--%s\">%s</label>\n", ha(id), f, f
  if (multi) printf "<textarea id=\"%s--%s\" rows=\"2\" data-current=\"%s\">%s</textarea>\n", ha(id), f, ha(v), ht(v)
  else       printf "<input id=\"%s--%s\" value=\"%s\" data-current=\"%s\">\n", ha(id), f, ha(v), ha(v)
  printf "<div class=\"cmdrow\"><pre class=\"cmd\">%s</pre><button type=\"button\" class=\"copy\" disabled>Copy</button><span class=\"why\">unchanged</span></div>\n", ht(cmdset(id, f, v))
  print "</div>"
}
function do_html(   i, id, j, st, any, rbv) {
  print "<nav class=\"toc\"><strong>Skills</strong>"
  for (i = 1; i <= nsk; i++) printf " <a href=\"#sk-%s\">%s</a> <span class=\"pill %s\">%s</span>", ha(SKI[i]), ht(SKI[i]), stclass(state(SKI[i])), ht(state(SKI[i]))
  printf " · <a href=\"#proposals\">Proposals (%d)</a></nav>\n", uncat()

  for (i = 1; i <= nsk; i++) {
    id = SKI[i]; st = state(id)
    printf "<section class=\"card\" id=\"sk-%s\">\n", ha(id)
    printf "<header><h2>%s</h2><span class=\"pill %s\">%s</span></header>\n", ht(id), stclass(st), ht(st)
    if (st == "lapsed") printf "<p class=\"alert\">Review date %s has passed. V43 refuses every design that names it until it is re-attested: set a new review_by below.</p>\n", ht(SRB[id])
    else if (st == "due within 60 days") printf "<p class=\"warn\">Review date %s is within 60 days. After it passes, V43 refuses every design that names this skill.</p>\n", ht(SRB[id])
    else if (st == "proposed") printf "<p class=\"warn\">Proposed and not in force. %s has been named to own it; until they accept it no step may depend on it (V40), and no bundle logs it.</p>\n", ht(SOW[id])
    print "<dl class=\"fields\">"
    for (j = 1; j <= NF_[id]; j++) printf "<dt>%s</dt><dd>%s</dd>\n", ht(FK[id, j]), ht(FV[id, j])
    print "</dl>"
    print "<h3>Used by</h3>"
    print svg(id)
    any = 0
    for (j = 1; j <= nu; j++) if (US[j] == id) {
      if (!any) print "<div class=\"tw\"><table><thead><tr><th>Design</th><th>Step</th><th>What the step does</th><th>Why the design applies it</th></tr></thead><tbody>"
      any = 1
      printf "<tr><td>%s</td><td>%s&nbsp;<code>%s</code><br><span class=\"muted\">%s</span></td><td>%s</td><td>%s</td></tr>\n", ht(UD[j]), ht(UST[j]), ht(UN[j]), ht(UT[j]), ht(UX[j]), ht(UW[j])
    }
    if (any) print "</tbody></table></div>"
    if (st != "proposed") print "<p class=\"ledger\">A step that applies it writes one ledger row per unit: <code>skill " ht(id) " (" ht(SOW[id]) ") catalog " ht(SHA12) ": in force, not verified as applied</code></p>"

    print "<details class=\"refine\"><summary>Refine this skill</summary>"
    print "<p class=\"muted\">Edit a value and copy the command it composes. Run it from the repository root: the tool writes the catalog, records who and when, and re-checks it. This page writes nothing.</p>"
    refine_row(id, "covers", fval(id, "covers"), 1)
    refine_row(id, "applies_to", fval(id, "applies_to"), 1)
    refine_row(id, "because", fval(id, "because"), 1)
    refine_row(id, "owner", fval(id, "owner"), 0)
    if (st == "proposed") {
      printf "<div class=\"fld accept\" data-skill=\"%s\">\n<label for=\"%s--accept\">accept, with a review date (YYYY-MM)</label>\n", ha(id), ha(id)
      printf "<input id=\"%s--accept\" value=\"\" placeholder=\"YYYY-MM\" data-current=\"\">\n", ha(id)
      printf "<div class=\"cmdrow\"><pre class=\"cmd\">%s</pre><button type=\"button\" class=\"copy\" disabled>Copy</button><span class=\"why\">needs a review date</span></div>\n</div>\n", \
        ht("tooling/skills.sh accept " id " --review-by " sq("YYYY-MM") " --by " sq("<your name>") CATARG)
    } else refine_row(id, "review_by", fval(id, "review_by"), 0)
    print "</details>"
    print "</section>"
  }

  print "<section class=\"card\" id=\"proposals\"><header><h2>Proposals</h2></header>"
  print "<p>Know-how a design asked for that the catalog does not hold in force. A design may <em>propose</em> a skill (<code>used_by: -</code>) and may not <em>depend</em> on one nobody owns (V40). Each proposal is a request to whoever owns the catalog, the same procurement signal a missing tool is.</p>"
  any = 0
  for (i = 1; i <= np; i++) if (!(PS[i] in KNOWN) || SST[PS[i]] == "proposed") {
    if (!any) print "<div class=\"tw\"><table><thead><tr><th>Skill</th><th>Proposed by</th><th>Owner it names</th><th>What it says</th><th></th></tr></thead><tbody>"
    any = 1
    printf "<tr><td><code>%s</code>%s</td><td>%s<br><span class=\"muted\">%s</span></td><td>%s</td><td>%s</td>", ht(PS[i]), (PS[i] in KNOWN ? "<br><span class=\"pill prop\">catalogued as proposed</span>" : ""), ht(PD[i]), ht(PSRC[i]), (PO[i] == "" ? "<span class=\"muted\">none named; routes to the catalog owner</span>" : ht(PO[i])), ht(PX[i])
    if (PS[i] in KNOWN) print "<td></td></tr>"
    else printf "<td><button type=\"button\" class=\"prefill\" data-id=\"%s\" data-owner=\"%s\" data-because=\"%s\">Prefill</button></td></tr>\n", ha(PS[i]), ha(PO[i]), ha(PX[i])
  }
  if (any) print "</tbody></table></div>"
  else print "<p class=\"muted\">No design under the designs directory proposes a skill the catalog lacks.</p>"
  print "<details class=\"refine\" id=\"propose\" open><summary>Propose a skill</summary>"
  print "<p class=\"muted\">Adds a block marked <code>status: proposed</code>. It routes to the owner you name, and no step may depend on it until they accept it with a review date.</p>"
  print "<div class=\"grid\">"
  print "<label for=\"p-id\">id</label><input id=\"p-id\" placeholder=\"dose-phrase-conventions\">"
  print "<label for=\"p-owner\">owner</label><input id=\"p-owner\" placeholder=\"Practice operations\">"
  print "<label for=\"p-covers\">covers</label><textarea id=\"p-covers\" rows=\"2\"></textarea>"
  print "<label for=\"p-applies\">applies_to</label><textarea id=\"p-applies\" rows=\"2\"></textarea>"
  print "<label for=\"p-because\">because</label><textarea id=\"p-because\" rows=\"2\"></textarea>"
  print "</div>"
  printf "<div class=\"cmdrow\"><pre class=\"cmd\" id=\"p-cmd\">%s</pre><button type=\"button\" class=\"copy\" id=\"p-copy\" disabled>Copy</button><span class=\"why\" id=\"p-why\">fill every field</span></div>\n", \
    ht("tooling/skills.sh propose <id> --owner " sq("<owner>") " --covers " sq("<covers>") " --applies-to " sq("<applies_to>") " --because " sq("<because>") " --by " sq("<your name>") CATARG)
  print "</details></section>"
}

END {
  if (MODE == "list") do_list()
  else if (MODE == "show") do_show()
  else if (MODE == "html") do_html()
}
