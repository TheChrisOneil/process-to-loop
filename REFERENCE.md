# The Gas City formula surface

What a formula can contain, for the purpose of writing a compiler that emits them.

**Primary source:** <https://docs.gascity.com/reference/specs/formula-spec-v2> — the formulas v2
contract. Read it. This file is a working digest organized as a compile target, not a
replacement for it.

**Verification:** every rule marked **[v]** below was reproduced against the installed `gc` by
`./probe.sh`, which builds a throwaway, never-registered city and feeds it one malformed
formula at a time. Counts marked **[c]** are from a corpus of 96 unique `*.formula.toml` files
(deduplicated by content) gathered from working Gas City installations. Where the spec and this machine disagree, the spec wins and the difference is noted.

## What a formula is

`gc formula --help`, verbatim:

> A formula is a reusable TOML method for how multi-step work should be done (a bead is the
> work itself).

That is why it is a good compile target. A design describes a method. A formula *is* a method.
The unit of work arrives separately, as a bead.

## The data model (spec §0)

A formula encodes **how** work proceeds — steps, ordering, dependencies, control flow —
independent of storage. It produces work when applied; it is not itself work.

```
formula (TOML)
  → compiled recipe            flat, topologically ordered
    → workflow root bead       type "task", gc.kind = "workflow"
    + step beads               independently routable work, blocking edges only
    + control beads            orchestrator-owned: check, retry, fanout, drain,
                               scope-check, workflow-finalize
```

**The execution split is the thing to internalize.** The orchestrator executes every control
bead. Agents execute only plain work beads. Your compiler authors work beads and *declares*
control; it never authors a control bead directly.

How v2 differs from v1, because the local corpus is full of both:

| Axis | v1 | v2 |
|---|---|---|
| Shape | parent-child molecule tree | flat graph, blocking edges only |
| Engine | none; conditions resolve at cook time | the orchestrator's control dispatcher |
| Advancement | agents, inside their own sessions | the orchestrator, outside them |
| Fan-out | manual routing across agents | per-step routing at dispatch; drain and on_complete scatter at runtime |
| Root | the container root is the handle | the root blocks on `workflow-finalize` |

## Start here — six things that bite a compiler author

1. **Canonical filename is `formulas/<name>.toml`.** `<name>.formula.toml` is accepted but
   **deprecated**, and the infix is not part of the name. Every file in the local corpus uses
   the deprecated form. Emit `<name>.toml`. **[v]**
2. **Opt in with `[requires] formula_compiler = ">=2.0.0"`.** `contract = "graph.v2"` is the
   deprecated opt-in and warns in `gc doctor`. 78 of 96 local files still use it. **[c]**
3. **Graph-only constructs force that opt-in.** `check`, `retry`, `drain`, `on_complete` and
   authored reserved `gc.*` metadata all fail without it.
4. **`check`, `retry` and `drain` are mutually exclusive on one step.** The full matrix is
   below. This is the single most likely thing to get wrong when generating steps. **[v]**
5. **A v2 graph grows a step.** The compiler appends `workflow-finalize`, depending on every
   sink. One authored step compiles to two. **[v]**
6. **`gc converge` accepts only v1 formulas and rejects v2.** If your compiler emits v2 — and
   it must, to use gates — convergence loops are not available to its output.

## Top-level keys

| Key | Type | Req | Notes |
|---|---|---|---|
| `formula` | string | **yes** | unique name |
| `description` | string | no | prose; `{{var}}` substituted |
| `type` | string | no | `workflow` (default), `expansion`, `aspect` |
| `extends` | []string | no | parent formulas; circular chains fail |
| `contract` | string | no | only `graph.v2`; **deprecated** |
| `phase` | string | no | `liquid` or `vapor`; v1 compat, avoid |
| `pour` | bool | no | monotonic through `extends` — an ancestor's `true` sticks |
| `[requires]` | table | no | `formula_compiler` semver; **unknown keys fail** |
| `[catalog]` | table | no | `name`, `description` — opts into catalog discovery |
| `[vars]` | table | no | declarations |
| `[[steps]]` | array | no | the work |
| `[template]` | array | no | `type = "expansion"` only |
| `[compose]` | table | no | `bond_points`, `hooks`, `expand`, `map`, `branch`, `gate`, `aspects` |
| `[[advice]]` | array | no | before/after/around transformations |
| `[[pointcuts]]` | array | no | `type = "aspect"` only |

Unknown top-level keys are silently ignored — except unknown keys inside `[requires]`, which
fail. **[v]** A typo'd top-level key is a no-op your compiler must not produce.

## `[vars]`

Two forms: `name = "default"` shorthand, or a table.

| Key | Notes |
|---|---|
| `description` | shown by `gc formula show` |
| `default` | empty string is valid |
| `required` | **cannot be combined with `default`** — `vars.x: cannot have both required:true and default` **[v]** |
| `enum` | []string, enforced at instantiation |
| `pattern` | regex, enforced at instantiation |
| `type` | `string`/`int`/`bool` — **parsed but never enforced** |

**Reserved names: `convoy_id` and `bead_id` cannot be declared** — `vars.convoy_id: formulas v2
reserved variable cannot be declared` **[v]**, and callers cannot supply them either.
`{{bead_id}}` is gone in v2; use `{{convoy_id}}`. `{{issue}}` is a deprecated alias that warns
at cook and sling.

`{{key}}` substitutes into `description`, `title`, `notes`, `assignee` and metadata *values*.

## `[[steps]]`

| Key | Req | Notes |
|---|---|---|
| `id` | **yes** | unique across the formula **including `children`** **[v]** |
| `title` | **yes** | unless `expand` is set **[v]** |
| `description` | no | the instruction body |
| `description_file` | no | path to Markdown; must resolve or v2 **fails fast** **[v]**; over 4096B it becomes a pointer |
| `notes` | no | |
| `type` | no | `task`/`bug`/`feature`/`epic`/`chore` — not validated |
| `priority` | no | int 0–4; out of range rejected |
| `tags` | no | []string. The TOML key is `tags`; `labels` is the deprecated JSON form |
| `assignee` | no | |
| `needs` / `depends_on` | no | aliases; both become blocking edges; must resolve **[v]** |
| `condition` | no | compile-time filter: `{{v}}`, `!{{v}}`, `{{v}} == x`, `{{v}} != x` |
| `children` | no | nested steps, same schema, shared id namespace |
| `expand` / `expand_vars` | no | inline expansion; the step is replaced |
| `waits_for` | no | `all-children`, `any-children`, `children-of(id)`. The edge blocks; the **mode is inert** |
| `metadata` | no | string map; `gc.*` reserved |
| `[steps.check]` | no | graph-only |
| `[steps.retry]` | no | graph-only |
| `[steps.drain]` | no | graph-only |
| `[steps.on_complete]` | no | graph-only |
| `[steps.gate]` | no | `{type, id, timeout}`. **The gate blocks; the `type` is inert** — see §4 |
| `[steps.loop]` | no | see below; until-loops are **inert** |
| `timeout` | no | positive Go duration; **requires `check`** |
| `[steps.tally]` | — | **removed** — `steps.tally was removed from the SDK` |

Unknown step keys are silently ignored.

### `[steps.check]` — the gate

```toml
[steps.check]
max_attempts = 1                  # required, >= 1                     [v]
[steps.check.check]
mode = "exec"                     # required, only exec supported      [v]
path = ".gc/scripts/checks/x.sh"  # required, non-empty                [v]
timeout = "2m"                    # positive duration; beats step timeout
```

**Script exit codes are the contract:**

| Exit | Meaning |
|---|---|
| `0` | pass — the step closes |
| `75` | infrastructure unreachable — re-run, **attempt not consumed** |
| other | "not yet" — consumes an attempt |

Materializes as a spec sidecar, an iteration bead, and a control bead of kind `ralph`.

### `[steps.retry]`

```toml
max_attempts = 2                  # >= 1                                [v]
on_exhausted = "hard_fail"        # hard_fail (default) | soft_fail     [v]
```

`soft_fail` closes the control as passed with `gc.final_disposition = soft_fail`.

### `[steps.drain]` — fan-out

```toml
formula = "item-formula"          # required; no {{templated}} names    [v]
context = "separate"              # separate (default) | shared         [v]
member_access = "read"            # read (default) | exclusive          [v]
max_units = 100                   # [1,100], default 100 — a hard cap
on_item_failure = "continue"      # skip_remaining | continue           [v]
continuation_group = "..."        # only with context = "shared"
[steps.drain.item]
single_lane = true                # must be true for shared drains
```

`on_item_failure` defaults differ by context: `continue` for separate, `skip_remaining` for
shared. **The item formula must itself declare the v2 contract.** Drain forces targeted
invocation.

### `[steps.on_complete]` — fan-out over structured output

`for_each` (must start with `output.`) and `bond` are required together; `parallel` (default
true) and `sequential` are mutually exclusive. Placeholders `{item}`, `{item.field}`, `{index}`.

### `[steps.loop]`

Exactly one of `count`, `until`, `range`; `body` non-empty; `max` required with `until`.
**Until-loop re-execution is inert** — see §4. Use `check` for orchestrator-driven
re-execution.

## The incompatibility matrix

A step may carry at most one of these, with these exclusions:

| Construct | Cannot combine with |
|---|---|
| `check` | `loop`, `on_complete`, `gate`, `expand`, `assignee`, `retry` **[v]** |
| `retry` | `check` **[v]**, `loop`, `on_complete`, `gate`, `expand`, `children` |
| `drain` | `assignee`, `expand`, `gate`, `loop`, `on_complete`, `check`, `retry`, `children`, `timeout`, authored `gc.kind` |

This is the constraint a generator will violate first. A step that both runs a model and
carries its own gate is not expressible — the gate is a separate step, or the check is the
step. That is the same conclusion the loop's V17 reaches from the other direction.

## Reserved `gc.*` metadata

| Key | Author may set | Purpose |
|---|---|---|
| `gc.run_target` | yes | routing intent; resolved to `gc.routed_to` at dispatch. 358 uses **[c]** |
| `gc.scope_name`, `gc.scope_role`, `gc.scope_ref` | yes | scoping; `scope_role` ∈ setup/member/teardown/body/control |
| `gc.on_fail` | yes | only `abort_scope` |
| `gc.continuation_group` | yes | shared execution group |
| `gc.kind` | **only `scope`, `cleanup`** | everything else is compiler-owned |
| `gc.output_json_required` | compiler | |
| `gc.output_json` | **deprecated** | `gc lint` warns; use `drain` |
| `gc.model` | **deprecated** | use `opt_model`; `gc doctor` migrates |
| `opt_*` | yes | provider options, validated at spawn |

Authoring any reserved `gc.*` key forces the v2 declaration.

`gc.kind` vocabulary — control kinds `retry`, `ralph`, `check`, `retry-eval`, `fanout`,
`drain`, `scope-check`, `workflow-finalize` are dispatched; `scope`, `cleanup`, `run`,
`retry-run` are structural and never dispatched; `workflow`, `wisp` are roots; `spec` is a
sidecar.

## File resolution

`formulas/<name>.toml` (canonical) beats `<name>.formula.toml` (deprecated) beats
`<name>.formula.json` (loader-only), within a layer. Layers, lowest to highest: city packs,
city's own `formulas/`, rig packs, rig `formulas_dir`. Last wins. `[formulas].dir` in
`city.toml` is a hard error.

## Compilation (spec §2)

Ten deterministic stages, in order: load and resolve `extends` → reserved-symbol validation →
control-flow expansion → advice, then inline expansion → compose expand/map, then aspects →
condition filtering, then standalone expansion → requirement merge and the explicit-declaration
check → retry transform, then check transform → host requirement validation → graph validation,
control injection, recipe.

Two consequences for a generator:

- **The explicit-declaration check runs *after* expansion and aspects.** A construct composed
  in from a parent triggers it too. You cannot dodge the v2 opt-in by inheriting `check`.
- **The retry and check transforms run late.** What you author as one step with a `check`
  becomes a spec sidecar, an iteration bead and a control bead. Your step counts will not match
  the compiled graph.

### Edges

Three kinds, and only the first blocks readiness in the way you would expect:

| Edge | From | Meaning |
|---|---|---|
| `blocks` | `needs` / `depends_on` | ordinary blocking dependency |
| `waits-for` | `waits_for` | readiness-blocking; the all/any distinction is inert in v0 |
| `tracks` | compiler | informational, non-blocking; cascade deletion, and root → finalizer |

**There are no parent-child edges.** `children` affects the ID namespace and validation only,
never runtime hierarchy. A step does not wait for its children unless you say so in `needs`.

### Root stamping

The recipe root is type `task`, `gc.kind = "workflow"`, plus a `gc.formula_contract` marker.
Sling adds `gc.input_convoy_id` (targeted), `gc.graphv2_root_key` (idempotency) and
`gc.graphv2_vars.v1` (a variable snapshot). Non-batch adds `gc.formula_source` and
**`gc.formula_hash`, a SHA-256 of the raw formula bytes**.

That hash matters to you: **Gas City already content-hashes the method.** An acceptance
register should sign that hash rather than invent its own.

### The close-ownership invariant

**The compiled graph never blocks a node on the control bead that closes it.** A scope body is
not blocked by its scope-checks; the workflow root is not blocked by `workflow-finalize`, which
is why the root reaches it through `tracks` instead. Such an edge is a permanent deadlock — the
store refuses to close a blocked issue, and the only bead that could clear the blocker is the
one being refused. The compiler rejects recipes containing it.

Your generator must not emit one either, and the case it will reach for is exactly the wrong
one: making a step depend on its own gate.

## Scopes and failure policy (spec §3.5)

A scope groups steps under one durable failure policy. The body is an authored step with
`gc.kind = "scope"`, a `gc.scope_name`, and `gc.scope_role = "body"`. Members carry
`gc.scope_ref = "<body-step-id>"` and a role of `setup`, `member` or `teardown`. Cleanup steps
use `gc.kind = "cleanup"`. The compiler injects a `<step>-scope-check` control per member.
`scope` and `cleanup` are the only `gc.kind` values an author may set.

`gc.on_fail = "abort_scope"` is the only specified value. On a member failure the orchestrator
skips the remaining open members, propagates the member's non-`gc.*` metadata onto the body so
diagnostics survive, and closes the body `gc.outcome = fail`.

**The worker-result contract is fail-closed, and this is the rule generated steps must honor:**
a member that closes with `gc.outcome = fail` counts as failed — and so does a member with a
**missing or unknown** `gc.outcome`. Only `pass` and `skipped` do not abort the scope. Every
step your compiler emits must close with an explicit outcome, or it will abort a scope by
saying nothing.

**Teardown outlives settlement.** Teardown steps never block `workflow-finalize` and are left
open when finalize closes everything else, so they still run. They may read the run's final
`gc.outcome` — which gives you "clean up on pass, preserve the workspace on fail" for free.
Teardown never re-grades the root.

**Finalize** aggregates blocker outcomes into one pass/fail, closes the root first for
crash-recovery, closes the spec sidecars, and on pass only propagates closure along the
`gc.source_bead_id` chain. A failure deliberately leaves parent source beads open for
investigation.

## Composition and inheritance (spec §1.7)

`extends` merges parents into a child:

- **Steps** — a child step with the same id **replaces the parent's whole step**, in the
  parent's position. No field-level merge. New child steps append.
- **Vars** — inherited, child overrides.
- **`phase`** — child, else the first parent declaring one.
- **`pour`** — monotonic. Any ancestor's `true` sticks and a child cannot opt out.
- **`contract` / `requires`** — child, else first parent; but requirement *constraints* are
  collected from **every** parent and validated as a set. A child may only tighten.
- **Circular chains** fail: `circular extends detected: a -> b -> a`.

**A formula resolved through `extends` drops `advice` and `pointcuts` entirely — including its
own.** When both sides declare `compose`, the merge keeps `bond_points`, `hooks`, `expand` and
`map`, and drops `branch`, `gate` and `aspects` from both. If your compiler ever emits those,
inheritance will silently delete them.

## Conformance (spec §5)

`formula_compiler` is the **only** `[requires]` axis. A bad comparator fails
`formula.compiler_requirement_invalid`; an unknown axis fails `formula.requirement_unknown`.
The host switch is `[daemon] formula_v2` in `city.toml`, default `true`; with it off, compiler
capability is 1.0.0 and every v2 formula fails to compile.

`gc doctor`'s `formula-requirements` check reports per layer: parse failures as errors,
deprecated `contract = "graph.v2"` as a warning, graph-only constructs without the v2
declaration as an error, host mismatches as an error. `gc lint` warns on deprecated
`gc.output_json`; warnings do not fail lint.

Run both in the compiler's own test loop. They are the equivalent of `make ready`.

## Accepted but inert (spec §4)

Four constructs the parser and compiler accept that **no runtime component consumes** in the
current release. They raise **no error and no warning** — they simply sit in the formula doing
nothing, which makes them the most dangerous thing on this page for a generator. Distinct from
*removed* constructs, which fail compilation (`steps.tally`), and *deprecated* ones, which warn
and have a replacement (`contract = "graph.v2"`, `{{issue}}`, `gc.output_json`, `gc.model`).

| # | Construct | What the compiler does | What never happens |
|---|---|---|---|
| 1 | `[steps.loop]` with `until` + `max` | validates the condition, writes a `loop:` label carrying `{"until":…,"max":…}` on the first body step | nothing reads the label. **Exactly one iteration runs**, whatever the condition or budget |
| 2 | `[steps.gate].type` — `gh:run`, `gh:pr`, `timer`, `human`, `mail` | records the value **without validating it** | no bundled watcher acts on any of them |
| 3 | `waits_for` modes | compiles a readiness-blocking `waits-for` edge **plus** a gate-mode label | no dispatcher interprets `all-children` vs `any-children` |
| 4 | `[vars.<name>].type` — `string`, `int`, `bool` | parses it into the variable definition | never enforced. Only `required`, `enum` and `pattern` are checked at instantiation |

**Read 2 and 3 carefully, because half of each one works.**

For the gate, the compiler **synthesizes a real gate bead** (type `gate`) that blocks its step
until that bead is closed — manually, or by a watcher you write. The blocking is real. Only the
`type` vocabulary is decoration.

That makes `[steps.gate]` the honest primitive for a named human approval: a hold that nothing
can pass until a person closes it. It is stronger than a prompt asking an agent to wait. Emit
it, put the approver's name in the step, and write your own watcher if you want automation —
but do not expect `type = "human"` to summon one.

Likewise `waits_for` genuinely blocks readiness. Only the all/any distinction is ignored, so
treat every mode as "all" and do not encode meaning in the choice.

Zero bundled formulas use `gate` or `waits_for`, and none of the 96 in that corpus do either. If
your compiler emits them it is the first thing in this city that does.

**Compiler rule:** never emit construct 1 or 4, and never let a validation rule depend on 2 or
3's inert half. A rule that trusts an inert construct is a rule that does nothing, which is the
failure mode this whole project exists to catch.

## What gc enforces — reproduced locally

`./probe.sh` reproduces: step `id` required; `title` required unless `expand`; duplicate id;
`needs` unresolved; dependency cycle; `check.max_attempts >= 1`; `check.check.mode` exec only;
`check.check.path` required; `on_exhausted` enum; all four drain enums; `required`+`default`
conflict; reserved variable declaration; check/retry incompatibility.

## What gc does not enforce — where your rules live

| Not checked | Consequence |
|---|---|
| A formula with no steps | compiles; `Root only: true` **[v]** |
| A step with no description | compiles; an empty instruction **[v]** |
| `{{undeclared_var}}` | compiles; ships literal braces to the agent **[v]** |
| An unknown top-level or step key | silently ignored **[v]** |
| **A check script that does not exist** | **compiles — a gate that cannot run** **[v]** |
| Whether any step has a check at all | compiles; a formula with no gates is valid |
| Whether a human approves anything | compiles |
| `vars.<name>.type` | parsed, never enforced |
| Whether the method is any good | not its job |

The missing check script is the formula equivalent of the scaffolder bug that dropped a gate:
declared, reported, absent. gc will not catch it. The compiler must.

## The compiler's own rules

Carried from the loop compiler's 22, which are about method quality and therefore do not
overlap with gc's structural set:

| Loop rule | Formula equivalent |
|---|---|
| V3 named approver | a human gate step exists with `notify` bound to a person |
| V4 exit criterion has a figure | no native field — `[catalog]` or metadata, by convention |
| V7 a judgment names its check | every step with `gc.provider`/`opt_model` has a downstream `check` step |
| V13 thinking is followed by a test | same, over `needs` |
| V14 at least two gates | at least two `[steps.check]` blocks |
| V15 a condition has a number | the check script **exists and is executable** — stronger than prose |
| V16 a refusal names the next action | the check's non-zero output names one |
| V17 proof written mechanically | the artifact step carries no provider — and the matrix enforces half of this already |
| V19 three KPIs | no native field — by convention |
| V21 batch before unit | parent formula plus `[steps.drain]` item formula |

New rules the formula target demands:

- Every `check.check.path` resolves to an existing, executable file.
- Every `{{var}}` used is declared, and is not `convoy_id` or `bead_id`.
- Every `description_file` resolves.
- `formula`, `[catalog].name` and the filename agree.
- No step carries two of `check`, `retry`, `drain`.
- Emit `[requires] formula_compiler`, never bare `contract`.
- Emit `<name>.toml`, never `<name>.formula.toml`.
- Any drain's item formula also declares v2.
- Exit 75 is reserved — a generated check script must not return it for a business failure.
- Every emitted step closes with an explicit `gc.outcome` — silence reads as failure.
- No step is blocked on the control bead that closes it (the close-ownership invariant).
- Nothing relies on `children` for ordering; ordering is `needs` or it does not exist.
- Cleanup belongs in a `teardown` scope member, never in the last work step.
- No `until` loop and no `vars.type` is ever emitted; both are inert.
- A human approval is a `[steps.gate]`, whose block is real, not a `type` that is not.

## Reproducing

```bash
./probe.sh
```

Builds a city in a temp dir and never registers it, so no controller and no patrol runs
against it. Diff its output against a new `gc` rather than trusting this file.

## Coverage against the spec's contents

| Spec section | Here |
|---|---|
| 0 Concept and Data Model | The data model |
| 1.1 File Naming and Layers | File resolution |
| 1.2 Top-Level Keys | Top-level keys |
| 1.3 Steps | `[[steps]]`, the incompatibility matrix |
| 1.4 Variables | `[vars]` |
| 1.5 Conditions | `[[steps]]` — `condition` grammar only |
| 1.6 Loops | `[steps.loop]` — summary |
| 1.7 Composition and Inheritance | Composition and inheritance |
| 1.8 Description Files | `[[steps]]` — resolution and the 4096B pointer |
| 1.9 Validation | What gc enforces / does not enforce |
| 2 Compilation | Compilation |
| 3.1–3.3 Check, Retry, Drain | the three sub-tables |
| 3.4 On-Complete and Tally | `[steps.on_complete]`; tally removed |
| 3.5 Scopes and Failure Policy | Scopes and failure policy |
| 4 Accepted But Inert | Accepted but inert |
| 5 Conformance and Compatibility | Conformance |

Thin by choice: 1.5, 1.6, and the aspect/advice/pointcut surface. Read the spec for those
before using them.
