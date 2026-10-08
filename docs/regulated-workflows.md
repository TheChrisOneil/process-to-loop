# Regulated Workflows: the approach, what is proven, and what it costs

A design document for deciding whether this is worth continuing.

Started 2026-10-05 after a week of building. Rewritten 2026-10-08, after the first run went end
to end and produced a bundle that runs. It states the approach, the evidence for and against,
and the open questions. It is not a pitch.

> **Send-ready summary:** §9, *The abstract*.

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

### Why this is not ordinary loop engineering

Current practice says: stop prompting agents, write loops that prompt them. The best public guide
to it lists where loops do *not* work, and names this exactly:

> **Safety-critical systems** — Medical, legal, or financial systems where the process itself is
> regulated, not just the outcome.

It is right about the reason. A loop's exit condition must be machine-verifiable — *"all CI checks
passing"*. In a regulated process the outcome is not the only thing judged. The **process** is. A
green check does not say what was checked, by whom, against what rule, on what authority, or where
it is written down.

This project is the attempt to give the loop pattern a vocabulary for that. See
`loop-engineering-in-a-regulated-space.md` for the full comparison.

---

## 2. The chain

Two artifacts are authored by a model — the questions and the design. Everything else is derived
deterministically.

```
  a described process, in its owner's words
        │
        ▼
  QUESTIONS   what the description does not say, asked against a catalog of
              what the organization already has. Three answers are legal:
              stated · unanswered (who owes it) · delegated (what was chosen)
        │
        ▼
  DESIGN      @meta @assumptions @unit @steps @gates @sources @tools
              @skills @decisions @evidence @record @kpis
        │
        ├── 45 rules            form, provenance, policy. deterministic, no model.
        ├── adversarial audit   a different PROVIDER, 7 dimensions
        ├── audit-verdict       deterministic: did the audit happen, on another
        │                       model, about THIS design
        ├── a named person      signs the SHA-256, not the filename
        │
        ▼
  COMPILE     → a Gas City formula + one check script per gate
              → a standalone bundle + its launchd job
        │
        ▼
  RUN         launchd ticks it; every read logs its source, its tool and the
              permission it ran under; every unit produces an outcome row
```

Seventeen steps, seven of them gates. Each arrow can refuse, and each refusal names the next
human action.

---

## 3. What makes an outcome auditable

Eight properties, each carried by a mechanism rather than by convention.

### 3.1 The decision is traceable to a rule somebody approved

A gate's condition is a check script, not a sentence in a prompt. A gate naming a check that is
not on disk fails the formula rules (F5). A gate backed by a **decision table** compiles to
working logic; a gate backed by prose compiles to a stub that says it is a stub.

### 3.2 Acceptance binds to content, not to a name

The register records the SHA-256 of the design as it stood. Change one character and the
acceptance stops covering what would be built. The register is chained; an edited row breaks it.
The signer must equal `@meta.approver`.

### 3.3 The review is adversarial and decorrelated

The audit runs on a different **provider**, not merely a different model — two models from one lab
share training and tooling. A deterministic check refuses a verdict whose author and auditor
match, or that is bound by digest to a different design.

### 3.4 Evidence is written by something that did not make the claim

`@evidence.writer_step` must name a mechanical step. Evidence a model can edit is not evidence.

### 3.5 The running process records what the design promised

The records gate runs one tick and reads the ledger. A bundle that reports a ledger it never
writes is the same defect as a gate whose check does not exist.

### 3.6 Every value has a provenance, and every read a permission

```
read  appointments via eb-appointment-service (phi; may not leave the covered boundary): 5 row(s)
```

Which source, through which tool, under which permission, how many rows. A gate stops a violation;
the ledger proves the non-violation for every unit that passed, which is what a regulated audit
actually asks for.

### 3.7 Policy lives where a contract change is a reviewable diff

Whether PHI may reach a model is an **agreement**, not a property of the data. It is in the
catalog with an attestation date, and the rule reads it. A lapsed attestation refuses — a stale
catalog asserting a tool is safe is worse than no catalog, because designs cite it.

### 3.8 Know-how is owned, dated, and never load-bearing for a gate

Know-how that **decides** is a decision table, where completeness and overlap are provable.
Know-how that **frames** is a catalogued skill with an owner and a review date. A gate may never
rest on a skill: nothing can prove a document was read. The ledger records a skill as **in force**,
never as applied — because *which version was in effect on that date* is answerable and *was it
followed* is not.

---

## 4. What is actually proven

Honest accounting, because this is a go/no-go document.

### Settled since the first draft

The 2026-10-05 version listed three experiments that would settle the claim. Two are done.

**1 — One run end to end. DONE.** On 2026-10-07 a described clinical process became a signed
design and a 22-step bundle. It runs, reads five catalogued sources, logs the permission each read
ran under, and **refuses at the first gate whose check is not installed**, naming the missing file.

**2 — A revision driven by findings. DONE.** The audit returned six findings; the revision
returned one; the next returned zero. The one critical in between was a real deadlock: a model
confidently answering *different* produced an entry that could never be marked prescription-only,
and a gate required that mark. It existed only because a policy change let a model into the
design, and the audit found it in a single pass.

**3 — Somebody else drives it. NOT DONE**, and it is now the largest open question.

### Also proven

**The adversarial audit finds real defects.** Not style. From three designs:

> *Step 7 and Gate 7 enforce a zero reconciliation variance **before** exceptions are reviewed —
> an execution deadlock.*

> *Gate 7 compares a shortfall quantity against a received line sum, so it **refuses 100% of
> partial receipts**.*

> *Steps 4 and 5 read the ledger, but `local-ledger` is declared in neither `@sources` nor
> `@tools`.*

All three read as correct prose. All three are unrunnable. A human reviewer skimming any of them
would very likely approve it.

**The interview finds capability gaps nobody planted.** It found that the catalogued form service
carries a submission's identity but not what is inside one — so the patient's side of every
comparison had no source at all, and the design could not have been built from the catalog as it
stood. On a later run it found that the worklist a design writes to **had no command that writes
to it**. Both would have failed on the first real tick.

**Determinism holds where it is claimed.** Two ticks of the same bundle four hours apart produced
byte-identical ledger rows but for the timestamp. Diagrams render by rule. The validator is awk.

**The gates refuse, including against their author.** F5 on a missing check script. V32 on a design
bound to a question set that no longer exists. V38 on two decision rules claiming the same input.
`compile` on a run whose gates were rehearsed.

### Not proven

**Nobody has operated this who did not build it.** Every run was driven by its author.

**No interview has been answered by a person.** Every answer in every run was supplied by the
system standing in for the owner, marked `synthetic`, counted, and raised as a critical finding —
and it remains the largest untested assumption here.

**No tool is real.** Seven catalogued tools, all fabricated, all backed by CSV and XML fixtures.
The pipeline is proven; the integrations are not.

**No gate logic has been authored.** The emitted bundle refuses at its first gate. That is correct
behaviour and it is also half a system.

**Nothing has been maintained.** No design has been revised six months later by somebody who did
not write it.

---

## 5. What it costs

Measured, not estimated.

| | |
|---|---|
| interview, per run | ~8 minutes, one model call |
| authoring, per attempt | ~4 minutes, 46k–83k output tokens |
| attempts per run | up to 5; two is typical, three is normal |
| audit | one call to a second provider per attempt |
| deterministic stages | seconds, zero tokens |
| a full run, prose to bundle | roughly 40 minutes of wall clock |

The expensive part is the two places a model is given latitude. Everything else is awk and bash.

**The real cost was never tokens.** It was defects at the boundary between the formula and the
scripts it invokes: checks installed where they do not resolve, a controller that exports no
variables, `$USER` unset under launchd, `$HOME` pointing at a city directory, a validator that
never returned, an install that did not carry the catalog. Each passed by hand and failed in the
real environment, and **each reported something other than its cause.**

That is the honest headline for an estimate: **the business logic was never the hard part.**
`DISCOVERIES.md` is the full accounting — 26 entries, each with what it cost.

---

## 6. The argument against

Stated plainly, because a decision needs it.

- **It is a lot of machinery.** Seventeen steps, seven gates, forty-five rules, a second provider,
  an acceptance register, a catalog with an owner and review dates. A competent analyst with a
  checklist catches some of what the audit catches.
- **The gates are only as good as the design format.** Everything rests on `@steps`/`@gates` being
  expressive enough for real processes. Four samples is not evidence.
- **The catalog is an organizational commitment, not a file.** A stale catalog asserting a tool is
  PHI-safe after its agreement lapsed is worse than no catalog. We refuse a lapsed attestation; we
  cannot make anybody re-attest.
- **A quarantined check does not stop its step.** Gas City behaviour, not ours. We work around it;
  we do not control it.
- **It is not obvious a clinician will engage with any of it.** The one plausible route is owning a
  *skill* entry — a thing they already have opinions about — rather than approving a design in an
  unfamiliar format.

---

## 7. What would settle it now

Two experiments, in order, neither large.

1. **A real interview.** A process owner who did not build this answers the questions themselves.
   Settles whether the front door is real, and removes the critical finding every design currently
   carries.
2. **One real tool.** Replace one fixture-backed stand-in with an actual EverBetter service.
   Settles whether the catalog contract survives contact.

Until (1), every design this system has produced is a rehearsal, and says so.

---

## 8. Where it is honest about being a rehearsal

A design can be a rehearsal two ways, and they are recorded apart because they are different
claims:

| | recorded on |
|---|---|
| the interview was answered on somebody's behalf | the question set, the findings, the register row, the beads |
| a gate was closed without a person | `REHEARSAL`, the beads, the findings; **`compile` refuses to build from it** |

The escape hatch takes a name, not a flag: `ALLOW_REHEARSAL="Name, Role"`. An override with
nobody's name on it is an unexplained pass.

---

## 9. The abstract

*Self-contained. Send this.*

> **Regulated Workflows: compiling a described process into an auditable one**
>
> Automating a regulated process means answering three questions about every decision the
> automation made: what rule produced this outcome and who approved it; what evidence exists that
> the rule was applied, written by something that did not also make the claim; and if the process
> changed, when, by whom, and against what review.
>
> Conventional practice answers these with documents — a requirements review, a design review, a
> test readiness review — and the documents become the audit trail. Conventional AI practice
> answers them not at all: the current state of the art is to write loops that prompt agents until
> a machine-verifiable goal is met, and the best public guide to that technique explicitly excludes
> medical, legal and financial systems, "where the process itself is regulated, not just the
> outcome."
>
> This work asks whether those review gates can be **properties of an artifact** rather than
> meetings about one, such that the audit trail is produced by running the process rather than by
> writing about it afterwards.
>
> A business process, described in its owner's own words, is first **interviewed**: the system
> works out what the description does not say and asks, against a catalog of what the organization
> has already sanctioned — so the questions are *confirm or deviate* rather than open research.
> Three answers are legal, including "I don't know, and X owes the answer" and "you decide", the
> latter recorded as a delegation rather than smuggled in as an assumption.
>
> The answers produce a **design**: a plain-text file a business person can read, naming its unit
> of work, the single judgment a rule cannot settle, its gates and their refusals, where every
> value comes from, which tools may touch which class of data, and what know-how it applies. The
> design is judged three times before any person is asked — 45 deterministic rules, then an
> adversarial audit on a *different vendor's* model, then a deterministic check that the audit
> happened and is about this exact design. A named person then signs its content hash into a
> chained register. Only then is anything compiled.
>
> Compilation is deterministic and produces a standalone automation: a scheduled job that reads
> its sources, logs for every read which source, which tool and under which permission, refuses at
> any gate whose check is not installed, and writes an append-only ledger. Nothing in that chain
> is a model being trusted.
>
> **The verification rules and the check scripts are per industry, by design.** The engine is
> industry-neutral: the pipeline, the acceptance register, the exit-code contract, the adversarial
> audit, the requirement that evidence be written by something that did not make the claim. What
> an industry supplies is a *cartridge* — its data classes and what may touch them, its catalog of
> sanctioned tools and the agreements covering them, the handful of rules its regulator implies,
> the dimensions its audit must cover, and who is qualified to sign. Healthcare's cartridge names
> protected health information, business associate agreements with attestation dates, and a
> clinician as signer. A financial-services cartridge would name materiality, segregation of
> duties, and a controller. The design format, the gates and the compiler do not change.
>
> **Entering a new industry is a bounded, enumerable piece of work** — seven steps, none of which
> is writing software: name the data classes and the boundary each may not cross; seed the catalog
> with the tools already sanctioned, each with an owner, a rationale and a review date; write the
> rules the regulator implies, as additions to the industry-neutral set; name the dimensions the
> adversarial audit must cover; version the interview script with that industry's structural
> questions; name who may sign and what makes them qualified; and write down the know-how that
> frames judgment, owned and dated. Each artifact is a file under version control, reviewed as a
> pull request, which is itself the point: the industry's compliance posture becomes a diff with a
> date and a name on it.
>
> **Status.** The chain has run end to end on a clinical process neither author had seen: sixteen
> questions, a design the audit returned as sound after two revisions, a signature, and a
> twenty-two step automation that runs. The adversarial audit has found genuine execution
> deadlocks in three separate designs, each of which read as correct prose. The interview has twice
> found capability gaps that would have failed on first contact — including a data store the design
> was written to write to, which had no way to be written to.
>
> **Limits, stated plainly.** No interview has yet been answered by a real process owner; every
> run so far was answered by the system standing in for one, which the artifacts record as a
> rehearsal and raise as a critical finding. The catalogued tools are stand-ins. The gate logic
> itself is not yet authored — the emitted automation refuses at its first gate and names the
> missing file, which is correct and is also half a system. Only one industry cartridge exists, so
> the separation between engine and industry is an architectural claim rather than a demonstrated
> one; one rule and the audit prompt still name healthcare's vocabulary directly.
>
> The open question is not whether the machinery works. It is whether a process owner who did not
> build it can drive it.

---

## 10. Entering a new industry

The engine is industry-neutral. An industry supplies a **cartridge** — seven artifacts, none of
which is code.

| # | what | where it lives today | healthcare's answer |
|---|---|---|---|
| 1 | **the data classes**, and the boundary each may not cross | `data_class` and `may_not` on every catalog entry | `phi`, `credential`, `operational`; *may not leave the covered boundary* |
| 2 | **the catalog** of sanctioned tools — each an owner, a rationale, a review date | `catalog/*.catalog` | 7 entries |
| 3 | **the agreements**, with attestation dates | `@catalog` keys | `phi_may_reach_models`, the BAA, `phi_model_review_by` |
| 4 | **the rules the regulator implies**, added to the neutral set | `tooling/lib/validate.awk` | V27–V31 on sources, tools and where PHI may go |
| 5 | **the audit dimensions** | `tooling/audit-design.sh` | 7, including `source-integrity` |
| 6 | **the interview**, versioned | `tooling/method/INTERVIEW.md` | v1, 13 questions |
| 7 | **the skills** — know-how that frames judgment, owned and dated | `@skill` in the catalog | 2 entries |

Six of the seven are data files reviewed as pull requests. Only (4) and (5) are code, and they are
additive: a cartridge adds rules and dimensions, it does not modify the neutral ones.

**What does not change:** the design format, the pipeline's seventeen steps, the acceptance
register, the exit-code contract, the adversarial-audit requirement, the compiler, the ledger.

### The honest state of this claim

One cartridge exists. The separation is architectural, not demonstrated, and two places still name
healthcare directly:

- **V31** compares a data class against the literal string `"phi"`. Every other rule reads the
  class generically. This is the one rule that would need parameterising, not rewriting.
- **The audit prompt** names its seven dimensions inline rather than reading them from the
  cartridge.

Both are small and both are known. Neither is evidence the separation holds — a second cartridge
is. The cheapest test is a non-clinical EverBetter process: the same engine, a different catalog,
different signers, and whatever rules the regulator implies.

---

## References

- `loop-engineering-in-a-regulated-space.md` — the frame, and the two loops
- `DISCOVERIES.md` — what surprised us, dated, with what it cost
- `next-design.md` — what we decided, and what is still open
- `standing-up-a-city.md` — the operational runbook
- `schema/DESIGN-FORMAT.md` · `schema/QUESTIONS-FORMAT.md` — the artifact formats
- `tooling/method/GENERATE.md` · `INTERVIEW.md` · `CONTRACT.md` — the versioned methods
- `formulas/design-authoring.toml` — the pipeline, 17 formula rules
- `upstream-parking-lot.md` — what belongs to Gas City, not here
