# An exec check needs a third outcome: could-not-run

## Summary

An exec check can currently say *pass* or *fail*. It cannot say *I could not run*, so an
infrastructure problem — an unreachable dependency, a missing credential, a service that is
down — consumes the step's attempts and closes it `fail`, which is indistinguishable from the
check having evaluated its condition and refused.

Proposal: give the check a third outcome, and reach it through exit codes that already carry this
meaning — `75` from `sysexits.h`, and `126`/`127` from the shell. No number needs assigning.

## These exit codes already mean something, and gc flattens all of them

The proposal does not need a number assigned to it. Several already carry this meaning, from
conventions older than gc and independent of it.

**From the shell, universally:**

| exit | meaning | source |
|---|---|---|
| `127` | command not found | POSIX shell |
| `126` | found but not executable | POSIX shell |
| `128+n` | killed by signal n — e.g. `143` is SIGTERM | POSIX |

**From `sysexits.h`** — a BSD header originating in sendmail, shipped by the OS, nothing to do
with gc:

```c
/*	EX_TEMPFAIL -- temporary failure, indicating something that
 *		is not really an error.  In sendmail, this means
 *		that a mailer (e.g.) could not create a connection,
 *		and the request should be reattempted later.
 */
#define EX_TEMPFAIL	75	/* temp failure; user is invited to retry */
```

gc does not currently assign any of these a meaning. It reads zero versus non-zero and treats
everything else alike, so all four land in `fail`.

The sharpest case needs no convention at all: **a check whose script is not on disk exits 127, and
that is recorded as the step having failed.** The step did not fail. Nothing ran.

A check killed by gc's own `timeout` is the same story, arriving as `143` or `124`.

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
| `75` | **could not run** — `EX_TEMPFAIL`: the check ran and could not do its job |
| `126`, `127` | **could not run** — the check never ran: not executable, or not there |
| `128`+ | **could not run** — killed by a signal, including gc's own timeout |
| everything else | fail — a business outcome, attempt consumed |

A *could not run* outcome consumes no attempt, does not close the step, and halts the run.

Whether `128+` belongs in that set is the one judgement call here. A signal-killed check has not
evaluated its condition, so treating it as a refusal asserts something that did not happen — but a
project may reasonably want a timeout to count against its attempts. It could be the one part made
configurable, or simply left as `fail` if that is the house view.

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

## On repurposing 75

75 is not currently reserved by gc for anything — it is swept into `fail` along with every other
non-zero value. The compatibility question is whether a check somewhere exits 75 *meaning* a
business refusal, and the version gate above is what makes that safe to ignore: formulas declaring
an earlier compiler version keep today's behaviour exactly.

126, 127 and `128+` carry less risk still. A check author does not choose those — the shell does.

## Related, but separate

An unrecognised key inside `[steps.check.check]` is accepted at cook time, dropped, and never
mentioned — as is a misspelled optional key such as `timeou`. A misspelled *constrained* key is
caught cleanly (`max_attempts must be >= 1`). Worth fixing, independent of this, and happy to
raise separately.
