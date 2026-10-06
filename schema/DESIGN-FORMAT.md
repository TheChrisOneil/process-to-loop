# The design format

One plain-text file describes one agentic loop. It is the artifact every later step reads:
the validator gates on it, the diagram renders from it, the scaffolder builds from it.

Readable by a student, parseable by a script, and writable by a model. Those three constraints
are why it is not JSON.

## Shape

- Sections open with `@name` on its own line.
- Inside a **keyed** section, one `key: value` per line.
- Inside a **list** section, one `- item` per line.
- Inside a **table** section, one record per line, fields separated by ` | `.
- `#` at the start of a line is a comment. Blank lines are ignored.

## Sections

### `@meta` — keyed, all required

| Key | Meaning |
|---|---|
| `use_case` | The business process, in one sentence. 20 characters minimum |
| `author` | Team or person |
| `date` | ISO date |
| `approver` | **A named role or person.** Never "the system", "the agent", or "automatic" |
| `exit_criterion` | The number on which this loop is shut down. Must contain a figure |
| `questions_sha256` | The SHA-256 of the `QUESTIONS.md` this design was authored from. Required when a question set is supplied; see `QUESTIONS-FORMAT.md` |

### `@assumptions` — list, at least one

Every assumption the design rests on, stated plainly. A design declaring no assumptions is
hiding them, and the validator refuses it.

**An assumption answering a question cites it, and says how it was answered.**

```
- [Q1] stated by Buzz, process owner: one unit is one appointment
- [Q4] unanswered — Finance owes the retention period; assumed seven years
- [Q9] delegated by Buzz, who asked the system to choose: 48 hours
```

Three provenances, three different claims. "The owner stated this" is not "the owner asked me
to choose" and neither is "I inferred this". Rules V33 and V34 refuse a design that drops a
question or flattens the three into one voice — because an auditor reading a list of 44
assumptions cannot otherwise tell a confirmed fact from a surviving guess, which is most of
what the interview was for.

### `@unit` — keyed

| Key | Meaning |
|---|---|
| `definition` | One unit of work: the smallest thing that gets one decision |
| `kind` | `rule` or `judgment` — the two-people test result |
| `two_people_test` | What two competent people, unable to confer, would do |
| `checked_by` | **Required when `kind: judgment`.** What checks the decomposition |
| `fanout` | How many units run at once. A number |
| `fanout_reason` | What bounds that number — contention, blast radius, or review capacity |
| `thinking_justification` | Optional. Required only when the design has more than one thinking step |

### `@steps` — table, `id | name | type | actor | description | scope`

- `id` — sequential from 1, no gaps
- `type` — `coordination` · `mechanical` · `thinking` · `test` · `gate`
- `actor` — `code` · `model` · `human`
- `description` — what it does, 15 characters minimum

- `scope` — optional, `batch` or `unit`. Default `unit`

Type and actor must agree: coordination, mechanical, test and gate are always `code`.
Thinking is `model` or `human`.

**Scope** is what the scaffolder needs to build a runnable loop. A `batch` step runs once per
tick, before any unit exists — the steps that turn a pile into units and choose what is worked.
A `unit` step runs once per unit. Every batch step must come before every unit step.

### `@gates` — table, `after | condition | refusal`, at least two

- `after` — the step id this gate follows
- `condition` — what refuses. **Must contain a number, a comparison, or the word "never."**
  A condition with none of those is a suggestion
- `refusal` — the message, naming the **next human action**. 25 characters minimum, and it may
  not be a placeholder like "needs review", "escalate" or "cannot proceed"

### `@sources` — table, `id | from | provides | constraint`

Where a unit's fields come from. Without it, every `$VALUE` a gate compares is unexplained.

- **id** — what this process calls it
- **from** — the id of a tool in the **catalog**. A design does not invent tools.
- **provides** — the fields this process takes. Must be a subset of what the catalog says the
  tool provides, and what the tool itself reports from `schema`. A design may **narrow**, never
  invent.
- **constraint** — a predicate that must hold, or `-`

A constraint is one of two kinds, and the difference decides what it compiles to:

- **checkable** — verifiable at run time, so it becomes a gate. *"statement format is ofx or csv"*
- **structural** — a property of the step graph, so it becomes a rule the validator enforces on
  the design. *"never reaches a model"*

Write a structural constraint beginning `never` or `only`. Anything else is read as checkable,
and a checkable constraint that cannot be evaluated is a constraint in name only.

### `@tools` — table, `id | used_by | purpose`

Which tools this process uses, and in which steps.

- **id** — a catalogued tool id
- **used_by** — step ids, space separated
- **purpose** — one line

A design **inherits** the catalog's permissions and may only narrow them. It cannot grant a tool
a data class the catalog withheld. The rule that matters: a tool carrying `data_class: phi`
cannot be `used_by` a step whose actor is `model`, because the catalog says that data may not
leave the local boundary and a model call does.

### `@evidence` — keyed

| Key | Meaning |
|---|---|
| `writer_step` | The step id that writes the proof. **Must be a mechanical step** |
| `artifact` | What the proof contains |
| `integrity` | How tampering is detected |

### `@record` — keyed, all required

What this loop writes down, so that what it did and who allowed it can be answered later.
A loop that records nothing cannot be audited, and an RPA with no ledger cannot tell you
why it refused a unit last Tuesday.

| Key | Meaning |
|---|---|
| `transitions` | where every state change is appended. Append-only, written by code only |
| `units` | where each unit's outcome is recorded, with what decided it |
| `retention` | how long the records are kept. A period, not "as needed" |
| `acceptance` | where the approval signature lives, tied to the design's digest |

### `@kpis` — table, `name | kind | baseline`, at least three

`kind` is one of eight values in two families.

**Operational (TCO).** What the loop costs and whether it can be trusted.

| Kind | Measures |
|---|---|
| `cost` | Spend per completed decision |
| `quality` | Defects that escape the loop |
| `throughput` | Time or volume through the loop itself |
| `control` | Refusals, overrides and other control activity |

**Total Value Realized (TVR).** What the business gains when the loop runs at scale. The four
kinds are the four value vectors in the executive deck (`course/harness/project/slides/tvr.html`).

| Kind | Value vector | Measures |
|---|---|---|
| `tvr-velocity` | Market velocity | Cycle time at a client touchpoint, e.g. days to collect or to respond |
| `tvr-throughput` | High-yield throughput | Volume handled by the existing team, e.g. units per reviewer per week |
| `tvr-speed` | Organizational speed | Iterations of a product, proposal or response per period |
| `tvr-margin` | Margin amplification | Value recovered or retained per unit, net of compute spend |

No other `kind` is accepted. At least one `cost`, one `quality` and one `tvr-*` KPI are required. `baseline` is what the
manual process does today, or `unmeasured` — which the validator accepts and warns about. A TVR
baseline nobody has measured is written `unmeasured`, never estimated.

## Minimum viable design

```
@meta
use_case: Supplier invoices that do not match their purchase order
author: Team 3
date: 2026-09-21
approver: A. Rivera, Accounts Payable
exit_criterion: Shut down if review minutes per unit exceeds 4 for two consecutive weeks

@assumptions
- Invoice and purchase order data are retrievable from the ERP by query

@unit
definition: One (supplier, purchase order) pair
kind: rule
two_people_test: Two buyers given the same files produce the same units
fanout: 5
fanout_reason: Bounded by what one approver reads in a morning

@steps
1 | decompose | mechanical | code | Group invoice lines by supplier and purchase order | batch
2 | judge | thinking | model | Decide whether a variance is a dispute, discount or typo
3 | verify | test | code | Recompute the claimed adjustment from the raw files
4 | deliver | coordination | code | Write a proposal assigned to the named approver

@gates
3 | exposure over 2000 USD | Route to a second approver before anything is proposed
4 | recomputed adjustment differs by more than 0.01 | Return to the reviewer with both figures

@evidence
writer_step: 3
artifact: The arithmetic, the commands run, and the judgment
integrity: Checksum verified at delivery

@kpis
cost per completed decision | cost | unmeasured
escaped defect rate | quality | 0 known in the last quarter
review minutes per unit | throughput | 9 minutes
days from invoice receipt to payment decision | tvr-velocity | unmeasured
```
