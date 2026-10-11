# Handoff: process-to-loop and the Gas City upstream work

**Purpose:** Let a person or a Claude Code session pick up this work on another Mac, and switch back, with nothing lost.

**EX:** Two draft PRs on `gastownhall/gascity` are open and pushed: #7416 (`gc pack diff`) and #7439 (doctor drift checks). Both live on GitHub, so cloning recreates them. The local Gas City city (`~/cities/ptl-city`) and rig (`~/cities/ptl-rig`) are not on GitHub. Recreate the city from `docs/standing-up-a-city.md`. Copy the rig's `processes/` folder by hand, because it exists only on the old machine.

As of 2026-10-11. Written on the machine at `/Users/thechrisoneil` (macOS 26.5.2, arm64).

---

## 1. Current status

### Upstream PRs (gastownhall/gascity)

| PR | Branch (fork `TheChrisOneil/gascity-upstream`) | Head | State | What it does |
|---|---|---|---|---|
| [#7416](https://github.com/gastownhall/gascity/pull/7416) | `feat/contrib-pack-capability-diff` | `85b39e670` | Draft | Adds `gc pack diff` and `gc pack capability`, plus the Go package `internal/packcap` |
| [#7439](https://github.com/gastownhall/gascity/pull/7439) | `feat/doctor-pack-capability-checks` | `fcdb68451` | Draft | Adds advisory doctor checks `prompt-gc-commands`, `import-version-pins` and `nested-pack-commits` |

Both have been code-reviewed, and all 13 review findings are fixed with regression tests. Both `--help` texts and the docs state the commands' strategy and limitations. Neither has run Bazel, nogo or gofumpt locally; GitHub CI is their first run.

**Remaining steps for the PRs:**
1. Read CI on both PRs and fix any failures.
2. Mark each PR ready with `gh pr ready <n> -R gastownhall/gascity`.
3. Possible follow-ups, listed in the PR bodies:
   - a COMPATIBLE doctor check using `.gc/capability.lock`;
   - one shared prompt-command extractor (`packcap.ExtractMandates`) used by both PRs;
   - a cancellable `CheckContext` for doctor checks.

**Already fixed upstream on 2026-10-09** by julianknutsen, from the 2026-10-08 email to Chris Sells. None of these is in a release yet: `gc` v1.4.2 lacks them.

| Upstream PR | Fixes |
|---|---|
| #7377 | A check that cannot launch now holds its step open instead of failing open |
| #7382 | `gc rig add --include` now records a version and accepts `--include <name>=<url>` |
| #7378 | `opt_*` pins, including `opt_effort`, now reach pooled sessions |

### This repo (process-to-loop)

- **Branch:** `main` matches `origin/main`. PR #1 is merged; it fixed the `pack/lib` capability bug and updated the parking lot.
- **Parking lot:** `docs/upstream-parking-lot.md` holds the status of PARKED-1 to PARKED-4 and RESOLVED-5.
- **Uncommitted, not part of this work:** `Claude outputs/everbetter-sovereign-platform*.png`.

### Open non-code items

- **Thank-you email:** a Gmail draft to Chris Sells, with Bo on cc, in the thread "Business processes compiled into Gas City formulas". Check whether it was sent.
- **Maintainer preference:** the gascity maintainers want finished PRs they can keep or reject. Do not send proposals or questions first.

---

## 2. Folder layout (keep it the same on both machines)

Claude Code's memory and several docs assume these exact paths. Use the same macOS username (`thechrisoneil`) on both machines if you can.

```
~/software/
  process-to-loop/                      git: TheChrisOneil/process-to-loop        (this repo)
  Github/
    gascity-upstream/                   git: TheChrisOneil/gascity-upstream (fork of gastownhall/gascity)
    wt-contrib-pack-capability-diff/    git worktree, branch feat/contrib-pack-capability-diff (#7416)
    wt-doctor-capability/               git worktree, branch feat/doctor-pack-capability-checks (#7439)
~/cities/                               must NOT be inside any git checkout
  ptl-city/                             Gas City city, not a git repo, rebuilt per machine
  ptl-rig/                              git: TheChrisOneil/ptl-rig (PRIVATE), branch master; processes/ holds run data
~/.claude/projects/-Users-thechrisoneil-cities/memory/   Claude Code memory for sessions started in ~/cities
```

---

## 3. One-time setup on a new machine

### 3.1 Tools

Versions on the current machine are shown in comments.

```bash
brew install gh go tmux dolt jq icu4c gascity beads
# homebrew/core formulae: gascity (gc 1.4.2), beads (bd 1.3.0), go 1.26.5, tmux 3.7c, dolt 2.3.5
```

Also install these by hand:
- **Python 3.13** (python.org installer). The gascity repo-tree scripts need `tomllib`, and the default `python3` here is 3.10.
- **Node 22** through nvm, then `npm i -g @google/gemini-cli` for the city's second provider.
- **Claude Code CLI** (currently 2.1.296).

**Not installed on the current machine:** Bazel, Bazelisk and shellcheck. CI covers them. Installing Bazelisk would let you run `make check` locally.

**Sign in.** These steps belong to you; Claude must not enter credentials:

```bash
gh auth login        # account TheChrisOneil, protocol ssh
claude               # sign in
gemini               # sign in
```

### 3.2 Repositories

```bash
mkdir -p ~/software/Github ~/cities
git clone https://github.com/TheChrisOneil/process-to-loop.git ~/software/process-to-loop
git clone git@github.com:TheChrisOneil/gascity-upstream.git ~/software/Github/gascity-upstream
cd ~/software/Github/gascity-upstream
git remote add upstream git@github.com:gastownhall/gascity.git
git fetch upstream origin
git worktree add ../wt-contrib-pack-capability-diff feat/contrib-pack-capability-diff
git worktree add ../wt-doctor-capability feat/doctor-pack-capability-checks
```

**Do not base work on the fork's `main`.** It is far behind upstream. Branch from `upstream/main`.

### 3.3 Build environment for gascity (macOS)

Plain `go test` fails with `'unicode/regex.h' file not found` unless the ICU flags are set. Add these lines to `~/.zshrc`:

```bash
export CGO_CPPFLAGS="-I$(brew --prefix icu4c)/include"
export CGO_LDFLAGS="-L$(brew --prefix icu4c)/lib"
```

Check that both branches build:

```bash
cd ~/software/Github/wt-contrib-pack-capability-diff && go build -o /tmp/gc-7416 ./cmd/gc
cd ~/software/Github/wt-doctor-capability && go build -o /tmp/gc-7439 ./cmd/gc
```

### 3.4 The city and the rig

- **City:** `~/cities/ptl-city` is generated, not cloned. Follow `docs/standing-up-a-city.md` from step 1, naming the city `ptl-city`, the rig `ptl-rig`, the rig binding `work` and the prefix `wk`. Then install this repo's content:

  ```bash
  cd ~/software/process-to-loop
  make install-city CITY=~/cities/ptl-city
  make install-rig RIG=~/cities/ptl-rig
  make install-mayor CITY=~/cities/ptl-city
  make city-preflight CITY=~/cities/ptl-city
  ```

- **Import pins:** keep these exact values so both machines run the same packs.
  - `pack.toml`:
    - `[imports.bd]` and `[imports.core]`: `version = "sha:f895c0ff47d6ee9334ed282a416387eb5b084d24"`
    - `[imports.gc]`: `source = "https://github.com/gastownhall/gascity-packs/tree/main/gascity"` with `version = "sha:2e7ec4c5598173ff00c20a2048ef28d4202bd38a"`
  - `city.toml`, rig `work`:
    - `[rigs.imports.gc]`: `source = ".../gascity-packs/tree/main/gascity/roles"` at the same `sha:2e7ec4c5…`
    - keep `suspended_on_start = true`
  - The city also defines a `gemini` provider (`base = "builtin:gemini"`) for the audit lane.

- **Rig:** `~/cities/ptl-rig` is the private repo `TheChrisOneil/ptl-rig`. Its `processes/` folder holds run data for five processes: `appointment-chase`, `chase`, `med-rec`, `monthly-close` and `po-reconciliation`. It also tracks the `checks/`, `tooling/`, `catalog/` and `tools/` that `make install-rig` puts there. Per-machine state (`.gc/`, `.claude/`, `.gemini/` and the bead database) is ignored and never pushed.

  **The rig now has a git remote, so the trap in `docs/standing-up-a-city.md` step 1 applies.** `gc rig add` runs `bd init`, which copies a dolt `sync.remote` from the rig's git origin. That would push the bead database to GitHub. On a new machine, take the remote off before `gc rig add` and put it back afterwards:

  ```bash
  git clone git@github.com:TheChrisOneil/ptl-rig.git ~/cities/ptl-rig
  cd ~/cities/ptl-rig && git remote remove origin && git remote -v      # must print nothing
  cd ~/cities/ptl-city && gc rig add ~/cities/ptl-rig --name work --prefix wk --start-suspended
  cd ~/cities/ptl-rig && bd config get sync.remote                      # must say "not set"
  git remote add origin git@github.com:TheChrisOneil/ptl-rig.git && git fetch -q origin && git branch -u origin/master
  ```

  After `gc rig add`, fix the rig import exactly as `docs/standing-up-a-city.md` step 3 describes, and pin it as listed above.

  **Check `sync.remote` whenever `gc` re-initializes beads.** If it ever names a URL, unset it before starting the city:

  ```bash
  cd ~/cities/ptl-rig && bd config get sync.remote
  ```

  The rig's run data uses tokenized patient references (`PT-4417`) and no names or dates of birth. Treat that as a working assumption that it is synthetic. Keep real patient data out of this repo.

- **Never move a running city.** Run `gc stop` in `~/cities/ptl-city` before leaving a machine. The supervisor registry (`~/.gc/cities.toml`) is per machine. It also lists the cities `~/software/gascity` and `~/software/eb-city`. Those are separate projects, not part of this work, and this handoff does not cover them.

### 3.5 Claude Code memory

Memory lives at `~/.claude/projects/-Users-thechrisoneil-cities/memory/`. The folder name comes from the path of the session's working directory, so it matches only if the username and `~/cities` path are the same. Copy the folder across:

```bash
rsync -a old-mac:~/.claude/projects/-Users-thechrisoneil-cities/memory/ ~/.claude/projects/-Users-thechrisoneil-cities/memory/
```

It currently holds one memory, `gascity-maintainers-want-solved-prs`: ship complete PRs to gascity, and do not open with proposals.

---

## 4. Switching machines

**Before you leave a machine:**

1. Run `gc stop` in `~/cities/ptl-city`.
2. Commit and push every repo you changed:
   - `process-to-loop`
   - both `wt-*` worktrees: push to `origin`, never force-push
   - `~/cities/ptl-rig`: commit `processes/` and push
3. Copy the Claude memory folder across. It is the only thing git does not carry.

**When you arrive:**

1. Run `git pull` in each repo, including `~/cities/ptl-rig`.
2. Run `git fetch upstream` in `gascity-upstream`.
3. Copy the memory folder if the other machine changed it.
4. Re-run the four `make install-*`/`city-preflight` commands in 3.4 if `process-to-loop` changed.
5. Run `gc start`.


---

## 5. Testing the two PRs

The ICU flags from 3.3 must be set for every step.

**#7416 (`gc pack diff`):**

```bash
cd ~/software/Github/wt-contrib-pack-capability-diff && go build -o /tmp/gc-7416 ./cmd/gc
rm -rf /tmp/pd && mkdir -p /tmp/pd/old /tmp/pd/new
git archive f895c0f internal/bootstrap/packs/core | tar -x -C /tmp/pd/old
git archive upstream/main internal/bootstrap/packs/core | tar -x -C /tmp/pd/new
/tmp/gc-7416 pack diff /tmp/pd/old/internal/bootstrap/packs/core /tmp/pd/new/internal/bootstrap/packs/core; echo "exit=$?"
/tmp/gc-7416 pack diff --help
go test ./internal/packcap/... ./cmd/gc/ -run 'TestDiff|TestCompute|TestExtract|TestPack|ProductMetrics|Census' -count=1
```

- **Diff:** expect `VERDICT BREAKING` and exit 2, with `gc agent claim <agent> <id>` no longer stated.
- **Same pack on both sides:** expect NONE and exit 0.

**#7439 (doctor checks):** this run is read-only.

```bash
cd ~/software/Github/wt-doctor-capability && go build -o /tmp/gc-7439 ./cmd/gc
cd ~/cities/ptl-city && /tmp/gc-7439 doctor --check prompt-gc-commands --check import-version-pins --check nested-pack-commits -v
cd ~/software/Github/wt-doctor-capability && go test ./cmd/gc/ -run 'TestPromptGC|TestImportVersionPins|TestNestedPackCommits|TestBuildDoctorChecks|Doctor' -count=1
```

Expect three ✓ lines. On the old machine, `prompt-gc-commands` resolved 254 invocations in 20 prompts.

Try `--fix` only on a throwaway city, never on `ptl-city`.

---

## 6. Gotchas found during this work

- **Missing ICU flags:** cgo build failure (`unicode/regex.h`). See 3.3.
- **New `gc` command:** register it in `cmd/gc/productmetrics_command_census.json`, then run `go run ./cmd/gen-command-census`. Otherwise `TestProductMetricsLifecycle*` fails.
- **Changed command help:** run `go run ./cmd/genschema` to regenerate `docs/reference/cli.md`, then `CGO_ENABLED=0 go test ./test/docsync/`.
- **New files:** run `python3.13 tools/bazel/repo_tree.py` and hand-edit `BUILD.bazel`, because Bazel is not installed.
- **Full suite:** `go test ./cmd/gc/ ./internal/...` on this machine fails some tests even on unmodified upstream `main` (`b22698474`). Examples are `TestCascadeNudgeAbsorbsDuplicateCloseEvents`, `TestStopManagedCityBoundsForcedShutdownWhenRuntimeHangs` and `TestSessionScriptStart*` in `internal/runtime/k8s`. Several more are 5-second timeouts that pass when run alone. Before blaming a branch, re-run a failure by itself and on the base commit.
- **CI on the PRs:** Auto-fix is on in the Claude Code desktop app for this session, so CI failures and review comments on #7416 and #7439 come back as events. On a new machine or session, turn it on again from the PR bar.
- **Before building anything upstream,** search history with `git log --grep` and `gh pr list -R gastownhall/gascity --search ...`. Three of four reported issues were fixed upstream before work began.

---

## 7. Starting a new Claude Code session

Open Claude Code in `~/cities`, so the memory in 3.5 loads, and paste this prompt:

> Read ~/software/process-to-loop/HANDOFF.md. Verify the folder layout and tools in sections 2–3 on this machine and report anything missing. Then check CI on gastownhall/gascity#7416 and #7439, and report what needs fixing before they leave draft.

---

References:
[1] TheChrisOneil, "feat(pack): gc pack diff computes capability-surface compatibility," gastownhall/gascity, Draft PR #7416, Oct. 2026.
[2] TheChrisOneil, "feat(doctor): flag prompt commands, unpinned imports and split subpacks," gastownhall/gascity, Draft PR #7439, Oct. 2026.
[3] process-to-loop, "Standing up a city to run these formulas," `docs/standing-up-a-city.md`.
[4] process-to-loop, "Upstream parking lot," `docs/upstream-parking-lot.md`.
