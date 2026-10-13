# An exec check needs a third outcome: could-not-run

## Summary

A check can currently say *pass* or *fail*. It cannot say *I could not run*, so a step whose check
never executed is recorded identically to a step whose check evaluated its condition and refused.

Two parts, independent, and the first needs nothing new at all.

---

## Part 1 — gc already classifies this, then discards its own classification

When the controller cannot run a check, it says so precisely:

```
gc.controller_error       = resolving check path: lstat .../check.sh: no such file or directory
gc.controller_error_class = hard
```

```
gc.controller_error       = resolving check path: file is not executable: .../check.sh
gc.controller_error_class = hard
```

In both cases the step then closes:

```
gc.outcome = fail
```

**The check never ran.** The condition was never evaluated. Nothing refused anything. The
controller knows this — it computed `controller_error_class` — and the outcome throws that away.

### Proposed

When `controller_error_class` is set, the step does not close `fail`. It records that it could not
run, consumes no attempt, and halts the run.

No new exit codes, no conventions, no configuration, and no compatibility question: this uses a
field the controller already populates, in the case it already detects.

### Why it matters

A reader of the bead store afterwards cannot tell a design that failed its checks from a run whose
checks were never reachable. Both read `fail`. For anything running unattended — where the bead
store is the only record of what happened — those are different facts and the cost of separating
them is somebody remembering what was going on at the time.

---

## Part 2 — a check that runs and cannot do its job

Part 1 covers a check the controller could not reach. It does not cover a check that ran fine and
discovered that *its own dependency* is unavailable: a service that is down, a credential that has
expired, a file it needed that is not there.

That check has to report the difference itself, and there is an established way:

```c
/*	EX_TEMPFAIL -- temporary failure, indicating something that
 *		is not really an error.  In sendmail, this means
 *		that a mailer (e.g.) could not create a connection,
 *		and the request should be reattempted later.
 */
#define EX_TEMPFAIL	75	/* temp failure; user is invited to retry */
```

That is `sysexits.h` — a BSD header originating in sendmail, shipped by the OS and unrelated to
gc. *"Something that is not really an error"* is exactly the distinction wanted, and an exec check
is already a process with an exit status, so nothing is being introduced.

### Current behaviour

A one-step formula, `max_attempts = 2`, a check that always exits 75:

```json
gc.attempt_log = [
  {"action":"fail","attempt":"1","outcome":"fail","reason":"...exit 75"},
  {"action":"fail","attempt":"2","outcome":"fail","reason":"...exit 75"}
]
```

Both attempts consumed, step closed `fail`. gc reads zero versus non-zero and treats every other
value alike, so 75 is not reserved for anything today — it is undifferentiated.

### Proposed

| exit | outcome |
|---|---|
| `0` | pass |
| `75` | could not run — no attempt consumed, step does not close, run halts |
| anything else | fail — a business outcome, attempt consumed |

Behind a version gate, so no formula in the field changes on upgrade:

```toml
[requires]
formula_compiler = ">=2.1.0"
```

A formula declaring an earlier version keeps today's behaviour exactly.

### On repurposing 75

The compatibility question is whether some check somewhere exits 75 *meaning* a business refusal.
The version gate makes that safe to ignore. It is also unlikely: 75 has meant EX_TEMPFAIL for
forty years, and a check author reaching for a refusal code reaches for 1.

---

## The outcome already exists

A custom status in the `frozen` category behaves correctly today:

```
$ bd config set status.custom "could_not_run:frozen"
$ bd update <id> --status could_not_run
```

| | |
|---|---|
| offered as work? | no |
| counted closed? | no |

A frozen step halts the run without claiming the work failed — which is the wanted semantics, and
it ships. Both parts above are about reaching it.

---

## Related, but separate

An unrecognised key inside `[steps.check.check]` is accepted at cook time, dropped, and never
mentioned — as is a misspelled optional key such as `timeou`. A misspelled *constrained* key is
caught cleanly (`max_attempts must be >= 1`). Worth fixing, independent of this, happy to raise
separately.
