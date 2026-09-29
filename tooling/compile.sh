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
while IFS=$'\t' read -r n cond ref; do
  [ -n "${n:-}" ] || continue
  NN=$(printf '%02d' "$n")
  awk -f "$HERE/lib/emit-check.awk" -v NAME="$NAME" -v N="$NN" \
      -v COND="$cond" -v REFUSAL="$ref" /dev/null > "$OUT/$CHECKDIR/$NAME-g$NN.sh"
  chmod +x "$OUT/$CHECKDIR/$NAME-g$NN.sh"
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
echo
echo "  Next:  make conformance OUT=$OUT NAME=$NAME     # ask gc whether it compiles"
echo "         then implement each check script, because a gate that cannot run is not a gate"
