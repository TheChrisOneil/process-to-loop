#!/usr/bin/env bash
# The skills in the catalog: review them, and refine them without hand-editing.
#
#   skills.sh list    [--catalog <f>] [--designs <dir>]       one line per skill
#   skills.sh show    <id> [--catalog <f>] [--designs <dir>]  every field, and where it is used
#   skills.sh check   [--catalog <f>]                          is every @skill block well formed?
#   skills.sh set     <id> <field> <value> --by <who>          refine one field
#   skills.sh propose <id> --owner <o> --covers <t> --applies-to <t> --because <t> --by <who>
#   skills.sh accept  <id> --review-by YYYY-MM --by <who>      a proposal's owner takes it on
#   skills.sh review  [--out <file.html>] [--designs <dir>]    the review page
#
# A skill is know-how a step applies; the catalog is the only place it lives.
# Its owner, often not the person who wrote the design, has to be able to read
# every skill, see exactly which steps of which designs lean on it, and change it.
# Before this tool the only way to change one was to open the catalog in an
# editor, and a hand-edited catalog is the control that is declared, reported and
# absent: nothing records who changed the wording a clinician's note follows, or
# when, and a typo in review_by silently lapses every design that names it.
#
# So the catalog is written by `set`, `propose` and `accept`, never by hand. Each
# write names who made it, appends a dated `refined:` line, touches no field it
# was not asked to, re-runs `check`, and proves all of that against the file it
# wrote before replacing the catalog. A refused write leaves the catalog
# byte-identical.
#
# `review` writes one static page, self-contained so it opens from a file or an
# attachment with no network, and it composes the exact `set`/`propose`/`accept`
# commands for a person to copy. The page never writes anything; this tool does.
#
# Fields `set` may change: covers, applies_to, because, review_by, owner.
# decided_by is set to --by on every write; chosen and the refined: history are
# the record and are never rewritten.
#
# Designs default to the rig's processes, one current design per process:
# <dir>/*.design and <dir>/*/*.design. prior/ and bundle copies are history, not
# use, and counting them would report a skill as used by runs nobody can start.
#
# Exit 0 ok · 1 refused · 64 wrong arguments · 75 could not run
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
DEFAULT_CATALOG="$ROOT/catalog/eb-tools.catalog"
CATALOG=${CATALOG:-$DEFAULT_CATALOG}
DESIGNS=${PTL_DESIGNS:-$HOME/cities/ptl-rig/processes}
OUTF=""; BY=""; OWNER=""; COVERS=""; APPLIES=""; BECAUSE=""; REVIEWBY=""
HAVE_BY=0; HAVE_OWNER=0; HAVE_COVERS=0; HAVE_APPLIES=0; HAVE_BECAUSE=0; HAVE_REVIEWBY=0
# The date is overridable so the tests can stand on a fixed day; nothing else is.
TODAY=${SKILLS_TODAY:-$(date +%F)}
THISMONTH=${TODAY%-*}

usage() { sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
CMD=${1:-}; shift 2>/dev/null || true
[ -n "$CMD" ] || usage
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --catalog)    [ $# -ge 2 ] || usage; CATALOG=$2; shift 2 ;;
    --designs)    [ $# -ge 2 ] || usage; DESIGNS=$2; shift 2 ;;
    --out)        [ $# -ge 2 ] || usage; OUTF=$2; shift 2 ;;
    --by)         [ $# -ge 2 ] || usage; BY=$2; HAVE_BY=1; shift 2 ;;
    --owner)      [ $# -ge 2 ] || usage; OWNER=$2; HAVE_OWNER=1; shift 2 ;;
    --covers)     [ $# -ge 2 ] || usage; COVERS=$2; HAVE_COVERS=1; shift 2 ;;
    --applies-to) [ $# -ge 2 ] || usage; APPLIES=$2; HAVE_APPLIES=1; shift 2 ;;
    --because)    [ $# -ge 2 ] || usage; BECAUSE=$2; HAVE_BECAUSE=1; shift 2 ;;
    --review-by)  [ $# -ge 2 ] || usage; REVIEWBY=$2; HAVE_REVIEWBY=1; shift 2 ;;
    --) shift; while [ $# -gt 0 ]; do POS+=("$1"); shift; done ;;
    --*) echo "REFUSED: unknown option $1" >&2; exit 64 ;;
    *) POS+=("$1"); shift ;;
  esac
done
P1=${POS[0]:-}; P2=${POS[1]:-}; P3=${POS[2]-}; NPOS=${#POS[@]}

[ -f "$CATALOG" ] || { echo "REFUSED: no catalog at $CATALOG." >&2; exit 75; }
[ -f "$HERE/lib/catalog.awk" ] && [ -f "$HERE/lib/parse.awk" ] && [ -f "$HERE/lib/skills-review.awk" ] \
  || { echo "REFUSED: the parsers are not beside this script in $HERE/lib." >&2; exit 75; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# ---- reading ----------------------------------------------------------------
# The catalog, flattened by the one catalog parser: S per skill, F per field in
# the order written, T per tool. Every check below compares two of these.
cat > "$WORK/cat.q" <<'CATQ'
END {
  for (i = 1; i <= ns; i++) { id = SKID[i]
    printf "S\t%s\t%s\t%s\t%s\n", id, SK[id ".status"], SK[id ".owner"], SK[id ".review_by"] }
  for (i = 1; i <= ns; i++) { id = SKID[i]; if (id in DONE) continue; DONE[id] = 1
    for (j = 1; j <= SKNF[id]; j++) { v = SKFV[id, j]; gsub(/\t/, " ", v); printf "F\t%s\t%s\t%s\n", id, SKF[id, j], v } }
  for (i = 1; i <= t; i++) printf "T\t%s\n", TID[i]
}
CATQ
flat() { awk -f "$HERE/lib/catalog.awk" -f "$WORK/cat.q" "$1"; }

# One design's skills, through the design parser: U per step that applies a
# skill, P per proposal. Variables are prefixed: every name in parse.awk is
# global, and reusing one has hung the validator before.
cat > "$WORK/uses.q" <<'USEQ'
function sr_trim(x) { gsub(/^[ \t]+|[ \t]+$/, "", x); gsub(/\t/, " ", x); return x }
# The owner a proposal names, when its why says so in the house phrasing the
# design method uses: "confirm with <owner>" or "owned by <owner>". Anything
# else is reported as no owner named, never guessed.
function sr_owner(w,   o) {
  if (match(w, /confirm with [^,;.]+/)) return sr_trim(substr(w, RSTART + 13, RLENGTH - 13))
  if (match(w, /owned by [^,;.]+/))     return sr_trim(substr(w, RSTART + 9, RLENGTH - 9))
  return ""
}
END {
  for (sr_z = 1; sr_z <= n_skill; sr_z++) {
    sr_id = sr_trim(SKL_ID[sr_z]); sr_ub = sr_trim(SKL_BY[sr_z]); sr_w = sr_trim(SKL_WHY[sr_z])
    if (sr_ub == "" || sr_ub == "-") {
      printf "P\t%s\t%s\t%s\tdesign @skills\t%s\t%s\n", DN, DP, sr_id, sr_owner(sr_w), sr_w; continue }
    sr_n = split(sr_ub, sr_B, / +/)
    for (sr_y = 1; sr_y <= sr_n; sr_y++) {
      sr_st = sr_B[sr_y]; sr_hit = 0
      for (sr_m = 1; sr_m <= s; sr_m++) if (sr_trim(SID[sr_m]) == sr_st) {
        sr_hit = 1
        printf "U\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", DN, DP, sr_id, sr_st, sr_trim(SNAME[sr_m]), sr_trim(STYPE[sr_m]), sr_trim(SDESC[sr_m]), sr_w
      }
      if (!sr_hit) printf "U\t%s\t%s\t%s\t%s\t(no such step)\t-\tthe design names step %s and has no step %s; V41 refuses it\t%s\n", DN, DP, sr_id, sr_st, sr_st, sr_st, sr_w
    }
  }
}
USEQ

# A FINDINGS.md routes a design's proposal to the catalog owner. Read here so a
# proposal shows up even when the finding outlived an edit to the design.
findings_rows() { # <design-name> <FINDINGS.md>
  awk -v DN="$1" -v FP="$2" '
    /^## [0-9]+\. .*FOR THE CATALOG OWNER.*know-how the catalog does not have: / {
      id = $0; sub(/.*know-how the catalog does not have: /, "", id); gsub(/[ \t]+$/, "", id); want = 1; next }
    want && NF { gsub(/\t/, " "); printf "P\t%s\t%s\t%s\tFINDINGS.md\t\t%s\n", DN, FP, id, $0; want = 0 }
  ' "$2"
}

designs_flat() { # writes uses.tsv; appends a D row per design to cat.tsv
  [ -d "$DESIGNS" ] || { echo "REFUSED: no designs at $DESIGNS, so where each skill is used cannot be read." >&2
                         echo "         Pass --designs <dir> (or set PTL_DESIGNS). A review that silently found no use is the wrong answer." >&2
                         exit 75; }
  : > "$WORK/uses.tsv"
  local d dn
  for d in "$DESIGNS"/*.design "$DESIGNS"/*/*.design; do
    [ -f "$d" ] || continue
    dn=$(basename "$d" .design)
    printf 'D\t%s\n' "$dn" >> "$WORK/cat.tsv"
    awk -v DN="$dn" -v DP="$d" -f "$HERE/lib/parse.awk" -f "$WORK/uses.q" "$d" >> "$WORK/uses.tsv" 2>/dev/null \
      || { echo "REFUSED: could not parse $d." >&2; exit 75; }
    [ -f "$(dirname "$d")/FINDINGS.md" ] && findings_rows "$dn" "$(dirname "$d")/FINDINGS.md" >> "$WORK/uses.tsv"
  done
  return 0
}

render() { # <mode> [awk -v args...]
  local mode=$1; shift
  awk -v MODE="$mode" -v TODAY="$TODAY" -v CATTSV="$WORK/cat.tsv" -v DESIGNS="$DESIGNS" "$@" \
      -f "$HERE/lib/skills-review.awk" "$WORK/cat.tsv" "$WORK/uses.tsv"
}

# ---- the catalog's own check ------------------------------------------------
# What a well-formed @skill block is. Run by `check`, and on every file a write
# produces before that file is allowed to replace the catalog.
check_file() { # <catalog> ; prints problems, returns 0/1
  flat "$1" > "$WORK/chk.tsv" || { echo "  the catalog does not parse"; return 1; }
  awk -F'\t' '
    function ym(s) { return s ~ /^[0-9][0-9][0-9][0-9]-(0[1-9]|1[0-2])$/ }
    $1 == "T" { TOOL[$2] = 1; next }
    $1 == "S" { n++; ID[n] = $2; ST[$2] = $3; SEEN[$2]++; next }
    $1 == "F" { K[$2, $3]++; V[$2, $3] = $4; next }
    END {
      bad = 0; prop = 0
      for (i = 1; i <= n; i++) { id = ID[i]
        if (id in DONE) continue; DONE[id] = 1
        if (id !~ /^[a-z0-9][a-z0-9-]*$/) { print "  " id ": an id is lowercase letters, digits and hyphens"; bad++ }
        if (SEEN[id] > 1) { print "  " id ": catalogued " SEEN[id] " times; designs would depend on whichever was read last"; bad++ }
        if (id in TOOL)   { print "  " id ": is also a tool id; a design naming it would be ambiguous"; bad++ }
        if (ST[id] != "" && ST[id] != "proposed") { print "  " id ": status is \"" ST[id] "\"; the only status is proposed, and in force is its absence"; bad++ }
        if (ST[id] == "proposed") prop++
        nreq = split("covers owner applies_to because", R, " ")
        if (ST[id] != "proposed") { R[++nreq] = "decided_by"; R[++nreq] = "review_by" }
        for (r = 1; r <= nreq; r++) if (V[id, R[r]] == "") { print "  " id ": no " R[r]; bad++ }
        if (V[id, "review_by"] != "" && !ym(V[id, "review_by"])) { print "  " id ": review_by \"" V[id, "review_by"] "\" is not YYYY-MM"; bad++ }
        for (kk in K) { split(kk, KP, SUBSEP)
          if (KP[1] == id && KP[2] != "refined" && K[kk] > 1) { print "  " id ": " KP[2] " is written " K[kk] " times; only the last is read"; bad++ } }
      }
      exit (bad > 0)
    }' "$WORK/chk.tsv"
}

check_cmd() {
  local out rc
  out=$(check_file "$CATALOG"); rc=$?
  if [ $rc -eq 0 ]; then
    n=$(awk -F'\t' '$1=="S"{n++} $1=="S"&&$3=="proposed"{p++} END{printf "%d skill(s), %d in force, %d proposed", n, n-p, p}' "$WORK/chk.tsv")
    echo "every @skill block is well formed: $n"
    return 0
  fi
  echo "REFUSED: the catalog's skills are not well formed:" >&2
  printf '%s\n' "$out" >&2
  return 1
}

# ---- writing ----------------------------------------------------------------
# Line numbers of one skill block: its header and its last field line. Trailing
# comments and blank lines belong to whatever comes next, so a new line is
# placed after the last FIELD, never after a comment introducing the next block.
block_of() { # <catalog> <id> -> "start last" or nothing
  awk -v id="$2" '
    inb && /^@/ { inb = 0; stop = 1 }
    !stop && !start && /^@skill[ \t]/ && $2 == id { inb = 1; start = NR; last = NR; next }
    inb && !/^[[:space:]]*#/ && !/^[[:space:]]*$/ { last = NR }
    END { if (start) print start, last }' "$1"
}

refuse() { echo "REFUSED: $*" >&2; exit 1; }

one_line() { # <label> <value> ; refuses a value the catalog cannot hold
  case "$2" in *$'\n'*|*$'\r'*) refuse "$1 is one line; the catalog reads a value up to the end of its line." ;; esac
  case "$2" in *$'\t'*) refuse "$1 holds a tab, which the review page cannot carry intact." ;; esac
}
trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

need_by() {
  [ "$HAVE_BY" = 1 ] || { echo "REFUSED: --by is required. A change with no author has no provenance." >&2; exit 64; }
  one_line "--by" "$BY"; BY=$(trim "$BY")
  [ -n "$BY" ] || refuse "--by is empty. A change with no author has no provenance."
}

# A review date is a month, and it is in the future. V43 compares it with today
# as a string, so "2026-10" is already lapsed on 2026-10-01: a review_by of this
# month would be refused by the validator the moment it was written.
check_month() { # <value>
  case "$1" in
    [0-9][0-9][0-9][0-9]-0[1-9]|[0-9][0-9][0-9][0-9]-1[0-2]) : ;;
    *) refuse "review_by is a month, YYYY-MM, not \"$1\"." ;;
  esac
  [ "$1" \> "$THISMONTH" ] || refuse "review_by $1 is not after this month ($THISMONTH). V43 would refuse every design naming it today; a review date re-attests only if it is in the future."
}

# Prove the write before it lands: the new file passes `check`, every other
# skill and every tool reads exactly as before, and the named skill differs only
# in the keys this write was allowed to touch.
prove_and_replace() { # <new-file> <id> <allowed keys, space separated>
  local new=$1 id=$2 allowed=$3 out
  out=$(check_file "$new") || { echo "REFUSED: the catalog this would write fails its own check, so nothing was written:" >&2
                                printf '%s\n' "$out" >&2; exit 1; }
  flat "$CATALOG" > "$WORK/before.tsv"; flat "$new" > "$WORK/after.tsv"
  strip() { awk -F'\t' -v id="$id" -v allowed=" $allowed " '
    $1 == "S" && $2 == id { next }
    $1 == "F" && $2 == id && index(allowed, " " $3 " ") { next }
    { print }' "$1"; }
  if ! diff <(strip "$WORK/before.tsv") <(strip "$WORK/after.tsv") > "$WORK/diff" 2>&1; then
    echo "REFUSED: the write would have changed something it was not asked to, so nothing was written:" >&2
    sed 's/^/         /' "$WORK/diff" >&2
    exit 1
  fi
  cat "$new" > "$CATALOG" || { echo "REFUSED: could not write $CATALOG." >&2; exit 75; }
}

set_cmd() {
  [ "$NPOS" -ge 3 ] || { echo "usage: skills.sh set <id> <field> <value> --by <who>" >&2; exit 64; }
  [ "$NPOS" -eq 3 ] || { echo "REFUSED: set takes one value; quote it. Got $NPOS arguments." >&2; exit 64; }
  local id=$P1 field=$P2 value
  need_by
  case "$field" in
    covers|applies_to|because|review_by|owner) : ;;
    *) refuse "set refines covers, applies_to, because, review_by or owner, not \"$field\". decided_by and the refined: history are written by the tool; status changes with propose and accept." ;;
  esac
  one_line "the value" "$P3"; value=$(trim "$P3")
  [ -n "$value" ] || refuse "the value is empty. An empty $field reads as the field being absent."
  local blk; blk=$(block_of "$CATALOG" "$id")
  [ -n "$blk" ] || refuse "the catalog has no skill $id. To add one, propose it."
  [ "$field" != "review_by" ] || check_month "$value"
  local current
  current=$(awk -F'\t' -v id="$id" -v k="$field" '$1=="F" && $2==id && $3==k {v=$4} END{print v}' <(flat "$CATALOG"))
  # A refined: line that records a change which did not happen is a false record.
  [ "$current" != "$value" ] || refuse "$id $field is already that. Nothing to refine, and nothing was written."

  SK_VAL="$value" SK_WHO="$BY" awk -v s="${blk% *}" -v e="${blk#* }" -v f="$field" -v today="$TODAY" '
    function lead(l) { match(l, /^[ \t]*/); return substr(l, 1, RLENGTH) }
    {
      out = $0
      if (NR >= s && NR <= e) {
        if (!df && $0 ~ ("^[ \t]*" f ":"))          { out = lead($0) f ": " ENVIRON["SK_VAL"]; df = 1 }
        else if (!dd && $0 ~ /^[ \t]*decided_by:/)  { out = lead($0) "decided_by: " ENVIRON["SK_WHO"]; dd = 1 }
      }
      print out
      if (NR == e) {
        if (!df) print f ": " ENVIRON["SK_VAL"]
        if (!dd) print "decided_by: " ENVIRON["SK_WHO"]
        print "refined: " today " by " ENVIRON["SK_WHO"] ": " f
      }
    }' "$CATALOG" > "$WORK/new.catalog"
  prove_and_replace "$WORK/new.catalog" "$id" "$field decided_by refined"
  echo "$id: $field refined by $BY on $TODAY"
  echo "  $field: $value"
}

propose_cmd() {
  [ "$NPOS" -eq 1 ] || { echo "usage: skills.sh propose <id> --owner <o> --covers <t> --applies-to <t> --because <t> --by <who>" >&2; exit 64; }
  local id=$P1
  need_by
  [ "$HAVE_OWNER$HAVE_COVERS$HAVE_APPLIES$HAVE_BECAUSE" = 1111 ] \
    || { echo "REFUSED: a proposal names --owner, --covers, --applies-to and --because. The owner is who it routes to." >&2; exit 64; }
  one_line --owner "$OWNER";        OWNER=$(trim "$OWNER")
  one_line --covers "$COVERS";      COVERS=$(trim "$COVERS")
  one_line --applies-to "$APPLIES"; APPLIES=$(trim "$APPLIES")
  one_line --because "$BECAUSE";    BECAUSE=$(trim "$BECAUSE")
  [ -n "$OWNER" ]   || refuse "--owner is empty. A proposal routes to its owner, so it must name one."
  [ -n "$COVERS" ]  || refuse "--covers is empty."
  [ -n "$APPLIES" ] || refuse "--applies-to is empty."
  [ -n "$BECAUSE" ] || refuse "--because is empty. The reason is the part that stops the research being redone."
  printf '%s' "$id" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || refuse "a skill id is lowercase letters, digits and hyphens, not \"$id\"."
  flat "$CATALOG" > "$WORK/before.tsv"
  awk -F'\t' -v id="$id" '($1=="S"||$1=="T") && $2==id {f=1} END{exit !f}' "$WORK/before.tsv" \
    && refuse "$id is already in the catalog. Refine it with set instead."

  # After the last skill's last field; at the end of the file if there is none.
  local after
  after=$(awk '
    /^@/ { inb = 0 }
    /^@skill[ \t]/ { inb = 1; last = NR; next }
    inb && !/^[[:space:]]*#/ && !/^[[:space:]]*$/ { last = NR }
    END { print last + 0 }' "$CATALOG")
  SK_ID="$id" SK_OWN="$OWNER" SK_COV="$COVERS" SK_APP="$APPLIES" SK_BEC="$BECAUSE" SK_WHO="$BY" \
  awk -v after="$after" -v today="$TODAY" '
    function block() {
      print ""
      print "@skill " ENVIRON["SK_ID"]
      print "status: proposed"
      print "covers: " ENVIRON["SK_COV"]
      print "owner: " ENVIRON["SK_OWN"]
      print "applies_to: " ENVIRON["SK_APP"]
      print "because: " ENVIRON["SK_BEC"]
      print "proposed: " today " by " ENVIRON["SK_WHO"]
    }
    { print }
    NR == after { block(); done = 1 }
    END { if (!done) block() }' "$CATALOG" > "$WORK/new.catalog"
  prove_and_replace "$WORK/new.catalog" "$id" "status covers owner applies_to because proposed"
  awk -F'\t' -v id="$id" '$1=="S" && $2==id && $3=="proposed" {f=1} END{exit !f}' <(flat "$CATALOG") \
    || { echo "REFUSED: the proposal did not read back as proposed." >&2; exit 1; }
  echo "$id proposed by $BY on $TODAY; it routes to $OWNER, and no step may depend on it until they accept it."
}

accept_cmd() {
  [ "$NPOS" -eq 1 ] || { echo "usage: skills.sh accept <id> --review-by YYYY-MM --by <who>" >&2; exit 64; }
  local id=$P1
  need_by
  [ "$HAVE_REVIEWBY" = 1 ] || { echo "REFUSED: --review-by is required. Accepting know-how is promising to re-read it by a date." >&2; exit 64; }
  check_month "$REVIEWBY"
  local blk; blk=$(block_of "$CATALOG" "$id")
  [ -n "$blk" ] || refuse "the catalog has no skill $id."
  awk -F'\t' -v id="$id" '$1=="S" && $2==id && $3=="proposed" {f=1} END{exit !f}' <(flat "$CATALOG") \
    || refuse "$id is not a proposal; it is already in force."
  SK_RB="$REVIEWBY" SK_WHO="$BY" awk -v s="${blk% *}" -v e="${blk#* }" -v today="$TODAY" -v month="$THISMONTH" '
    {
      if (NR >= s && NR <= e) {
        if ($0 ~ /^[ \t]*status:/) { if (NR == e) tail(); next }
        if ($0 ~ /^[ \t]*review_by:/)  { print "review_by: " ENVIRON["SK_RB"]; rb = 1; if (NR == e) tail(); next }
        if ($0 ~ /^[ \t]*decided_by:/) { print "decided_by: " ENVIRON["SK_WHO"]; dd = 1; if (NR == e) tail(); next }
        if ($0 ~ /^[ \t]*chosen:/) ch = 1
      }
      print
      if (NR == e) tail()
    }
    function tail() {
      if (!ch) print "chosen: " month
      if (!dd) print "decided_by: " ENVIRON["SK_WHO"]
      if (!rb) print "review_by: " ENVIRON["SK_RB"]
      print "refined: " today " by " ENVIRON["SK_WHO"] ": accepted"
    }' "$CATALOG" > "$WORK/new.catalog"
  prove_and_replace "$WORK/new.catalog" "$id" "status chosen decided_by review_by refined"
  echo "$id accepted by $BY on $TODAY, in force until $REVIEWBY. Steps may now depend on it."
}

catarg() { # the --catalog a copied command needs, when it is not the default
  [ "$(cd "$(dirname "$CATALOG")" && pwd)/$(basename "$CATALOG")" = "$DEFAULT_CATALOG" ] && return 0
  printf " --catalog '%s'" "$(printf '%s' "$CATALOG" | sed "s/'/'\\\\''/g")"
}

review_cmd() {
  local out=${OUTF:-$ROOT/build/skills-review.html}
  mkdir -p "$(dirname "$out")" || { echo "REFUSED: cannot create $(dirname "$out")." >&2; exit 75; }
  local sha now ca
  sha=$(shasum -a 256 "$CATALOG" | cut -d' ' -f1)
  now=$(date '+%Y-%m-%d %H:%M %Z')
  ca=$(catarg)
  esc() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }
  {
    cat <<'HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="process-to-loop tooling/skills.sh review">
<title>Skills review</title>
<style>
:root { --bg:#fbfaf8; --fg:#1d1d1f; --muted:#62626a; --card:#ffffff; --line:#dedbd5; --code:#f2efe9;
  --accent:#2f5f8f; --ok:#1f7a45; --okbg:#e3f3e8; --due:#8a5a00; --duebg:#fbf0d6; --bad:#a3262a; --badbg:#fbe4e2;
  --prop:#5b4a9e; --propbg:#ece8fa; --skill:#dce8f5; --step:#f2efe9; --design:#e8f1e6; }
@media (prefers-color-scheme: dark) { :root { --bg:#151618; --fg:#e8e6e1; --muted:#a09e99; --card:#1e2022; --line:#34373a;
  --code:#26292c; --accent:#8db8e6; --ok:#7fd19b; --okbg:#1c3325; --due:#f0c46a; --duebg:#3a2f15; --bad:#f2948f;
  --badbg:#3d1d1c; --prop:#bcaef0; --propbg:#2b2640; --skill:#1f3348; --step:#2a2d30; --design:#203325; } }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
main { max-width:1100px; margin:0 auto; padding:24px 16px 64px; }
h1 { font-size:1.6rem; margin:0 0 4px; } h2 { font-size:1.25rem; margin:0; } h3 { font-size:1rem; margin:20px 0 8px; }
code, pre, input, textarea { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size:13px; }
code { background:var(--code); padding:1px 4px; border-radius:4px; }
.meta { color:var(--muted); font-size:13px; margin:0 0 16px; } .meta code { word-break:break-all; }
.muted { color:var(--muted); }
.explain { background:var(--card); border:1px solid var(--line); border-left:4px solid var(--accent); border-radius:8px; padding:12px 16px; margin:16px 0; }
.toc { margin:16px 0; line-height:2; } .toc a { color:var(--accent); }
.card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:16px; margin:20px 0; }
.card > header { display:flex; gap:12px; align-items:center; flex-wrap:wrap; }
.pill { display:inline-block; font-size:12px; padding:1px 8px; border-radius:99px; white-space:nowrap; }
.pill.ok { background:var(--okbg); color:var(--ok); } .pill.due { background:var(--duebg); color:var(--due); }
.pill.bad { background:var(--badbg); color:var(--bad); } .pill.prop { background:var(--propbg); color:var(--prop); }
.alert { background:var(--badbg); color:var(--bad); padding:8px 12px; border-radius:6px; }
.warn { background:var(--duebg); color:var(--due); padding:8px 12px; border-radius:6px; }
dl.fields { display:grid; grid-template-columns:max-content 1fr; gap:4px 16px; margin:12px 0; }
dl.fields dt { color:var(--muted); font-family: ui-monospace, Menlo, monospace; font-size:13px; } dl.fields dd { margin:0; }
.tw { overflow-x:auto; } table { border-collapse:collapse; width:100%; font-size:14px; }
th, td { text-align:left; vertical-align:top; border-top:1px solid var(--line); padding:8px; } th { color:var(--muted); font-weight:600; }
svg.map { width:100%; max-width:660px; height:auto; display:block; margin:8px 0; }
svg.map text { font-size:12px; fill:var(--fg); } svg.map text.b { font-weight:600; }
svg.map .edge { fill:none; stroke:var(--muted); stroke-width:1.2; }
svg.map .n { stroke:var(--line); } svg.map .skill { fill:var(--skill); } svg.map .step { fill:var(--step); } svg.map .design { fill:var(--design); }
.legend { font-size:12px; color:var(--muted); }
.ledger { font-size:13px; color:var(--muted); }
details.refine { margin-top:16px; border-top:1px dashed var(--line); padding-top:8px; }
details.refine summary { cursor:pointer; color:var(--accent); font-weight:600; }
.fld { margin:12px 0; } .fld label, .grid label { display:block; font-family: ui-monospace, Menlo, monospace; font-size:13px; color:var(--muted); }
input, textarea { width:100%; background:var(--bg); color:var(--fg); border:1px solid var(--line); border-radius:6px; padding:6px 8px; }
.grid { display:grid; grid-template-columns:max-content 1fr; gap:6px 12px; align-items:start; margin:8px 0; }
.cmdrow { display:flex; gap:8px; align-items:flex-start; margin-top:6px; flex-wrap:wrap; }
pre.cmd { flex:1 1 420px; margin:0; background:var(--code); padding:8px; border-radius:6px; white-space:pre-wrap; word-break:break-word; }
button { font:inherit; font-size:13px; padding:6px 12px; border-radius:6px; border:1px solid var(--accent); background:var(--accent); color:var(--bg); cursor:pointer; }
button[disabled] { opacity:.45; cursor:not-allowed; } button.prefill { background:transparent; color:var(--accent); }
.why { font-size:12px; color:var(--muted); align-self:center; }
.who { display:flex; gap:12px; align-items:center; flex-wrap:wrap; } .who input { max-width:320px; }
</style>
</head>
HEAD
    printf '<body data-catarg="%s">\n<main>\n' "$(esc "$ca")"
    printf '<h1>Skills review</h1>\n'
    printf '<p class="meta">Generated by <code>tooling/skills.sh review</code> on %s. Catalog <code>%s</code>, sha256 <code>%s</code>. Designs read from <code>%s</code>. This page is a snapshot: it writes nothing, and it is out of date the moment the catalog changes. Regenerate it with <code>make skills-review</code>.</p>\n' \
      "$(esc "$now")" "$(esc "$CATALOG")" "${sha:0:12}" "$(esc "$DESIGNS")"
    cat <<'EXPLAIN'
<div class="explain">
<p><strong>A skill is know-how a step applies.</strong> It reaches nothing and decides nothing. It is catalogued so that two designs cannot word the same thing two ways, and so that one person owns it and re-reads it by a date.</p>
<p>When a step that applies a skill runs, its ledger row says <code>in force, not verified as applied</code>. That is the strongest claim available: nothing can prove a model or a person read a document, so the row records which version of the catalog was in force, by digest, and claims nothing more. For the same reason <strong>no gate may depend on a skill (V42)</strong>: a gate resting on something unprovable is a control that is declared, reported and absent. Know-how that decides belongs in a <code>@decisions</code> table, where completeness and overlap can be checked.</p>
</div>
<div class="who"><label for="who"><strong>Your name</strong>, as the catalog should record who made a change:</label><input id="who" placeholder="Practice operations" autocomplete="name"></div>
<p class="legend">Each diagram reads left to right: the skill, the steps that apply it, the designs those steps belong to.</p>
EXPLAIN
    render html -v SHA12="${sha:0:12}" -v CATARG="$ca"
    cat <<'SCRIPT'
</main>
<script>
// Plain JS, no network: composes the commands the tool runs. It never writes.
(function () {
  var CATARG = document.body.getAttribute('data-catarg') || '';
  function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
  function one(s) { return String(s).replace(/\s*[\r\n]+\s*/g, ' ').trim(); }
  function who() { return one(document.getElementById('who').value); }
  function arm(btn, why, ready, reason) {
    btn.disabled = !ready; why.textContent = ready ? 'ready to copy' : reason;
  }
  function refresh() {
    var w = who();
    document.querySelectorAll('.fld[data-field]').forEach(function (f) {
      var el = f.querySelector('input, textarea'), v = one(el.value), cur = el.getAttribute('data-current');
      var id = f.getAttribute('data-skill'), field = f.getAttribute('data-field');
      f.querySelector('pre.cmd').textContent = 'tooling/skills.sh set ' + id + ' ' + field + ' ' + shq(v) + ' --by ' + shq(w || '<your name>') + CATARG;
      var reason = !v ? 'a value cannot be empty' : v === cur ? 'unchanged' : !w ? 'enter your name above' :
        (field === 'review_by' && !/^\d{4}-(0[1-9]|1[0-2])$/.test(v)) ? 'review_by is YYYY-MM' : '';
      arm(f.querySelector('button.copy'), f.querySelector('.why'), !reason, reason);
    });
    document.querySelectorAll('.fld.accept').forEach(function (f) {
      var v = one(f.querySelector('input').value), id = f.getAttribute('data-skill');
      f.querySelector('pre.cmd').textContent = 'tooling/skills.sh accept ' + id + ' --review-by ' + shq(v || 'YYYY-MM') + ' --by ' + shq(w || '<your name>') + CATARG;
      var reason = !/^\d{4}-(0[1-9]|1[0-2])$/.test(v) ? 'needs a review date, YYYY-MM' : !w ? 'enter your name above' : '';
      arm(f.querySelector('button.copy'), f.querySelector('.why'), !reason, reason);
    });
    var g = function (i) { return one(document.getElementById(i).value); };
    var p = { id: g('p-id'), owner: g('p-owner'), covers: g('p-covers'), applies: g('p-applies'), because: g('p-because') };
    document.getElementById('p-cmd').textContent = 'tooling/skills.sh propose ' + (p.id || '<id>') +
      ' --owner ' + shq(p.owner || '<owner>') + ' --covers ' + shq(p.covers || '<covers>') +
      ' --applies-to ' + shq(p.applies || '<applies_to>') + ' --because ' + shq(p.because || '<because>') +
      ' --by ' + shq(w || '<your name>') + CATARG;
    var pr = !(p.id && p.owner && p.covers && p.applies && p.because) ? 'fill every field' :
      !/^[a-z0-9][a-z0-9-]*$/.test(p.id) ? 'an id is lowercase letters, digits and hyphens' : !w ? 'enter your name above' : '';
    arm(document.getElementById('p-copy'), document.getElementById('p-why'), !pr, pr);
  }
  function copy(text, btn) {
    function done() { var t = btn.textContent; btn.textContent = 'Copied'; setTimeout(function () { btn.textContent = t; }, 1500); }
    function fallback() {
      var ta = document.createElement('textarea'); ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta); ta.select();
      try { document.execCommand('copy') ? done() : (btn.textContent = 'Select and copy'); } catch (e) { btn.textContent = 'Select and copy'; }
      document.body.removeChild(ta);
    }
    if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(done, fallback); else fallback();
  }
  document.addEventListener('input', refresh);
  document.addEventListener('click', function (e) {
    var b = e.target.closest('button'); if (!b) return;
    if (b.classList.contains('copy')) copy(b.parentNode.querySelector('pre.cmd').textContent, b);
    if (b.classList.contains('prefill')) {
      document.getElementById('p-id').value = b.getAttribute('data-id');
      document.getElementById('p-owner').value = b.getAttribute('data-owner');
      document.getElementById('p-because').value = b.getAttribute('data-because');
      document.getElementById('propose').open = true; document.getElementById('p-covers').focus(); refresh();
    }
  });
  refresh();
})();
</script>
</body>
</html>
SCRIPT
  } > "$WORK/page.html" || { echo "REFUSED: could not render the page." >&2; exit 75; }
  # The renderer exits 1 only from `show`; any failure here is one the page would hide.
  grep -q '</html>' "$WORK/page.html" || { echo "REFUSED: the page did not render to the end." >&2; exit 75; }
  cat "$WORK/page.html" > "$out" || { echo "REFUSED: could not write $out." >&2; exit 75; }
  echo "$out"
}

case "$CMD" in
  list|show|review)
    flat "$CATALOG" > "$WORK/cat.tsv" || { echo "REFUSED: could not read $CATALOG." >&2; exit 75; }
    designs_flat
    case "$CMD" in
      list)   render list ;;
      show)   [ -n "$P1" ] || { echo "usage: skills.sh show <id> [--designs <dir>]" >&2; exit 64; }
              render show -v WANT="$P1" ;;
      review) review_cmd ;;
    esac ;;
  check)   check_cmd ;;
  set)     set_cmd ;;
  propose) propose_cmd ;;
  accept)  accept_cmd ;;
  -h|--help|help) sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown command: $CMD" >&2; usage ;;
esac
