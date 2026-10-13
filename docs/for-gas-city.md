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

It works, including unattended for three days across a credential expiry — the beads carried
every run intact, and nothing had to be reconstructed.

The failures we hit were almost entirely at **the boundary between a formula and the scripts it
invokes** — which is partly your surface, and is in §5.

---

## 5. What we would ask for

Ordered by how much it costs us.

**1. A step that could not run must not close as a step that failed — and a check that could not
run must not let its step close at all.** One ask, because it is one missing distinction, and it
is the only thing on this list I would call a correctness problem rather than an ergonomics one.

Gas City records a step as `pass` or `fail`. There is no third outcome for *could not run*, and the
gap shows in both directions:

- **failing open.** A quarantined check leaves its step free to close, so a gate permits when its
  own check is broken. We work around it by making every gate its own step with a bead a person can
  read afterwards. We cannot work around it in general.
- **failing closed, and misattributing it.** An infrastructure failure consumes the step's attempts
  and closes it `fail`, which reads as a verdict on the work.

### The incident, 2026-10-09

We left two workflows running unattended over three days. The Claude CLI's OAuth session expired:

```
Failed to authenticate: OAuth session expired and could not be refreshed
```

Every agent attempt after that failed in under a second. When we came back, one run showed **seven
steps closed `fail`**:

```
FAILED  Write the design
FAILED  Gate: the design passes its rules
FAILED  Gate: every question came back with an answer
FAILED  Gate: the audit is real and came from a different model
FAILED  A person answers
FAILED  Put the findings in front of a person
FAILED  Draw both views and the brief
```

Read cold, that is a design that failed its rules, failed its audit gate, and could not even be
drawn. **None of it is true.** It is one expired credential. The authoring step spent all five of its attempts on an
auth error, and the `gc.attempt_log` records only `attempt subject <id> already failed` — which
names the bead that failed, not what failed about it.

Nothing was lost, because our artifacts are files and the answers survived. But anyone auditing
those beads later finds six controls that read as refusals and were not, and the cost of telling
the difference is a person remembering what was happening that week.

### Why we care about this one more than the others

We already solved it inside our own layer, which is how we know the fix is small and the benefit is
large. Every check we write honours three codes, and the third is the whole point:

```
0   the condition does not hold; work continues
1   refused — a BUSINESS outcome, and the refusal names the next human action
75  could not run — INFRASTRUCTURE. Costs no attempt, and never reads as a failure
```

Before we had 75, a missing API key reached a person as *"your design needs revision."* After it,
the same failure says what was missing and costs nothing. That one distinction removed more
confusion than any other change we made.

What we cannot do is carry it upward, and we measured exactly how far it gets.

### The probe, 2026-10-13

A one-step formula. `max_attempts = 2`. One exec check, which always exits 75 and says so:

```
gc.attempt_log = [
  {"action":"fail","attempt":"1","outcome":"fail","reason":"PROBE: this check could not run (exit 75)"},
  {"action":"fail","attempt":"2","outcome":"fail","reason":"PROBE: this check could not run (exit 75)"}
]
```

**Both attempts consumed, step closed `fail`, workflow closed `fail`.** Exit 75 is treated
exactly as exit 1.

We had asserted the opposite in our own generated code for weeks — every check this project emits
carried a comment saying 75 *"does not consume an attempt"*. It was never true, and nothing had
tested it. We have corrected the comment rather than the behaviour, because the behaviour is
yours.

One thing the probe did show is that the information is already there. When a check cannot be
found at all, you record it:

```
gc.controller_error       = absolute gc.check_path "..." escapes trusted roots
gc.controller_error_class = hard
```

So the controller already distinguishes *a check that could not be reached* from *a check that
returned non-zero*. What it does not do is carry either distinction into the step's outcome, or
let a formula say what to do about it. Across 186 recorded outcomes in our bead store, exactly two
values appear: `pass` and `fail`. For a regulated buyer this matters beyond
ergonomics: **the bead store is the audit record**, and an audit record that cannot distinguish
*"this was refused"* from *"this could not be attempted"* is answering a regulator's question
wrongly, in the direction that looks worse than reality.

### Two incidents, one cause, opposite symptoms

**2026-10-09.** A credential expired while two workflows ran unattended. Seven steps closed
`fail`, reading as a design that failed its rules and could not be drawn. Loud, and wrong about
the cause.

**2026-10-13.** Re-slung after logging back in. The agent sessions had started before the login
landed and held the dead credential, so the run materialized, one step sat ready, three agents
were up — and **nothing happened at all.** No failure, no message, nothing on any screen. We
reported the run as healthy before checking.

Same missing distinction. Silence is the harder of the two, because nothing prompts you to look.
For a product aimed at unattended operation, it is also the disqualifying one.

### The shape of the ask

A third terminal outcome on a step — `blocked`, `could_not_run`, whatever you call it — that does
not consume an attempt, and that a formula can be told to treat as neither pass nor fail. Exit 75
from an exec check already reaches you, `controller_error_class` already exists, and
`bd config set status.custom` already accepts new states. The information and the vocabulary are
both present; what is missing is the wiring between them.

Failing that, two smaller things would recover most of the value:

- **a non-zero exit that does not consume an attempt**, selectable per check. Even one reserved
  code would do
- **an agent that cannot authenticate should not claim work.** A session holding a dead credential
  claims a bead, fails in under a second, and the only trace is `attempt subject <id> already
  failed` — which names the bead that failed, not what failed about it

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
