# Discoveries

Append-only. One entry per thing we learned the hard way, newest last, written
when it is still fresh enough to be accurate.

**This is not a changelog and not a decision record.** `next-design.md` holds
decisions — what we chose and why. `standing-up-a-city.md` holds the runbook —
how to do it. This holds **what surprised us**, which is the only one of the
three that cannot be reconstructed later. A decision leaves a diff. A surprise
leaves nothing unless somebody writes it down the day it happens.

Entries are written by `tooling/discovery.sh`, never by hand, so the shape cannot
drift and nothing goes in without its cost.

Each entry answers five questions:

| | |
|---|---|
| **believed** | what we thought was true |
| **happened** | what actually happened |
| **cost** | what it cost to find out — hours, tokens, a run, a record |
| **changed** | what we changed because of it |
| **generalizes** | the version of this lesson that outlives this repo |

---

## D1 · 2026-09-29 · The design must be a file, not a prompt

**believed** A sufficiently detailed prompt can carry a process definition.
**happened** Nothing downstream could check it. A prompt has no sections to
validate, no hash to sign, no fields a diagram can render from.
**cost** The first week, before anything else could be built.
**changed** Plain text with `@sections`, parseable by awk, readable by a student,
writable by a model. Deliberately not JSON.
**generalizes** If a regulator must read it, it is an artifact. If only a model
reads it, it is a prompt. Do not confuse the two.

---

## D2 · 2026-10-02 · A control that leaves no bead leaves no evidence

**believed** Folding the audit into the authoring loop was a simplification.
**happened** The authoring step closed `pass` three times having written no
verdict at all, and nothing downstream could tell. There was no bead whose job
was to notice.
**cost** Three clean runs that had audited nothing.
**changed** `audit-verdict` is its own step whose only job is to run one check.
Same for `validate`, `diagrams`, `records`.
**generalizes** A control you cannot point at afterwards did not run. Give every
control a record of its own, even when that costs a step.

---

## D3 · 2026-10-02 · Every expensive defect was at the formula↔script boundary

**believed** The risk was in the business logic the model writes.
**happened** Eight distinct defects in one week, every one at the seam:
environment, cwd, install location, PATH, `$HOME`, `$USER`. None in the logic.
**cost** Most of a week.
**changed** Values are bound into wrapper checks at cook time, once, while every
value is known. The result needs nothing but a filesystem.
**generalizes** The model is not where your bugs are. The place two systems hand
something to each other is.

---

## D4 · 2026-10-02 · Each defect reported something other than its cause

**believed** A failing check tells you what failed.
**happened** A missing API key read as *"your design needs revision."* An
unreachable bead store read as *"DESIGN_PATH is not set."* An unset `$USER` read
as a locked keychain. A stale rig catalog would have answered confidently about
tools that did not exist.
**cost** Hours per incident, repeatedly.
**changed** Every refusal prints **where it looked**, not just that it failed.
**generalizes** Diagnosis cost, not fix cost, is what makes a defect expensive.
Print the path you tried.

---

## D5 · 2026-10-02 · Exit codes are a safety control

**believed** Non-zero means failure; the distinction is cosmetic.
**happened** An infrastructure failure consumed a revision attempt and reached a
person as a defective design.
**cost** A whole authoring budget, spent on an absent credential.
**changed** 0 pass · 1 refused, a business outcome · 75 could not run,
infrastructure, costs no attempt. The contract is language-neutral and every
emitted step honours it.
**generalizes** *"It failed"* and *"it could not run"* are different facts. A
system that conflates them will blame the wrong party, every time.

---

## D6 · 2026-10-05 · One awk variable, 46 GB of memory

**believed** A shared parser is a shared parser.
**happened** `parse.awk` reused `k` for a keyed-section key. A later
`for (i=1;i<=k;i++)` became a string comparison that is always true, and
`KKIND[i]` auto-vivified forever. Processes reached 40–46 GB and took the machine
down.
**cost** An urgent investigation, and a reset box.
**changed** `ky` for the key, `k+0` to force numeric, and a comment in the file
naming every variable that must never be reused.
**generalizes** In a language where everything is global, a shared library is a
shared namespace. Name the hazard in the file, not in your head.

---

## D7 · 2026-10-05 · The test harness leaked the runaway it was capping

**believed** `kill -9 $!` kills the thing you started.
**happened** It killed the subshell. The awk grandchild kept allocating.
**cost** The second half of the same incident.
**changed** Job control, process-group kill, and a `pkill` fallback by name.
**generalizes** A guard that has never been tested against the failure it guards
is decoration.

---

## D8 · 2026-10-05 · The catalog turns research into confirmation

**believed** A design should discover what tools exist.
**happened** Without a catalog the only question available is *"how do you get
appointment data?"*, which is answerable only by doing research. With one it
becomes *"your organization has `eb-appointment-service` sanctioned, and it
carries clinician and status in one call — use it, or is your process
different?"*
**cost** Nothing. This one we got right by thinking first.
**changed** The catalog enters **before** the questions. An entry is a decision —
chosen over what, because of what, by whom, reviewed when — not an inventory row.
**generalizes** For a clinical process this is the difference between asking a
doctor to describe an architecture and asking them to confirm one.

---

## D9 · 2026-10-05 · Deviation is a finding, not an assumption

**believed** If the catalog has no tool for a stated need, the design should
assume one.
**happened** That produces a design depending on something nobody owns.
**changed** `catalog: none` is the honest answer, and it surfaces as a finding:
*this process requires a capability the organization does not have.*
**generalizes** A procurement signal raised at design time costs a conversation.
Raised at implementation time it costs a quarter.

---

## D10 · 2026-10-06 · Three answers make dialogue possible

**believed** A question needs an answer.
**happened** A run that accepts only answers stalls on the first thing nobody
knows, and then somebody edits the artifact by hand to get moving.
**changed** `stated` · `unanswered` (naming who owes it) · `delegated` (carrying
what was chosen). A delegated **structural** answer becomes a finding before
signing.
**generalizes** Delegation produces the same value a silent assumption would,
with different provenance. *"The owner was asked and chose to let the system
decide"* survives an audit. *"The system decided and mentioned it afterwards"*
does not.

---

## D11 · 2026-10-06 · Fifteen copies of one fact bury the two that matter

**believed** One finding per synthetic answer is honest.
**happened** A wholly synthetic interview produced 17 findings, 15 of them the
same claim, burying the two delegated structural choices that needed a decision.
**cost** One acceptance screen nobody could have used.
**changed** When every answer is synthetic it is raised **once**, as critical,
listing what it covers. 17 findings became 5.
**generalizes** Completeness is not the same as legibility. A control that
reports everything equally reports nothing.

---

## D12 · 2026-10-06 · A revision destroyed the interview it was revising

**believed** The archive step copied everything that mattered.
**happened** `QUESTIONS.md` was on neither the copy-and-delete list nor the
copy-and-keep list, so it was not copied at all. The revision wrote sixteen fresh
open questions over fifteen answered ones. The only record of what a person was
asked, and said, was gone.
**cost** A full interview. In a system whose entire claim is auditable
provenance.
**changed** It is kept, not deleted. The questions step writes a **proposal** and
`questions.sh merge` folds it in: answers survive, ids are matched by text and
never by position, and the merge refuses to write a set with fewer answers than
it started with.
**generalizes** An explicit list of what to preserve will eventually omit
something. The question to ask of any such list is not *"is everything on it"*
but *"what happens to a thing on neither list"*.

---

## D13 · 2026-10-06 · V32 noticed the damage and could not prevent it

**believed** Having a control is having protection.
**happened** The design was bound by digest to a question set that no longer
existed, and said so — after the destruction.
**changed** Nothing about V32; it did its job. The prevention went in beside it.
**generalizes** A control that **notices** and a control that **prevents** are
different controls. Know which one you have before you rely on it.

---

## D14 · 2026-10-06 · Ids are permanent because citations are

**believed** Renumbering questions on a revision is harmless tidying.
**happened** Assumptions cite `[Qn]` and a rule checks every citation resolves.
Renumbering re-points a citation at a different question, silently.
**changed** An existing question keeps its id forever; new ones continue from the
highest.
**generalizes** The moment anything cites an identifier, that identifier is part
of the contract.

---

## D15 · 2026-10-06 · A gate backed by prose compiles to a stub

**believed** The decision-table question was about readability.
**happened** It was about whether anything can be **proved**. Three questions are
answerable about a table and are not answerable about a bash conditional: does
any input fall through, do two rules claim the same input, is any output never
produced.
**changed** Both are allowed, and the difference is visible: a prose gate
compiles to a stub that says it is a stub; a table-backed gate compiles to
working logic. A fall-through is a **refusal**, never a default.
**generalizes** Pick the representation that admits the question you will be
asked, not the one that is nicest to write.

---

## D16 · 2026-10-06 · A rehearsal must be a property of the artifact

**believed** A dry-run mode is a mode.
**happened** Blocking "does the machinery work" on "is this design right" parked
a run for four hours with every upstream step green.
**changed** A gate may be closed without a person. The mark is written **before**
the close, lands on the beads and the register row, opens the findings as
critical, and `compile` refuses to build from it.
**generalizes** Make the escape hatch, then make it impossible to use quietly.

---

## D17 · 2026-10-07 · An override must name who permitted it

**believed** `ALLOW_REHEARSAL=1` is an escape hatch.
**happened** A flag is an unexplained pass, and an unexplained pass in an
environment variable is indistinguishable from a leftover export.
**changed** `=1` is refused explicitly. It takes a name, and the name goes in
the output beside the count of rehearsed gates.
**generalizes** Every override is a decision. A decision with nobody's name on it
is not one.

---

## D18 · 2026-10-07 · Where PHI may go is an agreement, not a property of the data

**believed** *No tool carrying PHI may be used by a model step* is a rule about
PHI.
**happened** It was a rule about what the company had signed. The day a BAA
covering both model providers was confirmed, the rule was wrong — and the fix
would have been editing a validator.
**cost** Nearly encoded a contract into code.
**changed** The catalog carries it, with an attestation date. The rule reads it,
and refuses a **lapsed** attestation.
**generalizes** If the answer changes when a contract changes, it is policy, not
logic. Policy goes where a diff can be reviewed and dated.

---

## D19 · 2026-10-07 · A stale catalog is worse than no catalog

**believed** A missing policy file is the dangerous case.
**happened** `install-rig` synced `checks`, `tooling` and `lib` — not `catalog`.
The rig held a four-entry catalog while the run used a six-entry one. It did not
bite only because the binding passed an explicit path.
**changed** Both install targets carry `catalog/` and `tools/`, asserted by name.
**generalizes** An absent control fails loudly. A stale one answers confidently
from the wrong source, and everything downstream cites it.

---

## D20 · 2026-10-07 · The interview found gaps nobody planted

**believed** The interview would mostly restate the description.
**happened** It found that the catalogued form service carries a submission's
identity but not what is inside one — so the patient's side of every comparison
had **no source at all**. The design could not have been built from the catalog
as it stood. It also found that the catalog chose a medication service *because*
an RxNorm code makes two spellings comparable, and nothing assigns that code to a
typed name.
**cost** Nothing. This is the thing working.
**changed** Two tools catalogued in response, which is what a procurement signal
is for.
**generalizes** The value of asking is not the answers. It is the questions that
turn out to have no answer.

---

## D21 · 2026-10-07 · The permission rule named the absolute path

**believed** A permission rule for a wrapper script was not taking effect.
**happened** The rule names the absolute path. Every invocation was
`./tooling/...`, which does not match it. Three sessions of denials, one wrong
invocation form.
**cost** Several hours of being blocked, and a wrong conclusion stated twice.
**changed** Invoke permitted wrappers by their full path.
**generalizes** When a permission "does not work", check the literal string being
matched before concluding the mechanism is broken.

---

## D22 · 2026-10-07 · The audit found a deadlock the BAA created

**believed** Permitting a model step was a loosening with no structural
consequence.
**happened** With a model deciding same-drug pairs, an entry the model confidently
called *different* became new — but never reached the assistant to be marked
prescription-only, and a gate required that mark. The design would stall forever
on exactly the case it exists to catch.
**cost** One revision attempt. The audit found it in a single pass.
**changed** The settlement step reads entries new by **any** route, including the
model's.
**generalizes** Relaxing a constraint does not simplify a design. It opens paths
the design was not written for, and the new paths are where the deadlocks are.

---

## D23 · 2026-10-08 · A design invented a skill, and a gate rested on it

**believed** Know-how either fits in @tools, or it is detail a design can carry in prose.
**happened** The med-rec design invented two clinical lookup tables inline, named Practice operations as their owner in an assumption line, and gate 19 then refused on them. A control was resting on know-how that existed nowhere but prose, and the next design would have re-derived it — possibly differently.
**cost** Nothing yet. It was found by reading our own output, before it mattered.
**changed** @skills on the design, @skill in the catalog, and V40-V43. The load-bearing rule shipped BEFORE the section: a gate may never depend on a skill, because nothing can prove a document was read.
**generalizes** Know-how that DECIDES and know-how that FRAMES are different things and must not share a section. The first is a decision table, where completeness and overlap are provable. The second is a skill, and the only honest claim about it is which version was in force — never that it was applied.

---

## D24 · 2026-10-08 · The rule against inventing know-how would have refused the design that revealed it

**believed** A design must never name know-how the catalog does not hold. Symmetric with tools, where V27 refuses an uncatalogued one.
**happened** The med-rec design invented two clinical lookup tables and ended the assumption with 'proposed, confirm with Practice operations'. It knew it was proposing and named the owner. V40 as first written would have refused that design — destroying the only signal that told us skills were needed at all.
**cost** Nothing, because Buzz read the rule against the thing that produced it. It would have cost every future skill.
**changed** used_by '-' is a PROPOSAL and routes to the catalog owner as a finding, exactly as a missing tool does. Naming a step is a DEPENDENCY and still requires somebody to own it first.
**generalizes** Tools are discoverable from the use case; skills emerge from the design. For anything only visible at design time, a hard refusal at design time destroys the signal instead of routing it. Ask of any new rule: would it have refused the artifact that taught me I needed the rule?

---

## D25 · 2026-10-08 · Tools are discoverable from the use case; skills emerge from the design

**believed** Everything an organization needs to supply can be settled in the interview, before authoring starts. The interview asks, the catalog answers or routes, and by the time a design is written the inputs are known.
**happened** That holds for tools and sources and does not hold for know-how. A person can answer where appointment data comes from without seeing a design. Nobody can answer what counts as the same dosing frequency until somebody is writing the step that compares two. The need did not exist before the step did.
**cost** One rule written the wrong way round, caught by reading it against the artifact that produced it.
**changed** Each kind of knowledge now surfaces where it can: sources and tools in the interview, as confirm-or-deviate against the catalog; decisions and skills during authoring, as proposals routed to the catalog owner. A design PROPOSES know-how and DEPENDS only on know-how somebody owns.
**generalizes** Knowledge has a moment at which it becomes askable, and a pipeline must put each question at its moment. Ask too early and nobody can answer; refuse too early and the question never gets asked. The test for any gate is not whether the thing is known, but whether it was KNOWABLE yet.

---

## D26 · 2026-10-08 · A failed close left a record saying it had succeeded

**believed** Writing the rehearsal mark before closing the gate is the safe order: a closed gate then always has a mark beside it.
**happened** The close failed — the bead was assigned to the agent session — and the mark stayed. A REHEARSAL file now claimed a gate had been closed without a person when no close had happened at all. The false record was produced by the tool written to be honest about rehearsals.
**cost** Nothing. It failed loudly enough to notice, in a rehearsal, which is what rehearsals are for.
**changed** The mark and the close are atomic: both present or neither. A failed close removes the line it just appended, clears the metadata, and refuses.
**generalizes** Ordering two writes so the dangerous one comes second protects against the second failing. It does nothing about the FIRST succeeding alone. Any write-then-act pair needs the undo, not just the order.

---

## D27 · 2026-10-08 · A filter applied to one of three lists reads as working

**believed** run-status was scoped to one run. The closed-steps list was fixed on 2026-10-05 to filter by root bead, and the screen reported correctly every time it was checked.
**happened** Two runs shared a rig for the first time on 2026-10-08. The in-progress and ready lists had never been scoped, so each run's screen carried the other's steps, and one step appeared as both NOW and next. The fix had been applied to one of the three places that needed it, and nothing distinguished that from all three for three days.
**cost** Nothing, because it surfaced the first time the condition occurred. It was invisible until then by construction.
**changed** All three lists go through one scoped lister in its own file. A test feeds it two beads from different runs and asserts the foreign one is dropped.
**generalizes** A partial fix to a repeated pattern is indistinguishable from a complete one until the untouched copy is exercised. When fixing something that appears N times, the test should be against the PROPERTY, not against the instance you noticed.

---

## D28 · 2026-10-09 · Two of seven diagrams did not compile, and they were the ones asked for

**believed** A Mermaid diagram written carefully is a Mermaid diagram that renders. The repo already renders diagrams by rule, so the format was understood.
**happened** Five of seven rendered. The two that failed were the sequence diagrams, which were the specific thing requested. In a sequence diagram the lexer reads < as an arrow token and ; as a statement separator, so <br/> and a semicolon in message text are both fatal — and both are legal in the flowchart and class labels that rendered fine.
**cost** Nothing, because they were rendered before being published. Everything, had they not been.
**changed** Every diagram is rendered to SVG and committed beside the document, and a test refuses a sequence message carrying either token.
**generalizes** A document is not verified by being written carefully. The same notation can have different lexers per diagram type, and the subset that works in one is not the subset that works in another. Render it, or do not claim it.
