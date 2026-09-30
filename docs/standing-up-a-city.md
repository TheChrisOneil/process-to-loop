# Standing up a city to run these formulas

Everything below was learned by doing it on a clean machine, in this order. None of it is
guessable, and five of the steps cost a failed run each.

If you only want to compile and validate formulas, you need none of this — `make test` and
`make conformance` build a throwaway city in a temp directory and delete it. This guide is for
actually **running** a workflow.

## What you need

| | |
|---|---|
| `gc` | the Gas City CLI. `brew install gascity` |
| `tmux` | agents run in tmux panes. No tmux, no agents |
| a provider CLI | `claude`, or whatever your city's provider is |
| bash, awk, make | already on macOS and Linux |

## 1. Put the city outside every git repository

**This is the one that can leak data.** `gc rig add` runs `bd init`, which derives a dolt
`sync.remote` from the repository's git origin. If the city directory has no git remote, `bd`
walks *up the tree* and inherits whatever it finds. A city created under a directory that
happens to be a git repo will quietly be configured to push its entire bead database — every
title, description and close reason — to that repository's remote.

```bash
mkdir -p ~/cities                      # NOT inside a checkout
cd ~/cities && git rev-parse --show-toplevel   # must fail: "not a git repository"
```

If that command prints a path, pick somewhere else, or remove the remote from that repo.

## 2. Initialize without registering

`--no-start` creates the files and imports but registers nothing and starts nothing. That is
the only window in which you can check the remotes before anything could sync.

```bash
gc init --template minimal --providers claude --default-provider claude \
        --skip-provider-readiness --no-start --name my-city ~/cities/my-city
```

Then verify **both** layers:

```bash
grep -iE "remote|sync|origin|push" ~/cities/my-city/.beads/config.yaml
# gc.endpoint_origin: managed_city   <- fine, an endpoint marker, not a remote
# anything naming a URL              <- stop and remove it
```

## 3. Take the current pin, and name the import `gc`

Two mistakes here, and I made both. They cost more time than everything else in this guide put
together.

### Take the current sha — do not copy one from another city

```bash
gh api repos/gastownhall/gascity-packs/commits/main -q .sha
```

Use that. Copying a pin out of a city that has been running for months gives you that city's
history, and **`gc doctor` does not check whether your imports are behind** — 77 checks pass and
none of them is "your pack is four months old." I copied a pin, then spent hours on a command
the pinned version did not ship.

The difference is not cosmetic. Older versions of the pack have no `commands/` directory at all,
so nothing projects; the role prompts in those versions correctly tell the agent to call
`gc hook --claim --json` directly. Newer versions ship `commands/claim` and their prompts say
`gc gc claim`. **Each version is internally consistent. Mixing one version's expectations with
another's is what breaks.**

### The import's key is the namespace — for agents *and* commands

`gc.run-operator` and `gc gc claim` both mean the import named **`gc`**. Name it anything else
and neither resolves, while every file looks correct.

In `pack.toml`, at city level:

```toml
[imports.gc]               # gc, so its commands project as `gc gc <cmd>`
source = "https://github.com/gastownhall/gascity-packs/tree/main/gascity"
version = "sha:<current>"
```

And in `city.toml`, per rig:

```toml
[rigs.imports]
[rigs.imports.gc]          # gc, so its agents resolve as `gc.run-operator`
source = "https://github.com/gastownhall/gascity-packs/tree/main/gascity/roles"
version = "sha:<current>"
```

`gc rig add --include <url>` names the import for you, and it will not pick `gc`. Fix the key
afterwards, every time.

Then install, and verify both namespaces resolved rather than trusting the file:

```bash
gc import install
gc gc --help        # "Commands from the gc import", listing claim
gc agent list       # work/gc.run-operator among them
```

If `gc gc --help` prints the top-level CLI help instead, one of the two mistakes above is still
in place: either the pin has no `commands/`, or the import is not named `gc`.

## 4. You need a rig, even if you have no code

`gc.run-operator` is **rig-scoped**. eb-style pools are `<rig>/gc.run-operator`. A city with no
rigs cannot route it, whatever the formula says.

Make the rig a git repository with **no remote**, so step 1's trap has nothing to inherit:

```bash
mkdir -p ~/cities/my-rig && cd ~/cities/my-rig && git init
git remote -v          # must be empty

cd ~/cities/my-city
gc rig add ~/cities/my-rig --name work --prefix wk --start-suspended \
   --include "https://github.com/gastownhall/gascity-packs/tree/main/gascity/roles"
```

`--start-suspended` means no agent spawns until you say so. Add it. Then fix the import key as
step 3 describes, because `--include` will have named it something else.

Verify the trap did not fire:

```bash
grep -iE "remote|sync|origin|push" ~/cities/my-rig/.beads/config.yaml
```

## 5. Do not leave the mayor resident

The minimal template writes `mode = "always"` for the mayor, which holds a provider session
open in a city that is idle most of the time. Change it in `pack.toml`:

```toml
[[named_session]]
template = "mayor"
mode = "on_demand"
```

## 6. Start the city — and know what it touches

```bash
cd ~/cities/my-city && gc start
```

`gc start` reconciles the supervisor, which manages **every registered city on the machine**.
It prints a warning saying so, and that it may escalate to a kill-and-respawn that cycles other
cities' in-flight work. It does not gate on that warning. If another city matters to you, know
its state before running this.

Later config changes do not need another supervisor reconcile — `gc reload` is city-scoped and
does not restart the controller.

## 7. Run doctor, then the preflight

```bash
gc doctor
make city-preflight CITY=~/cities/my-city     # from the process-to-loop repo
```

Doctor checks the city against Gas City's own rules and will not tell you your pins are stale;
there is no such check, because the pack spec defines none. The preflight is that check. It
asserts six properties the spec leaves undefined — see **The drift semantics** below — and the
one that matters reads the claim command your role prompt mandates and confirms it resolves
here.

Read doctor's failures, not its passes. It catches config drift, deprecated formula
declarations, store bloat and stale orders, and it takes thirty seconds.

## 8. Trust every agent workspace, once

Agent sessions die on startup until Claude Code's folder-trust prompt is answered for their
workspace, and **each agent has its own workspace**:

```
Accessing workspace: /Users/you/cities/my-rig
Quick safety check: Is this a project you created or one you trust?
  ❯ No, exit
    Yes, I trust this folder
Pane is dead (status 1)
```

The supervisor cannot answer an interactive prompt, so it retries forever — mine spawned 32
dead sessions before I suspended the rig. Nothing is spent, because the session dies before
reaching a model, but nothing progresses either.

Answer it by hand, once per workspace:

```bash
cd ~/cities/my-rig && claude          # answer Yes, then exit
cd ~/cities/my-city/.gc/agents/bd.dog-1 && claude   # each agent workspace too
```

`bd.dog` is the beads maintenance dog and dies on its own workspace. It cannot be turned off
with `gc agent suspend` — *"agent bd.dog is defined by a pack — use [[patches]] to override"*.
Either trust its folder or patch it out; left alone it burns a reconciler wave every tick.

## 9. Sling the workflow — do not just cook it

**`gc formula cook` does not route.** It compiles the formula and materializes the beads so you
can look at them, and then stops. Nothing runs, nothing is assigned, and the supervisor logs
`assignedWorkBeads: 0 beads` forever while the ready queue sits there looking healthy. The
tutorial says so plainly; I spent hours not reading it.

The normal path is one command:

```bash
gc sling work/gc.run-operator check-authoring --formula \
  --var design_path=/abs/path/to.design --var gate_number=01 \
  --var check_path=/abs/path/gate-01.sh \
  --var fixtures_path=/abs/path/gate-01.fixtures.tsv \
  --var notify="A. Rivera, Accounts Payable" \
  --var artifact_root=/abs/path/run
```

`sling` compiles, materializes **and** routes. Use `cook` only when you want to inspect the
graph first — and then sling the root it printed to finish the job:

```bash
gc formula cook check-authoring --rig work --var …     # prints: Root: wk-wdl
gc sling work/gc.run-operator wk-wdl                   # the half that routes
```

Confirm the routing landed rather than trusting the command's output:

```bash
cd ~/cities/my-rig && gc bd show wk-wdl --json | grep routed_to
#   gc.routed_to = work/gc.run-operator
```

You should also see the pool respond in the supervisor log — `poolDesired` for your target goes
up by one per routed workflow.

A seven-step formula cooks to fourteen beads: your steps, plus a spec sidecar, an iteration and
a control for each `[steps.check]`, plus the gate bead and `workflow-finalize`. Expect the count
to differ from what you wrote — that is the compiler, not a fault.

Check the graph gated correctly:

```bash
gc bd ready          # only the first step, not all of them
```

## 10. Watch the agents on the city's own tmux socket

**Each city gets its own tmux socket, named after the city.** Plain `tmux ls` reads the default
socket, finds nothing, and tells you no server is running while four agents are working a few
inches away. I reported that as a finding three times before checking.

```bash
ls /private/tmp/tmux-501/            # one socket per city
tmux -L my-city ls                   # the sessions actually running
tmux -L my-city attach -t gc__run-operator-pc-xxxxx     # watch one work
tmux -L my-city capture-pane -p -t gc__run-operator-pc-xxxxx | tail -30
```

`capture-pane` is the one to reach for: it prints what the agent is doing without attaching, so
you can check on a session from a script without stealing the terminal. It also shows the
session's running token count, which is how you notice an agent that is meandering rather than
working.

## When an agent cannot claim

If a session starts, stays alive and never claims anything, check what it is actually running:

```bash
tmux -L my-city capture-pane -p -t gc__run-operator-pc-xxxxx | tail -30
```

An agent reporting `PREFLIGHT FAIL: gc gc claim not registered` has a correct prompt and a
misconfigured city — step 3, one or both halves. The claim protocol itself is easy to test by
hand, and needs no model:

```bash
cd ~/cities/my-rig && GC_AGENT=work/gc.run-operator gc hook --claim --json
```

A healthy answer claims a bead and assigns its continuation group:

```json
{ "ok": true, "reason": "claimed", "bead_id": "wk-1ku",
  "assignee": "work--gc__run-operator", "root_bead_id": "wk-wdl",
  "continuation_assigned": ["wk-5of","wk-cdd","wk-ljf","wk-oen","wk-q12"] }
```

If that works and the agent still cannot, the problem is the agent's prompt or its pack version,
not routing.

## Other things that bit

**`gc dolt` is pack-projected** and stopped resolving partway through — `gc: unknown flag:
--dry-run` — after the pack set changed. Check `.beads/config.yaml` directly instead; it is the
durable evidence anyway.

**A `brew upgrade` of gascity moves the bead schema.** `bd` 1.3.0 expects v66; an older city's
database stays where it was and every command then warns *"refusing to auto-apply 13 pending
schema migrations to a shared server database"*. That is bd protecting co-resident clients on
the old schema, not damage. `bd migrate schema` applies them — but every client touching that
database must be on the new version first, so back up `.beads/dolt` and do it deliberately.

## The drift semantics

The pack specification is explicit that it has none:

> The specification contains **no normative drift or staleness detection semantics.** It does
> not define when or how an operator discovers that a resolved pack directory no longer matches
> its upstream source.

`requires_gc` exists as pack metadata and is **not enforced** — the spec says enforcement "must
be introduced by an explicit future implementation change." So a city can run packs its binary
was never tested against, and nothing says so.

`make city-preflight` defines six properties in place of that gap:

| | |
|---|---|
| **PINNED** | every import declares a version. A blank one floats, which is worse than stale — it changes between installs and yesterday's behavior cannot be reproduced |
| **COHERENT** | declared, locked and resolved agree, per import |
| **UNIFIED** | every import of one pack family resolves to one version. Prompts and commands ship together and must match |
| **CURRENT** | the declared sha is upstream `main`, or knowingly behind. Builtins are exempt — `gc init` pins those to the binary |
| **CAPABLE** | `gc hook --claim` answers and `gc.run-operator` resolves |
| **CONSISTENT** | **the claim command the role prompt mandates exists in this city** |

The last one is the point. A version number tells you which number somebody wrote down. It does
not tell you whether `gc gc claim` exists. The preflight reads the installed prompt, extracts the
command it mandates, and checks that command resolves — the same shape as refusing a formula
whose check script is missing, one layer up.

A city that fails any of these is a city whose capability surface you cannot see, and formulas
written against it may be written for commands it does not have.
