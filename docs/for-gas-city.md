# What process-to-loop is, and why it may matter to Gas City

For the Gas City CEO. Written 2026-10-08 by Buzz O'Neil, EverBetter.

This is a working repo, not a pitch deck. Where something is unproven it says so.

---

## In one paragraph

`process-to-loop` turns a business process, described in its owner's own words, into **a Gas City
formula and a running bundle** — through an interview, a design file, forty-five deterministic
rules, an adversarial audit on a second vendor's model, and a named person's signature over a
content hash. The whole pipeline is itself a Gas City formula: seventeen steps, seven gates, a
bounded author loop, two human gates, agents dispatched across two providers. It has run end to
end and produced a twenty-two step automation that executes.

---

## 1. The adoption argument

Gas City's primitives are formulas, beads, rigs and agents. They are good primitives. They also
set the adoption ceiling, because **someone has to author a formula**, and a formula is TOML with
a step graph, check modes, gate semantics and an exit-code contract. That is a developer artifact.

The people whose processes most need orchestrating — a practice manager, a controller, a clinical
lead — cannot write one and will not learn to.

This project moves the authoring bar:

| | who can do it |
|---|---|
| **today** | write a 17-step formula with gates and checks |
| **with this** | describe your job in prose, and answer questions about it |

A formula stops being a source format and becomes **a build artifact**. Nobody hand-writes it, for
the same reason nobody hand-writes assembly. That is good for Gas City in a way worth stating
plainly: *formulas can get more sophisticated without raising the authoring bar*, because the
number of people who must understand one stops being the constraint.

**Proof point:** the loop that writes Gas City formulas is a Gas City formula. The platform is
expressive enough to orchestrate its own authoring, including a five-attempt bounded check loop,
cross-provider agent dispatch, and two gates that block on a human.

---

## 2. Beads are already an audit record — nobody is saying so

This is the repositioning I would push hardest.

Beads read as work tracking. In a regulated process they are something more valuable: **the
durable record of what was checked, by whom, and what it concluded** — one that outlives the
working directory, survives restarts, and cannot be quietly edited.

What we put on them, on top of what Gas City already writes:

```
gc.outcome                      pass / fail per step — a closed bead is not a passed bead
gc.attempt_log                  every attempt, with its verdict
eb.rehearsal                    true — this design was not confirmed by a person
eb.rehearsal.synthetic_answers  24 of 24
eb.rehearsal.basis              24 interview answers supplied on the approver's behalf
eb.rehearsal.design_sha256      which design this is about
```

A regulated buyer's first objection to any agent platform is *"I cannot let an agent make
decisions I cannot audit."* The answer Gas City can give that nobody else can is: **the
orchestrator's own state is the audit trail.** Not a log shipped to a SIEM. The bead store.

That needs nothing new from you. It needs the story told, and it needs one behaviour fixed — see
§5.

---

## 3. The catalog, and why it compounds

This is the part I think is the commercial core, and I want to be precise about what is mechanism
and what is prediction.

### The mechanism, which exists

Every design is written against a **catalog** — the organization's sanctioned tools and know-how.
Each entry is a decision, not an inventory row:

```
@tool eb-medication-service
provides:    patient_ref, drug_name, rxnorm, dose, unit, frequency, status
data_class:  phi
may_not:     leave the covered boundary
chosen:      2026-10, over reading the FHIR MedicationStatement endpoint directly
because:     carries rxnorm beside the free-text name, which is what makes two
             spellings of one drug comparable without a model
decided_by:  Buzz, process owner
review_by:   2027-10
```

Three things follow, and all three are built:

**Questions become confirm-or-deviate.** Not *"how do you get appointment data?"* — answerable
only by research — but *"your organization has `eb-appointment-service` sanctioned, and it carries
clinician and status in one call. Use it, or is this process different?"* For a clinical process
that is the difference between asking a doctor to describe an architecture and asking them to
confirm one.

**A gap becomes a procurement signal at design time.** If the catalog has no tool for a stated
need, the design does not assume one. It writes `catalog: none` and that routes to whoever owns
the catalog as a finding. Twice this has caught something real: once that a sanctioned form
service carried a submission's identity but not its contents — so the design could not have been
built at all — and once that a data store the design was written to *write to* had no command that
writes to it. Both would have failed on first contact with production.

**Know-how accumulates where it can be owned.** A design may *propose* know-how and may not
*depend* on know-how nobody owns. A proposal routes to the catalog owner; once somebody owns it,
with a review date, steps may use it. Lapse the review date and designs citing it refuse.

### Why this is a moat, and whose moat it is

The catalog is **the customer's accumulated operational knowledge in a reviewable form**, and it
lives inside Gas City.

It is deliberately *not* lock-in by format — every file is plain text under version control, and
that is a feature I would not trade. It is lock-in by accumulated value: the catalog is worth more
every quarter, the second workflow costs less than the first, and the knowledge in it is the part
a competitor cannot copy from your codebase.

It is also the adoption wedge into the people who hold the knowledge. **A clinician will not review
a formula. A clinician will review one catalog entry with their name on it and a review date in
April.** That is five minutes of their time, it is a thing they already have opinions about, and it
is how domain experts enter the system at all.

### The prediction, which is NOT yet tested

If the mechanism works, **questions-asked-per-process should fall and the confirm-or-deviate ratio
should rise** as the catalog fills. That is measurable and the pipeline already records the raw
material on the beads:

```
questions.catalog_confirm = Q1 Q4 eb-form-builder-service; Q3 eb-medication-service; ...
questions.catalog_none    = Q6 typed name to RxNorm code; Q8 delivery to a clinician
```

**What our data actually shows: nothing about this yet.** We have run one process three times, and
the question count went *up* — 15, 16, 24 — because each revision got more rigorous, not because
the catalog got worse. The compounding claim needs several *different* processes against one
growing catalog, and we have not done that. The instrumentation is also written by an agent rather
than by a script, so it is inconsistent run to run. Both are fixable and neither is fixed.

I would rather you heard that from me than found it.

---

## 4. What this exercises in your platform

A non-trivial workload, run repeatedly over two weeks:

- a 17-step formula with 7 gates, carried across machine restarts and supervisor upgrades
- a bounded `[steps.check]` author loop, up to 5 attempts, re-running on classified findings
- agents dispatched to two different providers in one workflow
- two `[steps.gate]` beads blocking on a human for hours, then releasing cleanly
- `gc sling` → cook → materialize → route, confirmed by reading `routed_to` rather than output
- the control dispatcher, the ready queue, and bead metadata as the run's own record

It works. The failures we hit were almost entirely at **the boundary between a formula and the
scripts it invokes** — which is partly your surface, and is in §5.

---

## 5. What we would ask for

Ordered by how much it costs us.

**1. A quarantined check must not let its step close.** This is the one that matters. A check that
cannot run leaves its step free to close, so a gate can fail *open* when its check is broken. For
anyone using checks as controls — which is the entire regulated use case — that is a correctness
problem, not an ergonomics one. We work around it by making each gate its own step with a bead a
person can read afterwards. We cannot work around it in general.

**2. Per-step thinking effort.** No supported way to set it, so every stumble in a cheap
deterministic step costs max-effort deliberation. Our most expensive runs were expensive for this
reason.

**3. `gc session new <named-agent>` seizes the name.** It creates an ad-hoc session that takes the
name, after which the configured agent can never start — and it sits in `start-pending` with the
supervisor log silent, so it reads as a supervisor fault. The real conflict surfaces only on nudge.
Cost us an afternoon. `gc session attach` is the right call and nothing says so.

**4. `gc rig add --include` writes an import that cannot work** — no version, name derived from the
URL. Detail in `docs/upstream-parking-lot.md`.

**5. Capability-surface diffing for packs.** Every pack version on one machine declares `0.1.0`,
and `0.x.y` permits breaking changes, so the field is unusable rather than stale. We built
`pack-capability.sh` and `pack-diff.sh` to compute the surface instead — six properties, four
verdicts, `UNCLASSIFIED` never collapsing to `NONE`. Offered, not pushed: it has run against one
city and our rule is that nothing goes upstream on a hunch.

---

## 6. What we are not claiming

- **One user.** Every run was driven by the person who built it. Nobody else has tried.
- **No real interview.** Every answer in every run was supplied by the system standing in for the
  owner. The artifacts mark it `synthetic`, count it, and raise it as a critical finding — and it
  is the largest untested assumption here.
- **No real tools.** Seven catalogued tools, all fabricated, all backed by CSV and XML fixtures.
- **No gate logic.** The emitted bundle refuses at its first gate and names the missing check.
  Correct behaviour, and half a system.
- **One industry.** The engine is meant to be industry-neutral with a per-industry cartridge —
  data classes, catalog, rules, audit dimensions, signer. Only healthcare's exists, so the
  separation is an architectural claim rather than a demonstrated one.

---

## 7. What I would do next, together

1. **One Gas City-side conversation about §5.1.** If a quarantined check cannot be made to block
   its step, the regulated story has a hole in it that neither of us can paper over.
2. **A second industry cartridge**, non-clinical, on the same engine. Cheapest possible test of the
   separation, and it is the claim everything else rests on.
3. **Somebody who did not build this drives one process through it.** If that works, the adoption
   argument in §1 is real. If it does not, I would rather know in a week than in a quarter.

The repo is public: `github.com/TheChrisOneil/process-to-loop` (Apache-2.0).
`docs/regulated-workflows.md` is the full technical account; `docs/DISCOVERIES.md` is twenty-six
entries of what surprised us, each with what it cost.
