# QUESTIONS.md — the format

The interview is the interface. This file is the record.

A question set is Markdown a person can read and awk can parse. The parser is
`tooling/lib/questions.awk`; the rules are `tooling/questions.sh validate` and
`tooling/questions.sh answered`.

---

## Shape

```markdown
# Questions on <process-name>

interview: tooling/method/INTERVIEW.md v1
asked: 2026-10-06
catalog: catalog/eb-tools.catalog
use_case_sha256: 3f1c...

Any prose. It is ignored by the parser and read by the person.

## Q1 — the unit of work
class: structural
asks: Is one unit one appointment, or one patient?
why: Everything downstream is costed per unit, and no gate can be written first.
catalog: eb-appointment-service provides appointment_id, patient_ref, clinician
answer: stated | Buzz, process owner | 2026-10-06 | one appointment | real
```

**A keyed line** is lowercase and underscores only, hard against the left
margin, then a colon. Prose does not look like that, and a question's own text —
which does contain colons — is the value of `asks:`, never a line of its own.

**Keyed lines before the first `## Q`** are the header. After it, they belong to
that question.

---

## The header

| key | meaning |
|---|---|
| `interview` | which version of the interview script asked these |
| `asked` | the date |
| `catalog` | the catalog these questions were asked against |
| `use_case_sha256` | the described process these are about. Change it and they are about something else |

All four are required.

---

## A question

| key | required | meaning |
|---|---|---|
| `class` | yes | `structural` or `parametric`. There is no third kind |
| `asks` | yes | the sentence you would say out loud, ending in a question mark |
| `why` | yes | what it blocks or what it costs. The reason an answer is worth giving |
| `catalog` | no | what the organization already has for this, or `none` |
| `answer` | yes | written by `questions.sh answer`, never by hand |

`questions.sh ask` renders one of these for a person to answer; `questions.sh brief` renders all
of them as a table for the acceptance screen. Neither is a second definition of the format —
both read the same parser.

Ids run `Q1..Qn` with no gaps, because a finding cites a question by id.

---

## The answer line

```
answer: <type> | <by> | <date> | <value> | <provenance>
```

| field | |
|---|---|
| `type` | `stated` · `unanswered` · `delegated` |
| `by` | who said it. For `unanswered`, who owes it |
| `date` | `YYYY-MM-DD` |
| `value` | the answer. Empty for `unanswered`; begins `assumed:` for `delegated` |
| `provenance` | `real` or `synthetic`. Default `real` |

A pipe separates the fields, so it cannot appear inside one.

**`synthetic`** means the answer was supplied on behalf of the named person
rather than by them — a test run, a rehearsal, a dry fit. It is counted and
reported, because a design whose interview was answered by the system is not a
design anybody confirmed.

---

## What happens to an answer

| answer | in the design | at the gate |
|---|---|---|
| `stated` | an assumption citing `[Qn]` and the word *stated* | an auditor can tell it from a guess |
| `unanswered` | an assumption citing `[Qn]` and the word *unanswered* | a minor finding naming who owes it |
| `delegated`, parametric | an assumption citing `[Qn]` and the word *delegated* | visible among the assumptions |
| `delegated`, **structural** | the same | **a major finding** — the owner sees what was chosen before signing |

Rules V32, V33 and V34 enforce the first column. `findings.sh --questions`
produces the second.
