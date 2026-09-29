#!/usr/bin/env bash
# design -> a standalone RPA bundle, plus a launchd job that runs it.
#
#   emit-bundle.sh <design> --name <bundle-name> [--out <dir>] [--checks <dir>] [--interval <sec>]
#
# The bundle does not need gc, a city, or a network. It ticks, it writes an
# append-only ledger and checksummed proof, and it exits with a code launchd
# can act on. Gates call the check scripts that were authored, self-tested and
# audited — not placeholders.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

DESIGN=""; NAME=""; OUT="bundles"; CHECKS=""; INTERVAL=3600
while [ $# -gt 0 ]; do
  case "$1" in
    --name)     NAME=${2:-}; shift 2 ;;
    --out)      OUT=${2:-}; shift 2 ;;
    --checks)   CHECKS=${2:-}; shift 2 ;;
    --interval) INTERVAL=${2:-}; shift 2 ;;
    -*) echo "emit-bundle.sh <design> --name <bundle-name> [--out <dir>] [--checks <dir>] [--interval <sec>]" >&2; exit 64 ;;
    *)  DESIGN=$1; shift ;;
  esac
done
[ -n "$DESIGN" ] && [ -n "$NAME" ] || { echo "emit-bundle.sh <design> --name <bundle-name> [--out <dir>] [--checks <dir>] [--interval <sec>]" >&2; exit 64; }
[ -f "$DESIGN" ] || { echo "REFUSED: no design at $DESIGN." >&2; exit 1; }
case "$NAME" in -*|*[!a-z0-9-]*) echo "REFUSED: --name must be lower case letters, digits and dashes." >&2
  echo "         Next human action: pass a name like invoice-reconciliation." >&2; exit 1 ;; esac
case "$INTERVAL" in ''|*[!0-9]*) echo "REFUSED: --interval must be whole seconds." >&2; exit 1 ;; esac

echo "  validating the design …"
if ! "$HERE/validate.sh" "$DESIGN" > /tmp/eb-design.$$ 2>&1; then
  sed 's/^/    /' /tmp/eb-design.$$; rm -f /tmp/eb-design.$$
  echo "REFUSED: the design does not pass its own rules, so no bundle was built." >&2
  echo "         Next human action: fix the design, then build again." >&2; exit 1
fi
rm -f /tmp/eb-design.$$

B="$OUT/$NAME"
rm -rf "$B"; mkdir -p "$B"/{steps,lib,checks,memory,proof,outbox,design,data}
cp "$DESIGN" "$B/design/loop.design"

PLAN=$(awk -f "$HERE/lib/parse.awk" -f "$HERE/lib/emit-plan.awk" "$DESIGN")
m() { printf '%s\n' "$PLAN" | awk -F'\t' -v k="$1" '$1=="meta" && $2==k {print $3}'; }
USE_CASE=$(m use_case); APPROVER=$(m approver); UNIT_DEF=$(m unit)
FANOUT=$(m fanout); EVID_STEP=$(m evidence_step); INTEGRITY=$(m integrity); EXITC=$(m exit)
GATES=$(printf '%s\n' "$PLAN" | awk -F'\t' '$1=="gate"' | wc -l | tr -d ' ')

# ---------------------------------------------------------------- config.sh
cat > "$B/config.sh" <<EOF
#!/usr/bin/env bash
# Every tunable in one file. No step invents a number of its own.
ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
MEM="\$ROOT/memory"; OUTBOX="\$ROOT/outbox"; PROOF="\$ROOT/proof"; CHECKS="\$ROOT/checks"

# From the design:
APPROVER="\${APPROVER:-$APPROVER}"
FANOUT="\${FANOUT:-$FANOUT}"
EXIT_CRITERION="$EXITC"

# Where the work comes from. A tick reads this and writes one row per unit worked.
UNITS_IN="\${UNITS_IN:-\$ROOT/data/units.tsv}"

. "\$ROOT/lib/say.sh"
mkdir -p "\$MEM" "\$OUTBOX" "\$PROOF"
EOF

cat > "$B/lib/say.sh" <<'EOF'
#!/usr/bin/env bash
# What a step prints. The TYPE is on the line on purpose: watching a tick should show
# the shape of the process — how much is a rule, and how little is judgment.
if [ -t 1 ]; then
  C_MECH=$'\033[32m'; C_COORD=$'\033[33m'; C_THINK=$'\033[35m'
  C_TEST=$'\033[36m'; C_GATE=$'\033[33m'; C_OFF=$'\033[0m'
else
  C_MECH=""; C_COORD=""; C_THINK=""; C_TEST=""; C_GATE=""; C_OFF=""
fi
step_say() {
  local c=""
  case "$3" in
    mechanical) c="$C_MECH" ;; coordination) c="$C_COORD" ;;
    thinking)   c="$C_THINK" ;; test)        c="$C_TEST"  ;;
    gate)       c="$C_GATE" ;;
  esac
  printf '  %2s %-22.22s %s%-14s%s %s\n' "$1" "$2" "$c" "[$3]" "$C_OFF" "$4"
}
EOF

cat > "$B/lib/ledger.sh" <<'EOF'
#!/usr/bin/env bash
# The append-only ledger. One line per transition, written by code only.
# You are not storing where the work is. You are storing how it got there.
ledger() { printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%FT%T)" "$1" "$2" "$3" "${4:-}" >> "$MEM/ledger.tsv"; }
ledger_init() { [ -f "$MEM/ledger.tsv" ] || printf 'timestamp\tunit\tstep\tstatus\tdetail\n' > "$MEM/ledger.tsv"; }
unit_row() { printf '%s\t%s\t%s\t%s\n' "$(date +%FT%T)" "$1" "$2" "${3:-}" >> "$MEM/units.tsv"; }
unit_init() { [ -f "$MEM/units.tsv" ] || printf 'timestamp\tunit\toutcome\tdecided_by\n' > "$MEM/units.tsv"; }
EOF

# ---------------------------------------------------------------- the steps
BATCH=""; UNITSTEPS=""
while IFS=$'\t' read -r _ ID SLUG TYPE ACTOR DESC SCOPE; do
  [ -n "${ID:-}" ] || continue
  F="$B/steps/$ID-$SLUG.sh"
  GCOND=$(printf '%s\n' "$PLAN" | awk -F'\t' -v i="$ID" '$1=="gate" && $2==i {print $3; exit}')
  GREF=$(printf '%s\n'  "$PLAN" | awk -F'\t' -v i="$ID" '$1=="gate" && $2==i {print $4; exit}')
  GN=""
  if [ -n "$GCOND" ]; then
    GN=$(printf '%s\n' "$PLAN" | awk -F'\t' -v i="$ID" '$1=="gate"{n++; if($2==i){printf "%02d", n; exit}}')
  fi
  case "$SCOPE" in batch) BATCH="$BATCH $ID-$SLUG" ;; *) UNITSTEPS="$UNITSTEPS $ID-$SLUG" ;; esac

  NOTE="a step of the process"
  case "$TYPE" in
    mechanical)   NOTE="a rule: same input, same output, no tokens" ;;
    coordination) NOTE="binds, routes, records — it decides nothing" ;;
    test)         NOTE="runs the real check against the before-state" ;;
    thinking)     NOTE="the one question a rule cannot answer" ;;
    gate)         NOTE="permits or refuses — the condition lives in a check script" ;;
  esac

  { cat <<EOF
#!/usr/bin/env bash
# STEP $ID — $SLUG
# TYPE:  $TYPE   ($NOTE)
# ACTOR: $ACTOR
# SCOPE: $SCOPE
#
# From the design:
#   $DESC
set -euo pipefail
source "\$(dirname "\$0")/../config.sh"
source "\$(dirname "\$0")/../lib/ledger.sh"; ledger_init; unit_init
UNIT="\${1:--}"
VALUE="\${2:-}"
EOF
  } > "$F"

  if [ -n "$GCOND" ]; then
    cat >> "$F" <<EOF

# THIS STEP CARRIES A GATE. The design attaches one to step $ID.
#
# THE CONDITION, from the design:
#   $GCOND
#
# THE REFUSAL, from the design:
#   $GREF
#
# The condition is not written here and it is not written in a prompt. It lives in
# the check script below, which was authored, self-tested against fixtures, and
# audited by a second model before it was installed.
CHECK="\$CHECKS/$NAME-g$GN.sh"

refuse() {
  { echo "# REFUSED — \$UNIT"
    echo
    echo "**Why this stopped:** $GCOND"
    echo
    echo "**Next human action:** $GREF"
    echo
    echo "Assigned to: \$APPROVER"
  } > "\$OUTBOX/\$UNIT.REFUSED.md"
  ledger "\$UNIT" "$SLUG" refused "gate $GN"
  unit_row "\$UNIT" refused "gate $GN"
  step_say "$ID" "$SLUG" "gate" "REFUSED — $GREF"
  exit 1
}

if [ ! -x "\$CHECK" ]; then
  ledger "\$UNIT" "$SLUG" refused "check script missing: \$CHECK"
  unit_row "\$UNIT" refused "gate $GN — no check installed"
  step_say "$ID" "$SLUG" "gate" "REFUSED — no check script at \$CHECK"
  echo "REFUSED: gate $GN names a check that is not installed." >&2
  echo "         Next human action: build the check, then rebuild the bundle." >&2
  exit 1
fi

set +e
"\$CHECK" "\$UNIT" "\$VALUE"
CODE=\$?
set -e
case "\$CODE" in
  0)  : ;;                       # the condition does not hold — work continues
  75) ledger "\$UNIT" "$SLUG" deferred "check could not run"
      unit_row "\$UNIT" deferred "gate $GN — the check could not run"
      step_say "$ID" "$SLUG" "gate" "DEFERRED — the check could not run"
      exit 75 ;;                 # not a verdict; launchd sees a distinct code
  *)  refuse ;;
esac

ledger "\$UNIT" "$SLUG" proceed "gate $GN passed"
step_say "$ID" "$SLUG" "$TYPE" "proceed"
EOF
  else
    cat >> "$F" <<EOF

# ------------------------------------------------------------------ YOUR LOGIC
# TODO: what this step does. $TYPE work goes here, and nothing else.
RESULT="ok"
# -----------------------------------------------------------------------------
EOF
    if [ "$ID" = "$EVID_STEP" ]; then
      cat >> "$F" <<EOF

# This step writes the proof. The design names it, and nothing that reasons may
# write its own evidence.
P="\$PROOF/\$UNIT.proof"
{ echo "unit: \$UNIT"; echo "written: \$(date +%FT%T)"; echo "by: step $ID ($SLUG)"; } > "\$P"
if command -v shasum >/dev/null; then shasum -a 256 "\$P" | cut -d' ' -f1 > "\$P.sha256"; fi
ledger "\$UNIT" "$SLUG" proved "$INTEGRITY"
EOF
    fi
    cat >> "$F" <<EOF
ledger "\$UNIT" "$SLUG" "\$RESULT" "step $ID, $TYPE"
step_say "$ID" "$SLUG" "$TYPE" "\$RESULT"
EOF
  fi
  chmod +x "$F"
done <<EOF
$(printf '%s\n' "$PLAN" | awk -F'\t' '$1=="step"')
EOF

# ---------------------------------------------------------------- the checks
WIRED=0
if [ -n "$CHECKS" ] && [ -d "$CHECKS" ]; then
  for f in "$CHECKS"/*-g[0-9][0-9].sh; do
    [ -e "$f" ] || continue
    base=$(basename "$f"); n=${base##*-g}; n=${n%.sh}
    cp "$f" "$B/checks/$NAME-g$n.sh"; chmod +x "$B/checks/$NAME-g$n.sh"
    [ -f "${f%.sh}.fixtures.tsv" ] && cp "${f%.sh}.fixtures.tsv" "$B/checks/$NAME-g$n.fixtures.tsv"
    WIRED=$((WIRED+1))
  done
fi

# ---------------------------------------------------------------- sample units
cat > "$B/data/units.tsv" <<'EOF'
unit	value
U-001	1500
U-002	2500
U-003	900
EOF

# ---------------------------------------------------------------- run.sh
cat > "$B/run.sh" <<EOF
#!/usr/bin/env bash
# One tick. Batch steps run once; unit steps run once per unit.
#
# Exit codes, so launchd can act on them:
#   0   the tick completed; refusals are an outcome, not a failure
#   1   a step failed for a reason that is not a refusal
#   75  a check could not run — infrastructure, not business
set -uo pipefail
cd "\$(dirname "\$0")"
source ./config.sh
source ./lib/ledger.sh; ledger_init; unit_init

echo "=== $NAME — \$(date +%FT%T) ==="
for s in$BATCH; do
  ./steps/\$s.sh "-" || { echo "batch step \$s failed"; exit 1; }
done

worked=0; refused=0; delivered=0; deferred=0
while IFS=\$'\t' read -r unit value; do
  case "\$unit" in unit|''|\\#*) continue ;; esac
  worked=\$((worked+1))
  echo
  echo "\$unit"
  ok=1
  for s in$UNITSTEPS; do
    ./steps/\$s.sh "\$unit" "\$value"; code=\$?
    if [ "\$code" = 75 ]; then deferred=\$((deferred+1)); ok=0; break; fi
    if [ "\$code" != 0 ]; then refused=\$((refused+1)); ok=0; break; fi
  done
  [ "\$ok" = 1 ] && { delivered=\$((delivered+1)); unit_row "\$unit" delivered "the process"; }
done < "\$UNITS_IN"

echo
echo "=== worked \$worked   delivered \$delivered   refused \$refused   deferred \$deferred ==="
echo "    ledger in memory/ledger.tsv   proof in proof/   refusals in outbox/"
echo "    exit criterion: \$EXIT_CRITERION"
[ "\$deferred" -eq 0 ] || exit 75
exit 0
EOF
chmod +x "$B/run.sh"

# ---------------------------------------------------------------- launchd
LABEL="com.process-to-loop.$NAME"
cat > "$B/$LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>                 <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>BUNDLE_PATH/run.sh</string>
  </array>
  <key>WorkingDirectory</key>      <string>BUNDLE_PATH</string>
  <key>StartInterval</key>         <integer>$INTERVAL</integer>
  <key>RunAtLoad</key>             <false/>
  <key>StandardOutPath</key>       <string>BUNDLE_PATH/memory/launchd.out.log</string>
  <key>StandardErrorPath</key>     <string>BUNDLE_PATH/memory/launchd.err.log</string>
  <key>ProcessType</key>           <string>Background</string>
</dict>
</plist>
EOF
ABS=$(cd "$B" && pwd)
sed -i.bak "s|BUNDLE_PATH|$ABS|g" "$B/$LABEL.plist" && rm -f "$B/$LABEL.plist.bak"

cat > "$B/Makefile" <<'EOF'
tick:    ; @./run.sh
report:  ; @column -t -s'	' memory/units.tsv 2>/dev/null || cat memory/units.tsv
ledger:  ; @column -t -s'	' memory/ledger.tsv 2>/dev/null || cat memory/ledger.tsv
refusals:; @ls -1 outbox/*.REFUSED.md 2>/dev/null || echo "none"
clean:   ; @rm -rf memory proof outbox && echo "cleaned — the design and the checks are kept"
.PHONY: tick report ledger refusals clean
EOF

cat > "$B/README.md" <<EOF
# $NAME

$USE_CASE

Built from \`design/loop.design\` by process-to-loop. Do not edit the steps by hand —
edit the design and build again.

**Unit of work:** $UNIT_DEF
**Approver:** $APPROVER
**Exit criterion:** $EXITC

## Run it

\`\`\`bash
./run.sh          # one tick
make report       # what happened, per unit
make ledger       # every transition
\`\`\`

## Schedule it

\`\`\`bash
cp $LABEL.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/$LABEL.plist
launchctl list | grep $NAME
\`\`\`

Every $INTERVAL seconds. Logs land in \`memory/launchd.*.log\`. Unload with
\`launchctl unload ~/Library/LaunchAgents/$LABEL.plist\`.

## What it needs

Bash and awk. No gc, no city, no network.
EOF

# ---------------------------------------------------------------- build guard
BUILT=$(grep -l 'CHECK="\$CHECKS' "$B"/steps/*.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "$BUILT" != "$GATES" ]; then
  rm -rf "$B"
  echo "REFUSED: the design has $GATES gate(s) and only $BUILT reached the bundle." >&2
  echo "         Nothing was left behind. Next human action: report this — a control was dropped." >&2
  exit 1
fi

echo
echo "  $B/"
echo "    run.sh            one tick, no gc and no network"
echo "    steps/            $(ls "$B/steps" | wc -l | tr -d ' ') steps from the design"
echo "    checks/           $WIRED of $GATES gate(s) wired to an installed check"
echo "    $LABEL.plist"
echo
if [ "$WIRED" -lt "$GATES" ]; then
  echo "  $((GATES-WIRED)) gate(s) have no check installed. The bundle refuses those units"
  echo "  rather than passing them. Build the checks, then build the bundle again."
  echo
fi
echo "  Next:  cd $B && ./run.sh"
echo "         then cp $LABEL.plist ~/Library/LaunchAgents/ && launchctl load ~/Library/LaunchAgents/$LABEL.plist"
