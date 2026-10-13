# Upstream proposal: a check has three outcomes, not two

Draft for Gas City. Written 2026-10-13 against the build installed that day. **Not yet submitted.**

This supersedes the framing in `pr-f18-unknown-check-keys.md`. That draft proposed a configurable
`blocked_exit_codes` key and then spent most of its length on how to keep an extension registry
from becoming a coordination problem. The registry was solving a problem the draft had invented.

The ask is simpler and needs no new vocabulary at all.

---

## The ask

**A check returns one of three things: pass, fail, or could-not-run.**

```
exit 0        pass    the condition holds; the step closes pass
exit 1..74,
     76..     fail    a business outcome; the attempt is consumed
exit 75       FROZEN  the check could not run; no attempt consumed,
                      the step does not close, the run halts
```

No configuration key. No registry. No namespace. The number is already chosen, by a convention
that predates gc by decades.

## 75 is already defined, and defined as exactly this

`sysexits.h`, shipped on every BSD and macOS and widely followed on Linux:

```c
/*	EX_TEMPFAIL -- temporary failure, indicating something that
 *		is not really an error.  In sendmail, this means
 *		that a mailer (e.g.) could not create a connection,
 *		and the request should be reattempted later.
 */
#define EX_TEMPFAIL	75	/* temp failure; user is invited to retry */
```

*"Something that is not really an error."* *"The request should be reattempted later."* That is
the semantics being asked for, written down in 1980s sendmail and still on the system today.

gc would not be introducing a concept. It would be honouring one its own exec checks already sit
inside.

## Both halves already exist in gc

This is the part that makes it small.

**The outcome exists.** `bd config set status.custom "could_not_run:frozen"` creates a status, a
bead holds it, and the semantics are already right:

| | |
|---|---|
| offered as work? | **no** |
| counted closed? | **no** |

A `frozen` step halts the run without claiming the work failed. That is precisely the third
outcome, and it ships today.

**The signal exists.** The controller already reads the exit code — it distinguishes zero from
non-zero to decide pass from fail, and it already computes `gc.controller_error_class` (`hard`)
when it cannot reach a check at all.

What is missing is one branch between them.

## What it costs today

Measured, not argued. A one-step formula, `max_attempts = 2`, one check that always exits 75:

```
gc.attempt_log = [
  {"action":"fail","attempt":"1","outcome":"fail","reason":"...exit 75"},
  {"action":"fail","attempt":"2","outcome":"fail","reason":"...exit 75"}
]
```

Both attempts consumed. Step closed `fail`. Exit 75 is treated identically to exit 1.

Two incidents a week apart, from one expired credential:

- **2026-10-09** — seven steps closed `fail`, reading as a design that failed its rules and could
  not be drawn. All of it one dead OAuth token.
- **2026-10-13** — the same expiry produced *silence*. A run materialized, a step sat ready, three
  agents were up, nothing moved, and no screen said why.

The first is wrong about the cause. The second is the one that matters for unattended operation:
nothing prompts anybody to look.

## The change

Where the controller decides pass from fail on a check's exit status, add the third case. Suggested
shape, deliberately conservative:

- exit 75 sets the step to a frozen status rather than closing it
- the attempt is **not** consumed
- the reason is recorded where a reader will find it
- gate it behind `[requires] formula_compiler >= 2.1.0`, so no formula in the field changes
  behaviour on upgrade

A formula that wants the old behaviour does nothing. A formula that wants the new behaviour
declares a compiler version it was written against, which is a mechanism gc already has.

## What this does not need

Stated because the first draft of this proposal reached for all of them and none is required:

- **no new key in `[steps.check.check]`.** The exit code carries it.
- **no extension registry.** Nothing is being extended.
- **no reserved namespace.** No new names at all.
- **no new status vocabulary.** `frozen` already behaves correctly.

## A smaller, independent defect, worth a separate PR

An unrecognised key in `[steps.check.check]` is accepted at cook time, dropped, and never
mentioned — as is a misspelled optional key (`timeou`). Meanwhile a misspelled *constrained* key is
caught cleanly: `max_attempts must be >= 1`.

That is worth fixing on its own, and it is **not** load-bearing for the three-outcome ask. Design
and the extensibility objection are in `pr-f18-unknown-check-keys.md`, kept because the analysis
stands even though the motivating example does not.

## A smaller one still, possibly the best first contribution

A step that `needs` itself is refused — at graph-apply, *after* beads have been created:

```
native graph apply: adding edge wk-2sjj->wk-2sjj: cannot add self-dependency
```

Catching it in the loader, beside the existing `needs references unknown step` check, avoids
materialising a graph that cannot run. Small, uncontroversial, no design conversation needed.
