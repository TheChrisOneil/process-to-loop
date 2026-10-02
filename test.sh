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
echo "THE DESIGN LANE"
if "$HERE/tooling/validate-formula.sh" "$HERE/formulas/design-authoring.toml" --checkroot "$HERE" >/dev/null 2>&1
then ok "design-authoring passes the formula rules"
else no "design-authoring fails the formula rules"; fi
[ -f "$HERE/tooling/method/GENERATE.md" ] && ok "the written method the author follows is present" \
                                          || no "no method/GENERATE.md for the author step"
DT=$(mktemp)
printf 'not a process' > "$DT"
if DESIGN_PATH="$DT" "$HERE/checks/design-validate.sh" >/dev/null 2>&1
then no "a file that is not a design passed the validate gate"
else ok "a file that is not a design is refused by the validate gate"; fi
DESIGN_PATH=/nowhere "$HERE/checks/design-validate.sh" >/dev/null 2>&1
[ $? -eq 75 ] && ok "a missing design exits 75 — could not run, not a bad design" \
              || no "a missing design did not exit 75"
if DESIGN_PATH="$HERE/examples/invoices.design" "$HERE/checks/design-validate.sh" >/dev/null 2>&1
then ok "a real design passes the validate gate"
else no "a real design was refused by the validate gate"; fi

DD=$(mktemp -d); cp "$HERE/examples/invoices.design" "$DD/d.design"
DESIGN_PATH="$DD/d.design" "$HERE/checks/diagrams-complete.sh" >/dev/null 2>&1
[ $? -eq 1 ] && ok "undrawn diagrams are refused" || no "undrawn diagrams were accepted"
"$HERE/tooling/brief.sh" "$DD/d.design" >/dev/null 2>&1
DESIGN_PATH="$DD/d.design" "$HERE/checks/diagrams-complete.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "drawn diagrams carrying every gate pass" || no "drawn diagrams were refused"
touch "$DD/d.design"
DESIGN_PATH="$DD/d.design" "$HERE/checks/diagrams-complete.sh" >/dev/null 2>&1
[ $? -eq 1 ] && ok "a diagram older than its design is refused as stale" || no "stale diagrams were accepted"
rm -rf "$DD"
rm -f "$DT"

echo
echo "THE REVISION LOOP"
LT=$(mktemp -d); cp "$HERE/examples/invoices.design" "$LT/d.design"
mkv() { printf '%s' "$1" > "$LT/v.json"; touch "$LT/v.json"; }
mkv '{"defects":[]}'
DESIGN_PATH="$LT/d.design" AUDIT_VERDICT="$LT/v.json" "$HERE/checks/design-reviewed.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a sound design is done with the model" || no "a sound design did not pass"
mkv '{"defects":[{"severity":"major","fixable":"by_revision","what":"w","why":"y"}]}'
DESIGN_PATH="$LT/d.design" AUDIT_VERDICT="$LT/v.json" "$HERE/checks/design-reviewed.sh" >/dev/null 2>&1
[ $? -eq 1 ] && ok "a fixable finding re-runs the author" || no "a fixable finding did not re-run authoring"
mkv '{"defects":[{"severity":"major","fixable":"needs_a_person","what":"w","why":"y"}]}'
DESIGN_PATH="$LT/d.design" AUDIT_VERDICT="$LT/v.json" "$HERE/checks/design-reviewed.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a finding only a person can settle is surfaced, not retried" || no "a human-only finding was retried"
mkv '{"defects":[{"severity":"major","what":"w","why":"y"}]}'
DESIGN_PATH="$LT/d.design" AUDIT_VERDICT="$LT/v.json" "$HERE/checks/design-reviewed.sh" >/dev/null 2>&1
[ $? -eq 1 ] && ok "an unclassified finding cannot be routed, so it is refused" || no "an unclassified finding was accepted"
AUTHOR_MODEL=x AUDIT_MODEL=x "$HERE/tooling/audit-design.sh" "$LT/d.design" "$LT/d.design" /dev/null >/dev/null 2>&1
[ $? -eq 1 ] && ok "one model cannot audit its own design" || no "the same model was allowed to audit itself"
rm -rf "$LT"

echo
echo "FINDINGS"
FT=$(mktemp -d)
printf '{"author_model":"a","audit_model":"b","verdict":"defective","confidence":"high","checked":["unit-of-work"],"defects":[{"severity":"minor","what":"m","why":"y"},{"severity":"critical","what":"c","why":"y"},{"severity":"major","what":"j","why":"y"}]}' > "$FT/v.json"
cp "$HERE/examples/invoices.design" "$FT/d.design"
if "$HERE/tooling/findings.sh" "$FT/v.json" "$FT/d.design" >/dev/null 2>&1
then ok "a verdict renders to FINDINGS.md"; else no "findings.sh did not render"; fi
FIRST=$(grep -m1 "^## [0-9]" "$FT/FINDINGS.md" 2>/dev/null)
case "$FIRST" in *CRITICAL*) ok "the worst finding is listed first" ;;
  *) no "findings are not ordered by severity: $FIRST" ;; esac
grep -q "accepted as it stands, because" "$FT/FINDINGS.md" 2>/dev/null \
  && ok "each finding demands a decision with a reason" || no "no decision boxes rendered"
printf '{"author_model":"a","audit_model":"b","verdict":"sound","checked":["unit-of-work"],"defects":[]}' > "$FT/v.json"
"$HERE/tooling/findings.sh" "$FT/v.json" "$FT/d.design" >/dev/null 2>&1
grep -q "It found nothing" "$FT/FINDINGS.md" 2>/dev/null \
  && ok "a clean audit still writes the file — absence is a result" || no "a clean audit wrote nothing"
AV=$(mktemp)
printf '{"author_model":"a","audit_model":"b","verdict":"defective","checked":["polarity","boundary","source-of-truth","exit-75","refusal-text"],"defects":[{"severity":"major","what":"w","why":"y"}]}' > "$AV"
if AUDIT_VERDICT="$AV" "$HERE/checks/audit-verdict.sh" >/dev/null 2>&1
then ok "a defective verdict passes the gate — soundness is a person's call"
else no "the gate still refuses a defective verdict"; fi
rm -rf "$FT" "$AV"

echo
echo "THE RECORD LAYER"
for d in "$HERE"/examples/*.design; do
  case "$(basename "$d")" in broken.design) continue ;; esac
  grep -q "^@record" "$d" || { no "$(basename "$d") declares no @record"; continue; }
done
ok "every example declares its record layer"
RT=$(mktemp)
python3 - "$HERE/examples/invoices.design" "$RT" <<'PY2'
import re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_text(re.sub(r"\n@record\n(?:(?!\n@)[\s\S])*", "\n", t, count=1))
PY2
V26OUT=$("$HERE/tooling/validate.sh" "$RT" 2>&1) || true
case "$V26OUT" in *FAIL*V26*) ok "a design with no @record fails V26" ;;
  *) no "a design with no @record passed V26" ;; esac
rm -f "$RT"

BR=$(mktemp -d)
"$HERE/tooling/emit-bundle.sh" "$HERE/examples/invoices.design" --name r1 --out "$BR" >/dev/null 2>&1
if BUNDLE_PATH="$BR/r1" DESIGN_PATH="$HERE/examples/invoices.design" "$HERE/checks/bundle-records.sh" >/dev/null 2>&1
then ok "a bundle that keeps its records passes the records gate"
else no "a correct bundle was refused by the records gate"; fi
sed -i.bak 's/^ledger /#ledger /' "$BR/r1/steps/2-match.sh" 2>/dev/null
if BUNDLE_PATH="$BR/r1" DESIGN_PATH="$HERE/examples/invoices.design" "$HERE/checks/bundle-records.sh" >/dev/null 2>&1
then no "a step with its ledger call commented out was accepted"
else ok "a commented-out ledger call is refused — # is not a call"; fi
rm -rf "$BR"

REGOUT=$(echo "I accept" | "$HERE/tooling/accept.sh" "$HERE/examples/invoices.design" --by "Nobody, Impostor" 2>&1) || true
case "$REGOUT" in *"somebody else"*) ok "a signature from anyone but the named approver is refused" ;;
  *) no "the register accepted a signature from the wrong person" ;; esac

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
  if "$HERE/tooling/conformance.sh" "$HERE" design-authoring >/dev/null 2>&1
  then ok "gc compiles the design-authoring workflow"
  else no "gc refused the design-authoring workflow"; fi
else
  printf "  SKIP  gc is not installed\n"
fi


echo
echo "MAYOR PROMPT"
MP="$HERE/agents/mayor/prompt.template.md"
if [ -f "$MP" ]; then
  ok "the mayor prompt is in the repo, not only in a city"
else
  no "the mayor prompt is missing"
fi

# The agent prompt is rendered by Go templating. A {{formula_var}} in it is not
# substituted — it is a parse error, and the mayor then has no prompt at all.
STRAY=$(grep -o '{{[^}]*}}' "$MP" 2>/dev/null \
        | grep -vE 'define|^\{\{-? ?end|templateFirst' || true)
if [ -z "$STRAY" ]; then
  ok "the prompt carries no formula-var braces the renderer would reject"
else
  no "the prompt has Go-template braces that are not Go template: $STRAY"
fi

# Every --var the prompt tells the mayor to pass must be a var the formula has.
MISSING=""
for v in $(grep -o -- '--var [a-z_]*=' "$MP" | awk '{print $2}' | tr -d '=' | sort -u); do
  grep -q "^\[vars\.$v\]" "$HERE/formulas/design-authoring.toml" || MISSING="$MISSING $v"
done
if [ -z "$MISSING" ]; then
  ok "every --var the prompt names exists in design-authoring"
else
  no "the prompt passes vars the formula does not define:$MISSING"
fi

# Every required var must appear in the prompt's start-a-run command.
UNSET=""
for v in $(awk '/^\[vars\./{n=$0} /^required = true/{gsub(/\[vars\.|\]/,"",n); print n}' \
           "$HERE/formulas/design-authoring.toml"); do
  grep -q -- "--var $v=" "$MP" || UNSET="$UNSET $v"
done
if [ -z "$UNSET" ]; then
  ok "the prompt sets every var the formula requires"
else
  no "the prompt omits required vars:$UNSET"
fi

if [ -f "$HERE/schema/DESIGN-FORMAT.md" ]; then
  ok "the method the prompt points method_path at exists"
else
  no "the prompt points method_path at a file that is not there"
fi
echo
printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
