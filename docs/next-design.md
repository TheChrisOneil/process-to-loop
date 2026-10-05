# The next design

What the pipeline should become, decided in discussion on 2026-10-05. Nothing here is built.

The current system turns a described process into a validated, audited, signed design and a
scaffold. Three gaps surfaced while running it against two real processes, and each has a
decided shape.

---

## 1. The design cannot say where its data comes from

A gate compares `$VALUE`. Nothing in the artifact says where `$VALUE` originates, what it is
allowed to come from, or what was used to fetch it. For monthly-close that is most of the risk
and no gate looks at it.

### `@sources` — table

```
id | provides | via | constraint
```

- **provides** — the fields a unit carries from this source
- **via** — the tool that reaches it
- **constraint** — the predicate that must hold

Each row compiles to **a ledger field** recorded per unit, and — where the constraint is
checkable — **a gate** that refuses the run.

Both, deliberately. The gate stops a violation. The ledger proves the non-violation for the 600
receipts that passed, which is what a regulated audit actually asks for.

### `@tools` — table

A tool is not only how a source is reached. It is also a capability a step exercises: `security`
for secrets, `sqlite` for the ledger, `gemini` for a rule proposal. Those belong in their own
table, because the constraint on them is about **what they may do and touch**, not about where
data came from.

The monthly-close use case already states one, in prose, where nothing can enforce it:

> Permitted: propose new rules.yaml entries. **Prohibited:** computing amounts or balances;
> sending raw statements or account numbers to any API.

That is a **tool × data-class permission**. Generalised, it is the control EverBetter needs for
PHI, in the same shape.

### The distinction that must not be lost

**A checkable constraint compiles to a gate.** "Banking is SimpleFIN" — verified once per run.

**A structural constraint compiles to a validator rule.** "The model never saw an account
number" cannot be checked at run time. It is a property of the step graph: the model's only
input is the output of a redacting mechanical step. It has to be enforced on the *design*.

Conflate them and we ship constraints that look enforced and are not — the failure this project
exists to catch, one level up.

### New audit dimension: `source-integrity`

Does every field a gate compares come from a declared source, and **is any stated constraint
unverifiable as written?** The second question is the one worth paying for.

---

## 2. The design cannot ask

The current design carries **44 declared assumptions**, one of which records that the system was
asked to ask and could not:

> *Line 86, the heading OPEN PARAMETERS (ask before building), asks the reader to ask before
> building and was not acted on.*

### The rule

**A dialogue turn becomes an artifact, not a conversation.** The conversation is the interface;
the file is the record. That gives chat ergonomics without putting the audit trail in a
scrollback.

### `QUESTIONS.md`

The same shape as `FINDINGS.md` — one block per question, with provenance and a place to answer,
and a gate that refuses until every block is answered. The file is the **artifact**; the
interview is the **interface**.

### Blocking vs deferrable

- **Structural questions block**: the unit of work, the sources, the schema. A wrong assumption
  here poisons every step downstream.
- **Parametric questions defer**: SLA days, token budget, a threshold. Assume, declare, surface
  with the findings. One interruption instead of eight.

This extends the classification that already exists on findings — `by_revision` vs
`needs_a_person` — rather than inventing a parallel one.

### Three answer types

A question must accept more than an answer, or the run stalls on the first thing nobody knows.

```
stated     by Buzz, process owner, 2026-10-05: accrual basis
unanswered owner Finance, asked 2026-10-05
delegated  by Buzz, process owner, 2026-10-05 — assumed: accrual basis
```

**Delegation is not what happens today.** Today the model assumes silently and declares it among
43 other assumptions nobody reads. Delegation produces the same value with different provenance:
the owner was asked and chose to let the system decide. That is defensible in an audit. "The
system decided and mentioned it afterwards" is not.

**A delegated structural choice becomes an automatic finding.** Delegate the SLA days and that is
the end of it. Delegate the unit of work — the highest-leverage decision in the system — and the
choice lands in `FINDINGS.md` as `needs_a_person`, so the owner sees what was chosen before
signing.

Delegation therefore **defers** a decision to the acceptance gate rather than removing it, which
makes "you pick it" always safe to say: the chance to disagree moves to the point where there is
a whole design to look at, instead of a question answered cold.

**Mark them distinctly at signing.** The acceptance step already puts assumptions in front of the
approver. A delegated assumption must be visually distinct from an inferred one — *"you asked me
to choose this"* is a different claim from *"I inferred this"*.

**Count them.** The failure mode is that delegation becomes the fast path and the design arrives
with 44 assumptions and extra ceremony. The ratio of stated to delegated answers is measurable
per use case, and a use case with more delegated than stated answers says the interview is not
working or the person was not really available. Worth reporting at the acceptance gate, and
possibly worth a KPI.

The audit should treat delegated assumptions as higher risk. They are the ones where nobody with
domain knowledge confirmed anything.

### Consequence: the pipeline reorders

```
intake → questions → answers → author → ...
```

`@sources` cannot be written before the schema is known, and no gate can reference a field before
`@sources` exists. So dialogue is the **opening move**, not a refinement pass.

### The attribution win

Today all 44 assumptions are authored by a model. An auditor cannot tell a confirmed fact from a
surviving guess. After this, some become:

```
answered by Buzz, process owner, 2026-10-05: accrual basis
```

Not "the model assumed" but "the owner stated." For a regulated process that is most of the value.

---

## 3. The intake has no front door

Today a use case is written in another chatbot and pasted into a file. Intake recorded seven
sentences addressed to the system — `You are a senior Python engineer`, `Build the system
specified below`, `1. Repo layout and README` — which exist **because the use case was written as
a prompt for another model.** The seam shows in the artifact.

### The mayor interviews

Conversation produces `use-case.txt`. Four rules:

1. **The mayor transcribes; it does not author.** If it can fill in an answer it did not get, the
   result is indistinguishable from today's model-authored assumptions. Same principle as
   evidence written by something that did not make the claim.
2. **"I don't know" and "you pick it" are both legal answers** — see *Three answer types* above.
   An unanswered question names who owes the answer; a delegated one records that the owner chose
   to let the system decide, and surfaces a structural choice as a finding before signing.
3. **Provenance without transcripts.** A session id and timestamp in the header. A transcript
   invites someone to treat it as authoritative over the file.
4. **A change is a new version.** `intake.use_case_sha256` already exists, so a changed use case
   is detectable, and the design's `@meta.use_case` chains back to it.

### `INTERVIEW.md`

The interview needs a versioned script or two interviews produce incomparable use cases. Its
questions derive from what the design format requires: the unit, the volume, who decides today,
the exceptions, the thresholds, the system of record, who signs.

Design quality will depend on this document more than on the author prompt.

### The honest limit

The mayor lives in tmux. That is fine for one person and wrong for the business people this is
aimed at. We would be prototyping the **interaction**, not the surface.

---

## 4. Language

### The design's own language stays

Plain text with `@sections`. Readable by a student, parseable by awk, writable by a model. Not
JSON, on purpose, and it is working.

### The emitted RPA

The use case says **Python 3.12, SQLite, pytest**. The emitter produces bash, silently. Same
shape as sources: stated in prose, inexpressible in the design, unenforced.

**The contract is already language-neutral:**

```
0   the condition does not hold; work continues
1   refused — a business outcome
75  the check could not run — infrastructure, never a business failure
```

Plus append-only TSV ledger lines. A Python step, a Go binary and a bash script satisfy that
identically.

### Decision

**A bash orchestrator owning the ledger, exit codes and launchd integration; steps in any
language.** `steps/04-categorize.sh` is three lines that `exec python3 categorize.py`. A
`language` column on `@steps`; `@tools` names the runtime with its constraint (`python >= 3.12`);
preflight checks the runtime exists, exactly as it now checks providers.

**Rejected: one emitter per target language.** It trades a small deterministic core for several
larger ones, each re-implementing the ledger and exit-code contract — precisely where divergence
would hide.

### The open fork

**Gate logic as bash conditionals, or DMN-style decision tables?** A decision table is auditable
by inspection, diffable, and readable by a non-programmer — which matters if business people are
meant to own these processes. Bash is more flexible and less reviewable.

This constrains the language question more than the runtime does, and is the more consequential
choice.

---

## Prior art to take from

| | what to take |
|---|---|
| **BPMN / DMN** | the ISO vocabulary an auditor may already know; DMN decision tables as a target for gate logic |
| **Temporal** | the event history *is* the execution, not a side effect of it |
| **dbt** | tests beside the model, lineage and docs generated from one source |
| **Open Policy Agent** | policy as code with a decision log — the right shape for tool × data permissions |
| **Great Expectations** | declarative data constraints with validation results as artifacts |
| **UiPath / Blue Prism** | what not to be: logic in a GUI, hard to diff, review or prove |

---

## Order of work

1. `@sources` alone, and see whether a real design can state its data contract honestly.
2. `QUESTIONS.md` and the blocking/deferrable split.
3. The interview, tested on a process neither of us has seen.
4. `@tools` and permissions, which are only useful once the ledger records them.

Each is separable. None is worth starting before one run completes end to end.
