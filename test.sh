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
echo "THE CITY PREFLIGHT"
if "$HERE/tooling/city-preflight.sh" --city /nowhere >/dev/null 2>&1
then no "a directory that is not a city was accepted"
else ok "a directory with no city.toml is refused"; fi
for prop in PINNED COHERENT UNIFIED CURRENT CAPABLE CONSISTENT; do
  grep -q "^#   $prop" "$HERE/tooling/city-preflight.sh" \
    && ok "$prop is defined in the semantics" \
    || no "$prop is not documented in city-preflight.sh"
done

echo
echo "PACK COMPATIBILITY"
PA=$(find ~/.gc/cache/repos -maxdepth 2 -type d -name gascity 2>/dev/null | head -1)
PB=$(find ~/.gc/cache/repos -maxdepth 2 -type d -name gascity 2>/dev/null | sed -n 2p)
if [ -n "$PA" ] && [ -d "$PA" ]; then
  M=$("$HERE/tooling/pack-capability.sh" "$PA" 2>/dev/null)
  [ -n "$M" ] && ok "a pack yields a capability manifest" || no "the manifest came back empty"
  M2=$("$HERE/tooling/pack-capability.sh" "$PA" 2>/dev/null)
  [ "$M" = "$M2" ] && ok "the manifest is deterministic — same pack, same bytes" \
                   || no "two runs of pack-capability differed"
  for prop in PROVIDES MANDATES DEMANDS USES NORMS OPAQUE; do
    grep -q "^#   $prop" "$HERE/tooling/lib/capability.awk" \
      || grep -q "$prop" "$HERE/tooling/pack-capability.sh" \
      && ok "$prop is a declared property" || no "$prop is not documented"
  done
  "$HERE/tooling/pack-diff.sh" "$PA" "$PA" >/dev/null 2>&1 \
    && ok "a pack against itself is NONE" || no "a pack against itself was not NONE"
  if [ -n "$PB" ] && [ -d "$PB" ]; then
    "$HERE/tooling/pack-diff.sh" "$PA" "$PB" >/dev/null 2>&1; rc=$?
    [ "$rc" -le 2 ] && ok "two pack versions classify (exit $rc)" || no "pack-diff errored"
  fi
else printf "  SKIP  no cached gascity pack to diff\n"; fi

echo
echo "THE STEP LANE"
if "$HERE/tooling/validate-formula.sh" "$HERE/formulas/step-authoring.toml" --checkroot "$HERE" >/dev/null 2>&1
then ok "step-authoring passes the formula rules"
else no "step-authoring fails the formula rules"; fi

PT=$(mktemp)
"$HERE/tooling/properties.sh" "$HERE/examples/invoices.design" 5 > "$PT" 2>/dev/null
if grep -q "^is-model" "$PT"; then ok "a thinking step must call exactly one provider"
else no "the thinking step got no is-model property"; fi
"$HERE/tooling/properties.sh" "$HERE/examples/invoices.design" 2 > "$PT" 2>/dev/null
if grep -q "^no-model" "$PT" && grep -q "^determinism" "$PT"
then ok "a rule-typed step must call nothing and repeat itself exactly"
else no "the mechanical step got no no-model or determinism property"; fi
if grep -q "^no-proof" "$PT"; then ok "only the step the design names may write evidence"
else no "a non-writer step was not held to no-proof"; fi
"$HERE/tooling/properties.sh" "$HERE/examples/invoices.design" 99 >/dev/null 2>&1 \
  && no "a step id that does not exist was accepted" \
  || ok "a step id that does not exist is refused"

BT=$(mktemp -d)
"$HERE/tooling/emit-bundle.sh" "$HERE/examples/invoices.design" --name s1 --out "$BT" >/dev/null 2>&1
"$HERE/tooling/properties.sh" "$HERE/examples/invoices.design" 8 > "$BT/p8.tsv" 2>/dev/null
if "$HERE/tooling/step-selftest.sh" "$BT/s1/steps/8-prove.sh" "$BT/p8.tsv" --bundle "$BT/s1" >/dev/null 2>&1
then ok "the evidence-writing step holds its properties"
else no "the evidence-writing step failed its properties"; fi
# a rule step that calls a model must fail no-model
sed 's|^RESULT="ok"|RESULT=$(claude -p "decide this" 2>/dev/null)|' "$BT/s1/steps/2-match.sh" > "$BT/bad.sh"
chmod +x "$BT/bad.sh"
"$HERE/tooling/properties.sh" "$HERE/examples/invoices.design" 2 > "$BT/p2.tsv" 2>/dev/null
if "$HERE/tooling/step-selftest.sh" "$BT/bad.sh" "$BT/p2.tsv" --bundle "$BT/s1" >/dev/null 2>&1
then no "a rule-typed step that calls a model was accepted"
else ok "a rule-typed step that calls a model is refused"; fi
rm -rf "$BT" "$PT"

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
  then ok "gc compiles the check-authoring workflow"
  else no "gc refused the check-authoring workflow"; fi
  if "$HERE/tooling/conformance.sh" "$HERE" step-authoring >/dev/null 2>&1
  then ok "gc compiles the step-authoring workflow"
  else no "gc refused the step-authoring workflow"; fi
else
  printf "  SKIP  gc is not installed\n"
fi

echo
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
