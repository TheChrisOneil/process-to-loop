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
mkv() { python3 - "$LT/v.json" "$1" "$(shasum -a 256 "$LT/d.design" | awk '{print $1}')" <<'PY_MKV'
import json, sys
out, body, sha = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.loads(body); d["subject_sha256"] = sha
json.dump(d, open(out, "w"))
PY_MKV
}
mkv '{"defects":[]}'
DESIGN_PATH="$LT/d.design" AUDIT_VERDICT="$LT/v.json" "$HERE/checks/design-reviewed.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a sound design is done with the model" || no "a sound design did not pass"
mkv '{"defects":[{"severity":"major","fixable":"by_revision","what":"w","why":"y"}]}'
DESIGN_PATH="$LT/d.design" AUDIT_VERDICT="$LT/v.json" "$HERE/checks/design-reviewed.sh" >/dev/null 2>&1
[ $? -eq 1 ] && ok "a fixable finding re-runs the author" || no "a fixable finding did not re-run authoring"
# A revision that does not reduce the fixable count should surface what it has,
# not spend another attempt. appointment-chase went 9 findings to 7, then died
# on its last attempt holding one fixable item and six a person needed to see.
rm -f "$LT/v.json.fixable"
mkv '{"defects":[{"severity":"major","fixable":"by_revision","what":"w","why":"y"},{"severity":"major","fixable":"needs_a_person","what":"w","why":"y"}]}'
DESIGN_PATH="$LT/d.design" AUDIT_VERDICT="$LT/v.json" "$HERE/checks/design-reviewed.sh" >/dev/null 2>&1
[ $? -eq 1 ] && ok "a first fixable finding sends it back to the author" || no "the first fixable finding did not re-run authoring"
mkv '{"defects":[{"severity":"major","fixable":"by_revision","what":"w","why":"y"},{"severity":"major","fixable":"needs_a_person","what":"w","why":"y"}]}'
DESIGN_PATH="$LT/d.design" AUDIT_VERDICT="$LT/v.json" "$HERE/checks/design-reviewed.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a revision that reduced nothing surfaces instead of retrying" \
             || no "the loop kept retrying while making no progress"
rm -f "$LT/v.json.fixable"

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
AV=$(mktemp); AVS=$(mktemp); printf 'the audited artifact\n' > "$AVS"
printf '{"author_model":"a","audit_model":"b","verdict":"defective","checked":["polarity","boundary","source-of-truth","exit-75","refusal-text"],"defects":[{"severity":"major","what":"w","why":"y"}],"subject_sha256":"%s"}' \
  "$(shasum -a 256 "$AVS" | awk '{print $1}')" > "$AV"
if AUDIT_VERDICT="$AV" AUDIT_SUBJECT="$AVS" "$HERE/checks/audit-verdict.sh" >/dev/null 2>&1
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
echo "THE VALIDATOR TERMINATES"
# parse.awk used k for a keyed-section key name AND as the KPI counter. After
# @meta, k held a string like "approver", so validate.awk's `for (i=1;i<=k;i++)`
# became a string comparison that is always true. Any design with no @kpis
# section hung the validator forever — the first gate, spinning on exactly the
# malformed input it exists to reject, until the controller's 15m timeout.
VT=$(mktemp -d)
printf '@meta\nuse_case: x\napprover: A. Person\n' > "$VT/nokpis.design"
# Job control, so the child gets its own process group and the kill below
# reaches the awk it spawns. `kill -9 $PID` on a subshell leaves the grandchild
# orphaned and still allocating: on 2026-10-05 that leaked three awk processes
# holding 40-46 GB each, because the loop this test guards auto-vivifies an
# array element per iteration.
set -m
( "$HERE/tooling/validate.sh" "$VT/nokpis.design" >/dev/null 2>&1; echo $? > "$VT/rc" ) &
VP=$!
set +m
VN=0
while kill -0 $VP 2>/dev/null && [ $VN -lt 15 ]; do sleep 1; VN=$((VN+1)); done
if kill -0 $VP 2>/dev/null; then
  kill -9 -$VP 2>/dev/null || kill -9 $VP 2>/dev/null
  pkill -9 -f 'lib/validate.awk' 2>/dev/null
  no "the validator hangs on a design with no @kpis section"
else
  ok "the validator terminates on a design with no @kpis section"
  [ "$(cat "$VT/rc" 2>/dev/null)" = "1" ] \
    && ok "and refuses it rather than passing it" \
    || no "it terminated but did not refuse an incomplete design"
fi
rm -rf "$VT"

echo
echo "STATUS REPORTS OUTCOMES"
# run-status printed every closed bead as "done". On 2026-10-05 that showed two
# gates which had REFUSED as though they had passed, and the run read as healthy
# while it had failed. A status tool that cannot distinguish pass from fail is
# the defect this repo exists to catch, in the tool written to watch for it.
grep -q 'gc.outcome' "$HERE/tooling/run-status.sh" \
  && ok "the status tool reads gc.outcome" \
  || no "run-status still reports closed beads without their outcome"
grep -q 'FAILED' "$HERE/tooling/run-status.sh" \
  && ok "it has a distinct label for a failed step" \
  || no "run-status has no way to render a failure"
grep -q 'ROOT_BEAD' "$HERE/tooling/run-status.sh" \
  && ok "the status tool scopes to one workflow" \
  || no "run-status mixes steps from other runs in the same rig"
grep -q 'iteration' "$HERE/tooling/run-status.sh" \
  && ok "it reports the logical bead, not every iteration" \
  || no "run-status would show a step as both done and failed"

echo
echo "THE BUNDLE READS ITS SOURCES"
# The records gate used to prove a ledger existed. It now proves PROVENANCE: the
# bundle called the tool the design named and logged which source, via which
# tool, at what data class. That is the row an auditor reads.
BR=$(mktemp -d)
"$HERE/tooling/emit-bundle.sh" "$HERE/examples/appointments-chase.design" --name appt --out "$BR" >/dev/null 2>&1
[ -x "$BR/appt/run.sh" ] && ok "a design with sources emits a runnable bundle" \
                         || no "emit-bundle produced nothing for a design with sources"
( cd "$BR/appt" && ./run.sh >/dev/null 2>&1 ) || true
grep -q '	read	appointments via eb-appointment-service' "$BR/appt/memory/ledger.tsv" 2>/dev/null \
  && ok "a tick read the CSV-backed source and logged it" \
  || no "the bundle did not log a read of appointments"
grep -q '	read	intake-forms via eb-form-builder-service' "$BR/appt/memory/ledger.tsv" 2>/dev/null \
  && ok "a tick read the XML-backed source and logged it" \
  || no "the bundle did not log a read of intake-forms"
# (phi) or (phi; may not ...) — the class is the part this asserts, and pinning
# it to the exact old spelling made adding the permission look like a regression.
grep -qE '\(phi[);]' "$BR/appt/memory/ledger.tsv" 2>/dev/null \
  && ok "the ledger records the data class of what was read" \
  || no "the ledger does not say what class of data was read"
[ -s "$BR/appt/memory/appointments.tsv" ] \
  && ok "the tool's rows landed where the design said" \
  || no "no rows were written for the appointments source"

BRES=$(DESIGN_PATH="$HERE/examples/appointments-chase.design" BUNDLE_PATH="$BR/appt" \
       "$HERE/checks/bundle-records.sh" 2>&1 || true)
case "$BRES" in
  *"provenance: 2 source(s) read and logged"*) ok "the records gate confirms provenance" ;;
  *) no "the records gate did not confirm provenance: $BRES" ;;
esac

# And refuses a bundle that declares a source it never reads.
python3 - "$BR/appt/steps/1-pull-appointments.sh" <<'PY_STRIP'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'\n# ---- source: appointments.*?(?=\nledger |\n# |\Z)', '\n', s, flags=re.S)
s = re.sub(r'\nledger "\$UNIT" "pull-appointments" read .*\n', '\n', s)
s = re.sub(r'\nstep_say "1" "pull-appointments" "mechanical" "read .*\n', '\n', s)
open(p, 'w').write(s)
PY_STRIP
rm -f "$BR/appt/memory/ledger.tsv" "$BR/appt/memory/units.tsv"
BRES2=$(DESIGN_PATH="$HERE/examples/appointments-chase.design" BUNDLE_PATH="$BR/appt" \
        "$HERE/checks/bundle-records.sh" 2>&1 || true)
case "$BRES2" in
  *"logged no read of it"*) ok "a declared source that is never read is refused" ;;
  *) no "a bundle ignoring a declared source passed the records gate" ;;
esac
rm -rf "$BR"

echo
echo "THE DATA CONTRACT (V27-V31)"
DC=$(mktemp -d); DESIGN_OK="$HERE/examples/appointments-chase.design"
dcheck() { # dcheck <rule> <design> <want FAIL|PASS> <label> [catalog]
  r=$(CATALOG="${5:-$HERE/catalog/eb-tools.catalog}" "$HERE/tooling/validate.sh" "$2" 2>&1 \
      | grep -E "  $1  " | head -1)
  case "$r" in
    *FAIL*) got=FAIL ;; *PASS*) got=PASS ;; *) got=ABSENT ;;
  esac
  [ "$got" = "$3" ] && ok "$1 $4" || no "$1 $4 — got $got, wanted $3"
}
dcheck V27 "$DESIGN_OK" PASS "accepts sources and tools that are catalogued"
dcheck V28 "$DESIGN_OK" PASS "accepts fields the tool provides"
dcheck V29 "$DESIGN_OK" PASS "accepts tools used by real steps"
dcheck V30 "$DESIGN_OK" PASS "accepts a structural constraint"
dcheck V31 "$DESIGN_OK" PASS "accepts PHI that never reaches a model"

python3 - "$DESIGN_OK" "$DC" <<'PY_DC'
import sys
g, d = sys.argv[1], sys.argv[2]
s = open(g).read()
open(d+"/uncat.design","w").write(s.replace("eb-appointment-service | 1 |","eb-shadow-service | 1 |"))
open(d+"/invent.design","w").write(s.replace("appointment_id, patient_ref, status","appointment_id, insurance_plan"))
open(d+"/nostep.design","w").write(s.replace("eb-form-builder-service | 2 |","eb-form-builder-service | 99 |"))
open(d+"/vague.design","w").write(s.replace("| never reaches a model","| should be handled carefully"))
# Point the PHI tool at whichever step has a model actor, by rule rather than by
# a literal string that goes stale the moment the example is reworded.
import re
model_step = re.search(r"^(\d+) \| [^|]*\| *thinking *\| *model", s, re.M).group(1)
leak = re.sub(r"^(eb-form-builder-service \| )[0-9 ]+(\|)", r"\g<1>" + model_step + r" \2", s, flags=re.M)
assert leak != s, "leak mutation did not apply"
open(d+"/leak.design","w").write(leak)
PY_DC

dcheck V27 "$DC/uncat.design"  FAIL "refuses a tool nobody catalogued"
dcheck V28 "$DC/invent.design" FAIL "refuses a field the tool does not provide"
dcheck V29 "$DC/nostep.design" FAIL "refuses a tool used by a step that does not exist"
dcheck V30 "$DC/vague.design"  FAIL "refuses a constraint that is neither structural nor evaluable"
# V31 is about a BUSINESS AGREEMENT now, not about the data, so the refusal has
# to be tested against a catalog that records no agreement. Under the one that
# does, the same design is correct — which is the behaviour, not a regression.
sed 's/phi_may_reach_models: yes/phi_may_reach_models: no/' "$HERE/catalog/eb-tools.catalog" > "$DC/nobaa.catalog"
dcheck V31 "$DC/leak.design"   FAIL "refuses PHI reaching a model where nothing permits it" "$DC/nobaa.catalog"
dcheck V31 "$DC/leak.design"   PASS "allows it where the catalog records a covering agreement"

# And the rule that cannot be skipped by omission: no catalog, no verification.
# Capture first, then match. validate.sh exits non-zero on a failing design and
# pipefail then masks a grep that succeeded — the trap documented in this repo,
# walked into again here.
NOCAT=$(CATALOG=/nonexistent "$HERE/tooling/validate.sh" "$DESIGN_OK" 2>&1 || true)
case "$NOCAT" in
  *"no catalog was readable"*) ok "a design naming sources without a readable catalog is refused" ;;
  *) no "sources went unverified when no catalog was present" ;;
esac
rm -rf "$DC"

echo
echo "THE TOOL CATALOG"
CT="$HERE/catalog/eb-tools.catalog"
[ -f "$CT" ] && ok "a tool catalog exists" || no "no catalog at catalog/eb-tools.catalog"

# Every tool it names must answer. A catalog nothing verifies is a comment.
"$HERE/tooling/catalog.sh" "$CT" health >/dev/null 2>&1 \
  && ok "every tool in the catalog answers health" \
  || no "a catalogued tool is unreachable"

# And must actually provide what the catalog claims. This is the one that stops
# a design naming a field that will not exist at run time.
for TID in eb-appointment-service eb-form-builder-service; do
  "$HERE/tooling/catalog.sh" "$CT" verify "$TID" >/dev/null 2>&1 \
    && ok "$TID provides every field the catalog claims" \
    || no "$TID does not report a field the catalog claims"
done

CTT=$(mktemp -d)
sed 's/^provides: appointment_id, patient_ref/provides: appointment_id, patient_ref, insurance_plan/' "$CT" > "$CTT/bad"
"$HERE/tooling/catalog.sh" "$CTT/bad" verify eb-appointment-service >/dev/null 2>&1
[ $? -eq 1 ] && ok "a claimed field the tool does not report is refused" \
             || no "the catalog accepted a claim the tool contradicts"
"$HERE/tooling/catalog.sh" "$CT" stale 2030-01 >/dev/null 2>&1
[ $? -eq 1 ] && ok "an entry past its review date is reported stale" \
             || no "a stale attestation passed"
sed 's|via: tools/eb-appointment-service|via: tools/eb-nope-service|' "$CT" > "$CTT/gone"
"$HERE/tooling/catalog.sh" "$CTT/gone" health >/dev/null 2>&1
[ $? -eq 1 ] && ok "an unreachable tool fails health" \
             || no "health passed a tool that is not there"
rm -rf "$CTT"

# The tools themselves hold the three-subcommand contract, including 75.
for TOOL in eb-appointment-service eb-form-builder-service; do
  "$HERE/tools/$TOOL" schema >/dev/null 2>&1 && "$HERE/tools/$TOOL" fetch >/dev/null 2>&1 \
    && ok "$TOOL answers schema and fetch" || no "$TOOL does not hold the tool contract"
done
EB_APPOINTMENT_FIXTURE=/nope "$HERE/tools/eb-appointment-service" fetch >/dev/null 2>&1
[ $? -eq 75 ] && ok "an unreadable source exits 75, not 1" \
              || no "a tool reported infrastructure failure as a business outcome"

echo
echo "COMPILE-TIME BINDING"
BT=$(mktemp -d); mkdir -p "$BT/run"
printf '@meta\nuse_case: x\napprover: A. Person\n' > "$BT/run/x.design"
"$HERE/tooling/bind-checks.sh" "$BT/run" "$HERE/checks" \
  DESIGN_PATH="$BT/run/x.design" ARTIFACT_ROOT="$BT/run" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a run binds its checks" || no "bind-checks failed on a valid run"

# BUNDLE_PATH is produced by compile, not declared as a var, so it could not be
# bound and the records gate exited 75 with "BUNDLE_PATH is not set" on the first
# run that ever reached it. The path is deterministic; bind it.
grep -q 'BUNDLE_PATH={{artifact_root}}/bundle' "$HERE/formulas/design-authoring.toml" \
  && ok "the formula binds a deterministic bundle path" \
  || no "BUNDLE_PATH is not bound, so the records gate cannot find the bundle"

# The property the whole change exists for: no gc, no env, no cwd.
OUT=$(cd / && env -i PATH=/usr/bin:/bin bash "$BT/run/checks/design-validate.sh" 2>&1)
case "$OUT" in
  *"DESIGN_PATH is not set"*) no "a bound check still could not find its inputs" ;;
  *) ok "a bound check runs with no gc, no environment and from /" ;;
esac

# A wrapper that carries no value is worse than none: it runs on whatever it finds.
sed 's/^export DESIGN_PATH=.*$//' "$BT/run/checks/design-validate.sh" > "$BT/run/checks/tmp" \
  && mv "$BT/run/checks/tmp" "$BT/run/checks/design-validate.sh" && chmod +x "$BT/run/checks/design-validate.sh"
ARTIFACT_ROOT="$BT/run" "$HERE/checks/checks-bound.sh" >/dev/null 2>&1
[ $? -eq 1 ] && ok "the gate refuses a wrapper that binds no value" \
             || no "a wrapper carrying no DESIGN_PATH passed the binding gate"

# And one pointing at a check that is not there.
BT2=$(mktemp -d); mkdir -p "$BT2/run"
"$HERE/tooling/bind-checks.sh" "$BT2/run" "$HERE/checks" DESIGN_PATH=/x ARTIFACT_ROOT="$BT2/run" >/dev/null 2>&1
sed -i '' "s|^exec '.*'|exec '/no/such/check.sh'|" "$BT2/run/checks/design-validate.sh"
ARTIFACT_ROOT="$BT2/run" "$HERE/checks/checks-bound.sh" >/dev/null 2>&1
[ $? -eq 1 ] && ok "the gate refuses a wrapper whose target does not exist" \
             || no "a wrapper pointing at nothing passed the binding gate"

# A missing source check must stop the binding entirely, not half-write it.
BT3=$(mktemp -d); mkdir -p "$BT3/run" "$BT3/empty"
"$HERE/tooling/bind-checks.sh" "$BT3/run" "$BT3/empty" DESIGN_PATH=/x >/dev/null 2>&1
[ $? -eq 1 ] && ok "binding refuses when a named check is missing" \
             || no "binding wrote wrappers against a checks dir that has none"
[ ! -d "$BT3/run/checks" ] && ok "a refused binding wrote nothing" \
                          || no "a refused binding left partial wrappers behind"
rm -rf "$BT" "$BT2" "$BT3"

echo
echo "ARCHIVING A RUN"
AT=$(mktemp -d)
printf 'd\n' > "$AT/x.design"; printf 'b\n' > "$AT/BRIEF.md"
printf '{"subject_sha256":"old"}\n' > "$AT/design-audit-verdict.json"
printf 'f\n' > "$AT/FINDINGS.md"; printf 'u\n' > "$AT/use-case.txt"
mkdir -p "$AT/diagrams"; printf 'g\n' > "$AT/diagrams/flow.mmd"
"$HERE/tooling/archive-run.sh" "$AT" run-1 >/dev/null 2>&1
[ $? -eq 0 ] && ok "a run with artifacts archives cleanly" || no "archive-run failed on a populated directory"
[ -f "$AT/prior/run-1/FINDINGS.md" ] && [ -f "$AT/prior/run-1/design-audit-verdict.json" ] \
  && ok "the conclusions are copied into the archive" \
  || no "the archive does not hold the verdict and findings"
[ ! -e "$AT/design-audit-verdict.json" ] && [ ! -e "$AT/FINDINGS.md" ] \
  && ok "the conclusions are gone from where a later step would read them" \
  || no "a stale verdict or findings file survived the archive"
[ -f "$AT/use-case.txt" ] && ok "the inputs are left alone" || no "the archive deleted an input"
[ -f "$AT/prior/run-1/MANIFEST.txt" ] && grep -q 'design_sha256' "$AT/prior/run-1/MANIFEST.txt" \
  && ok "the archive records which design it holds" \
  || no "the archive has no manifest naming the design"

# The gate is about the invariant, not about whether a copy happened.
ARTIFACT_ROOT="$AT" "$HERE/checks/prior-archived.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "the gate passes once nothing derived is left" || no "the gate refused a clean directory"
printf 'stale\n' > "$AT/FINDINGS.md"
ARTIFACT_ROOT="$AT" "$HERE/checks/prior-archived.sh" >/dev/null 2>&1
[ $? -eq 1 ] && ok "the gate refuses when a previous findings file is still readable" \
             || no "the gate let a stale findings file through"
rm -f "$AT/FINDINGS.md"

# A first run has nothing to archive and must not be an error.
AE=$(mktemp -d)
"$HERE/tooling/archive-run.sh" "$AE" first >/dev/null 2>&1
[ $? -eq 0 ] && ok "a first run with nothing to archive is not an error" || no "archive-run failed on an empty directory"
ARTIFACT_ROOT="$AE" "$HERE/checks/prior-archived.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "the gate passes a first run with no archive" || no "the gate refused a legitimate first run"
rm -rf "$AT" "$AE"

# "Archive the previous run" happens once per RUN, not once per invocation. A
# step and its iteration both ran this on 2026-10-02 and made two archives.
AI=$(mktemp -d)
printf 'd\n' > "$AI/x.design"; printf 'b\n' > "$AI/BRIEF.md"
printf 'f\n' > "$AI/FINDINGS.md"; printf '{"s":1}\n' > "$AI/design-audit-verdict.json"
RUN_ID=wk-aaa "$HERE/tooling/archive-run.sh" "$AI" a1 >/dev/null 2>&1
RUN_ID=wk-aaa "$HERE/tooling/archive-run.sh" "$AI" a2 >/dev/null 2>&1
N=$(ls -1 "$AI/prior" | grep -v '^latest$' | wc -l | tr -d ' ')
[ "$N" = "1" ] && ok "a second archive in the same run is a no-op" \
               || no "one run produced $N archives"
# A later run with new content must still archive.
printf 'd2\n' > "$AI/x.design"
RUN_ID=wk-bbb "$HERE/tooling/archive-run.sh" "$AI" a3 >/dev/null 2>&1
N=$(ls -1 "$AI/prior" | grep -v '^latest$' | wc -l | tr -d ' ')
[ "$N" = "2" ] && ok "a different run still archives" || no "a new run did not archive; got $N"
rm -rf "$AI"

# Run by hand there is no run id, so identity falls back to content — which is
# what actually catches the observed double archive, since the second call sees
# the same bytes it just copied.
AJ=$(mktemp -d)
printf 'd\n' > "$AJ/x.design"; printf 'f\n' > "$AJ/FINDINGS.md"
"$HERE/tooling/archive-run.sh" "$AJ" b1 >/dev/null 2>&1
"$HERE/tooling/archive-run.sh" "$AJ" b2 >/dev/null 2>&1
N=$(ls -1 "$AJ/prior" | grep -v '^latest$' | wc -l | tr -d ' ')
[ "$N" = "1" ] && ok "with no run id, identical content archives once" \
               || no "unchanged content was archived $N times"
printf 'changed\n' > "$AJ/x.design"
"$HERE/tooling/archive-run.sh" "$AJ" b3 >/dev/null 2>&1
N=$(ls -1 "$AJ/prior" | grep -v '^latest$' | wc -l | tr -d ' ')
[ "$N" = "2" ] && ok "changed content is archived" || no "a real change was not archived; got $N"
rm -rf "$AJ"

# A cross-run revision is HANDED the previous findings by path. Archiving must
# not delete the input the run was started to act on.
AR=$(mktemp -d)
printf 'd\n' > "$AR/x.design"; printf 'f\n' > "$AR/FINDINGS.md"
printf '{"s":1}\n' > "$AR/design-audit-verdict.json"
PRIOR_FINDINGS_PATH="$AR/FINDINGS.md" "$HERE/tooling/archive-run.sh" "$AR" r1 >/dev/null 2>&1
[ $? -eq 1 ] && ok "archiving refuses when a revision cites the working copy" \
             || no "archiving accepted a revision whose input it was about to delete"
[ -f "$AR/FINDINGS.md" ] \
  && ok "the refused archive destroyed nothing" \
  || no "a refused archive still deleted the findings"

# With no prior vars it proceeds, and leaves a stable name for the archive.
"$HERE/tooling/archive-run.sh" "$AR" r1 >/dev/null 2>&1
[ "$(readlink "$AR/prior/latest")" = "r1" ] \
  && ok "prior/latest names the newest archive" || no "prior/latest does not point at the new archive"

# But latest is a moving pointer, so it is not a legal input either.
printf 'f2\n' > "$AR/FINDINGS.md"
PRIOR_FINDINGS_PATH="$AR/prior/latest/FINDINGS.md" "$HERE/tooling/archive-run.sh" "$AR" r2 >/dev/null 2>&1
[ $? -eq 1 ] && ok "archiving refuses a revision that reaches through prior/latest" \
             || no "a run was allowed to revise through a pointer this step moves"

# A fixed archive path is the one legal form.
PRIOR_FINDINGS_PATH="$AR/prior/r1/FINDINGS.md" "$HERE/tooling/archive-run.sh" "$AR" r2 >/dev/null 2>&1
[ $? -eq 0 ] && ok "a revision citing a fixed archive proceeds" || no "a legitimate revision was refused"
[ "$(cat "$AR/prior/r1/FINDINGS.md")" = "f" ] \
  && ok "the revision's input is still exactly what it was" \
  || no "the archived input the revision cited was altered"
rm -rf "$AR"

# And the formula has to run it, first, or none of the above happens.
grep -q 'id = "archive-prior"' "$HERE/formulas/design-authoring.toml" \
  && ok "the formula has the archive step" || no "the archive step is not in the formula"
grep -q 'needs = \["archive-prior"\]' "$HERE/formulas/design-authoring.toml" \
  && ok "intake waits for the archive" || no "intake does not depend on the archive step"

echo
echo "THE DESIGN GATES"
# These were folded into the authoring loop, and the authoring step then closed
# pass three times having written no audit verdict at all. A check makes the
# author try again; a gate leaves a bead saying it passed. Different jobs.
for g in validate audit-verdict; do
  grep -q "id = \"$g\"" "$HERE/formulas/design-authoring.toml" \
    && ok "$g is its own step again" || no "$g is not a step in the formula"
done
grep -q 'needs = \["audit-verdict"\]' "$HERE/formulas/design-authoring.toml" \
  && ok "nothing renders until the audit gate has passed" \
  || no "render does not depend on the audit gate"

# Every check must resolve its own inputs, or it passes by hand and fails under
# the controller — which is how three gates failed on wk-nh5 in silence.
CMISS=""
for c in design-validate diagrams-complete bundle-records design-reviewed prior-archived design-audited; do
  grep -q 'step-vars.sh' "$HERE/checks/$c.sh" 2>/dev/null || CMISS="$CMISS $c"
done
[ -z "$CMISS" ] && ok "every check recovers its inputs from the workflow" \
                || no "checks still read only their environment:$CMISS"

# The design gate must refuse a design with no audit at all — the wk-nh5 case.
GT=$(mktemp -d); printf '@meta\nuse_case: x\n' > "$GT/x.design"
DESIGN_PATH="$GT/x.design" "$HERE/checks/design-audited.sh" >/dev/null 2>&1
[ $? -eq 75 ] && ok "the audit gate cannot pass a design with no verdict" \
              || no "the audit gate did not refuse a design that was never audited"
rm -rf "$GT"

echo
echo "STEP VARS"
# The controller stores a formula's [vars] on the workflow root as gc.var.<name>
# and does not export them to an exec check. A check that reads only its
# environment exits 75 forever while the work it cannot see is done correctly.
( . "$HERE/tooling/step-vars.sh"
  unset GC_BEAD_ID GC_BEAD
  load_workflow_vars ) >/dev/null 2>&1 \
  && ok "with no bead in the environment the resolver is a no-op" \
  || no "load_workflow_vars failed when there was no bead to resolve"

# The environment wins, so a check stays runnable by hand.
VAL=$( . "$HERE/tooling/step-vars.sh"
       GC_BEAD_ID=no-such-bead DESIGN_PATH=/mine/own
       load_workflow_vars 2>/dev/null
       printf '%s' "$DESIGN_PATH" )
[ "$VAL" = "/mine/own" ] \
  && ok "a value already in the environment is not overwritten" \
  || no "the resolver clobbered a value the caller had set: $VAL"

# An unresolvable bead must SAY SO. The first version swallowed gc's error with
# 2>/dev/null and returned 0, so three gates failed under the controller while
# passing by hand and nothing anywhere said why.
SVERR=$( . "$HERE/tooling/step-vars.sh"
         GC_BEAD_ID=definitely-not-a-bead
         load_workflow_vars 2>&1 >/dev/null )
SVRC=$?
[ "$SVRC" -ne 0 ] && ok "an unresolvable bead is reported, not swallowed" \
                  || no "load_workflow_vars returned success without resolving anything"
case "$SVERR" in
  *WARNING*cwd=*) ok "the warning names the cwd and gc it actually used" ;;
  *) no "the failure gave nothing to diagnose with: $SVERR" ;;
esac
# But the caller must stay runnable — checks source it with || true.
( . "$HERE/tooling/step-vars.sh" 2>/dev/null
  GC_BEAD_ID=definitely-not-a-bead
  load_workflow_vars 2>/dev/null || true
  exit 0 ) \
  && ok "a check that cannot resolve its workflow still runs" \
  || no "an unresolvable bead wedged the calling check"

grep -q 'step-vars.sh' "$HERE/checks/design-reviewed.sh" \
  && ok "the authoring check recovers its inputs from the workflow" \
  || no "design-reviewed.sh still reads its inputs from the environment alone"

echo
echo "THE AUTHORING CONTRACT"
CT="$HERE/tooling/method/CONTRACT.md"
[ -f "$CT" ] && ok "the contract the author is handed exists" \
             || no "tooling/method/CONTRACT.md is missing"
# It tells the author to run things. I named emit-formula.sh here first, which is
# an awk library and not a command — the same class of bug this file documents.
CMISS=""
for c in $(grep -oE 'tooling/[a-z-]+\.sh' "$CT" 2>/dev/null | sort -u); do
  [ -x "$HERE/$c" ] || CMISS="$CMISS $c"
done
[ -z "$CMISS" ] && ok "every command the contract names exists and is executable" \
                || no "the contract tells the author to run things that are not there:$CMISS"
# Its whole purpose is that the author need not read the libraries.
grep -q 'lib/\*.awk' "$CT" && ok "the contract says which files not to read" \
                            || no "the contract does not tell the author to skip the libraries"
# And the formula has to actually hand it over, or none of this reaches anyone.
grep -q 'CONTRACT.md' "$HERE/formulas/design-authoring.toml" \
  && ok "the authoring step points at the contract" \
  || no "the formula never mentions the contract it depends on"

echo
echo "WHERE PHI MAY GO"
# Whether PHI may reach a model is a BUSINESS AGREEMENT, not a property of the
# data. It lives in the catalog so a contract change is a dated, reviewable diff
# rather than an edit to a rule — and so the rule can refuse a lapsed one.
PV=$(mktemp -d)
python3 - "$PV" <<'PYEOF'
import sys, pathlib
T=sys.argv[1]
d = pathlib.Path("examples/appointments-chase.design").read_text()
pathlib.Path(f"{T}/leak.design").write_text(
    d.replace("eb-appointment-service | 1 | read the day's appointments",
              "eb-appointment-service | 1 4 | read the day's appointments"))
c = pathlib.Path("catalog/eb-tools.catalog").read_text()
pathlib.Path(f"{T}/covered.catalog").write_text(c)
pathlib.Path(f"{T}/nobaa.catalog").write_text(c.replace("phi_may_reach_models: yes","phi_may_reach_models: no"))
pathlib.Path(f"{T}/lapsed.catalog").write_text(c.replace("phi_model_review_by: 2027-10-06","phi_model_review_by: 2026-01-01"))
pathlib.Path(f"{T}/nodate.catalog").write_text(c.replace("phi_model_review_by: 2027-10-06","phi_model_review_by:"))
PYEOF
phisay() { # <catalog> <verdict> <rule> <ok> <no>
  local o; o=$(CATALOG="$PV/$1.catalog" "$HERE/tooling/validate.sh" "$PV/leak.design" 2>&1 || true)
  case "$(printf '%s' "$o" | sed 's/\x1b\[[0-9;]*m//g')" in
    *"$2  V31"*) ok "$3" ;;
    *) no "$4" ;;
  esac
}
phisay covered PASS "a model step may read PHI where the catalog records a covering agreement" \
                    "a covered model call was refused"
phisay nobaa FAIL "without a covering agreement, PHI reaching a model is refused" \
                  "PHI went to a model with nothing permitting it"
phisay lapsed FAIL "a lapsed attestation refuses, because designs cite a stale catalog" \
                   "an expired agreement still permitted PHI to reach a model"
phisay nodate FAIL "a permission with no review date is refused" \
                   "a permission nobody has to renew was accepted"
# The policy must not be hard-coded in the rule, or changing a contract means
# editing a validator.
grep -q 'phi_may_reach_models' "$HERE/tooling/lib/validate.awk" \
  && ok "V31 reads the policy from the catalog, not from itself" \
  || no "the PHI boundary is written into the rule, so a contract change edits code"
grep -q 'phi_may_reach_models' "$HERE/catalog/eb-tools.catalog" \
  && grep -q 'phi_model_review_by' "$HERE/catalog/eb-tools.catalog" \
  && ok "the catalog states where PHI may go, and when that must be re-attested" \
  || no "the catalog does not record the boundary it is the source of truth for"
grep -q 'UNRECORDED' "$HERE/catalog/eb-tools.catalog" \
  && ok "the unverified half of the agreement is flagged in the entry, not assumed away" \
  || no "an agreement nobody verified reads as a verified one"
rm -rf "$PV"

echo
echo "DECISION TABLES"
DT=$(mktemp -d)
cp "$HERE/examples/appointments-chase.design" "$DT/d.design"
cat >> "$DT/d.design" <<'DTEOF'

@decisions
table: flag-severity | unique
inputs: difference | category
outputs: action | who
- new | prescription | flag | the clinician before the visit
- new | otc | record | nobody
- stopped | prescription | flag | the clinician before the visit
- stopped | otc | record | nobody
- unresolved | - | escalate | the medical assistant
DTEOF
"$HERE/tooling/validate.sh" "$DT/d.design" >/dev/null 2>&1 \
  && ok "a design carrying a decision table passes its rules" \
  || no "a well-formed decision table was refused"

# The three questions a table can answer and a bash conditional cannot.
sed 's/^- new | otc | record | nobody/- new | - | record | nobody/' "$DT/d.design" > "$DT/ov.design"
dtsay() { # <design> <rule> <ok msg> <no msg> — refused BY that rule?
  local o; o=$("$HERE/tooling/validate.sh" "$1" 2>&1 || true)
  case "$(printf '%s' "$o" | sed 's/\x1b\[[0-9;]*m//g')" in
    *"FAIL  $2"*) ok "$3" ;;
    *) no "$4" ;;
  esac
}
dtsay "$DT/ov.design" V38 "two rules claiming the same input are caught — the overlap check" \
                          "an overlapping table passed under a unique policy"
sed 's/^- unresolved | - | escalate | the medical assistant/- unresolved | - | escalate/' "$DT/d.design" > "$DT/sh.design"
dtsay "$DT/sh.design" V37 "a short row is caught before it shifts every output one column left" \
                          "a row with the wrong cell count was accepted"
sed 's/^table: flag-severity | unique/table: flag-severity/' "$DT/d.design" > "$DT/nh.design"
dtsay "$DT/nh.design" V36 "a table with no hit policy is refused" \
                          "a table with no hit policy was accepted"

# Evaluating one.
DTR_OUT=$("$HERE/tooling/decide.sh" "$DT/d.design" -- new prescription 2>&1); RC=$?
[ "$RC" = 0 ] && printf '%s' "$DTR_OUT" | grep -q 'flag' \
  && ok "a table evaluates to its outputs" \
  || no "evaluating a table did not produce its outputs"
DTR_OUT=$("$HERE/tooling/decide.sh" "$DT/d.design" -- unresolved anything 2>&1); RC=$?
[ "$RC" = 0 ] && printf '%s' "$DTR_OUT" | grep -q 'escalate' \
  && ok "a dash matches any value in that column" \
  || no "the any-value cell did not match"
"$HERE/tooling/decide.sh" "$DT/d.design" -- renamed prescription >/dev/null 2>&1
[ $? -eq 1 ] && ok "a case nobody decided is a refusal, never a default" \
             || no "a fall-through did not refuse"
"$HERE/tooling/decide.sh" "$DT/d.design" -- new >/dev/null 2>&1
[ $? -eq 75 ] && ok "the wrong number of inputs exits 75 — could not run, not a business failure" \
              || no "a bad arity was reported as a business outcome"

# The payoff: a gate naming a table compiles to a WORKING check, not a stub.
python3 - "$DT/d.design" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
t = t.replace("5 | the drafted wording contains 1 or more patient identifiers | return it to step 3 and redact again",
              "5 | flag-severity yields action escalate | hand it to the medical assistant named on the worklist")
p.write_text(t)
PYEOF
"$HERE/tooling/validate.sh" "$DT/d.design" >/dev/null 2>&1 \
  && ok "a gate may name a table instead of prose, and still be checkable" \
  || no "a gate backed by a table failed V15"
sed 's/flag-severity yields action escalate/flag-severty yields action escalate/' "$DT/d.design" > "$DT/typo.design"
dtsay "$DT/typo.design" V39 "a gate naming a table that does not exist is refused" \
                            "a typo compiled to a check that evaluates nothing and refuses everything"
sed 's/yields action escalate/yields severity escalate/' "$DT/d.design" > "$DT/bo.design"
dtsay "$DT/bo.design" V39 "a gate naming an output the table does not have is refused" \
                          "a gate read a column that does not exist"

if "$HERE/tooling/compile.sh" "$DT/d.design" --name dt-t --out "$DT/o" >/dev/null 2>&1; then
  [ -f "$DT/o/.gc/scripts/decisions/flag-severity.tsv" ] \
    && ok "the table ships beside the checks that evaluate it" \
    || no "the compiled check has no table to read"
  [ -f "$DT/o/.gc/scripts/lib/dt-cell.awk" ] \
    && ok "the cell semantics ship with it, so the check cannot drift from the rules" \
    || no "the emitted check carries no definition of what a cell means"
  CK="$DT/o/.gc/scripts/checks/dt-t-g02.sh"
  grep -q 'NOT a stub' "$CK" \
    && ok "a table-backed gate compiles to working logic, not a stub" \
    || no "a table-backed gate still compiled to a stub"
  grep -q 'not implemented' "$DT/o/.gc/scripts/checks/dt-t-g01.sh" \
    && ok "a prose gate still compiles to a stub that says so" \
    || no "a prose gate silently pretended to be implemented"
  "$CK" U1 unresolved prescription >/dev/null 2>&1
  [ $? -eq 1 ] && ok "the generated check refuses when the table yields the gated value" \
               || no "the generated check did not refuse on escalate"
  "$CK" U1 new prescription >/dev/null 2>&1
  [ $? -eq 0 ] && ok "the generated check passes when it does not" \
               || no "the generated check refused a unit it should have passed"
  "$CK" U1 >/dev/null 2>&1
  [ $? -eq 75 ] && ok "the generated check exits 75 when it has no inputs to decide on" \
                || no "a check with nothing to evaluate reported a business failure"
else
  no "a design with a decision table did not compile"
fi
rm -rf "$DT"

echo
echo "REHEARSAL"
# A gate may be closed without a person, because "does the machinery work" and
# "is this design right" are different questions and blocking the first on the
# second parks a run for hours. What a rehearsal may NOT do is look like an
# approval afterwards.
RH=$(mktemp -d)
cp "$HERE/examples/appointments-chase.design" "$RH/d.design"
"$HERE/tooling/compile.sh" "$RH/d.design" --name rh-clean --out "$RH/o" >/dev/null 2>&1 \
  && ok "a run with no rehearsal compiles" \
  || no "a clean design did not compile, so the rehearsal test proves nothing"
printf '2026-10-06T00:00:00Z\twk-x\tgate\tthe assistant\ttesting\n' > "$RH/REHEARSAL"
"$HERE/tooling/compile.sh" "$RH/d.design" --name rh-dirty --out "$RH/o" >"$RH/c" 2>&1 \
  && no "a bundle was compiled out of a rehearsal" \
  || ok "compile refuses a run whose gates were closed without a person"
grep -q 'may not build out of one' "$RH/c" \
  && ok "the refusal says what a rehearsal is for, and what it is not" \
  || no "the refusal does not explain itself"
grep -q 'wk-x' "$RH/c" && grep -q 'the assistant' "$RH/c" \
  && ok "the refusal names which gate was rehearsed and by whom" \
  || no "the refusal does not name the rehearsed gate"
"$HERE/tooling/emit-bundle.sh" "$RH/d.design" --name rh-b --out "$RH/b" >/dev/null 2>&1 \
  && no "the bundle emitter built out of a rehearsal" \
  || ok "the bundle emitter refuses one too, not just the formula compiler"
# The mark is written before the gate closes, so a closed gate always has one.
grep -n 'REHEARSAL' "$HERE/tooling/rehearse-gate.sh" | head -1 >/dev/null
awk '/>> "\$ART\/REHEARSAL"/{m=NR} /gc bd close/{c=NR} END{exit !(m>0 && c>0 && m<c)}' \
  "$HERE/tooling/rehearse-gate.sh" \
  && ok "the mark is written before the gate is closed, never after" \
  || no "a gate could close with no mark beside it if the write failed"
grep -q 'REHEARSAL' "$HERE/tooling/accept.sh" \
  && ok "the acceptance register records a rehearsed signature as rehearsed" \
  || no "a rehearsal could be signed and read back as a real acceptance"
grep -q 'REHEARSAL' "$HERE/tooling/run-status.sh" \
  && ok "the status screen says when a run is a rehearsal" \
  || no "a rehearsal is invisible on the screen I report from"
rm -rf "$RH"

echo
echo "WHAT AN INSTALL CARRIES"
# Every script that reads a catalog falls back to one beside its own tooling. A
# rig synced without catalog/ holds whatever it had when it was last copied, and
# answers questions about a set of tools the run was never given. Found on
# 2026-10-06 with a four-entry catalog in the rig and a six-entry one in the run.
for d in checks tooling lib catalog tools; do
  grep -qE "^	@for d in .*$d.*; do" "$HERE/Makefile" \
    && ok "install-rig and install-city carry $d/" \
    || no "an install leaves $d/ behind, so the rig keeps a stale copy"
done

echo
echo "TOOL PERMISSIONS IN THE LEDGER"
PB=$(mktemp -d)
if "$HERE/tooling/emit-bundle.sh" "$HERE/examples/appointments-chase.design" \
     --name tp --out "$PB" >/dev/null 2>&1; then
  grep -q 'may not leave the covered boundary' "$PB"/tp/steps/*.sh \
    && ok "an emitted read carries the permission the catalog withheld" \
    || no "the bundle logs the data class and not what the tool may not do"
  # On the read row, not beside it: a permission on a row of its own can be
  # absent while the reads continue.
  grep -hE 'ledger .*read .*may not ' "$PB"/tp/steps/*.sh >/dev/null 2>&1 \
    && ok "the permission is on the read row, not a row of its own" \
    || no "the permission is recorded separately from the read it governs"
  # A tick proves it, rather than the grep above trusting the emitter.
  PD="$HERE/examples/appointments-chase.design"
  if BUNDLE_PATH="$PB/tp" DESIGN_PATH="$PD" CATALOG="$HERE/catalog/eb-tools.catalog" \
       "$HERE/checks/bundle-records.sh" >"$PB/out" 2>&1; then
    grep -q 'permissions: .* logged the restriction' "$PB/out" \
      && ok "a tick proves the restriction reached the ledger" \
      || no "the gate passed without confirming any permission was logged"
  else
    no "a correctly emitted bundle was refused by the records gate" "$(tail -2 "$PB/out")"
  fi
  # And it must refuse when the emitter drops it. The gate runs its own tick, so
  # the ledger is cleared first — otherwise correct rows from the build survive
  # and mask the defect.
  sed -i '' 's/; may not leave the covered boundary//' "$PB"/tp/steps/*.sh 2>/dev/null \
    || sed -i 's/; may not leave the covered boundary//' "$PB"/tp/steps/*.sh
  : > "$PB/tp/memory/ledger.tsv"
  if BUNDLE_PATH="$PB/tp" DESIGN_PATH="$PD" CATALOG="$HERE/catalog/eb-tools.catalog" \
       "$HERE/checks/bundle-records.sh" >"$PB/out2" 2>&1; then
    no "a bundle that reads a restricted tool and logs no restriction was accepted"
  else
    grep -q 'does not record what the catalog forbids' "$PB/out2" \
      && ok "a read with no permission on it is refused, and the gate says which tool" \
      || no "the refusal did not name the tool whose permission was missing"
  fi
else
  no "the worked example did not emit a bundle"
fi
rm -rf "$PB"

echo
echo "THE INTERVIEW"
IV=$(mktemp -d)
cat > "$IV/Q.md" <<'QEOF'
# Questions on test

interview: tooling/method/INTERVIEW.md v1
asked: 2026-10-06
catalog: catalog/eb-tools.catalog
use_case_sha256: deadbeef

Prose: with a colon in it, which the parser must ignore.

## Q1 — the unit of work
class: structural
asks: Is one unit one appointment, or one patient?
why: Everything downstream is costed per unit.
catalog: eb-appointment-service provides appointment_id, patient_ref
answer:

## Q2 — the thresholds
class: parametric
asks: What figure separates routine from escalation?
why: Every gate condition must carry a number.
answer:
QEOF
cp "$IV/Q.md" "$IV/base.md"

"$HERE/tooling/questions.sh" validate "$IV/Q.md" >/dev/null 2>&1 \
  && ok "a well-formed question set passes its rules" \
  || no "a well-formed question set was refused"
"$HERE/tooling/questions.sh" answered "$IV/Q.md" >/dev/null 2>&1 \
  && no "a set with every block open was reported as answered" \
  || ok "an open block is refused — silence is not one of the three answers"

# The three answers, each legal, each leaving different provenance.
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q1 stated --by "Buzz" --value "one appointment" >/dev/null 2>&1 \
  && ok "a stated answer is written" || no "a stated answer was refused"
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q2 delegated --by "Buzz" --value "48 hours" >/dev/null 2>&1 \
  && ok "you pick it is a legal answer" || no "a delegated answer was refused"
grep -q 'assumed: 48 hours' "$IV/Q.md" \
  && ok "a delegated answer records the value chosen on their behalf" \
  || no "a delegated answer did not carry what was assumed"
"$HERE/tooling/questions.sh" answered "$IV/Q.md" >/dev/null 2>&1 \
  && ok "a fully answered set passes" || no "a fully answered set was refused"

cp "$IV/base.md" "$IV/Q.md"
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q1 unanswered --by "Finance" >/dev/null 2>&1 \
  && ok "I do not know is a legal answer" || no "an unanswered answer was refused"
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q1 stated --by "Buzz" >/dev/null 2>&1 \
  && no "a stated answer with no value was accepted" \
  || ok "a stated answer with no value is refused — that is unanswered with the wrong label"
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q1 maybe --by "Buzz" --value x >/dev/null 2>&1 \
  && no "a fourth answer type was accepted" || ok "there are exactly three answer types"
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q1 stated --by "Buzz|x" --value y >/dev/null 2>&1 \
  && no "a pipe inside a field was accepted" || ok "a pipe cannot appear inside a field it separates"
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q9 stated --by "Buzz" --value y >/dev/null 2>&1 \
  && no "an answer to a question that does not exist was accepted" \
  || ok "an answer to a question nobody asked is refused"

# use_case_sha256 holds digits. A key pattern of letters alone drops it silently.
grep -q 'use_case_sha256' "$IV/Q.md" && \
  "$HERE/tooling/questions.sh" validate "$IV/Q.md" 2>&1 | grep -q 'PASS.*I1' \
  && ok "a header key containing digits is parsed, not treated as prose" \
  || no "use_case_sha256 was not read as a header key"

# A catalog line naming something nobody has is the interview inventing a tool.
sed 's|catalog: eb-appointment-service.*|catalog: eb-no-such-service provides everything|' "$IV/base.md" > "$IV/ghost.md"
"$HERE/tooling/questions.sh" validate "$IV/ghost.md" >/dev/null 2>&1 \
  && no "a question citing a tool the organization does not have was accepted" \
  || ok "the interview cannot invent a tool — none is the honest answer"

# The gate must not accept questions about a different description.
UC=$(mktemp); echo "a described process" > "$UC"
cp "$IV/base.md" "$IV/Q.md"
QUESTIONS_PATH="$IV/Q.md" USE_CASE_PATH="$UC" "$HERE/checks/questions-asked.sh" >/dev/null 2>&1 \
  && no "questions about a different use case passed the gate" \
  || ok "a question set about another description is refused by digest"
QUESTIONS_PATH="$IV/nothing.md" "$HERE/checks/questions-asked.sh" >/dev/null 2>&1
[ $? -eq 75 ] && ok "a missing question set exits 75 — could not run, not a bad design" \
              || no "a missing question set did not exit 75"
rm -f "$UC"

# V32-V34: the design is bound to the answers, and says how each was given.
cp "$IV/base.md" "$IV/Q.md"
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q1 stated --by "Buzz" --value "one appointment" >/dev/null 2>&1
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q2 delegated --by "Buzz" --value "48 hours" >/dev/null 2>&1
QSHA=$(shasum -a 256 "$IV/Q.md" | cut -d' ' -f1)
sed -e "s|^@meta|@meta\nquestions_sha256: $QSHA|" \
    -e "s|^@assumptions|@assumptions\n- [Q1] stated by Buzz: one appointment\n- [Q2] delegated by Buzz, who asked the system to choose: 48 hours|" \
    "$HERE/examples/appointments-chase.design" > "$IV/d.design"
QUESTIONS="$IV/Q.md" "$HERE/tooling/validate.sh" "$IV/d.design" >/dev/null 2>&1 \
  && ok "a design citing every question, with its provenance, passes V32-V34" \
  || no "a correctly cited design was refused"
"$HERE/tooling/validate.sh" "$IV/d.design" 2>&1 | grep -q 'WARN.*V32.*no question set' \
  && ok "a run with no question set is WARNED, never silently skipped" \
  || no "V32 skipped without saying so — a rule that quietly does not run"
sed 's|^questions_sha256: .*|questions_sha256: 0000|' "$IV/d.design" > "$IV/d2.design"
QUESTIONS="$IV/Q.md" "$HERE/tooling/validate.sh" "$IV/d2.design" >/dev/null 2>&1 \
  && no "a design bound to a different set of answers was accepted" \
  || ok "a design authored from other answers is refused by digest"
grep -v '^- \[Q2\]' "$IV/d.design" > "$IV/d3.design"
QUESTIONS="$IV/Q.md" "$HERE/tooling/validate.sh" "$IV/d3.design" >/dev/null 2>&1 \
  && no "a design that dropped an answered question was accepted" \
  || ok "a question answered and then dropped is refused"
sed 's|^- \[Q2\] delegated by Buzz, who asked the system to choose:|- [Q2] the system chose:|' "$IV/d.design" > "$IV/d4.design"
QUESTIONS="$IV/Q.md" "$HERE/tooling/validate.sh" "$IV/d4.design" >/dev/null 2>&1 \
  && no "an assumption hiding how it was answered was accepted" \
  || ok "an assumption must say whether it was stated, unanswered or delegated"

# A delegated structural choice reaches the person who signs.
cat > "$IV/v.json" <<'VEOF'
{"author_model":"m1","audit_model":"m2","verdict":"sound","confidence":"high","checked":["unit-of-work"],"defects":[]}
VEOF
# Q2 is parametric and stays delegated: delegating a threshold is the end of it.
"$HERE/tooling/findings.sh" "$IV/v.json" "$IV/d.design" --questions "$IV/Q.md" >/dev/null 2>&1
grep -q 'You delegated a structural choice' "$IV/FINDINGS.md" \
  && no "delegating a PARAMETRIC answer raised a finding — that is the interruption this avoids" \
  || ok "a delegated threshold is the end of it, and interrupts nobody"
# Q1 is structural. Delegating the unit of work is the highest-leverage decision
# in the system being handed over, and it must come back before anybody signs.
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q1 delegated --by "Buzz" --value "one appointment" >/dev/null 2>&1
"$HERE/tooling/findings.sh" "$IV/v.json" "$IV/d.design" --questions "$IV/Q.md" >/dev/null 2>&1
grep -q 'You delegated a structural choice' "$IV/FINDINGS.md" \
  && ok "a delegated structural choice becomes a finding before signing" \
  || no "a delegated structural choice never reached the approver"
grep -q 'Q1' "$IV/FINDINGS.md" && grep -q 'one appointment' "$IV/FINDINGS.md" \
  && ok "the finding names the question and what was assumed" \
  || no "the finding did not say what was chosen"
grep -q 'How the questions were answered' "$IV/FINDINGS.md" \
  && ok "the ratio of stated to delegated is reported at the gate" \
  || no "the gate does not report how the questions were answered"
# One synthetic answer among real ones is its own finding.
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q1 stated --by "Buzz" --value "one appointment" --synthetic >/dev/null 2>&1
"$HERE/tooling/findings.sh" "$IV/v.json" "$IV/d.design" --questions "$IV/Q.md" >/dev/null 2>&1
grep -q 'Answered synthetically' "$IV/FINDINGS.md" \
  && ok "an answer supplied on the owner's behalf is declared, not hidden" \
  || no "a synthetic answer was indistinguishable from a real one"
# A WHOLLY synthetic interview is one fact, not one per question. Fifteen copies
# of the same claim buried the two findings that needed a decision.
"$HERE/tooling/questions.sh" answer "$IV/Q.md" Q2 delegated --by "Buzz" --value "48 hours" --synthetic >/dev/null 2>&1
"$HERE/tooling/findings.sh" "$IV/v.json" "$IV/d.design" --questions "$IV/Q.md" >/dev/null 2>&1
[ "$(grep -c 'Answered synthetically' "$IV/FINDINGS.md")" = "0" ] \
  && grep -q 'CRITICAL.*Every answer in this interview' "$IV/FINDINGS.md" \
  && ok "an interview answered entirely by the system is one critical finding, not one per question" \
  || no "a wholly synthetic interview raised a finding per answer and buried the real ones"
# The brief is the page the approver reads. It must say who answered what.
BQ=$("$HERE/tooling/questions.sh" brief "$IV/Q.md")
printf '%s' "$BQ" | grep -q '^| | question | how it was answered | by |' \
  && ok "the brief renders the interview as a table" \
  || no "the brief table has no header"
# Count DATA rows, not every line beginning with a pipe: the header and the
# separator both do, so a threshold over all of them passes on an empty table.
[ "$(printf '%s\n' "$BQ" | grep -cE '^\| (\*\*)?Q[0-9]')" -eq 2 ] \
  && ok "every question reaches the brief, not just the header" \
  || no "the brief table came back empty — the rows were lost in quoting"
printf '%s' "$BQ" | grep -q '\*\*Q1\*\*' \
  && ok "a structural question is marked in the brief" \
  || no "structural and parametric look the same in the brief"
printf '%s' "$BQ" | grep -q 'synthetic' \
  && ok "the brief says which answers were supplied on the owner behalf" \
  || no "the brief hides synthetic answers"
grep -q 'questions_path' "$HERE/formulas/design-authoring.toml" \
  && grep -q 'brief.sh {{design_path}} --questions' "$HERE/formulas/design-authoring.toml" \
  && ok "the render step hands the brief its question set" \
  || no "the brief is written without the answers, so the acceptance screen is half a screen"
# ask: the half that makes the interview a conversation rather than a file format.
# base.md is the pristine copy: by this point Q.md is fully answered, and ask
# would correctly report that there is nothing left to ask.
A1=$("$HERE/tooling/questions.sh" ask "$IV/base.md" 2>&1)
printf '%s' "$A1" | grep -q '^Q1 ' \
  && ok "ask puts the first open STRUCTURAL question first" \
  || no "ask did not lead with a structural question"
printf '%s' "$A1" | grep -q 'stated' && printf '%s' "$A1" | grep -q 'unanswered' \
  && printf '%s' "$A1" | grep -q 'delegated' \
  && ok "ask shows all three answers every time, so none is forgotten" \
  || no "ask does not offer all three answer types"
printf '%s' "$A1" | grep -q 'why it matters' \
  && ok "ask says what the question blocks" \
  || no "a question with no stated consequence gets a shrug"
printf '%s' "$A1" | grep -q 'becomes a finding' \
  && ok "ask says a delegated structural answer comes back before signing" \
  || no "ask does not say why you pick it is safe to offer here"
AE=$("$HERE/tooling/questions.sh" ask "$IV/Q.md" 2>&1)
printf '%s' "$AE" | grep -q 'Nothing left to ask' \
  && ok "ask says so when every question has an answer" \
  || no "ask invents a question when none is open"
grep -q 'questions.sh ask' "$HERE/agents/mayor/prompt.template.md" \
  && grep -q 'questions.sh ask' "$HERE/formulas/design-authoring.toml" \
  && ok "the mayor and the formula both point at ask" \
  || no "ask exists and nothing tells anyone to use it"

# run-status is the screen I report from, so its blind spots are mine.
RS="$HERE/tooling/run-status.sh"
grep -q 'gc bd gate list' "$RS" \
  && ok "run-status reads gates from the gate list" \
  || no "run-status looks for gates in gc bd list, which never contains one"
grep -q 'waiting for a person' "$RS" \
  && ok "a run parked at a human gate says so" \
  || no "a parked run shows every step done and nothing about why it stopped"
grep -q 'questions-count.awk' "$RS" && [ -f "$HERE/tooling/lib/questions-count.awk" ] \
  && ok "run-status says how the questions were answered" \
  || no "run-status does not show whether the interview was real or a rehearsal"
QC=$(awk -f "$HERE/tooling/lib/questions.awk" -f "$HERE/tooling/lib/questions-count.awk" "$IV/Q.md")
printf '%s' "$QC" | grep -q 'SYNTHETIC' \
  && ok "a rehearsal interview is called one on the status screen" \
  || no "a synthetic interview is indistinguishable from a real one at a glance"
grep -q 'cd "$Q"' "$RS" \
  && ok "run-status stands in the rig before asking gc anything" \
  || no "run-status asks whatever city the caller happened to be standing in"
rm -rf "$IV"

echo
echo "FORMULA PREFLIGHT"
PT=$(mktemp -d); mkdir -p "$PT/rig"
# A rig with no checks is exactly the 2026-10-02 failure. It must be caught
# before a sling, not twenty-five minutes into one.
"$HERE/tooling/formula-preflight.sh" "$HERE/formulas/design-authoring.toml" "$PT/rig" \
  use_case_path=/x design_path=/x method_path=/x artifact_root=/x approver=a >"$PT/out" 2>&1
[ $? -eq 1 ] && ok "preflight refuses a rig with no checks" \
             || no "preflight passed a rig that has none of the checks"
grep -q 'checks/design-reviewed.sh' "$PT/out" \
  && ok "preflight names the check that would not resolve" \
  || no "preflight did not say which check was missing"
# The real rig has them, so the same call must pass.
"$HERE/tooling/formula-preflight.sh" "$HERE/formulas/design-authoring.toml" "$HERE" \
  use_case_path="$HERE/README.md" design_path="$HERE/README.md" \
  method_path="$HERE/tooling/method/GENERATE.md" tooling_root="$HERE/tooling" \
  checks_root="$HERE/checks" catalog_path="$HERE/catalog/eb-tools.catalog" \
  questions_path="$HERE/README.md" interview_path="$HERE/tooling/method/INTERVIEW.md" \
  artifact_root="$HERE" approver=a >/dev/null 2>&1
[ $? -eq 0 ] && ok "preflight passes when everything resolves" \
             || no "preflight refused a setup where every path exists"
# Paths resolving is not readiness. Every path resolved on wk-6c4, preflight
# passed, and authoring spent all three attempts because the audit provider had
# no credential — knowable in a second, before the run.
"$HERE/tooling/formula-preflight.sh" "$HERE/formulas/design-authoring.toml" "$HERE" \
  use_case_path="$HERE/README.md" design_path="$HERE/README.md" \
  method_path="$HERE/tooling/method/GENERATE.md" tooling_root="$HERE/tooling" \
  checks_root="$HERE/checks" artifact_root="$HERE" approver=a \
  questions_path="$HERE/README.md" interview_path="$HERE/tooling/method/INTERVIEW.md" \
  audit_provider=ptl-no-such-provider >"$PT/cap" 2>&1
[ $? -eq 1 ] && ok "preflight refuses a provider that is not installed" \
             || no "preflight passed a run whose audit provider does not exist"
grep -q 'NOT ready to sling' "$PT/cap" \
  && ok "preflight says plainly whether the run is ready" \
  || no "preflight gave no ready/not-ready verdict"

# A catalogued tool that does not answer is a source the run will discover is
# unreachable on attempt one, having already spent an attempt.
PFC=$(mktemp -d)
sed 's|via: tools/eb-appointment-service|via: tools/eb-not-installed|' "$HERE/catalog/eb-tools.catalog" > "$PFC/broken.catalog"
"$HERE/tooling/formula-preflight.sh" "$HERE/formulas/design-authoring.toml" "$HERE" \
  use_case_path="$HERE/README.md" design_path="$HERE/README.md" \
  method_path="$HERE/tooling/method/GENERATE.md" tooling_root="$HERE/tooling" \
  checks_root="$HERE/checks" catalog_path="$PFC/broken.catalog" \
  artifact_root="$HERE" approver=a >/dev/null 2>&1
[ $? -eq 1 ] && ok "preflight refuses a catalogued tool that does not answer" \
             || no "preflight passed a run whose catalogued tool is not installed"
rm -rf "$PFC"

# A required var with no value must be named, not silently defaulted.
"$HERE/tooling/formula-preflight.sh" "$HERE/formulas/design-authoring.toml" "$HERE" \
  approver=a >"$PT/out2" 2>&1
grep -q 'required var not supplied' "$PT/out2" \
  && ok "preflight names required vars that were not supplied" \
  || no "preflight accepted a formula with required vars missing"
rm -rf "$PT"

echo
echo "RUN REPORT"
RT=$(mktemp -d)
python3 - "$RT/t.jsonl" <<'PY_RT'
import json, sys
rows = [
 {"type":"assistant","timestamp":"2026-10-02T10:00:00Z","thinkingDurationMs":1000,
  "message":{"model":"m","usage":{"output_tokens":10},"content":[
    {"type":"tool_use","name":"Bash","input":{"command":"cat /tmp/a/thing.awk"}}]}},
 {"type":"assistant","timestamp":"2026-10-02T10:05:00Z",
  "message":{"model":"m","usage":{"output_tokens":10},"content":[
    {"type":"tool_use","name":"Bash","input":{"command":"sed -n 1,5p /tmp/a/thing.awk"}}]}},
]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows))
PY_RT
OUT=$("$HERE/tooling/run-report.sh" "$RT/t.jsonl" 2>&1)
case "$OUT" in
  *"2x  /tmp/a/thing.awk"*) ok "the report counts files opened through bash, not only Read" ;;
  *) no "a file catted twice was not reported as opened twice" ;;
esac
case "$OUT" in *"0:05:00"*) ok "the report gives wall-clock span" ;;
               *) no "the report did not compute elapsed time" ;; esac
case "$OUT" in *"1 re-read"*) ok "the report totals the avoidable re-reads" ;;
               *) no "the report did not total re-reads" ;; esac
rm -rf "$RT"

echo
echo "CHECK PATHS"
# A formula's check path is resolved relative to the RIG working directory. A
# path that names nothing is the dropped-gate bug with a declaration in front of
# it: on 2026-10-02 three checks were quarantined with "no such file or
# directory" and two steps closed anyway.
MISSING=""
for f in "$HERE"/formulas/*.toml; do
  for cp in $(grep -o 'path = "[^"]*"' "$f" | sed 's/path = "//; s/"//'); do
    case "$cp" in
      *'{{'*)   # bound at run time; what gets bound still has to exist here
        [ -e "$HERE/checks/$(basename "$cp")" ] \
          || MISSING="$MISSING $(basename "$f"):$(basename "$cp")(bound)"
        continue ;;
      /*) continue ;;
    esac
    [ -e "$HERE/$cp" ] || MISSING="$MISSING $(basename "$f"):$cp"
  done
done
if [ -z "$MISSING" ]; then
  ok "every check a formula names exists in this repo"
else
  no "formulas name checks that are not here:$MISSING"
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

# Existence is not enough: this assertion passed while the prompt pointed
# method_path at the FORMAT SPEC, and a live run was slung with it. The method
# is the document that tells the author what to do, and it says so in its title.
MPATH=$(grep -o -- '--var method_path=[^ ]*' "$MP" | head -1 | sed 's|.*--var method_path=||; s|\$HOME|'"$HOME"'|')
if [ -z "$MPATH" ]; then
  no "the prompt sets no method_path"
elif [ ! -f "$MPATH" ]; then
  no "the prompt points method_path at a file that is not there: $MPATH"
elif head -1 "$MPATH" | grep -qi '^# Method'; then
  ok "method_path names a method, not a format spec"
else
  no "method_path names $MPATH, whose title is not a method: $(head -1 "$MPATH")"
fi
echo

echo
echo "CREDENTIAL"
# The environment wins, and nothing is printed.
( . "$HERE/tooling/credential.sh"
  PTL_FAKE_KEY=already-set
  out=$(load_credential PTL_FAKE_KEY ptl-nonexistent-service 2>&1)
  [ -z "$out" ] ) \
  && ok "a credential already in the environment is used silently" \
  || no "load_credential was not quiet when the variable was already set"

# Absent everywhere: refuse, and say exactly how to fix it. Never invent a key.
CRED_OUT=$( . "$HERE/tooling/credential.sh"
            unset PTL_ABSENT_KEY
            load_credential PTL_ABSENT_KEY ptl-nonexistent-service-$$ 2>&1 )
CRED_RC=$?
if [ "$CRED_RC" -ne 0 ]; then
  ok "a missing credential is refused, not guessed"
else
  no "load_credential returned success with no credential anywhere"
fi
case "$CRED_OUT" in
  *add-generic-password*) ok "the refusal names the command that stores the key" ;;
  *) no "the refusal does not say how to store a key: $CRED_OUT" ;;
esac
case "$CRED_OUT" in
  *-w*) ok "the store command reads the key from a prompt, not from argv" ;;
  *) no "the store command would put the key on the command line" ;;
esac

# The controller's environment has no USER — it is set by login shells, not by
# launchd. Under set -u a bare "$USER" is fatal, and the audit died in 399ms
# reporting a locked keychain it had never reached.
NOUSER=$( env -u USER -u LOGNAME bash -c '
  set -u
  . "'"$HERE"'/tooling/credential.sh"
  load_credential PTL_NOUSER_KEY ptl-nonexistent-service-'"$$"' ' 2>&1 )
case "$NOUSER" in
  *"unbound variable"*) no "credential.sh dies on an unset USER, as under the controller" ;;
  *) ok "credential.sh survives an environment with no USER" ;;
esac
# And no script may reference a bare $USER, which is the same trap elsewhere.
# Strip comments first: a mention in a comment is not a dependency, and the same
# blunt grep once passed a commented-out #ledger call as a real one.
BAREUSER=""
for f in "$HERE"/tooling/*.sh "$HERE"/checks/*.sh; do
  sed 's/#.*//' "$f" 2>/dev/null | grep -q '"\$USER"' && BAREUSER="$BAREUSER $(basename "$f")"
done
[ -z "$BAREUSER" ] && ok "no script depends on \$USER being set" \
                   || no "these still use a bare \$USER: $BAREUSER"

# The agent runs with HOME set to the city directory. A keychain path built from
# $HOME therefore pointed at .../cities/ptl-city/Library/Keychains and found
# nothing, while the key sat in the real home the whole time. Three runs died on
# this, each reporting "no such item".
WRONGHOME=$( env -u GEMINI_API_KEY HOME=/tmp bash -c '
  . "'"$HERE"'/tooling/credential.sh"
  load_credential GEMINI_API_KEY ptl-nonexistent-service-'"$$"' 2>&1 | grep -o "/tmp/Library" ' )
[ -z "$WRONGHOME" ] \
  && ok "the keychain path does not come from \$HOME" \
  || no "credential.sh builds its keychain path from HOME, which the agent overrides"

# The gemini CLI is a node script with `#!/usr/bin/env node`. Under nvm it sits
# beside the node it was built for, and an older node first on PATH kills it with
# a SyntaxError before it prints anything. It must run with its own runtime.
grep -q 'GEM_BIN' "$HERE/tooling/audit-design.sh" \
  && ok "the audit pins the gemini CLI to its own node" \
  || no "audit-design.sh lets PATH decide which node runs the gemini CLI"
grep -q 'GEMINI_CLI_TRUST_WORKSPACE' "$HERE/tooling/audit-design.sh" \
  && ok "the audit runs the CLI headlessly without a trust prompt" \
  || no "the gemini CLI will refuse an untrusted directory and exit 55"

echo
echo "AUDIT FRESHNESS"
FX=$(mktemp -d)
printf '@meta\nuse_case: x\n' > "$FX/subject.txt"
SUBJ_SHA=$(shasum -a 256 "$FX/subject.txt" | awk '{print $1}')
DIMS="unit-of-work,judgment-isolated,gate-coverage,refusal-quality,evidence-chain,exit-criterion"
mkverdict() {  # $1 out, $2 sha-or-empty
  python3 - "$1" "$2" <<'PY3'
import json, sys
v = {"author_model":"model-a","audit_model":"model-b","verdict":"sound",
     "checked":["unit-of-work","judgment-isolated","gate-coverage",
                "refusal-quality","evidence-chain","exit-criterion"],
     "defects":[],"confidence":"high"}
if sys.argv[2]: v["subject_sha256"] = sys.argv[2]
json.dump(v, open(sys.argv[1],"w"))
PY3
}

mkverdict "$FX/fresh.json" "$SUBJ_SHA"
mkverdict "$FX/nosha.json" ""
mkverdict "$FX/wrong.json" "$(printf '0%.0s' $(seq 1 64))"

AUDIT_DIMENSIONS=$DIMS AUDIT_VERDICT=$FX/fresh.json ./checks/audit-verdict.sh >/dev/null 2>&1
[ $? -eq 75 ] && ok "the gate cannot run without AUDIT_SUBJECT and says so (75)" \
              || no "the gate ran without knowing what it was gating"

AUDIT_DIMENSIONS=$DIMS AUDIT_VERDICT=$FX/fresh.json AUDIT_SUBJECT=$FX/subject.txt \
  ./checks/audit-verdict.sh >/dev/null 2>&1
[ $? -eq 0 ] && ok "a verdict about the gated file passes" \
             || no "the gate refused a verdict that matches its subject"

AUDIT_DIMENSIONS=$DIMS AUDIT_VERDICT=$FX/nosha.json AUDIT_SUBJECT=$FX/subject.txt \
  ./checks/audit-verdict.sh >/dev/null 2>&1
[ $? -eq 1 ] && ok "a verdict naming no subject is refused" \
             || no "a verdict that cannot be tied to any file was accepted"

AUDIT_DIMENSIONS=$DIMS AUDIT_VERDICT=$FX/wrong.json AUDIT_SUBJECT=$FX/subject.txt \
  ./checks/audit-verdict.sh >/dev/null 2>&1
[ $? -eq 1 ] && ok "a verdict about a DIFFERENT file is refused" \
             || no "a stale verdict passed the gate — the 2026-10-02 failure"

# A provider that cannot run is infrastructure (75), never a defective design,
# and it must not touch the verdict already on disk.
cp "$FX/fresh.json" "$FX/keep.json"
AUDIT_PROVIDER=ptl-no-such-cli AUDIT_MODEL=m1 AUTHOR_MODEL=m2 \
  ./tooling/audit-design.sh "$FX/subject.txt" "$FX/subject.txt" "$FX/keep.json" >/dev/null 2>&1
RC=$?
[ "$RC" -eq 75 ] && ok "an audit that cannot run exits 75, not 1" \
                 || no "a provider that is not installed exited $RC, which reads as a bad design"
cmp -s "$FX/fresh.json" "$FX/keep.json" \
  && ok "a failed audit leaves the existing verdict untouched" \
  || no "a failed audit overwrote the verdict on disk"
rm -rf "$FX"

printf "  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
