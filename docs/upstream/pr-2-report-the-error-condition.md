# When work cannot proceed, the reason should reach a bead

Draft. Supersedes `pr-2-three-check-outcomes.md`, which asked for a new step outcome. That ask was
breaking — a step that does not close `fail` leaves a run that never terminates — and it was
solving the wrong problem.

**The goal is that a coordinator has enough information to ask a person to fix something.** That
needs no new outcome and no semantic change. It needs the reason to be written down.

---

## The three cases, and what each records today

### 1. The check ran and failed — already correct

```json
gc.attempt_log = [{"action":"fail","attempt":"1","outcome":"fail","reason":"<the check's message>"}]
```

The reason is on the bead. A coordinator can read it and act. **No change wanted.**

### 2. The controller could not reach the check — recorded, but only in a field nothing surfaces

```
gc.controller_error       = resolving check path: lstat .../check.sh: no such file or directory
gc.controller_error_class = hard
gc.outcome                = fail
```

The information is there and it is good. What is missing is that `outcome` alone cannot
distinguish this from case 1, so anything reading outcomes — a dashboard, a status command, an
operator — sees a failure and not a thing to fix.

**Smallest useful change:** surface `controller_error` wherever a failed step's reason is shown,
and do not consume an attempt when `controller_error_class` is set. Neither alters the outcome
value, so nothing downstream breaks.

The attempt point matters on its own: a step with `max_attempts = 5` whose check path is wrong
burns all five on the same unreachable path, and a budget meant for revising work is spent on an
error no revision can fix.

### 3. An agent cannot claim the work — nothing is recorded anywhere

This is the real gap.

When an agent session cannot start work — an expired credential is the case we hit — the bead
shows:

```
gc.attempt_log = [{"action":"fail","attempt":"1","outcome":"fail","reason":"attempt subject wk-xxxx already failed"}]
```

and the bead it names, `wk-xxxx`, records:

```
gc.attempt_log            = (empty)
gc.controller_error       = (empty)
gc.controller_error_class = (empty)
```

The reason exists only on the agent's terminal. Nothing durable holds it. A coordinator reading
the bead store afterwards can see **that** something failed and has no way to learn **what**, and
the same condition can also present as silence — a run with a ready step, live agents, and nothing
moving.

**What would help:** when a claim or a session start fails, write the reason to the bead that
failed, rather than to a bead that records nothing. `attempt subject X already failed` points at
an empty record.

---

## Why this shape rather than a new outcome

A new terminal state is attractive and expensive. It changes what a finished run looks like, and
anything that polls for completion, retries on failure, or counts outcomes has to learn the new
value. For a coordinator deciding whether to ask a person for help, none of that is needed: the
decision follows from the *reason*, which is already the right place for it.

So the ask is narrow:

1. do not consume an attempt when `controller_error_class` is set
2. surface `controller_error` alongside the outcome wherever a failure is reported
3. when an agent cannot claim work, write why on the bead that could not be claimed

None of the three changes an outcome value. None breaks a consumer. All three put the reason where
somebody can act on it.

## Optional, separable, and not asked for here

If a distinguishable outcome is ever wanted, `bd config set status.custom "could_not_run:frozen"`
already produces a status that is neither offered as work nor counted closed. That is a larger
conversation and should be version-gated; it is not needed for the goal above.
