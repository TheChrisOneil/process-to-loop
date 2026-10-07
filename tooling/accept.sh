#!/usr/bin/env bash
# THE ACCEPTANCE GATE — a design is not built until a named person accepts it.
#
# Acceptance is of CONTENT, never of a filename. The register records the SHA-256 of the
# design as it stood when somebody accepted it. Change one character afterwards and the
# acceptance no longer covers what you are about to build — which is the whole control.
#
#   ./accept.sh <design> --by "Name, Role"     accept, after typing the phrase
#   ./accept.sh --status <design>              is this exact design accepted?
#   ./accept.sh --revoke <design> --by "Name" --reason "..."
#   ./accept.sh --note "..." --by "Name"       append a correcting entry
#   ./accept.sh --list                         the register
#   ./accept.sh --verify                       recompute the hash chain
#
# The register is append-only and chained: every row carries a hash of the row before it, so
# an edited row breaks the chain and --verify says which one.
# Students reach this through:  make accept DESIGN=<design> BY="Name, Role"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"          # the tooling
ROOT="$(cd "$HERE/.." && pwd)"                 # the workshop: jobs, loops, memory, examples
# The register location is configuration, not a control — tests point it at a scratch file.
REG="${ACCEPT_REGISTER:-$ROOT/memory/acceptances.tsv}"
PHRASE_REQUIRED="i accept"
GENESIS="0000000000000000000000000000000000000000000000000000000000000000"

# -s, not -f: an existing but EMPTY register would otherwise never get its header, and
# every lookup skips row 1 (NR>1) — an acceptance would record and then read back as absent.
init() { mkdir -p "$(dirname "$REG")"; [ -s "$REG" ] || printf 'seq\ttimestamp\taction\tdesign\tdesign_sha\tby\tdetail\tchain\n' > "$REG"; }
sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# The design names who may approve it. A signature from anyone else is not an
# acceptance — it is a different person's opinion recorded in the same column.
declared_approver() {
  awk '/^@meta/,/^@assumptions/' "$1" 2>/dev/null \
    | awk -F': *' '/^approver:/{sub(/^approver: */,""); print; exit}'
}
signer_matches() { # design by
  local want; want=$(declared_approver "$1")
  [ -n "$want" ] || return 1
  # a surname or role fragment is enough; the design is the authority on the name
  case "$(printf '%s' "$2" | tr "[:upper:]" "[:lower:]")" in
    *"$(printf '%s' "${want%%,*}" | tr "[:upper:]" "[:lower:]")"*) return 0 ;;
  esac
  case "$(printf '%s' "$want" | tr "[:upper:]" "[:lower:]")" in
    *"$(printf '%s' "${2%%,*}" | tr "[:upper:]" "[:lower:]")"*) return 0 ;;
  esac
  return 1
}
# Record the design path relative to the workshop, never absolute: an acceptance must survive
# the tree being moved. Matching stays per project, which is the point of keying on the path.
relpath() { case "$1" in "$ROOT/"*) printf '%s' "${1#"$ROOT/"}" ;; *) printf '%s' "$1" ;; esac; }
last_chain() { awk -F'\t' 'NR>1{c=$8} END{print (c==""?"'"$GENESIS"'":c)}' "$REG"; }
next_seq()  { awk -F'\t' 'NR>1{n=$1} END{print n+1}' "$REG"; }

append() { # action design sha by detail
  init
  local seq ts prev chain
  seq=$(next_seq); ts=$(date +%FT%T); prev=$(last_chain)
  chain=$(printf '%s|%s|%s|%s|%s|%s|%s|%s' "$prev" "$seq" "$ts" "$1" "$2" "$3" "$4" "$5" | shasum -a 256 | awk '{print $1}')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$seq" "$ts" "$1" "$2" "$3" "$4" "$5" "$chain" >> "$REG"
}

# Latest action recorded against this content AT THIS DESIGN PATH. Keying on content alone
# would let one project's approval silently cover another project's identical design —
# accountability is per project, not per byte-string.
state_of_sha() { awk -F'\t' -v s="$1" -v d="$2" 'NR>1 && $5==s && $4==d {a=$3; by=$6; ts=$2} END{print a"\t"by"\t"ts}' "$REG"; }
# has this path ever been accepted, under any hash?
ever_accepted_path() { awk -F'\t' -v d="$(relpath "$1")" 'NR>1 && $4==d && $3=="accept" {ts=$2; by=$6; sha=$5} END{print ts"\t"by"\t"sha}' "$REG"; }

status() { # design -> prints, returns 0 only when ACCEPTED
  local f="$1" sha st action by ts ever
  sha=$(sha_of "$f")
  IFS=$'\t' read -r action by ts <<<"$(state_of_sha "$sha" "$(relpath "$f")")"
  case "$action" in
    accept) echo "ACCEPTED — $f"
            echo "  accepted by $by at $ts"
            echo "  content    ${sha:0:16}"
            return 0 ;;
    revoke) echo "REVOKED — $f"
            echo "  revoked by $by at $ts"
            return 1 ;;
  esac
  IFS=$'\t' read -r ets eby esha <<<"$(ever_accepted_path "$f")"
  if [ -n "$ets" ]; then
    echo "CHANGED SINCE ACCEPTANCE — $f"
    echo "  $eby accepted a different version at $ets"
    echo "  accepted content ${esha:0:16}"
    echo "  current content  ${sha:0:16}"
    echo "  An acceptance covers the design that was read, never the one that replaced it."
    return 1
  fi
  echo "NOT ACCEPTED — $f"
  echo "  content ${sha:0:16} has never been accepted by anyone"
  return 1
}

# ------------------------------------------------------------------ commands
case "${1:-}" in
  --list)
    init; column -t -s$'\t' "$REG" 2>/dev/null || cat "$REG"; exit 0 ;;
  --verify)
    init
    awk -F'\t' -v g="$GENESIS" '
      NR==1 { next }
      { row = prev "|" $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7
        cmd = "printf %s \"" row "\" | shasum -a 256 | awk \x27{print $1}\x27"
        cmd | getline want; close(cmd)
        if (want != $8) { print "CHAIN BROKEN at row " $1 " (" $2 " " $3 ")"; bad=1 }
        prev = $8 }
      BEGIN { prev = g }
      END { if (bad) exit 1; print "chain intact — " (NR-1) " row(s)" }' "$REG"
    exit $? ;;
  --note)
    # A ledger is corrected by appending, never by editing. A row that turns out to be wrong,
    # or to refer to something since deleted, is explained by a later row — that is the whole
    # difference between a log and an audit trail.
    TEXT="${2:?usage: accept.sh --note \"text\" --by \"Name\"}"; shift 2
    BY=""
    while [ $# -gt 0 ]; do case "$1" in --by) BY="$2"; shift 2;; *) shift;; esac; done
    [ -n "$BY" ] || { echo "a note needs a named person: --by \"Name, Role\"" >&2; exit 64; }
    init; append note "-" "-" "$BY" "$TEXT"
    echo "noted by $BY, row $(awk -F'\t' 'END{print $1}' "$REG"). Nothing was edited."
    exit 0 ;;
  --status)
    F="${2:?usage: accept.sh --status <design>}"; init; status "$F"; exit $? ;;
  --revoke)
    F="${2:?usage: accept.sh --revoke <design> --by \"Name\" --reason \"...\"}"; shift 2
    BY=""; REASON=""
    while [ $# -gt 0 ]; do case "$1" in --by) BY="$2"; shift 2;; --reason) REASON="$2"; shift 2;; *) shift;; esac; done
    [ -n "$BY" ] || { echo "a revocation needs a named person: --by \"Name, Role\"" >&2; exit 64; }
    [ -n "$REASON" ] || { echo "a revocation needs a reason: --reason \"...\"" >&2; exit 64; }
    init; append revoke "$(relpath "$F")" "$(sha_of "$F")" "$BY" "$REASON"
    echo "revoked by $BY. The register keeps the acceptance and the revocation, in order."
    exit 0 ;;
esac

F="${1:?usage: accept.sh <design> --by \"Name, Role\"}"; shift
BY=""
while [ $# -gt 0 ]; do case "$1" in --by) BY="${2:-}"; shift 2;; *) shift;; esac; done
[ -f "$F" ] || { echo "no such design file: $F" >&2; exit 2; }
[ -n "$BY" ] || { echo "REFUSED: acceptance needs a named person — --by \"Name, Role\"" >&2
                  echo "         \"the team\" is not a person and cannot be held to a decision." >&2; exit 64; }
# Exact collective terms only. A role may legitimately contain "team" — "Refunds Team Lead"
# is a person; "the team" is not.
BYNORM=$(printf '%s' "$BY" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
case "$BYNORM" in
  "the team"|team|"our team"|us|we|"the group"|group|everyone|anyone|somebody|\
  "the system"|system|"the agent"|agent|ai|claude|n/a|na|tbd|unknown|"")
    echo "REFUSED: \"$BY\" is not a named person." >&2
    echo "         An acceptance nobody signed is not an acceptance. Use --by \"Name, Role\"." >&2
    exit 64 ;;
esac

# The design names who may approve it. A signature from anyone else is not an
# acceptance — it is a different person's opinion recorded in the same column.
if ! signer_matches "$F" "$BY"; then
  WANT=$(declared_approver "$F")
  echo "REFUSED: this design names \"${WANT:-nobody}\" as its approver; \"$BY\" is somebody else." >&2
  echo "         Next human action: have the named approver sign it, or change the approver" >&2
  echo "         in the design and have THAT change accepted first." >&2
  exit 1
fi

if ! "$HERE/validate.sh" "$F" >/dev/null 2>&1; then
  echo "REFUSED: this design does not pass the validator, so it cannot be accepted." >&2
  echo "         Run:  make check DESIGN=$F" >&2
  exit 1
fi

init
SHA=$(sha_of "$F")
if [ "$(state_of_sha "$SHA" "$(relpath "$F")" | cut -f1)" = "accept" ]; then status "$F"; exit 0; fi

echo
echo "You are accepting this design, exactly as it stands now:"
echo
sed -n '/^@meta/,/^@assumptions/p' "$F" | sed '/^@/d;/^$/d;s/^/    /'
echo "    content ${SHA:0:16}"
echo
echo "Accepting means: this is the design that will be built, and your name is on it."
echo "Type the phrase to accept, or anything else to stop."
echo
read -r -p "  Type \"I accept\": " TYPED
NORM=$(printf '%s' "$TYPED" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[.!]$//')
if [ "$NORM" != "$PHRASE_REQUIRED" ]; then
  echo
  echo "Not accepted. Nothing was recorded and nothing will be built."
  exit 1
fi

# A rehearsal does not become a signature by being signed. If any gate on this
# run was closed without a person, the register says so on the row, so no later
# reader can take the acceptance for more than it was.
DETAIL="$TYPED"
MARKS=""
DIR="$(cd "$(dirname "$F")" && pwd)"

# A gate closed without a person.
REH="$DIR/REHEARSAL"
if [ -f "$REH" ]; then
  NREH=$(grep -c . "$REH" 2>/dev/null || echo 0)
  MARKS="$NREH gate(s) closed without a person"
  echo
  echo "NOTE: $NREH gate(s) on this run were closed as a rehearsal, not by a person."
  echo "      compile will refuse to build from it unless somebody names themselves."
fi

# An interview answered on somebody's behalf. A DIFFERENT claim from the above,
# and the one that matters most to a signature: a design can pass every gate with
# a person at each one and still rest entirely on answers nobody gave.
QF="$DIR/QUESTIONS.md"
if [ -f "$QF" ] && [ -x "$HERE/questions.sh" ]; then
  QT=$("$HERE/questions.sh" tsv "$QF" 2>/dev/null)
  NSYN=$(printf '%s\n' "$QT" | awk -F'\t' '$7=="synthetic"{n++} END{print n+0}')
  NQ=$(printf '%s\n' "$QT" | grep -c . || true)
  if [ "$NSYN" -gt 0 ]; then
    [ -z "$MARKS" ] || MARKS="$MARKS; "
    MARKS="$MARKS$NSYN of $NQ interview answer(s) supplied on the approver's behalf"
    echo
    echo "NOTE: $NSYN of $NQ answers in this design's interview are SYNTHETIC — supplied"
    echo "      on behalf of the approver rather than by them. The register will say so"
    echo "      on this row, permanently, so no later reader takes this signature for"
    echo "      more than it was."
  fi
fi
[ -z "$MARKS" ] || DETAIL="$TYPED [REHEARSAL: $MARKS]"
append accept "$(relpath "$F")" "$SHA" "$BY" "$DETAIL"
echo
echo "Accepted by $BY."
echo "Recorded in memory/acceptances.tsv, row $(awk -F'\t' 'END{print $1}' "$REG"), chained."
echo "Change one character of the design and this acceptance stops covering it."
