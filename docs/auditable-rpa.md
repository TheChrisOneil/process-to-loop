# Auditable RPA: the approach, and what it costs

A design document for deciding whether this is worth continuing.

Written 2026-10-05, after a week of building it and running it against two business
processes. It states the approach, the evidence for and against, and the open questions. It is
not a pitch.

---

## 1. The claim

A regulated business automating a process has to answer three questions about any decision the
automation made:

1. **What rule produced this outcome, and who approved that rule?**
2. **What evidence exists that the rule was applied, written by something that did not also make
   the claim?**
3. **If the process changed, when, by whom, and against what review?**

The traditional answer is an Operational Plan: product requirements review, preliminary design
review, detailed design review, test readiness review, product release review. Those gates
produce documents, and the documents are the audit trail.

The claim here is that the same gates can be **properties of the artifact** rather than meetings
about it, and that a machine can hold them — so the audit trail is produced by running the
process, not by writing about it afterwards.

## 2. The chain

One artifact is authored by a model. Everything else is derived from it deterministically.

```
  a described process, in its owner's words
        │
        ▼
  DESIGN  @meta @assumptions @unit @steps @gates @evidence @record @kpis
        │
        ├── 26 rules            form. deterministic. no model.
        ├── adversarial audit   a different model on a different provider, 6 dimensions
        ├── a named person      signs the SHA-256, not the filename
        │
        ▼
  COMPILE  → formula + one check script per gate + a standalone bundle
        │
        ▼
  RUN      launchd ticks it; every unit produces a ledger line and an outcome row
```

Each arrow is a gate that can refuse, and each refusal names the next human action.

## 3. What makes an outcome auditable

Five properties, each carried by a specific mechanism rather than by convention.

### 3.1 The decision is traceable to a rule somebody approved

A design declares exactly **one judgment per unit of work**. Everything else is a rule. Rule V6
and V7 enforce the declaration; the audit's `judgment-isolated` dimension challenges whether it
is true.

The practical effect: when an auditor asks "why was this invoice refused", the answer is a gate
condition written in the design, compiled into a check script, with the design's SHA-256 in an
acceptance register. Not "the model decided."

### 3.2 Acceptance binds to content, not to a name

The register records the SHA-256 of the design as it stood when it was signed.

> Change one character afterwards and the acceptance no longer covers what you are about to
> build — which is the whole control.

Entries are chained, the signer must equal the `@meta.approver` the design itself names, and
revocations and corrections are appended rather than edited.

### 3.3 The review is adversarial and decorrelated

The design is audited by a **different model on a different provider**. Two models from one lab
share training and tooling; two providers do not. A gate refuses the run when the author and
auditor are the same model — the floor, with provider difference as the stronger form.

The audit covers six dimensions the deterministic rules cannot reach: unit-of-work,
judgment-isolated, gate-coverage, refusal-quality, evidence-chain, exit-criterion.

### 3.4 Evidence is written by something that did not make the claim

Rule V17: the proof is written by a **mechanical** step. Evidence a model can edit is not
evidence. V18 requires a declared integrity check.

### 3.5 The running process records what the design promised

`@record` declares four things — transitions, units, retention, acceptance — and the final gate
proves the emitted bundle keeps them, **by running one tick and reading the files**, not by
inspecting the source. A ledger nobody writes to is decoration.

## 4. What is actually proven

Honest accounting, because this is a go/no-go document.

### Proven

**The adversarial audit finds real defects.** Not style. On the monthly-close design:

> *Step 7 and Gate 7 enforce a zero reconciliation variance **before** exceptions are reviewed
> or resolved, and before journal entries are posted — an execution deadlock.*

On the PO design:

> *Gate 7 compares a shortfall quantity against a received line sum, so it **refuses 100% of
> partial receipts**.*

Both read as correct prose. Both are unrunnable. A human reviewer skimming either design would
very likely approve it.

**Determinism holds where it is claimed.** Diagrams render by rule; same design in, same bytes
out. The validator is 26 rules with no model. The formula compiler is awk.

**The gates refuse.** Repeatedly, including against their author. The verdict freshness check
catches an audit bound to a different design by SHA.

### Not proven

**No run has reached a compiled bundle.** Every run so far has stopped at or before the
acceptance gate. The compile and records gates are proven by test suite only — 147 assertions,
not live use.

**The loop has not demonstrably revised a design in response to findings.** Multi-attempt runs
happened, but for infrastructure reasons, not because an audit sent work back. Six findings sit
marked `by_revision` rather than having been applied.

**Nobody has operated this who did not build it.** Every run was driven by its author.

## 5. What it costs

Measured, not estimated.

| | |
|---|---|
| authoring, per attempt | ~4 minutes, 46k–83k output tokens |
| attempts per run | up to 3 |
| audit | one call to a second provider per attempt |
| deterministic stages | seconds, zero tokens |

The expensive part is the one place a model is given latitude. Everything downstream is awk and
bash.

**The first week's real cost was not tokens.** It was eight distinct defects at the boundary
between the formula and the scripts it invokes — checks installed where they do not resolve, a
controller that exports no variables to a check, `$USER` unset under launchd, a validator that
never returned. Each one passed by hand and failed in the real environment, and each reported
something other than its cause.

That is the honest headline for a cost estimate: **the business logic was never the hard part.**

## 6. The argument against

Stated plainly, because a decision needs it.

- **It is a lot of machinery for one design.** Eleven steps, seven gates, six check scripts, a
  second provider, an acceptance register. A competent analyst with a checklist catches some of
  what the audit catches.
- **The gates are only as good as the design format.** Everything rests on `@steps`/`@gates`
  being expressive enough for real processes. Two samples is not evidence.
- **A quarantined check does not stop its step.** That is Gas City behavior, not ours, and it
  means a gate can fail open when its check cannot run. We work around it; we do not control it.
- **Effort is not controllable.** No supported way to set per-step thinking effort, so every
  stumble costs max-effort deliberation.

## 7. What would settle it

Three experiments, in order, none large:

1. **One run end to end**, through compile and the records gate, producing a bundle whose tick
   writes a ledger. Settles whether the back half works at all.
2. **A revision driven by findings** — an audit returns fixable defects, the author applies them,
   the second audit finds fewer. Settles whether the loop is a loop.
3. **Somebody else drives it.** A process owner who did not build this takes a described process
   to an accepted design. Settles whether the front door is real.

Until (1), the auditable-outcome claim is a design, not a result.

---

## References

- `schema/DESIGN-FORMAT.md` — the design format
- `tooling/method/GENERATE.md` — the method the author follows
- `tooling/method/CONTRACT.md` — what the tooling requires of a design
- `formulas/design-authoring.toml` — the pipeline, 17 formula rules
- `tooling/accept.sh` — the acceptance register
- `docs/standing-up-a-city.md` — operational runbook
- `docs/upstream-parking-lot.md` — what belongs to Gas City, not here
