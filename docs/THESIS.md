# The thesis

One sentence, and everything else in this repository is a consequence of it.

> **A model may write something only where something that is not a model can check it.**

The constraint is about what can be demonstrated afterwards, which is a different property from
whether the model was right. A model may well produce a correct gate condition. What it cannot
produce is evidence that the condition is correct, because the only witness is the thing that
wrote it. A regulator asking *"what checked this"* will not accept *"we read it carefully"*, and
that answer does not improve by being true.

So the constraint has an operational form:

> **Every artifact shape must carry its own oracle** — a way of being checked that is derived from
> the specification rather than from the implementation.

"Derived from the specification" is the load-bearing half. A check written against the
implementation tests that the code does what the code does. A check derived from the declaration
tests that the code does what was asked, and those come apart precisely where it matters.

Where no oracle exists, the shape is wrong. Reviewing harder does not help, because the thing
missing is not attention but an independent witness.

---

## Why "review it carefully" is not an answer

The obvious alternative is: let a model write whatever is needed, and have a person or a second
model review it. That fails in two directions at once.

**A second model is one opinion twice.** Two models from one lab share training data and tooling,
so where one has a blind spot the other usually has the same one. The reviewing model then agrees,
and an agreeing review and an absent review produce the same artifact: a verdict saying nothing
was found. Nothing in the output distinguishes them. That is why the audit here runs on a
different *provider*, and why a deterministic check refuses a verdict whose author and auditor
share a model.

**A person does not have the time.** One analysis puts AI-generated code at 12× more expensive to
review than to generate: a contributor produces a pull request in 7 minutes, a maintainer spends
85 understanding it. At that ratio the review queue grows faster than it drains, so review becomes
something that happens to a sample. And the sample skews away from code that looks right, which is
the category a model reliably produces.

So: an oracle, derived from the spec, applied before anybody is asked.

---

## What an oracle looks like, by shape

Each shape in the design format earns its place by having one. The test for admitting a new shape
is the same question every time: *what checks this that is not the thing that wrote it?*

| shape | its oracle | derived from |
|---|---|---|
| **gate** | fixtures: below, at, above, absent | the condition itself — `"more than 0"` mechanically yields the four |
| **decision table** | completeness and overlap | the table's own rules, under a `unique` hit policy |
| **tool call** | the catalog's schema, and a logged read | what the tool declares it provides |
| **test step** | a violating case per claim | the claims the description enumerates |
| **plumbing** | the promises its declared type makes | determinism, no-model, confinement, scope |
| **judgment** | a test step and a gate on either side | the design format requires both |
| **the design itself** | 45 deterministic rules, then a different provider | the format, and the catalog |
| **the interview** | three answer types with provenance | what a person actually said, or did not |
| **acceptance** | a chained register, over a content hash | the design's own bytes |

Nothing in that column is a model's opinion about a model's output.

---

## The two shapes that prove the rule

### A gate: the oracle is generatable, so authoring is safe

A gate's condition is a predicate over one value, so its failure modes are enumerable — polarity,
boundary, source-of-truth, the misuse of an infrastructure exit code for a business failure.
Fixtures fall straight out of the condition:

```
below   -1      proceed  under the threshold, so the condition does not hold
at       0      declare  "more than 0" — does the threshold itself trip it?
above    1      refuse   over the threshold, so the condition holds
absent  <none>  declare  the field is missing — refuse, or exit 75 if unreachable
```

The `declare` rows are the interesting ones: the generator found a boundary the condition does not
settle and **forced a person to decide it before any code existed.** An off-by-one, caught by
arithmetic rather than by reading.

So a gate may be authored by a model. Something that is not a model will catch it.

### A step's logic: no oracle, so authoring is not safe

*"Apply the outcome table to the decision and the visit mark for the state, approved or declined,
and its reason"* is not a predicate. It does not enumerate its own input space, so nothing can be
generated from it. A model writing that step would be checked by a model reading it — the
correlated-blind-spot problem with the deterministic lane removed.

The answer is not a better review. **It is that steps are admitted only in shapes that carry an
oracle:** a tool call generated from the catalog, a decision table proved complete, a test step
whose claims each demand a violating case, plumbing checked against its type's promises, or a
judgment surrounded by a test and a gate.

Of the 22 steps in a real clinical design, almost none required authoring. Five were tool calls,
one a decision table, six gates, three test steps, four plumbing, two judgments. The authored
surface is the gates — the one shape with a generatable oracle.

---

## The failure this is all against

It has a name here, used constantly: **declared, reported, absent.** A control that is declared in
the design, reported as having run, and not actually there.

Every mechanism in this repository is a different way of refusing to take a claim at its word:

| the claim | what refuses to believe it |
|---|---|
| "the design is sound" | 45 rules, then a different provider, then a person |
| "it was audited" | a verdict stamped with the design's own hash |
| "the gate exists" | a formula rule refusing a check script that is not on disk |
| "it keeps records" | a gate that runs a tick and reads the ledger |
| "the tool was allowed to see this" | the permission, on the read row |
| "a person approved it" | a chained register, signer matched to the named approver |
| "a person answered the questions" | `synthetic` on every answer supplied on their behalf |
| "this know-how was applied" | **nothing can.** So the ledger claims only that it was *in force* |

That last row is the thesis holding under pressure. Nothing can prove a document was read, so the
system does not claim it. A gate may never rest on a skill, and the ledger records the version in
force and stops there.

---

## What follows, for anyone extending this

Before adding a shape, a section, or a step type, answer one question:

> **What checks this, that is not the thing that wrote it — and is it derived from the
> specification or from the implementation?**

If the answer is "a careful reviewer", the shape is wrong. If the answer is "a second model", the
shape is wrong. If the answer is "a check derived from the thing's own declaration", it belongs.

And if a shape genuinely has no oracle — as know-how does — then say so in the artifact, narrow
the claim to what is provable, and forbid anything load-bearing from resting on it.
