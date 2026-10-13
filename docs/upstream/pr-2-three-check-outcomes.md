# An exec check needs a third outcome: could-not-run

## Summary

An exec check can currently say *pass* or *fail*. It cannot say *I could not run*, so an
infrastructure problem — an unreachable dependency, a missing credential, a service that is
down — consumes the step's attempts and closes it `fail`, which is indistinguishable from the
check having evaluated its condition and refused.

Proposal: treat **exit 75** as a third outcome. It is already defined as exactly this.

## 75 is already EX_TEMPFAIL

From `sysexits.h`, shipped on BSD and macOS and widely followed elsewhere:

```c
/*	EX_TEMPFAIL -- temporary failure, indicating something that
 *		is not really an error.  In sendmail, this means
 *		that a mailer (e.g.) could not create a connection,
 *		and the request should be reattempted later.
 */
#define EX_TEMPFAIL	75	/* temp failure; user is invited to retry */
```

*"Something that is not really an error."* That is the semantics being asked for, and an exec
check is already a process with an exit status, so the convention applies without anything being
introduced.

## Current behaviour

```toml
[[steps]]
id = "probe"
title = "a step whose check always exits 75"
description = "Close with gc.outcome=pass."

[steps.check]
max_attempts = 2

[steps.check.check]
mode = "exec"
path = "checks/always-75.sh"   # echoes a message, exits 75
timeout = "1m"
```

```json
gc.attempt_log = [
  {"action":"fail","attempt":"1","outcome":"fail","reason":"...exit 75"},
  {"action":"fail","attempt":"2","outcome":"fail","reason":"...exit 75"}
]
```

Both attempts consumed, step closed `fail`. Exit 75 and exit 1 are treated identically.

## Proposed behaviour

| exit | outcome |
|---|---|
| `0` | pass |
| `1`–`74`, `76`+ | fail — a business outcome, attempt consumed |
| `75` | **could not run** — attempt **not** consumed, step does not close, run halts |

## Both halves already exist

**The outcome.** A custom status in the `frozen` category already behaves correctly:

```
$ bd config set status.custom "could_not_run:frozen"
$ bd update <id> --status could_not_run
```

| | |
|---|---|
| offered as work? | no |
| counted closed? | no |

A frozen step stops the run without claiming the work failed, which is the wanted semantics.

**The signal.** The controller already reads the exit status to decide pass from fail, and already
computes `gc.controller_error_class` when it cannot reach a check at all.

What is missing is one branch between them.

## Compatibility

Gate it behind the compiler version so no formula in the field changes behaviour on upgrade:

```toml
[requires]
formula_compiler = ">=2.1.0"
```

A formula that declares an earlier version keeps today's behaviour exactly.

## Why it matters for unattended runs

With two outcomes, an infrastructure failure is recorded as a verdict on the work. A reader of the
bead store afterwards sees steps that read as refusals and were not, and the cost of telling them
apart is somebody remembering what was happening at the time.

The failure is also easy to miss in the other direction: a run can stall with a step ready and
nothing claiming it, and no bead records a reason, because the thing that could not run never got
far enough to write one.

## Related, but separate

An unrecognised key inside `[steps.check.check]` is accepted at cook time, dropped, and never
mentioned — as is a misspelled optional key such as `timeou`. A misspelled *constrained* key is
caught cleanly (`max_attempts must be >= 1`). Worth fixing, independent of this, and happy to
raise separately.
