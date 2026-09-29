#!/usr/bin/env bash
# Run a candidate step script against the properties its declared type promises.
# Deterministic: no model.
#
#   step-selftest.sh <step-script> <properties.tsv> [--bundle <dir>]
#
# A gate is checked against values. A step is checked against properties, because
# its type is a promise about what the code may do and the promise is testable.
set -uo pipefail
S=${1:-}; P=${2:-}; BUNDLE=""
shift 2 2>/dev/null || true
while [ $# -gt 0 ]; do case "$1" in --bundle) BUNDLE=${2:-}; shift 2 ;; *) shift ;; esac; done
[ -n "$S" ] && [ -n "$P" ] || { echo "step-selftest.sh <step-script> <properties.tsv> [--bundle <dir>]" >&2; exit 64; }
[ -f "$S" ] || { echo "REFUSED: no step script at $S." >&2; exit 1; }
[ -x "$S" ] || { echo "REFUSED: $S is not executable. Next human action: chmod +x $S" >&2; exit 1; }
[ -f "$P" ] || { echo "REFUSED: no properties at $P." >&2; exit 1; }
[ -n "$BUNDLE" ] || BUNDLE=$(cd "$(dirname "$S")/.." && pwd)

G="\033[32m"; R="\033[31m"; Y="\033[33m"; Z="\033[0m"
pass=0; fail=0; skip=0
ok()   { pass=$((pass+1)); printf "  ${G}PASS${Z}  %-16s %s\n" "$1" "$2"; }
bad()  { fail=$((fail+1)); printf "  ${R}FAIL${Z}  %-16s %s\n" "$1" "$2"; }
note() { skip=$((skip+1)); printf "  ${Y}MANUAL${Z} %-16s %s\n" "$1" "$2"; }

SRC=$(cat "$S")
PROVIDERS='claude|openai|anthropic|gpt-|curl -|wget |llm |ollama'

while IFS=$'\t' read -r prop rule why; do
  case "${prop:-}" in ""|\#*|property) continue ;; esac
  case "$prop" in

    contract)
      if grep -qE '^\s*(UNIT|unit)=.*\$\{?1' <<<"$SRC" && grep -qE '^\s*(VALUE|value)=.*\$\{?2' <<<"$SRC"
      then ok "$prop" "reads \$1 as the unit and \$2 as the value"
      else bad "$prop" "does not read \$1 as the unit and \$2 as the value"; fi ;;

    ledger)
      n=$(grep -cE '(^|[^a-z_])ledger[ "]' <<<"$SRC")
      exits=$(grep -cE '^\s*exit [1-9]' <<<"$SRC")
      if [ "$n" -ge 1 ] && [ "$n" -gt "$((exits-1))" ]
      then ok "$prop" "$n ledger call(s) against $exits non-zero exit(s)"
      else bad "$prop" "$n ledger call(s) but $exits non-zero exit(s) — a path returns silently"; fi ;;

    no-model)
      if grep -qiE "$PROVIDERS" <<<"$SRC"
      then bad "$prop" "calls a provider, and its type says it is a rule"
      else ok "$prop" "no provider call"; fi ;;

    is-model)
      n=$(grep -ciE "$PROVIDERS" <<<"$SRC")
      if [ "$n" -eq 0 ]; then bad "$prop" "its type says it reasons, and it calls nothing"
      elif [ "$n" -gt 1 ]; then bad "$prop" "$n provider calls; the design names one judgment"
      else ok "$prop" "exactly one provider call"; fi ;;

    records-cost)
      if grep -qE 'usage\.tsv|log-cost' <<<"$SRC"
      then ok "$prop" "writes a usage row"
      else bad "$prop" "spends tokens and records no usage"; fi ;;

    confinement)
      strayed=$(grep -oE '>[ ]*"?\$(ROOT|BUNDLE)?/?[A-Za-z_./$-]+' <<<"$SRC" \
                | grep -vE 'MEM|PROOF|OUTBOX|memory|proof|outbox|/dev/null|/dev/stderr|\$P\b' | head -3)
      if [ -z "$strayed" ]
      then ok "$prop" "writes only where it is allowed"
      else bad "$prop" "writes outside memory/, proof/ and outbox/: $(tr '\n' ' ' <<<"$strayed")"; fi ;;

    no-proof)
      if grep -qE '\$PROOF' <<<"$SRC"
      then bad "$prop" "writes evidence, and the design names a different step as the writer"
      else ok "$prop" "does not write evidence"; fi ;;

    writes-proof)
      if grep -qE '\$PROOF' <<<"$SRC" && grep -qE 'shasum|sha256' <<<"$SRC"
      then ok "$prop" "writes the proof and a checksum"
      else bad "$prop" "the design names this step the writer, and it writes no checksummed proof"; fi ;;

    determinism)
      A=$(cd "$BUNDLE" && "$S" "U-DET" "1" 2>&1); ca=$?
      B=$(cd "$BUNDLE" && "$S" "U-DET" "1" 2>&1); cb=$?
      if [ "$ca" = "$cb" ] && [ "$A" = "$B" ]
      then ok "$prop" "two runs, identical output and exit $ca"
      else bad "$prop" "two runs differed — exits $ca and $cb"; fi ;;

    batch-scope)
      if grep -qE '\$\{?1' <<<"$SRC" && ! grep -qE 'UNIT="\$\{1:--\}"' <<<"$SRC"
      then note "$prop" "read the code: a batch step must not depend on a unit"
      else ok "$prop" "does not require a unit"; fi ;;

    unit-scope|before-state|quotes-evidence|is-human)
      note "$prop" "$rule — judgment, for the audit lane and the person" ;;

    *) note "$prop" "$rule" ;;
  esac
done < "$P"

echo
printf "  %d passed, %d failed, %d for a person\n" "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] || exit 1
