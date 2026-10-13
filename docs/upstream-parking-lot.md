# Upstream parking lot

Ideas that may belong to the Gas City community rather than to this repo — held here until
the evidence says so, and reviewed on a schedule so they are neither forgotten nor filed early.

**The rule:** nothing goes upstream on a hunch. A proposal leaves this file when it has run
against more than one city, over more than a few weeks, and its own numbers have stopped moving.
This repo has already drafted one issue that was wrong twice over and was never posted, because
a ten-second control test settled it. That is the standard.

---

## PARKED-1 · Capability-surface diffing for packs

**The idea.** A pack's declared version cannot carry compatibility. Every version of the gascity
pack on one machine declares `0.1.0`, and `0.x.y` formally permits breaking changes in any
release, so the field is unusable rather than stale. Compute the surface instead — the way
`cargo public-api`, `japicmp`, `go apidiff` and API Extractor compute a public API because semver
is a human promise about a surface and humans get it wrong.

**What we built.** `pack-capability.sh` emits six properties: PROVIDES, MANDATES, DEMANDS, USES
(what a pack commits to), then NORMS and OPAQUE (judgment, split into the computable half and
the detectable half). `pack-diff.sh` classifies BREAKING / ADDITIVE / UNCLASSIFIED / NONE.
UNCLASSIFIED is never NONE.

**Evidence so far.** On `sha:3b3b89f2` → current main it reports BREAKING and names the cause:
`gc hook --claim` no longer stated, `gc gc claim` newly stated. That is the change that cost this
project a day.

**What the community already says.** Issue **#4071** (open, kind/bug, p2) —
*"Bundled core-pack pin isn't refreshed before release, so `gc init` seeds fresh cities with a
stale pack SHA."* It calls this "a latent release-hygiene risk," documents a three-week lag
between the embedded pin and `main`, and proposes a release-gate check. **The sha it names,
`f895c0f`, is the one our preflight flags as the builtin pin in a city created this week.**

So staleness of the *bundled* pin is known and owned. What #4071 does not cover, and what we
might contribute:

- drift on **user-declared** imports, not just bundled ones
- **capability** comparison rather than commit comparison — knowing you are behind is not knowing
  what you are missing
- the **judgment** half: a prompt rewritten to change an agent's behaviour with no structural
  change, which no commit comparison can see

**Before proposing anything.** Comment on #4071 first rather than opening a new issue. Ask
whether capability diffing is wanted, or whether the release-gate check is considered sufficient.
A comment costs nothing and does not ask maintainers to triage an opinion.

**Status:** built in Go and offered as draft PR **#7416**: `gc pack diff <old> <new>` and
`gc pack capability <dir>`, backed by `internal/packcap`. CI is green as of 2026-10-11.

The maintainers asked for finished solutions they can keep or reject, not proposals, so the
contrib scripts were replaced by the native command. Code review found nine ways a real change
could read as NONE or as a false BREAKING, and all nine are fixed:
- every file is now digested;
- `.md.tmpl` prompts are read;
- symlinked packs work;
- CRLF line endings no longer read as a change;
- MANDATES are read with a token scanner rather than a regex;
- inline `[[agent]]` and `[[commands]]` count;
- the verdict precedence is BREAKING > UNCLASSIFIED > ADDITIVE > NONE;
- `gc.kindred` no longer matches `gc.kind`;
- the NORMS minimum-length check is no longer off by one.

`gc pack diff --help` states the strategy and the limitations.

Follow-ups:
- a COMPATIBLE doctor check that writes `.gc/capability.lock` and diffs against it;
- resolving an import binding or `source@ref` instead of requiring two directories.

---

## PARKED-2 · `city-preflight` as a contributed check

**The idea.** `gc doctor` runs 77 checks and none of them is "your imports are behind" or "the
command your role prompt mandates does not exist here." Our seven properties could be doctor
checks.

**Why it is parked.** They encode opinions Gas City has not adopted. `CURRENT` treats being
behind `main` as a failure, which a stable deployment would reasonably reject. `PINNED` refuses a
floating import, which `gc rig add` itself produces by default. Proposing these as universal
checks would be telling other people how to run their cities on the strength of one repo's
fortnight.

**What would change that.** Run it against every city we own, weekly, for a month. If CONSISTENT
and COMPATIBLE keep catching real problems and the others mostly do not, propose the two that
earn it rather than all seven.

**Status:** the generic half is offered as draft PR **#7439**, as three advisory built-in doctor
checks. CI is green as of 2026-10-11.

| Check | Property | What it does |
|---|---|---|
| `prompt-gc-commands` | CONSISTENT | Resolves every `gc` command written as code in a rendered agent prompt against the running `gc`. It skips commands a prompt names only to forbid them. |
| `import-version-pins` | PINNED | Flags a remote import with no version. `--fix` pins it, and pins a bundled source to the canonical pin. |
| `nested-pack-commits` | UNIFIED, for nested packs | Flags a subpack locked at a different commit than its parent pack. |

COHERENT was already covered by `packv2-import-state`. CAPABLE is partly covered.

CURRENT and COMPATIBLE stay here:
- CURRENT needs the network and is an opinion.
- COMPATIBLE needs the capability lock that #7416 makes possible.

`gc ptl preflight` still checks all seven properties for anyone who wants that opinion.

---

## PARKED-3 · `gc rig add --include` writes an import that cannot work

**The idea.** This is a defect report, not a proposal, and it is the strongest of the three.
Two sibling commands write different things for the same URL.

**Reproduction**, four commands in a throwaway city:

```bash
gc init --template minimal --providers claude --default-provider claude \
        --skip-provider-readiness --no-start --name t /tmp/c
mkdir -p /tmp/r && git -C /tmp/r init
cd /tmp/c
gc rig add /tmp/r --name work --prefix wk --start-suspended \
   --include "https://github.com/gastownhall/gascity-packs/tree/main/gascity/roles"
gc import add "https://github.com/gastownhall/gascity-packs/tree/main/gascity" --name gc
```

What each wrote:

```toml
# gc rig add --include  — no version, name derived from the URL
[rigs.imports.roles]
source = "https://github.com/gastownhall/gascity-packs/tree/main/gascity/roles"

# gc import add --name  — version resolved and recorded, name as asked
[imports.gc]
source = "https://github.com/gastownhall/gascity-packs/tree/main/gascity"
version = "^0.4"
```

**Two defects.**

1. **No version, so the import floats.** It resolves to whatever the resolver picks that day. In
   one city this produced two versions of one pack family — the rig on `f69ec02b`, the city-level
   import on `2e7ec4c5` — while `gc import check` reported **"Import state OK"**, because the
   lock was self-consistent. A floating pin is worse than a stale one: stale is wrong and
   reproducible; floating changes between installs and yesterday's behaviour cannot be recovered.

2. **The import name is derived from the URL and cannot be set.** `--include` names it `roles`,
   giving the target `roles.run-operator`, while every formula and pack prompt says
   `gc.run-operator`, which requires the import be named `gc`. `--name` on `gc rig add` sets the
   *rig* name. There is no flag for the import name, so the only fix is hand-editing `city.toml`
   afterwards — the step nobody knows to take, and the one that cost this project most of a day.

The help calls `--include` "compatibility sugar: `gc rig add` writes canonical rig imports." The
imports it writes are not equivalent to what `gc import add` writes.

**An aside worth keeping.** `gc import add` chose `version = "^0.4"`. Caret on a `0.x` version
admits `>=0.4.0 <0.5.0`, and `0.x.y` permits breaking changes in any release — so even the
command that pins correctly pins to a range that guarantees nothing. Same root cause as PARKED-1.

**Searched upstream, three ways, nothing found.** Distinct from #4071, which is about the
*bundled* pin; this is about *user-declared* imports.

**Status:** fixed upstream in **#7382** (`665e2a04e`, merged 2026-10-09), whose commit message
cites this entry. `--include` now resolves a version through the same helper as `gc import add`,
and `--include gc=<url>` sets the import name. Not yet in a release: v1.4.2 does not have it.
The aside about `^0.4` on a `0.x` version is not addressed and stays with PARKED-1.

---

## The vocabulary, so it is not reinvented

These terms were coined here over one long session. Written down because the next person to
reach for them — including us in three months — should not have to derive them again.

### The framing

**Packs are npm-shaped already.** A registry, a lockfile (`packs.lock` — schema, per-source
version, commit, fetched), a `version` constraint on imports, and an `engines` analogue
(`requires_gc`). What is missing is not machinery.

**The version field is unusable, not stale.** Every version of the gascity pack on one machine
declares `0.1.0`, and `0.x.y` **formally means breaking changes are permitted in any release**.
Even if the publisher began bumping honestly tomorrow, we would be trusting their classification
of prose edits. **Compute compatibility; do not consume it.**

**Publishing is not an event.** npm works because you cannot publish without bumping a version —
the discipline is enforced at the boundary. A Gas City pack is a subtree on `main`; every commit
is a release and none of them bumps anything.

**Prior art, so none of this is invented.** `cargo public-api`, `go apidiff`, `japicmp` and API
Extractor all exist because semver is a human promise about a surface and humans get it wrong,
so the tool computes the surface and reports what actually changed. The classification rules are
borrowed.

### The six properties of a capability manifest

The first four are what a pack **commits to**. The last two are **judgment**, split into the
half that can be computed and the half that can only be detected.

| Property | What it captures | Why it is separate |
|---|---|---|
| **PROVIDES** | commands, agents and formulas the pack ships | removal is unambiguously breaking |
| **MANDATES** | commands its prompts require an agent to run | the `gc hook --claim` → `gc gc claim` change lives here, and nothing structural moved |
| **DEMANDS** | output contracts and reserved metadata it requires | **adding** one is breaking — it is a new requirement on callers |
| **USES** | formula constructs it depends on | `check`, `drain`, `on_complete`, scopes |
| **NORMS** | every *must*, *never*, *only*, *do not* in the role prompts and fragments | a rule stated in prose is still a rule; changing one changes behaviour with no surface change |
| **OPAQUE** | a digest per prose file | the part that cannot be computed. When this moves and nothing else does, the answer is **UNCLASSIFIED** |

**Scope NORMS to the judgment surface** — role prompts and template fragments. Task instructions
elsewhere produce command-prefix churn that drowns the signal; those contribute OPAQUE instead.

### The four verdicts

| | |
|---|---|
| **BREAKING** | a commitment was removed or changed. Exit 2 |
| **ADDITIVE** | a commitment was added, nothing removed. Exit 0 |
| **UNCLASSIFIED** | prose moved and nothing computable did. Exit 1 |
| **NONE** | the manifests are byte-identical. Exit 0 |

**UNCLASSIFIED is not NONE, and this is the whole point.** A prompt rewritten to give different
judgment with the same surface lands in UNCLASSIFIED. Reporting it as NONE would be the
declared-reported-absent failure this project exists to catch, committed by the tool that catches
it.

### On embeddings

Vector distance would **rank** UNCLASSIFIED changes by how far the text moved, which beats a
hash for triage. It cannot be the verdict:

**Embeddings are weak at negation, and judgment prose is made of negations.** *"Never claim
through `gc bd ready`"* and *"Always claim through `gc bd ready`"* sit close together in vector
space and are opposites. The highest-risk change is the one distance is worst at seeing. NORMS
catches exactly that case by extracting the negation literally, which makes the two
complementary rather than substitutable.

There is also a recursion worth naming: an embedding model is a pinned dependency whose
behaviour can change under you — the precise class of problem being solved.

### The seven city properties

`PINNED` · `COHERENT` · `UNIFIED` · `CURRENT` · `CAPABLE` · `CONSISTENT` · `COMPATIBLE`.
Defined in `docs/standing-up-a-city.md`. The two that have earned their keep so far are
**CONSISTENT** (does the command your role prompt mandates exist here) and **COMPATIBLE**
(has the surface moved since you accepted it, via `.gc/capability.lock` — because `packs.lock`
records which version resolved and nothing recorded what that version committed to).

---

## Where the conversation happens

| | |
|---|---|
| Issues | `gastownhall/gascity` — active, high traffic, well-triaged with kind/ and priority/ labels |
| Discussions | enabled on the repo |
| Discord | `discord.gg/xHpUGUzZp2` — linked from the README |
| Contributing | `CONTRIBUTING.md`, `SUPPORT.md` in the repo root |

**Read before writing.** The issue tracker has a strong house style: reproduction steps, impact
stated honestly including "latent" when it is latent, and corrections appended when an earlier
attribution turns out wrong (#4071 does exactly that in its own body). Match it.

---

## The review

Look at this file when any of these happens, and at least monthly:

- `gc ptl preflight` fails a property on a city that was passing
- `pack-diff` returns BREAKING on an upgrade we were about to make
- a parked item's numbers stop moving — the check stops finding new things, which means it has
  either matured or gone blind, and both are worth knowing
- an upstream issue touches one of these topics

For each parked item ask three questions. **Is it still true?** **Has upstream solved it?** **Do
we have more than one city's worth of evidence?** Two yeses and a no is still parked.

## PARKED-4 — no supported way to set a step's thinking effort

gc starts every claude session with `--effort max`. For a formula whose steps
are mostly "run this script and report the exit code", that is the wrong
default, and for the one step with latitude it is a choice the formula should be
able to make. Observed 2026-10-02: an authoring step for a one-page business
process took 26:19, of which **1210s was thinking**.

Three routes tried on gc 1.4.2, none of which changed the session command:

- **`opt_effort` in step metadata.** The key exists in the binary, beside
  `opt_model` which the same metadata line sets successfully. Setting
  `opt_effort = "low"` on nine steps and `"high"` on one landed correctly on
  every bead and left `--effort max` on the session that claimed them.
- **`env` on `[providers.claude]` in city.toml.** Accepted by the config
  (`gc status` still reads the city), no effect. `--effort max` is passed as an
  explicit flag, which would override `CLAUDE_CODE_EFFORT_LEVEL` anyway.
- **Restarting the pool worker** so a fresh session picks up either of the
  above. The replacement session also started at max.

`CLAUDE_CODE_EFFORT_LEVEL` appears in the binary, so the plumbing exists
somewhere; what is missing is a documented, per-agent or per-step way to reach
it. A machine-wide env var is not an answer here: the supervisor is shared
across cities, so setting it would reach a production city too.

**What would help:** `opt_effort` honored at session creation the way `opt_model`
is, or an `effort` key on an agent definition.

**Status:** fixed upstream in **#7378** (`a776d2e4c`, merged 2026-10-09; closes #5710), whose
commit message cites this entry. The cause was broader than effort: no `opt_*` pin reached a
pooled session, because options were read only from a bead already claimed, and a pool session
claims after it launches. `opt_model` landed on the bead and did not reach the session either.
`opt_effort` now applies at launch. For a whole agent, `option_defaults = { effort = "low" }` in
its `agent.toml` already existed. Accepted values are `low`, `medium`, `high`, `xhigh`, `max`.
Not yet in a release: v1.4.2 does not have it.

## RESOLVED-5 · a check that cannot launch let its step close

Raised by email 2026-10-08, not parked first. A step check that the dispatcher could not launch
was quarantined, produced no exit code, and the step closed: the gate failed open.

**Status:** fixed upstream in **#7377** (`42b11ccbd`, merged 2026-10-09). A missing, dangling,
non-regular or non-executable check script now holds the step open with
`gc.control_pending_reason` set, and the next sweep heals it once the script is launchable.
Exit 75 and exec errors re-run up to 20 times without burning an attempt.

**What remains.** Once those 20 retries are spent the step closes `fail`, and a failed step still
releases its dependents (upstream #6246; proposed fixes #7174 and #5672). For a regulated
control, that is the follow-up to watch. Keep the per-gate step and the path preflight until it
lands.


---

## PARKED-5 · No step outcome for *could not run*

**Status 2026-10-13: investigated, with probes. Not yet proposed upstream.**

### The problem, in one line

An exec check that cannot run is indistinguishable, in the bead store, from one that refused.

### What was measured, not assumed

Four probes against a live city. Each is a control test, and two of them contradicted something
this repo had been asserting in generated code.

**1 — exit 75 is exit 1.** A one-step formula, `max_attempts = 2`, one check that always exits 75:

```
gc.attempt_log = [
  {"action":"fail","attempt":"1","outcome":"fail","reason":"...exit 75"},
  {"action":"fail","attempt":"2","outcome":"fail","reason":"...exit 75"}
]
```

Both attempts consumed, step closed `fail`. **We had asserted the opposite in every emitted check
for weeks** and never tested it.

**2 — an UNKNOWN key in `[steps.check.check]` is accepted and silently discarded.** A formula
declaring `blocked_exit_codes = [75]` and `on_could_not_run = "blocked"` cooked without a word of
complaint, and neither key reached the bead. Only `mode`, `path` and `timeout` survive.

Be precise about the scope, because the first draft of this note was not. gc **does** validate the
keys it knows: misspell `max_attempts` and cooking fails with *"max_attempts must be >= 1"*,
because its absence violates a constraint. The exposure is narrower than "typos are not caught":

| | caught? |
|---|---|
| a known key with a violated constraint | **yes** |
| a known key misspelled, leaving a constrained key absent | **yes**, indirectly |
| a key gc does not know | **no** — accepted, dropped, silent |
| a known optional key misspelled | **no** |

The second half of that table is where a formula can declare check behaviour that never happens.
It matters here more than elsewhere: this project's whole claim is that a formula is the
EXECUTABLE form of a method, as against a document that merely describes one. A formula carrying
declarations that are silently inert is, in that respect, partly a document — and a reader cannot
tell by looking which parts are load-bearing.

**3 — `gc.outcome` holds two values.** Across 186 recorded outcomes: `pass` and `fail`. Nothing else.

**4 — but the controller already classifies.** Point a check at a path outside the rig and gc
records:

```
gc.controller_error       = absolute gc.check_path "..." escapes trusted roots
gc.controller_error_class = hard
```

So the distinction *is* computed. It is simply not carried into the step's outcome, and no formula
can ask for it to be.

### The lever that already exists

`bd config set status.custom "could_not_run:frozen"` creates the status, and a bead holds it:

| asked | answer |
|---|---|
| can a bead hold it? | **yes** |
| is it offered as work? | **no** |
| is it counted closed? | **no** |

Category `frozen` is exactly the semantics wanted: the run halts, dependents stay blocked, and
nothing claims the work failed. **The vocabulary exists. What is missing is any way for a check
result to reach it.**

### The shape of the proposal

Smallest change that would close it, in preference order:

1. **A reserved exit code that sets a frozen status.** The controller already branches on the exit
   code; it needs one more branch, and `frozen` custom statuses already behave correctly. No new
   concepts.
2. **Per-check configuration**, e.g. `blocked_exit_codes = [75]` in `[steps.check.check]` — which
   is what an author would reach for first, which is why it was the shape probed. Requires the key
   to stop being discarded.
3. **Failing both: reject unknown keys in a check block.** If a formula cannot declare this, it
   should not be able to appear to. gc already validates the keys it knows; this asks it to also
   refuse the ones it does not.

### The second half, which is worse

For an agent that cannot authenticate, **nothing is written to any bead at all.** Every iteration
bead from the 2026-10-09 expiry has an empty `attempt_log` and an empty `controller_error`; the
logical bead records only `attempt subject wk-xxx already failed`, naming a bead that records
nothing. The reason existed only on a tmux pane.

An agent that cannot authenticate should not claim work. Failing that, the claim failure should
land somewhere durable. No amount of better reporting recovers a reason that was never written
down — which is why our own fix went into **preflight**, before the sling, rather than into the
status screen after it.

### What we did on our side, 2026-10-13

The bottom two rows of that table are now **F18**, a formula rule:

```
FAIL  F18  key gc will silently discard: [steps.check.check] blocked_exit_codes
           — it cooks without complaint, never reaches the bead, and the
           behaviour it declares never happens
```

It carries an allowlist of the keys a check block actually honours, and the
allowlist is **measured, not read**: a probe formula set each key, and the step
bead was read to see which arrived. The comment in `validate-formula.awk` records
the date and the procedure for widening it, because a refusal from F18 means one
of two things that look identical — the key is a typo, or gc has gained a key and
the list is stale. Measure before widening.

This does not fix gc. It stops *our* formulas from carrying inert declarations,
which is the half we own. The upstream ask stands, and is now smaller: gc already
validates the keys it knows, so refusing the ones it does not is the same
mechanism applied once more.

### Against proposing this yet

The rule in this file is that nothing goes upstream on a hunch, and this has run against one city.
What it has in its favour: four reproducible probes, two incidents a week apart with opposite
symptoms, and a fix that uses two mechanisms gc already ships. What it lacks: any evidence that
another operator has hit it, and any check of whether a newer gc has already changed this.

**Check the version first.** Our conclusion is about the gascity build installed on 2026-10-13.
