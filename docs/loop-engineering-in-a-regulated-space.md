# Loop Engineering in a Regulated Space

What this project is, why it is shaped the way it is, and what we have learned
building it. Written 2026-10-07, against Linas Beliūnas, *"Loop Engineering: How
to Design AI Loops That Build, Ship, and Improve While You Sleep"* (2026-06-10).

---

## The sentence this project answers

That guide is a good map of loop engineering as practised today. Near the end it
lists where loops do **not** work, and one line names us exactly:

> **Safety-critical systems** — Medical, legal, or financial systems where the
> process itself is regulated, not just the outcome.

It is right about the reason. A loop's exit condition has to be
machine-verifiable — *"all CI checks passing"*, *"the test suite is green"*. In a
regulated process the outcome is not the only thing being judged. **The process
is.** An auditor does not ask whether the right answer came out; they ask what
was checked, by whom, against what rule, on what authority, and where it is
written down. A green check answers none of that.

So the exclusion is not a gap in tooling. It is a statement that the loop
pattern, as described, has no vocabulary for the thing being regulated.

**This project is the attempt to give it one.** Everything below follows from a
single move: *make the process itself the artifact.* Not a prompt that describes
a process. A file that **is** one, that rules can refuse, a different model can
attack, a named person signs by content hash, and a compiler turns into something
that runs.

---

## Two loops, and only one of them is regulated

This is the distinction worth being rigid about, because everything confusing
about the project dissolves once it is held:

| | **L1 — the design loop** | **L2 — the emitted loop** |
|---|---|---|
| what it is | `design-authoring`, a Gas City formula | a standalone bundle + launchd job |
| what it consumes | a described process, in a person's own words | real records, on a schedule |
| what it produces | a signed design, and L2 | decisions, a ledger, refusals |
| is it regulated? | **no.** It is a development tool | **yes.** This is the thing an auditor reads |
| may it be a rehearsal? | **yes**, and it must say so | **no** |
| may its answers be synthetic? | yes, marked, counted, raised as a finding | no |
| who may close its gates | a person, or a recorded rehearsal | n/a — it has no human gates, only refusals |

**L1's entire job is to make L2 provable.** L1 is allowed to run on fabricated
tools, synthetic answers and rehearsed gates — because nothing it produces
touches a patient until a person signs it. L2 is allowed none of that.

Confusing the two is the single most expensive mistake available here. A control
that belongs in L2 and is implemented in L1 is advice. A control that belongs in
L1 and is implemented in L2 is ceremony at run time, every tick, forever.

### Yes, it is a loop that designs loops

L1 is itself a loop in the article's sense — it has a goal, iterations, a
between-iterations check and a machine-verifiable exit. Its *author* step is a
textbook Ralph loop: write, validate, audit on another provider, classify
findings, repeat up to five times. The recursion is real and it is not a trick:
the thing that makes a regulated loop defensible is a process, and a process is
exactly what a loop is good at producing.

---

## The anatomy, compared

The article gives a loop three parts. They are all present here, and a regulated
process needs five more that the article has no slot for.

### What the article specifies

```
GOAL         "all CI checks passing"
ITERATIONS   max 10, between-runs: gh pr checks
EXIT WHEN    all PR checks are success
```

### What L1 actually is

```
GOAL         a design that passes 39 rules, survives an audit by a different
             provider, and carries a named person's signature over its content hash
ITERATIONS   max 5 on the author step; between-runs: validate, audit, classify
EXIT WHEN    no finding remains that a revision could fix
```

### The five fields a regulated loop adds

| field | why the article has no slot for it |
|---|---|
| **provenance of the inputs** | *where did this value come from, through which tool, under which permission* — a green check does not say |
| **the judgment, isolated** | exactly one per unit, and what checks it. "The model decided" is not an answer to an auditor |
| **the refusal text** | every gate names the **next human action**. "Needs review" is a state, not an action |
| **the evidence writer** | proof must be written by a step that did not make the claim. Evidence a model can edit is not evidence |
| **the acceptance** | a named person, over a **content hash**, in a chained register. Not a click, not a filename |

Those five are the whole difference between a loop that ships code and a loop
that can be defended to a regulator.

---

## The primitives, compared

The article names six primitives. Ours overlap about half, and the differences
are the interesting part.

| the article's | ours | what changed, and why |
|---|---|---|
| **Automations** — the heartbeat | **the formula is the pipeline** | Every step that used to be a command somebody remembered to run is a step *inside the formula*, in order, with the gates between them. A step that is not in the flow is a step somebody can skip |
| **Worktrees** — parallel without chaos | *(inherited from Gas City)* | Real, and not where our risk lives |
| **Skills** — stop re-explaining | **the method files** (`GENERATE.md`, `INTERVIEW.md`, `CONTRACT.md`) | Same idea, one addition: `INTERVIEW.md` is **versioned**, because two interviews run from different scripts produce use cases nobody can compare |
| **Connectors** — touch real tools | **the tool catalog** | The larger move. Not *"what can the agent reach"* but *"what has the organization sanctioned, for which data class, under whose decision, reviewed when"*. An entry is a **decision**, not an inventory row |
| **Sub-agents** — maker and checker | **a different PROVIDER, not a different agent** | Two models from one lab share training and tooling. The verdict check refuses when author and auditor are the same model |
| **State** — memory on disk | **beads, and a chained register** | A markdown file is enough for a dev loop. A regulated process needs a record that survives the working directory and cannot be edited without detection |
| — | **the interview** | No equivalent. The article's loops start from a spec somebody wrote. Ours starts by discovering that the spec is missing seven things, and asking |
| — | **the exit criterion** | The number on which you shut the loop down. The article's loops exit when done; ours must also say when to **stop running it at all** |

---

## The pipeline as it stands

```
intake → questions → answers → answered → author ⟲ → validate → audited
       → render → diagrams → findings → ACCEPT → compile → records
```

Thirteen steps, seven of them gates. Three are held by a person: the answers, the
acceptance, and — implicitly — any refusal the emitted loop produces.

**Dialogue is the opening move, not a refinement pass.** `@sources` cannot be
written before the schema is known, and no gate can reference a field before
`@sources` exists. Asking afterwards is asking about a guess already built on.

**The design is judged three times before a person is asked, cheapest first:**
the rules (39, deterministic, free), the audit (a different provider, seven
dimensions the rules cannot reach), and the verdict check (deterministic: *did
the audit happen, on another model, about THIS design*). Only then a person.

---

## Where the article's three debts land here

The article names three debts that worsen as loops improve. Two of them we have
answers for. The third we have only partly answered, and it is the one that
matters most.

### 1. Comprehension debt — *partly answered*

The gap between what exists and what you understand. Our answer is that the
**design is the source and the formula is a build artifact**: a person reads a
plain-text file with `@steps` and `@gates`, not generated bash. The brief, both
diagrams and `FINDINGS.md` exist so the thing a person reads is not the thing a
machine runs.

Unanswered: nobody has yet read a design this system produced and had to
maintain it six months later.

### 2. Cognitive surrender — *answered structurally*

Accepting the model's output without forming a judgment. Three controls:

- the **audit runs on a different provider**, so the critique is not the author agreeing with itself
- **every finding needs a decision** — fixed, or accepted with a reason written down. An unexplained acceptance is indistinguishable from not reading it
- the **interview** forces the questions into the open before the design exists, instead of surfacing 44 assumptions after it

### 3. Verification remains on you — *this is the whole project*

> *"'Done' is a claim, not a proof."*

Every control here is a different way of refusing to accept a claim:

| the claim | what refuses to take its word |
|---|---|
| "the design is sound" | 39 rules, then a different provider, then a person |
| "it was audited" | a verdict stamped with the design's SHA-256; a gate refuses a mismatch |
| "the gate exists" | F5 refuses a formula naming a check script that is not on disk |
| "it keeps records" | the records gate **runs a tick** and reads the ledger |
| "the tool was allowed to see this" | the ledger row carries the permission the read ran under |
| "a person approved it" | a chained register, signer must equal `@meta.approver`, over content |
| "a person answered the questions" | `synthetic` on every answer supplied on their behalf, counted and raised |

The recurring failure this project exists to catch has a name we use constantly:
**declared, reported, absent.** A control that is declared in the design,
reported as having run, and not actually there. Every one of the rows above is a
place that was found, or could be.

---

## What we have discovered

The full log is `DISCOVERIES.md`, one entry per finding, dated and additive.
The themes:

**Every expensive defect was at the formula↔script boundary.** Environment, cwd,
install location — never business logic. And each one *reported something other
than its cause*: a missing API key read as "your design needs revision", an
unreachable bead store as "DESIGN_PATH is not set", an unset `$USER` as a locked
keychain. The fix was always cheap; the diagnosis expensive. Adding diagnostics
that print **where it looked** collapsed later diagnoses from hours to one step.

**Exit codes are a safety control, not a convention.** 0 pass / 1 refused
(business) / 75 could not run (infrastructure). Collapse 75 into 1 and an
infrastructure failure consumes a revision attempt and reads to a person as a
defective design.

**A control that leaves no bead leaves no evidence.** The audit gate was folded
into the authoring loop; the step closed `pass` three times having written no
verdict at all, and nothing downstream could tell. A gate that is its own step
leaves a record a person can read afterwards.

**Two copies of a definition become two dialects.** The cell semantics of a
decision table live in one file loaded by both the validator and the emitted
check. The first divergence would be between the rules that passed a design and
the check that enforces it.

**Policy belongs in the catalog, not in the rules.** V31 said *no tool carrying
PHI may be used by a model step*. That read like a fact about PHI and was really
a fact about what the company had signed. When a BAA covering both model
providers was confirmed, the rule was wrong — and a rule you must edit when a
contract changes is in the wrong place. It reads the catalog now, and refuses a
**lapsed attestation**, because a stale catalog asserting a tool is safe is worse
than no catalog: designs cite it.

**Three answers make dialogue possible.** `stated` / `unanswered` / `delegated`.
Without the third a run stalls on the first thing nobody knows. With it, *"you
pick it"* is always safe to say, because a delegated **structural** choice comes
back as a finding before signing — the decision is deferred to the signing
moment, not removed.

**A rehearsal must be a property of the artifact, not of the run.** Marked on the
beads, on the register row, in the findings, and in the question set. The beads
matter most: files get archived and overwritten, and the beads outlive them.

**Attribution beats prevention, where prevention is impossible.** We cannot stop
a person delegating every structural question. We can make the ratio visible at
the gate, and make a wholly synthetic interview a **critical** finding.

---

## What is not built

Stated plainly, because a document that lists only what works is marketing.

- **The gate check scripts.** The emitted bundle refuses at its first gate and
  names the missing file. Gate logic is `check-authoring`'s job, and the
  `@decisions` tables are one way to fill it — the only way where completeness
  and overlap are provable.
- **The catalog over MCP.** The file is truth; the server would be an interface.
  Four readers now justify it; it is still a file.
- **Any run with real answers.** Every interview this system has conducted was
  answered by the system standing in for the owner. That is marked everywhere,
  and it is still the largest untested assumption in the project.
- **Any run with real tools.** Six catalogued tools, all fabricated, all backed
  by CSV and XML fixtures. The pipeline is proven; the integrations are not.
- **Maintenance.** No design here has been revised six months later by somebody
  who did not write it.

---

## The claim, as narrowly as it can be put

A described business process, in a clinician's own words, became: sixteen
questions a person could answer three ways; a design bound by digest to those
answers; thirty-nine deterministic rules; an adversarial audit on a different
provider that found a real deadlock; a signature over a content hash in a chained
register; and a twenty-two step bundle that runs, reads five catalogued sources,
logs the permission each read ran under, and **refuses at the first gate whose
check is not installed.**

Nothing in that sentence is a model being trusted. That is the entire point, and
it is the only reason the article's exclusion might not hold.
