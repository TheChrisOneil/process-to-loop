#!/usr/bin/env bash
# Set up (or bring up to date) a Mac for process-to-loop and its Gas City city.
#
#   ./setup-machine.sh            # tools, repos, city, rig, start, test
#   NO_START=1 ./setup-machine.sh # everything except gc start and the live tests
#
# Safe to re-run: every step checks before it acts. It never signs in for you,
# never force-pushes, never deletes a city, and never answers Claude Code's
# folder-trust prompt (that one is yours; see the end of the run).
#
# Fresh machine, before this repo exists:
#   gh auth login && gh repo clone TheChrisOneil/process-to-loop ~/software/process-to-loop \
#     && ~/software/process-to-loop/setup-machine.sh
#
# Layout and the reasons behind each step: HANDOFF.md and docs/standing-up-a-city.md.
set -uo pipefail

SOFTWARE_DIR=${SOFTWARE_DIR:-$HOME/software}
CITIES_DIR=${CITIES_DIR:-$HOME/cities}
CITY_NAME=${CITY_NAME:-ptl-city}
RIG_DIRNAME=${RIG_DIRNAME:-ptl-rig}
CITY=$CITIES_DIR/$CITY_NAME
RIG=$CITIES_DIR/$RIG_DIRNAME
PTL=${PTL_DIR:-$SOFTWARE_DIR/process-to-loop}
UPSTREAM=${UPSTREAM_DIR:-$SOFTWARE_DIR/Github/gascity-upstream}
PR_BRANCHES=${PR_BRANCHES:-"feat/contrib-pack-capability-diff:wt-contrib-pack-capability-diff feat/doctor-pack-capability-checks:wt-doctor-capability"}

# The pins both machines run. Change them here, deliberately, in one commit.
GASCITY_PIN=sha:f895c0ff47d6ee9334ed282a416387eb5b084d24
PACKS_PIN=sha:2e7ec4c5598173ff00c20a2048ef28d4202bd38a
RIG_REMOTE=TheChrisOneil/ptl-rig

G="\033[32m"; R="\033[31m"; Y="\033[33m"; B="\033[1m"; Z="\033[0m"
FAILS=0; WARNS=0; TODO=()
step() { printf "\n${B}== %s${Z}\n" "$*"; }
ok()   { printf "  ${G}ok${Z}    %s\n" "$*"; }
warn() { WARNS=$((WARNS+1)); printf "  ${Y}warn${Z}  %s\n" "$*"; }
fail() { FAILS=$((FAILS+1)); printf "  ${R}FAIL${Z}  %s\n" "$*"; }
die()  { printf "  ${R}STOP${Z}  %s\n" "$*"; exit 1; }
todo() { TODO+=("$*"); }

# ---------------------------------------------------------------------------
step "1. Tools"
[ "$(uname -s)" = Darwin ] || warn "written for macOS; continuing"
command -v brew >/dev/null || die "Homebrew is missing. Install it from https://brew.sh, then re-run."
need=()
for f in gh go tmux dolt jq icu4c gascity beads; do
  case $f in gascity) c=gc ;; beads) c=bd ;; icu4c) c="" ;; *) c=$f ;; esac
  if [ -n "$c" ]; then command -v "$c" >/dev/null || need+=("$f")
  else ls -d "$(brew --prefix)"/opt/icu4c* >/dev/null 2>&1 || need+=("$f"); fi
done
if [ ${#need[@]} -gt 0 ]; then
  if [ "${SKIP_BREW:-0}" = 1 ]; then warn "missing (SKIP_BREW=1): ${need[*]}"
  else echo "  installing: ${need[*]}"; brew install "${need[@]}" || die "brew install failed"; fi
fi
for c in gh go tmux dolt jq gc bd; do command -v $c >/dev/null && ok "$c $( ($c --version 2>/dev/null || $c version 2>/dev/null) | head -1)"; done
command -v claude >/dev/null && ok "claude $(claude --version 2>/dev/null | head -1)" \
  || { warn "Claude Code CLI not found"; todo "Install Claude Code, then run: claude   (sign in)"; }
command -v gemini >/dev/null && ok "gemini $(gemini --version 2>/dev/null | head -1)" \
  || { warn "gemini CLI not found (the city's audit lane uses it)"; todo "Install Node 22 (nvm), then: npm i -g @google/gemini-cli && gemini   (sign in)"; }
command -v python3.13 >/dev/null && ok "python3.13 (gascity repo-tree scripts)" \
  || warn "python3.13 not found — only needed for gascity's tools/bazel/repo_tree.py"
gh auth status >/dev/null 2>&1 && ok "gh is signed in" \
  || die "gh is not signed in. Run: gh auth login   (you do this; the script never signs in). Then re-run."

# cgo needs ICU on macOS, or gascity's go test fails with 'unicode/regex.h' not found.
if ! grep -q 'CGO_CPPFLAGS=.*icu4c' "$HOME/.zshrc" 2>/dev/null; then
  { echo ''; echo '# gascity cgo build (ICU), added by process-to-loop/setup-machine.sh'
    echo 'export CGO_CPPFLAGS="-I$(brew --prefix icu4c)/include"'
    echo 'export CGO_LDFLAGS="-L$(brew --prefix icu4c)/lib"'; } >> "$HOME/.zshrc"
  ok "added ICU build flags to ~/.zshrc"
else ok "ICU build flags already in ~/.zshrc"; fi
export CGO_CPPFLAGS="-I$(brew --prefix icu4c)/include" CGO_LDFLAGS="-L$(brew --prefix icu4c)/lib"

# ---------------------------------------------------------------------------
# clone_or_update <owner/repo> <dir>: clone if absent; else fast-forward only.
clone_or_update() {
  local repo=$1 dir=$2
  if [ ! -d "$dir/.git" ]; then
    mkdir -p "$(dirname "$dir")"
    gh repo clone "$repo" "$dir" -- --quiet && ok "cloned $repo -> $dir" || { fail "clone $repo"; return 1; }
  else
    git -C "$dir" fetch --quiet --all --prune 2>/dev/null
    if ! git -C "$dir" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      ok "$dir (no upstream branch to pull; fetched)"
    elif git -C "$dir" merge --ff-only --quiet '@{u}' 2>/dev/null; then
      ok "$dir is at $(git -C "$dir" log --oneline -1 | cut -c1-60)"
    else
      warn "$dir could not fast-forward (local commits or conflicting changes); left as is"
    fi
  fi
}

step "2. Repositories"
mkdir -p "$SOFTWARE_DIR/Github" "$CITIES_DIR"
clone_or_update TheChrisOneil/process-to-loop "$PTL"
if [ "${SKIP_UPSTREAM:-0}" != 1 ]; then
  clone_or_update TheChrisOneil/gascity-upstream "$UPSTREAM"
  git -C "$UPSTREAM" remote get-url upstream >/dev/null 2>&1 \
    || git -C "$UPSTREAM" remote add upstream https://github.com/gastownhall/gascity.git
  git -C "$UPSTREAM" fetch --quiet upstream && ok "gascity upstream fetched"
  for pair in $PR_BRANCHES; do
    br=${pair%%:*}; wt="$(dirname "$UPSTREAM")/${pair##*:}"
    if [ -d "$wt" ]; then
      if [ -n "$(git -C "$wt" status --porcelain)" ]; then warn "$wt has uncommitted changes; not pulled"
      else git -C "$wt" merge --ff-only --quiet "origin/$br" 2>/dev/null \
             && ok "worktree $br at $(git -C "$wt" log --oneline -1 | cut -c1-9)" \
             || warn "worktree $br could not fast-forward to origin/$br"; fi
    elif git -C "$UPSTREAM" rev-parse --verify --quiet "origin/$br" >/dev/null; then
      git -C "$UPSTREAM" worktree add --quiet "$wt" "$br" 2>/dev/null \
        || git -C "$UPSTREAM" worktree add --quiet -b "$br" "$wt" "origin/$br"
      ok "worktree $br -> $wt"
    else warn "origin/$br not found (merged or deleted?); skipped"; fi
  done
else warn "SKIP_UPSTREAM=1: gascity fork not touched"; fi

# ---------------------------------------------------------------------------
step "3. The rig ($RIG)"
# The trap (docs/standing-up-a-city.md step 1): gc rig add runs bd init, which
# copies the rig's git origin into the bead store's sync.remote and would push
# every bead to GitHub. So the rig has NO origin while gc rig add runs.
git -C "$CITIES_DIR" rev-parse --show-toplevel >/dev/null 2>&1 \
  && die "$CITIES_DIR is inside a git repository. Cities must not be (step 1 of docs/standing-up-a-city.md)."
RIG_IS_NEW=0
if [ ! -d "$RIG/.git" ]; then
  gh repo clone "$RIG_REMOTE" "$RIG" -- --quiet || die "could not clone $RIG_REMOTE"
  git -C "$RIG" remote remove origin
  RIG_IS_NEW=1
  ok "cloned $RIG_REMOTE; origin removed until the rig is registered"
else
  if git -C "$RIG" remote get-url origin >/dev/null 2>&1; then
    git -C "$RIG" fetch --quiet origin 2>/dev/null
    git -C "$RIG" merge --ff-only --quiet '@{u}' 2>/dev/null \
      && ok "rig is at $(git -C "$RIG" log --oneline -1 | cut -c1-60)" \
      || warn "rig could not fast-forward; left as is"
  else ok "rig exists with no origin (it will be added after registration)"; fi
fi

# ---------------------------------------------------------------------------
step "4. The city ($CITY)"
check_no_remote() {   # $1 = dir with .beads/config.yaml
  local cfg="$1/.beads/config.yaml"
  [ -f "$cfg" ] || return 0
  if grep -iE "remote|sync|push" "$cfg" | grep -iqE "https?://|git@|dolthub"; then
    die "$cfg names a remote. Remove it before anything starts: $(grep -iE 'remote|sync|push' "$cfg" | tr '\n' ' ')"
  fi
  ok "no bead remote in $cfg"
}

if [ ! -f "$CITY/city.toml" ]; then
  gc init --template minimal --providers claude --default-provider claude \
          --skip-provider-readiness --no-start --name "$CITY_NAME" "$CITY" >/dev/null \
    || die "gc init failed"
  ok "gc init (not registered, not started)"
  check_no_remote "$CITY"

  # pack.toml: the pinned imports, the import named gc, the mayor on demand.
  cat > "$CITY/pack.toml" <<EOF
[pack]
name = "$CITY_NAME"
schema = 2

[imports]
[imports.bd]
source = "https://github.com/gastownhall/gascity/tree/main/examples/bd"
version = "$GASCITY_PIN"
[imports.core]
source = "https://github.com/gastownhall/gascity/tree/main/internal/bootstrap/packs/core"
version = "$GASCITY_PIN"

[imports.gc]
source = "https://github.com/gastownhall/gascity-packs/tree/main/gascity"
version = "$PACKS_PIN"

[[named_session]]
template = "mayor"
mode = "on_demand"
EOF
  ok "pack.toml written (pins $GASCITY_PIN, $PACKS_PIN)"

  # A second provider for the audit lane.
  grep -q '^\[providers.gemini\]' "$CITY/city.toml" || cat >> "$CITY/city.toml" <<'EOF'

# A second provider, so the audit lane can be genuinely decorrelated from the
# authoring lane. The audit-verdict gate enforces model difference.
[providers.gemini]
base = "builtin:gemini"
ready_delay_ms = 0
EOF
  ok "gemini provider added"
fi

if ! grep -q '^name = "work"' "$CITY/city.toml"; then
  git -C "$RIG" remote get-url origin >/dev/null 2>&1 \
    && die "the rig still has an origin; refusing to run gc rig add (bead remote trap)"
  # The rig repo tracks .beads/config.yaml, metadata.json and identity.toml,
  # so a clone is adopted (same project identity on every machine) rather
  # than initialized afresh. The bead database itself is per machine.
  adopt=()
  [ -f "$RIG/.beads/config.yaml" ] && [ -f "$RIG/.beads/metadata.json" ] && adopt=(--adopt)
  (cd "$CITY" && gc rig add "$RIG" --name work --prefix wk --start-suspended ${adopt[@]+"${adopt[@]}"} >/dev/null) \
    || die "gc rig add failed"
  ok "rig registered as work (wk), suspended on start${adopt[0]:+, existing beads identity adopted}"
fi
# The rig's import must be named gc (step 3 of the guide). gc rig add writes
# the [[rigs]] table last, so the import block appended here belongs to it.
if ! grep -q '^\[rigs.imports.gc\]' "$CITY/city.toml"; then
  [ "$(grep '^\[' "$CITY/city.toml" | tail -1)" = "[[rigs]]" ] \
    || die "city.toml's last table is not the work rig; add [rigs.imports.gc] by hand (docs/standing-up-a-city.md step 3)"
  cat >> "$CITY/city.toml" <<EOF
[rigs.imports]
[rigs.imports.gc]
source = "https://github.com/gastownhall/gascity-packs/tree/main/gascity/roles"
version = "$PACKS_PIN"
EOF
  ok "rig import named gc, pinned $PACKS_PIN"
fi
# gc rewrites metadata.json with this machine's Dolt port; keep that local.
if git -C "$RIG" ls-files --error-unmatch .beads/metadata.json >/dev/null 2>&1; then
  git -C "$RIG" update-index --skip-worktree .beads/metadata.json
fi
check_no_remote "$RIG"
if [ -d "$RIG/.beads" ]; then
  sr=$(cd "$RIG" && bd config get sync.remote 2>&1 | head -1)
  case $sr in *"not set"*|"") ok "rig sync.remote not set" ;;
    *) die "rig sync.remote is set ($sr). Unset it before going further." ;; esac
fi
if ! git -C "$RIG" remote get-url origin >/dev/null 2>&1; then
  git -C "$RIG" remote add origin "https://github.com/$RIG_REMOTE.git"
  git -C "$RIG" fetch --quiet origin && git -C "$RIG" branch --quiet -u origin/master 2>/dev/null
  ok "rig origin restored ($RIG_REMOTE)"
fi

(cd "$CITY" && gc import install >/dev/null 2>&1) && ok "gc import install" || fail "gc import install"

step "5. Install process-to-loop into the city and rig"
(cd "$PTL" && make --no-print-directory install-city CITY="$CITY" >/dev/null) && ok "install-city" || fail "install-city"
(cd "$PTL" && make --no-print-directory install-rig RIG="$RIG" >/dev/null) && ok "install-rig" || fail "install-rig"
(cd "$PTL" && make --no-print-directory install-mayor CITY="$CITY" >/dev/null) && ok "install-mayor" || fail "install-mayor"

# ---------------------------------------------------------------------------
step "6. Start the city"
if [ "${NO_START:-0}" = 1 ]; then warn "NO_START=1: not started"
else
  echo "  note: gc start reconciles the supervisor, which manages every registered city on this machine."
  (cd "$CITY" && gc start 2>&1 | tail -3 | sed 's/^/        /') && ok "gc start" || fail "gc start"
fi

# ---------------------------------------------------------------------------
step "7. Test"
(cd "$CITY" && gc gc --help 2>&1 | grep -q "claim") \
  && ok "gc gc --help lists claim (import named gc, pin ships commands)" \
  || fail "gc gc --help does not list claim — import not named gc, or the pin has no commands/"
(cd "$CITY" && gc agent list 2>/dev/null | grep -q "work/gc.run-operator") \
  && ok "work/gc.run-operator resolves" || fail "work/gc.run-operator does not resolve"
if [ "${NO_START:-0}" != 1 ]; then
  st=$(cd "$CITY" && gc status 2>&1)
  echo "$st" | grep -q "Controller: stopped" && fail "controller is stopped" || ok "controller is running"
  dr=$(cd "$CITY" && gc doctor 2>&1 | tail -1)
  case $dr in *failed*|*error*) warn "gc doctor: $dr  (run: cd $CITY && gc doctor)" ;;
    *) ok "gc doctor: $dr" ;; esac
fi
pf=$(cd "$PTL" && tooling/city-preflight.sh --city "$CITY" --offline 2>&1)
echo "$pf" | grep -E "PASS|FAIL|WARN" | sed 's/^/      /'
echo "$pf" | grep -q "FAIL" && warn "city-preflight reported a FAIL above (CURRENT fails by design when a pin is behind upstream)" \
  || ok "city-preflight"
(cd "$PTL" && ./test.sh >/dev/null 2>&1) && ok "process-to-loop test.sh" || fail "process-to-loop test.sh"

# ---------------------------------------------------------------------------
[ "$RIG_IS_NEW" = 1 ] && todo "Trust the rig for Claude Code once: cd $RIG && claude   (answer Yes, then /exit)"
todo "When an agent workspace first spawns, trust it the same way: cd $CITY/.gc/agents/<agent> && claude"
todo "Unsuspend the rig only when you mean to run work: cd $CITY && gc rig resume work"

step "Summary"
printf "  %d failure(s), %d warning(s)\n" "$FAILS" "$WARNS"
if [ ${#TODO[@]} -gt 0 ]; then
  printf "\n${B}Yours to do (the script will not):${Z}\n"
  for t in "${TODO[@]}"; do printf "  - %s\n" "$t"; done
fi
[ "$FAILS" -eq 0 ]
