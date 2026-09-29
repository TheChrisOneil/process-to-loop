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
echo "THE AUDIT WORKFLOW"
if "$HERE/tooling/validate-formula.sh" "$HERE/formulas/check-authoring.toml" --checkroot "$HERE" >/dev/null 2>&1
then ok "check-authoring passes the formula rules"
else no "check-authoring fails the formula rules"; fi

T=$(mktemp -d)
printf '{"author_model":"m1","audit_model":"m1","verdict":"sound","checked":["polarity","boundary","source-of-truth","exit-75","refusal-text"]}' > "$T/v.json"
if AUDIT_VERDICT="$T/v.json" "$HERE/checks/audit-verdict.sh" >/dev/null 2>&1
then no "an audit graded by the authoring model was accepted"
else ok "an audit by the same model is refused — correlated blind spots"; fi
printf '{"author_model":"m1","audit_model":"m2","verdict":"defective","defects":[],"checked":["polarity","boundary","source-of-truth","exit-75","refusal-text"]}' > "$T/v.json"
if AUDIT_VERDICT="$T/v.json" "$HERE/checks/audit-verdict.sh" >/dev/null 2>&1
then no "a defective verdict naming no defect was accepted"
else ok "a defective verdict that names no defect is refused"; fi
printf '{"author_model":"m1","audit_model":"m2","verdict":"sound","checked":["polarity"]}' > "$T/v.json"
if AUDIT_VERDICT="$T/v.json" "$HERE/checks/audit-verdict.sh" >/dev/null 2>&1
then no "an audit that skipped four of five dimensions was accepted"
else ok "an audit that skipped a required dimension is refused"; fi
AUDIT_VERDICT="$T/gone.json" "$HERE/checks/audit-verdict.sh" >/dev/null 2>&1
[ $? -eq 75 ] && ok "a missing verdict exits 75 — could not run, not a business failure" \
              || no "a missing verdict did not exit 75"
rm -rf "$T"

echo
echo "THE FIXTURES"
FX=$(awk -f "$HERE/tooling/lib/parse.awk" -f "$HERE/tooling/lib/gates.awk" "$HERE/examples/invoices.design" | head -1)
COND=$(printf '%s' "$FX" | cut -f2); REF=$(printf '%s' "$FX" | cut -f3)
TF=$(mktemp)
awk -f "$HERE/tooling/lib/fixtures.awk" -v N=01 -v COND="$COND" -v REFUSAL="$REF" /dev/null > "$TF"
if grep -q "^above	2001	refuse" "$TF"
then ok "over the threshold refuses — the condition describes what refuses"
else no "fixture polarity is wrong for a threshold condition"; fi
if grep -q "^at	2000	declare" "$TF"
then ok "the threshold itself is left for a person to decide"
else no "the boundary case was decided by the generator"; fi
if "$HERE/tooling/selftest.sh" "$HERE/tooling/selftest.sh" "$TF" >/dev/null 2>&1
then no "selftest passed a script that satisfies nothing"
else ok "selftest refuses a script that does not satisfy its fixtures"; fi
rm -f "$TF"

echo
echo "THE BUNDLE"
BOUT=$(mktemp -d)
if "$HERE/tooling/emit-bundle.sh" "$HERE/examples/invoices.design" --name b1 --out "$BOUT" >/dev/null 2>&1
then ok "a design becomes a standalone bundle"
else no "the bundle did not build"; fi
[ -x "$BOUT/b1/run.sh" ] && ok "run.sh is executable" || no "run.sh is not executable"
[ -f "$BOUT/b1/com.process-to-loop.b1.plist" ] && ok "a launchd job is emitted" || no "no launchd plist"
if grep -q "$BOUT/b1" "$BOUT/b1/com.process-to-loop.b1.plist" 2>/dev/null
then ok "the plist carries an absolute path, so launchd can find it"
else no "the plist path was not resolved"; fi
if grep -rq "gc \|gascity" "$BOUT/b1/run.sh" "$BOUT/b1"/steps/*.sh 2>/dev/null
then no "the bundle references gc — it must run standalone"
else ok "nothing in the bundle needs gc, a city or a network"; fi
( cd "$BOUT/b1" && ./run.sh >/dev/null 2>&1 )
if grep -q "refused" "$BOUT/b1/memory/units.tsv" 2>/dev/null
then ok "with no check installed the bundle refuses — it fails closed"
else no "the bundle passed units with no check installed"; fi
rm -rf "$BOUT"

echo
echo "CONFORMANCE"
if command -v gc >/dev/null; then
  if "$HERE/tooling/conformance.sh" "$OUT" fc-invoices >/dev/null 2>&1
  then ok "gc compiles the emitted formula"
  else no "gc refused the emitted formula"; fi
  if "$HERE/tooling/conformance.sh" "$HERE" check-authoring >/dev/null 2>&1
  then ok "gc compiles the audit workflow"
  else no "gc refused the audit workflow"; fi
else
  printf "  SKIP  gc is not installed\n"
fi

echo
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
