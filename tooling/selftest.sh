#!/usr/bin/env bash
# Run a candidate check script against its fixtures. Deterministic: no model.
#
#   selftest.sh <check-script> <fixtures.tsv>
#
# The fixture table says what each input must do. This runs the script and
# compares. It is the cheap half of verifying a gate, and it should run before
# anyone spends a token on an audit.
set -uo pipefail
SCRIPT=${1:-}; FIX=${2:-}
[ -n "$SCRIPT" ] && [ -n "$FIX" ] || { echo "selftest.sh <check-script> <fixtures.tsv>" >&2; exit 64; }
[ -f "$SCRIPT" ] || { echo "REFUSED: no check script at $SCRIPT." >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "REFUSED: $SCRIPT is not executable." >&2
                      echo "         Next human action: chmod +x $SCRIPT" >&2; exit 1; }
[ -f "$FIX" ] || { echo "REFUSED: no fixtures at $FIX." >&2; exit 1; }

G="\033[32m"; R="\033[31m"; Y="\033[33m"; Z="\033[0m"
pass=0; fail=0; undeclared=0

while IFS=$'\t' read -r name value expect why; do
  case "${name:-}" in ""|\#*|name) continue ;; esac
  case "$expect" in
    declare)
      undeclared=$((undeclared+1))
      printf "  ${Y}DECLARE${Z}  %-12s %s\n" "$name" "$why" ;;
    proceed|refuse)
      out=$("$SCRIPT" "$value" 2>&1); code=$?
      if [ "$code" = 75 ] && [ "$name" != "unreadable" ]; then
        fail=$((fail+1))
        printf "  ${R}FAIL${Z}     %-12s exited 75 on a business case. 75 means the check could not run.\n" "$name"
      elif [ "$expect" = proceed ] && [ "$code" = 0 ]; then
        pass=$((pass+1)); printf "  ${G}PASS${Z}     %-12s proceeded, as the fixture requires\n" "$name"
      elif [ "$expect" = refuse ] && [ "$code" != 0 ]; then
        pass=$((pass+1)); printf "  ${G}PASS${Z}     %-12s refused, as the fixture requires\n" "$name"
        case "$out" in *REFUSE*|*refus*) : ;; *)
          printf "           %-12s but the refusal says nothing a person can act on\n" "" ;; esac
      else
        fail=$((fail+1))
        printf "  ${R}FAIL${Z}     %-12s expected %s, exited %s\n" "$name" "$expect" "$code"
        [ -n "$out" ] && printf "           %s\n" "$(echo "$out" | head -1)"
      fi ;;
  esac
done < "$FIX"

echo
if [ "$undeclared" -gt 0 ]; then
  printf "  %d passed, %d failed, %d still undeclared\n" "$pass" "$fail" "$undeclared"
  echo "  REFUSED: a boundary nobody has decided is a bug waiting for the first real unit." >&2
  echo "           Next human action: edit $FIX and change every declare to proceed or refuse." >&2
  exit 1
fi
printf "  %d passed, %d failed\n" "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
