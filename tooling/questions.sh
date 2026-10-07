#!/usr/bin/env bash
# QUESTIONS.md — the interview as an artifact.
#
#   questions.sh validate  <QUESTIONS.md> [--catalog <file>]   is it well formed?
#   questions.sh answered  <QUESTIONS.md>                      has every block an answer?
#   questions.sh status    <QUESTIONS.md>                      the counts, and the ratio
#   questions.sh open      <QUESTIONS.md>                      what is still unanswered
#   questions.sh ask       <QUESTIONS.md> [Qn]                 put the next question to a person
#   questions.sh tsv       <QUESTIONS.md>                      one row per question
#   questions.sh brief     <QUESTIONS.md>                      the same, as a markdown table
#   questions.sh answer    <QUESTIONS.md> <Qn> <type> --by <who> [--value <v>] [--synthetic]
#   questions.sh merge     <QUESTIONS.md> <proposed.md>   fold a revision in, keeping answers
#
# The conversation is the interface; this file is the record. An answer is
# written by `answer`, never by hand: a hand-edited artifact is the control that
# is declared, reported and absent, which is the failure this system exists to
# catch. The subcommand also means the format can be changed in one place.
#
# Exit 0  passed
# Exit 1  refused — a question of form or completeness
# Exit 64 wrong arguments
# Exit 75 could not run — the file or the catalog is not there
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
AWKLIB="$HERE/lib/questions.awk"

CMD=${1:-}; shift || true
F=${1:-}; shift || true
[ -n "$CMD" ] && [ -n "$F" ] || { sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }
[ -f "$AWKLIB" ] || { echo "REFUSED: the questions parser is not at $AWKLIB." >&2; exit 75; }

CATALOG=${CATALOG:-$HERE/../catalog/eb-tools.catalog}
while [ $# -gt 0 ]; do
  case "$1" in
    --catalog) CATALOG=${2:-}; shift 2 ;;
    *) break ;;
  esac
done

# `answer` writes; everything else reads. Writing is handled first so a missing
# file is reported before the reader tries to parse it.
if [ "$CMD" = "answer" ]; then
  QID=${1:-}; TYPE=$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]'); shift 2 2>/dev/null || true
  BY=""; VALUE=""; PROV="real"; DATE=$(date +%F)
  while [ $# -gt 0 ]; do
    case "$1" in
      --by)        BY=${2:-}; shift 2 ;;
      --value)     VALUE=${2:-}; shift 2 ;;
      --date)      DATE=${2:-}; shift 2 ;;
      --synthetic) PROV="synthetic"; shift ;;
      *) echo "REFUSED: unknown option $1" >&2; exit 64 ;;
    esac
  done
  [ -f "$F" ] || { echo "REFUSED: no questions file at $F." >&2; exit 75; }
  [ -n "$QID" ] || { echo "REFUSED: name the question, e.g. Q3." >&2; exit 64; }
  case "$TYPE" in
    stated|unanswered|delegated) : ;;
    *) echo "REFUSED: the answer type is stated, unanswered or delegated — not \"$TYPE\"." >&2
       echo "         \"I don't know\" is unanswered and names who owes it." >&2
       echo "         \"you pick it\" is delegated and carries the value chosen." >&2; exit 64 ;;
  esac
  [ -n "$BY" ] || { echo "REFUSED: --by is required. An answer with no author has no provenance." >&2; exit 64; }
  case "$BY$VALUE" in *"|"*) echo "REFUSED: a pipe separates the fields, so it cannot appear inside one." >&2; exit 64 ;; esac
  case "$VALUE" in *$'\n'*) echo "REFUSED: an answer is one line." >&2; exit 64 ;; esac
  if [ "$TYPE" = "stated" ] && [ -z "$VALUE" ]; then
    echo "REFUSED: a stated answer with no value is an unanswered question wearing the wrong label." >&2; exit 64
  fi
  if [ "$TYPE" = "delegated" ]; then
    [ -n "$VALUE" ] || { echo "REFUSED: a delegated answer carries the value you chose on their behalf." >&2; exit 64; }
    case "$VALUE" in assumed:*) : ;; *) VALUE="assumed: $VALUE" ;; esac
  fi
  [ "$TYPE" != "unanswered" ] || VALUE=""

  # Does the question exist, and is it already answered?
  # Same rule as everywhere else here: once awk is given -f, every program comes
  # through -f. An inline one would be read as a data file and the question would
  # look absent.
  QP=$(mktemp)
  cat > "$QP" <<'QAWK'
END { for (qx=1; qx<=nq; qx++) if (QID[qx]==want) { print (Q[want ".answer_type"]=="" ? "open" : Q[want ".answer_type"]); exit } }
QAWK
  EXIST=$(awk -v want="$QID" -f "$AWKLIB" -f "$QP" "$F")
  [ -n "$EXIST" ] || { echo "REFUSED: $F has no $QID." >&2; exit 1; }
  [ "$EXIST" = "open" ] || echo "note: $QID was $EXIST; replacing it." >&2

  TMP=$(mktemp)
  LINE="answer: $TYPE | $BY | $DATE | $VALUE | $PROV"
  awk -v want="$QID" -v line="$LINE" '
    /^##[ \t]+Q[0-9]+/ { split($0, HF, /[ \t]+/); cur = HF[2]; wrote = 0 }
    /^answer:/ && cur == want { print line; wrote = 1; next }
    { print }
  ' "$F" > "$TMP" || { rm -f "$TMP"; echo "REFUSED: could not rewrite $F." >&2; exit 1; }
  # Prove it landed rather than trusting the rewrite: a silent no-op here would
  # leave a question looking answered to the person and open to the gate.
  cat > "$QP" <<'QAWK'
END { print Q[want ".answer_type"] }
QAWK
  GOT=$(awk -v want="$QID" -f "$AWKLIB" -f "$QP" "$TMP")
  rm -f "$QP"
  [ "$GOT" = "$TYPE" ] || { rm -f "$TMP"; echo "REFUSED: $QID has no answer: line to write to." >&2; exit 1; }
  cat "$TMP" > "$F" && rm -f "$TMP"
  echo "$QID answered $TYPE${VALUE:+ — $VALUE}${PROV:+ ($PROV)}"
  exit 0
fi

# `merge` folds a fresh proposal into an existing, answered set.
#
# A revision must not restart the conversation. On 2026-10-06 one did: the
# questions step wrote sixteen new open questions over fifteen answered ones and
# the only record of what the owner was asked, and said, was gone.
#
# Two properties decide the whole implementation:
#
#   ANSWERS SURVIVE.  A question already answered keeps its answer. A question
#                     the proposal drops is KEPT anyway — an answer that vanishes
#                     because a model rephrased something is the same loss in
#                     slower motion.
#   IDS ARE STABLE.   An existing question keeps its id forever, because
#                     assumptions and findings cite [Qn] and V33 checks they all
#                     still resolve. New questions continue from the highest id.
if [ "$CMD" = "merge" ]; then
  NEWF=${1:-}
  [ -n "$NEWF" ] && [ -f "$NEWF" ] || { echo "REFUSED: questions.sh merge <QUESTIONS.md> <proposed.md>" >&2; exit 64; }
  if [ ! -f "$F" ]; then
    cat "$NEWF" > "$F" && echo "no existing question set; the proposal is now $F"
    exit 0
  fi
  command -v python3 >/dev/null || { echo "REFUSED: no python3 to merge." >&2; exit 75; }
  TMP=$(mktemp)
  OLD_TSV=$(mktemp); NEW_TSV=$(mktemp)
  "$0" tsv "$F"    > "$OLD_TSV" 2>/dev/null
  "$0" tsv "$NEWF" > "$NEW_TSV" 2>/dev/null
  python3 - "$F" "$NEWF" "$OLD_TSV" "$NEW_TSV" "$TMP" <<'PYMERGE'
import sys, re, pathlib
oldp, newp, oldtsv, newtsv, out = sys.argv[1:6]

def norm(s):
    return re.sub(r'[^a-z0-9]+', ' ', (s or '').lower()).strip()

def blocks(path):
    """(header, [(id, text)]) — split on the question headings the parser uses."""
    txt = pathlib.Path(path).read_text()
    parts = re.split(r'(?m)^(##[ \t]+Q[0-9]+.*)$', txt)
    header, out_b = parts[0], []
    for i in range(1, len(parts), 2):
        head, body = parts[i], parts[i+1] if i+1 < len(parts) else ""
        qid = re.match(r'##[ \t]+(Q[0-9]+)', head).group(1)
        out_b.append((qid, head + body))
    return header, out_b

def asks(tsv):
    d = {}
    for line in pathlib.Path(tsv).read_text().splitlines():
        if not line.strip(): continue
        f = (line.split("\t") + [""] * 8)[:8]
        d[f[0]] = f[7]
    return d

old_header, old_blocks = blocks(oldp)
new_header, new_blocks = blocks(newp)
old_asks, new_asks = asks(oldtsv), asks(newtsv)

# An existing question is matched by TEXT, never by position: the proposal may
# reorder freely and must not thereby re-point an id at a different question.
seen = {norm(old_asks.get(qid, "")) for qid, _ in old_blocks}
maxid = max((int(qid[1:]) for qid, _ in old_blocks), default=0)

kept = [b for _, b in old_blocks]
added, nxt = [], maxid
for qid, body in new_blocks:
    if norm(new_asks.get(qid, "")) in seen:
        continue
    nxt += 1
    body = re.sub(r'(?m)^##[ \t]+Q[0-9]+', '## Q%d' % nxt, body, count=1)
    added.append(body)

# The header comes from the EXISTING set: it carries the use-case digest these
# answers were given against, and a proposal written later must not silently
# re-point them at a different description.
pathlib.Path(out).write_text(old_header + "".join(kept) + "".join(added))
print("kept %d answered question(s); added %d new" % (len(kept), len(added)), file=sys.stderr)
PYMERGE
  RC=$?
  rm -f "$OLD_TSV" "$NEW_TSV"
  [ "$RC" -eq 0 ] || { rm -f "$TMP"; echo "REFUSED: the merge failed; $F is unchanged." >&2; exit 1; }
  # Prove it before replacing: a merge that dropped an answer is the defect this
  # whole subcommand exists to prevent.
  BEFORE=$("$0" tsv "$F"   | awk -F'\t' '$3!=""' | wc -l | tr -d ' ')
  AFTER=$( "$0" tsv "$TMP" | awk -F'\t' '$3!=""' | wc -l | tr -d ' ')
  if [ "$AFTER" -lt "$BEFORE" ]; then
    rm -f "$TMP"
    echo "REFUSED: the merge would drop $((BEFORE-AFTER)) answer(s). $F is unchanged." >&2
    exit 1
  fi
  cat "$TMP" > "$F" && rm -f "$TMP"
  echo "merged into $F"
  "$0" status "$F"
  exit 0
fi

[ -f "$F" ] || { echo "REFUSED: no questions file at $F." >&2; exit 75; }

# The catalog, flattened, so the form rules can tell a real tool from a plausible
# one without a second parser. Same shape validate.sh already uses.
CATFILE=""
if [ -f "$CATALOG" ]; then
  CATFILE=$(mktemp)
  cat > "$CATFILE.q" <<'CATQ'
END{ for(ci=1;ci<=t;ci++) print TID[ci] }
CATQ
  awk -f "$HERE/lib/catalog.awk" -f "$CATFILE.q" "$CATALOG" > "$CATFILE" 2>/dev/null
  rm -f "$CATFILE.q"
fi
trap '[ -n "$CATFILE" ] && rm -f "$CATFILE"' EXIT

case "$CMD" in

tsv|open|status|brief|ask)
  # A short query program, appended to the parser. Once awk is given -f it takes
  # EVERY program that way, so these go to a file: a program passed inline after
  # -f is read as a data file, and the first symptom is a parse error quoting
  # your own program back at you.
  QP=$(mktemp)
  case "$CMD" in
  ask) cat > "$QP" <<'QAWK'
# One question, laid out to be read ALOUD. The interview is a conversation and
# the file is the record; this is the half that makes the conversation possible
# without a person learning the file format first.
END {
  pick = ""
  for (qx=1; qx<=nq; qx++) { qd=QID[qx]
    if (want != "") { if (qd==want) { pick=qd; break } ; continue }
    # Structural first: a parametric answer given before the unit is settled may
    # be an answer about the wrong thing.
    if (Q[qd ".answer_type"]=="" && Q[qd ".class"]=="structural") { pick=qd; break }
  }
  if (pick=="" && want=="")
    for (qx=1; qx<=nq; qx++) { qd=QID[qx]
      if (Q[qd ".answer_type"]=="") { pick=qd; break } }
  if (pick=="") { print "Every question has an answer. Nothing left to ask."; exit 0 }

  left=0
  for (qx=1; qx<=nq; qx++) if (Q[QID[qx] ".answer_type"]=="") left++

  printf "%s  (%s)   %d of %d still open\n\n", pick, Q[pick ".class"], left, nq
  print Q[pick ".asks"]
  printf "\n  why it matters: %s\n", Q[pick ".why"]
  if (Q[pick ".catalog"] != "") {
    if (tolower(Q[pick ".catalog"])=="none")
      print "  the catalog has nothing for this. If they need it, that is a finding, not an assumption."
    else
      printf "  your organization already has: %s\n", Q[pick ".catalog"]
  }
  if (Q[pick ".answer_type"] != "")
    printf "\n  ALREADY ANSWERED %s by %s on %s: %s\n", Q[pick ".answer_type"], Q[pick ".answer_by"], Q[pick ".answer_date"], Q[pick ".answer_value"]
  print "\n  Three answers are legal. Whichever they give, write it with:"
  printf "\n    questions.sh answer <file> %s stated     --by \"<who>\" --value \"<what they said>\"\n", pick
  printf "    questions.sh answer <file> %s unanswered --by \"<who owes the answer>\"\n", pick
  printf "    questions.sh answer <file> %s delegated  --by \"<who asked you to choose>\" --value \"<what you chose>\"\n", pick
  if (Q[pick ".class"]=="structural")
    print "\n  This one is structural. A delegated answer here becomes a finding they see\n  before they sign, so \"you pick it\" is safe to offer."
  else
    print "\n  This one is parametric. A delegated answer here is the end of it."
}
QAWK
    ;;
  tsv) cat > "$QP" <<'QAWK'
END { for (qx=1; qx<=nq; qx++) { qd=QID[qx]
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", qd, Q[qd ".class"],
    Q[qd ".answer_type"], Q[qd ".answer_by"], Q[qd ".answer_date"],
    Q[qd ".answer_value"], Q[qd ".answer_prov"], Q[qd ".asks"] } }
QAWK
    ;;
  open) cat > "$QP" <<'QAWK'
END { qo=0
  for (qx=1; qx<=nq; qx++) { qd=QID[qx]
    if (Q[qd ".answer_type"]=="") { qo++; printf "%s  %-10s %s\n", qd, Q[qd ".class"], Q[qd ".asks"] } }
  if (qo==0) print "every question has an answer."
  exit (qo>0 ? 1 : 0) }
QAWK
    ;;
  brief) cat > "$QP" <<'QAWK'
END {
  print "| | question | how it was answered | by |"
  print "|---|---|---|---|"
  for (qx=1; qx<=nq; qx++) { qd=QID[qx]
    qc  = Q[qd ".class"]
    qt  = Q[qd ".answer_type"]; if (qt=="") qt="OPEN"
    qby = Q[qd ".answer_by"]
    qv  = Q[qd ".answer_value"]
    qa  = Q[qd ".asks"]
    # A pipe inside a cell ends the cell. The answer writer refuses one in a
    # field, but the question text comes from a model and is not policed.
    gsub(/\|/, "\\|", qa); gsub(/\|/, "\\|", qv); gsub(/\|/, "\\|", qby)
    mark  = (qc=="structural" ? "**" qd "**" : qd)
    shown = (qt=="unanswered" ? "_nobody present knew_" : qv)
    if (Q[qd ".answer_prov"]=="synthetic") qby = qby " — **synthetic**"
    printf "| %s | %s | %s: %s | %s |\n", mark, qa, qt, shown, qby
  }
}
QAWK
    ;;
  status) cat > "$QP" <<'QAWK'
END {
  for (qx=1; qx<=nq; qx++) { qd=QID[qx]
    qt = Q[qd ".answer_type"]; if (qt=="") qt="open"
    CNT[qt]++; if (Q[qd ".answer_prov"]=="synthetic") syn++
    if (Q[qd ".class"]=="structural") { STR[qt]++; nstruct++ }
  }
  printf "%d question(s) — %d structural, %d parametric\n", nq, nstruct, nq-nstruct
  printf "  stated      %3d   (%d structural)\n", CNT["stated"]+0, STR["stated"]+0
  printf "  delegated   %3d   (%d structural — each becomes a finding)\n", CNT["delegated"]+0, STR["delegated"]+0
  printf "  unanswered  %3d   (%d structural)\n", CNT["unanswered"]+0, STR["unanswered"]+0
  if (CNT["open"]+0 > 0) printf "  OPEN        %3d   nothing proceeds until these have an answer\n", CNT["open"]
  if (syn+0 > 0) printf "\n  %d answer(s) are SYNTHETIC — supplied on behalf of the owner, not by them.\n", syn
  if (CNT["stated"]+0 < CNT["delegated"]+0)
    printf "\n  More delegated than stated. Either the interview is not working or the\n  person was not really available. Worth saying at the gate.\n"
}
QAWK
    ;;
  esac
  awk -v want="${1:-}" -f "$AWKLIB" -f "$QP" "$F"; RC=$?
  rm -f "$QP"; exit $RC
  ;;

validate|answered)
  RULES="$HERE/lib/questions-rules.awk"
  [ -f "$RULES" ] || { echo "REFUSED: the question rules are not at $RULES." >&2; exit 75; }
  awk -v mode="$CMD" -v CATFILE="$CATFILE" -f "$AWKLIB" -f "$RULES" "$F"
  ;;


*) echo "REFUSED: no subcommand \"$CMD\"." >&2; sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64 ;;
esac
