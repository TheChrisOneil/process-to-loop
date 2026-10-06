# INTERVIEW — the questions asked before a design is written

**Version 1.** 2026-10-06.

This document is the script. It is versioned because two interviews run from
different scripts produce use cases nobody can compare, and because the quality
of every design this system writes depends on this file more than on the author
prompt.

---

## The four rules

1. **Transcribe; do not author.** If you can fill in an answer you did not get,
   the result is indistinguishable from a model-authored assumption, which is
   the thing this step exists to replace. An answer you supplied is a
   `delegated` answer and must be recorded as one.
2. **"I don't know" and "you pick it" are both legal.** The run never stalls on
   the first thing nobody knows. See *The three answers*.
3. **Provenance, not transcripts.** Each answer carries who said it and when. A
   transcript invites someone to treat the scrollback as authoritative over the
   file.
4. **A change is a new version.** The use case's SHA-256 is recorded in the
   header. Change the use case and the questions are about a different process.

---

## The three answers

Every question takes exactly one of these. `questions.sh answer` writes them;
nothing is hand-edited.

| type | means | provenance it leaves |
|---|---|---|
| `stated` | the owner answered | *the owner stated this* |
| `unanswered` | nobody present knows; it names who owes it | *this is open, and X owes it* |
| `delegated` | the owner was asked and chose to let the system decide | *the owner asked me to choose* |

A `delegated` answer carries the value chosen, prefixed `assumed:`. It produces
the same value a silent assumption would, with different provenance — and that
difference is the whole point. "The owner was asked and chose to let the system
decide" is defensible in an audit. "The system decided and mentioned it
afterwards" is not.

**A delegated STRUCTURAL answer becomes a finding**, automatically, so the owner
sees what was chosen before they sign. Delegation therefore defers a decision to
the acceptance gate rather than removing it, which is what makes "you pick it"
always safe to say.

---

## Blocking and deferrable

**`structural`** — the unit, the judgment, the sources, the schema, who signs. A
wrong assumption here poisons every step downstream, and no gate can be written
before it is settled.

**`parametric`** — a threshold, an SLA, a volume, a retention period. Assume,
declare, and surface it with the findings. One interruption instead of eight.

This is the same classification the audit already applies to findings
(`by_revision` / `needs_a_person`), not a parallel one.

---

## Ask the catalog first

Before asking an open question about where data comes from, read the catalog.
It turns research into confirmation:

- without it — *"How do you get appointment data?"*, answerable only by research
- with it — *"Your organization has `eb-appointment-service` sanctioned for
  appointments, and it provides clinician and status in one call. Use it, or is
  this process different?"*

**Deviation is a finding, not an assumption.** If the catalog holds no tool for
a stated need, the honest answer is *this process requires a capability the
organization does not have*, routed to whoever owns the catalog. That is a
procurement and architecture signal raised at design time instead of at
implementation.

---

## The questions

Each derives from something the design format requires and the validator will
refuse without. The numbering is the asking order: structural first, because a
parametric answer given before the unit is settled may be an answer about the
wrong thing.

### Structural

| # | topic | asks | why it blocks |
|---|---|---|---|
| 1 | the unit of work | What is the smallest thing that gets one decision? | Everything downstream is costed per unit. The highest-leverage choice in the system. |
| 2 | the judgment | Within one unit, what is the one call a written rule cannot settle? | Exactly one per unit. If there are three, two are rules nobody has written down. |
| 3 | who decides today | Who makes that call now, and what do they look at? | It names the actor, and it is how you find the rules that already exist. |
| 4 | the sources | Where does each value come from — confirm or deviate against the catalog. | A gate comparing a value from nowhere is a gate on nothing. |
| 5 | the exceptions | What happens today when it goes wrong, and who hears about it? | Every refusal must name a next human action. |
| 6 | the record | What has to be written down, and who reads it afterwards? | `@record` and `@evidence` are both required, and evidence may not be written by the step that made the claim. |
| 7 | who signs | Which named person accepts this design? Never a team. | The acceptance register takes no other signature. For a clinical judgment this must be a clinician. |

### Parametric

| # | topic | asks | what to assume if delegated |
|---|---|---|---|
| 8 | the volume | How many units in a typical run, and how many at once? | A number bounded by contention, blast radius or review capacity. |
| 9 | the thresholds | What figure separates routine from escalation? | A figure from the description, or the most conservative one stated. |
| 10 | the clock | What is the deadline, and what happens when it passes? | The SLA the description implies. |
| 11 | retention | How long are the records kept? | The longest period any named regulation requires. |
| 12 | the exit criterion | What number would make you shut this down? | A figure tied to the quality measure. |
| 13 | the baselines | What does the manual process cost and how often is it wrong today? | `unmeasured`, which the validator warns about and does not refuse. |

A question with no answer in the description is still asked. A question the
description already answers is **not** asked — the interview is for what is
missing, and asking what was already said is how a person learns the interview
is not listening.

---

## What this does not do

It does not decide the design. Every answer here is an input to the authoring
step, which still follows `GENERATE.md`, still passes the rules, and is still
audited by a different model. An interview cannot make a bad design good; it can
stop a good design being built on a guess.
