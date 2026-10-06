#!/usr/bin/env bash
# design -> a Gas City formulas v2 file plus one check script per gate.
#
#   compile.sh <design> --name <formula-name> [--out <dir>]
#
# Refuses rather than emitting something that looks finished and is not. Every
# refusal names the next human action.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOLING=$HERE

DESIGN=""; NAME=""; OUT="build"
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME=${2:-}; shift 2 ;;
    --out)  OUT=${2:-};  shift 2 ;;
    -*) echo "compile.sh <design> --name <formula-name> [--out <dir>]" >&2; exit 64 ;;
    *)  DESIGN=$1; shift ;;
  esac
done
[ -n "$DESIGN" ] && [ -n "$NAME" ] || { echo "compile.sh <design> --name <formula-name> [--out <dir>]" >&2; exit 64; }
[ -f "$DESIGN" ] || { echo "REFUSED: no design at $DESIGN." >&2; exit 1; }
case "$NAME" in
  -*|*[!a-z0-9-]*) echo "REFUSED: --name must be lower case letters, digits and dashes." >&2
                   echo "         Next human action: pass a name like invoice-reconciliation." >&2; exit 1 ;;
esac


# ---- 1. the design must pass the design rules before anything is emitted
echo "  validating the design …"
# A rehearsal is not an approval, and this is where that becomes true rather
# than merely stated. A run whose gates were closed without a person leaves a
# REHEARSAL file beside the design; nothing is emitted from it.
#
# Remove this and rehearse-gate.sh turns the acceptance gate into a formality —
# a control that is declared, reported and absent, which is the defect this
# whole project exists to catch.
REHEARSAL="$(cd "$(dirname "$DESIGN")" && pwd)/REHEARSAL"
if [ -f "$REHEARSAL" ] && [ -z "${ALLOW_REHEARSAL:-}" ]; then
  echo "REFUSED: this run is a REHEARSAL. $(grep -c . "$REHEARSAL") gate(s) were closed without a person:" >&2
  awk -F'\t' '{printf "           %s  %s  by %s — %s\n", $1, $2, $4, $5}' "$REHEARSAL" >&2
  echo "         You may rehearse the whole pipeline. You may not build out of one." >&2
  echo "         Next human action: re-run it and have $(awk -F': *' '/^approver:/{print $2; exit}' "$DESIGN") close the gates." >&2
  exit 1
fi

if ! "$TOOLING/validate.sh" "$DESIGN" >/tmp/fc-design.$$ 2>&1; then
  sed 's/^/    /' /tmp/fc-design.$$; rm -f /tmp/fc-design.$$
  echo "REFUSED: the design does not pass its own rules, so nothing was emitted." >&2
  echo "         Next human action: fix the design, then compile again." >&2
  exit 1
fi
rm -f /tmp/fc-design.$$

CHECKDIR=".gc/scripts/checks"
mkdir -p "$OUT/formulas" "$OUT/$CHECKDIR"
FORMULA="$OUT/formulas/$NAME.toml"

# ---- 2. emit the formula
echo "  emitting $FORMULA …"
awk -f "$TOOLING/lib/parse.awk" -f "$HERE/lib/emit-formula.awk" \
    -v NAME="$NAME" -v CHECKDIR="$CHECKDIR" "$DESIGN" > "$FORMULA"

# ---- 3. emit one check script per gate
GATEROWS=$(awk -f "$TOOLING/lib/parse.awk" -f "$HERE/lib/gates.awk" "$DESIGN")
GATES=$(printf '%s' "$GATEROWS" | grep -c . || true)
# Any decision table in the design ships beside the checks, with the two awk
# files that evaluate it. A check carrying its own copy of what ">= 2000" means
# would be a second definition of the table the validator checked.
DEC=$(awk -f "$TOOLING/lib/parse.awk" -f "$TOOLING/lib/dt-cell.awk" \
          -f "$TOOLING/lib/decisions.awk" -f "$TOOLING/lib/emit-decision.awk" "$DESIGN" 2>/dev/null)
if [ -n "${DEC:-}" ]; then
  mkdir -p "$OUT/$(dirname "$CHECKDIR")/decisions" "$OUT/$(dirname "$CHECKDIR")/lib"
  printf '%s' "$DEC" | awk -v D="$OUT/$(dirname "$CHECKDIR")/decisions" -F'\t' '
    /^#table/ { f = D "/" $2 ".tsv"; printf "" > f }
    f != "" { print > f }'
  cp "$TOOLING/lib/dt-cell.awk" "$TOOLING/lib/decide.awk" "$OUT/$(dirname "$CHECKDIR")/lib/"
  echo "  decision table(s): $(ls "$OUT/$(dirname "$CHECKDIR")/decisions" | tr '\n' ' ')"
fi

while IFS=$'\t' read -r n cond ref; do
  [ -n "${n:-}" ] || continue
  NN=$(printf '%02d' "$n")
  # A gate naming a table compiles to a working check. One naming prose compiles
  # to a stub that refuses and says it is a stub. That difference is the point.
  DTAB=""; DOUT=""; DWANT=""
  case "$cond" in
    *" yields "*)
      DTAB=${cond%% *}
      REST=${cond#* yields }
      DOUT=${REST%% *}
      DWANT=${REST#* } ;;
  esac
  awk -f "$HERE/lib/emit-check.awk" -v NAME="$NAME" -v N="$NN" \
      -v COND="$cond" -v REFUSAL="$ref" \
      -v TABLE="$DTAB" -v OUT="$DOUT" -v WANT="$DWANT" \
      /dev/null > "$OUT/$CHECKDIR/$NAME-g$NN.sh"
  chmod +x "$OUT/$CHECKDIR/$NAME-g$NN.sh"
  awk -f "$HERE/lib/fixtures.awk" -v N="$NN" \
      -v COND="$cond" -v REFUSAL="$ref" /dev/null > "$OUT/$CHECKDIR/$NAME-g$NN.fixtures.tsv"
done <<< "$GATEROWS"

# ---- 4. the build guard: every gate reached the formula AND has a script
WROTE=$(grep -c '^\[steps.check\]' "$FORMULA" || true)
SCRIPTS=$(ls "$OUT/$CHECKDIR/$NAME-g"*.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "$WROTE" != "$GATES" ] || [ "$SCRIPTS" != "$GATES" ]; then
  rm -rf "$OUT/formulas/$NAME.toml" "$OUT/$CHECKDIR/$NAME-g"*.sh
  echo "REFUSED: the design has $GATES gate(s); $WROTE reached the formula and $SCRIPTS scripts were written." >&2
  echo "         Nothing was left behind. Next human action: report this — the compiler dropped a control." >&2
  exit 1
fi

# ---- 5. the compiler's own rules
"$HERE/validate-formula.sh" "$FORMULA" --checkroot "$OUT" || {
  echo "REFUSED: the emitted formula does not pass the compiler's rules." >&2
  echo "         Next human action: this is a compiler defect, not a design defect. Report it." >&2
  exit 1
}

echo
echo "  $FORMULA"
echo "  $OUT/$CHECKDIR/    $GATES check script(s), each refusing until implemented"
echo "                        $GATES fixture table(s) — the cases each check must satisfy"
echo
echo "  Next:  make conformance OUT=$OUT NAME=$NAME     # ask gc whether it compiles"
echo "         make selftest NAME=$NAME                    # run the checks against their fixtures"
echo
echo "  Each fixture table has boundary rows marked declare. Decide them — an"
echo "  undecided boundary is the off-by-one you find with the first real unit."
