#!/usr/bin/env bash
# Compile every example design end to end, and prove the refusals refuse.
# Exits non-zero on the first failure. This is the compiler's make ready.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HERE_EX="$HERE"
OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
PASS=0; FAIL=0
G="\033[32m"; R="\033[31m"; Z="\033[0m"
ok()  { PASS=$((PASS+1)); printf "  ${G}PASS${Z}  %s\n" "$1"; }
no()  { FAIL=$((FAIL+1)); printf "  ${R}FAIL${Z}  %s\n" "$1"; [ -n "${2:-}" ] && printf "        %s\n" "$2"; }

echo "COMPILING EVERY EXAMPLE"
for d in "$HERE"/examples/*.design; do
  n=$(basename "$d" .design)
  [ "$n" = "broken" ] && continue
  if out=$("$HERE/tooling/compile.sh" "$d" --name "fc-$n" --out "$OUT" 2>&1); then
    gates=$(grep -c '^\[steps.check\]' "$OUT/formulas/fc-$n.toml")
    want=$(awk -f "$HERE/tooling/lib/parse.awk" -f "$HERE/tooling/lib/gates.awk" "$d" | grep -c .)
    if [ "$gates" = "$want" ]; then ok "$n: $want gate(s) designed, $gates in the formula"
    else no "$n: $want gate(s) designed, only $gates reached the formula"; fi
  else
    no "$n did not compile" "$(echo "$out" | tail -2 | head -1)"
  fi
done

echo
echo "THE REFUSALS"
if "$HERE/tooling/compile.sh" "$HERE/examples/broken.design" --name fc-broken --out "$OUT" >/dev/null 2>&1
then no "a design that fails its own rules was compiled anyway"
else ok "a design that fails its own rules is refused before anything is emitted"; fi

if "$HERE/tooling/compile.sh" "$HERE/examples/invoices.design" --name "Bad Name" --out "$OUT" >/dev/null 2>&1
then no "a name that is not a slug was accepted"
else ok "a name that is not a slug is refused"; fi

if "$HERE/tooling/compile.sh" /nowhere/nothing.design --name fc-x --out "$OUT" >/dev/null 2>&1
then no "a missing design was accepted"
else ok "a missing design is refused"; fi

# F5: delete a check script and the formula must stop validating
cp "$OUT/formulas/fc-invoices.toml" "$OUT/f5.toml" 2>/dev/null
rm -f "$OUT/.gc/scripts/checks/fc-invoices-g01.sh"
if "$HERE/tooling/validate-formula.sh" "$OUT/f5.toml" --checkroot "$OUT" >/dev/null 2>&1
then no "a formula naming a check script that does not exist still validated"
else ok "a check script that does not exist fails F5 — the dropped-gate class of bug"; fi

echo
echo "CONFORMANCE"
if command -v gc >/dev/null; then
  if "$HERE/tooling/conformance.sh" "$OUT" fc-invoices >/dev/null 2>&1
  then ok "gc compiles the emitted formula"
  else no "gc refused the emitted formula"; fi
else
  printf "  SKIP  gc is not installed\n"
fi

echo
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
