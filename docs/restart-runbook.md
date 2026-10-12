# After the restart — what to do, in order

Written 2026-10-12, before shutting down. Everything in the repo is committed and pushed;
nothing below is recovery, it is resumption.

**The one blocker is the first step.** Nothing else will work until it is done.

---

## 1. Log the Claude CLI back in — this is the blocker

The CLI's OAuth session expired on about 2026-10-09:

```
Failed to authenticate: OAuth session expired and could not be refreshed
```

Every agent attempt since has failed instantly. In a terminal:

```bash
claude /login
```

Follow the browser flow. Then confirm it took, from any directory:

```bash
claude -p "reply with the single word: ok" --model claude-opus-5
```

If that prints `ok`, you are unblocked. If it prints anything about authentication, stop here —
nothing further will work.

---

## 2. Check the supervisor came back by itself

`com.gascity.supervisor` is a launchd agent with `RunAtLoad` and `KeepAlive`, so it should start
on login without you. Confirm rather than assume:

```bash
launchctl list | grep gascity          # expect: <pid>  0  com.gascity.supervisor
cd ~/cities/ptl-city && gc status
```

Expect `Controller: supervisor-managed (PID …)` and `Suspended: no`.

**If `gc status` shows every pool at zero and nothing moves**, suspect a stale supervisor across
the restart rather than a broken run — `docs/standing-up-a-city.md` has the check and the fix. A
quiet supervisor log is evidence it was never asked, not that it failed.

The tmux agent sessions do **not** survive a reboot, and they do not need to: the supervisor
starts them on demand when work is routed. An empty `tmux -S /private/tmp/tmux-501/ptl-city ls`
before you sling anything is normal.

---

## 3. Where the two runs actually are

| process | workflow | state |
|---|---|---|
| **med-rec** | `wk-usce` | **dead.** Eight steps marked FAILED, all of them the expired login. Needs re-slinging |
| **chase** | `wk-mo2n` | **parked at acceptance**, `wk-bph9`. Reached it before the expiry. Nothing wrong with it |

**Nothing is lost.** `QUESTIONS.md` survived for both — 24 answers for med-rec, 21 for chase — so a
re-sling resumes from the answers instead of re-interviewing. That is the archive fix from
2026-10-06 doing its job.

### What those FAILED steps are not

med-rec reads as a design that failed its rules eight ways: *Write the design*, *Gate: the design
passes its rules*, *Gate: every question came back with an answer*. None of it is true. It is one
expired credential, reported as a business outcome — the project's own recurring defect, appearing
one level above us. Worth remembering before anybody reads those beads as a verdict on the design.

---

## 4. Re-sling med-rec

One command. It carries the prior design and findings, so the author revises rather than starts
over:

```bash
cd ~/cities/ptl-city
A=$(readlink ~/cities/ptl-rig/processes/med-rec/prior/latest)
P=$HOME/cities/ptl-rig/processes/med-rec
gc sling work/gc.run-operator design-authoring --formula \
  --var use_case_path=$P/use-case.txt \
  --var design_path=$P/med-rec.design \
  --var method_path=$HOME/software/process-to-loop/tooling/method/GENERATE.md \
  --var tooling_root=$HOME/software/process-to-loop/tooling \
  --var checks_root=$HOME/cities/ptl-rig/checks \
  --var catalog_path=$HOME/software/process-to-loop/catalog/eb-tools.catalog \
  --var questions_path=$P/QUESTIONS.md \
  --var interview_path=$HOME/software/process-to-loop/tooling/method/INTERVIEW.md \
  --var artifact_root=$P \
  --var prior_design_path=$P/prior/$A/med-rec.design \
  --var prior_findings_path=$P/prior/$A/FINDINGS.md \
  --var approver="Buzz, process owner"
```

Then watch it:

```bash
~/software/process-to-loop/tooling/run-status.sh ~/cities/ptl-rig/processes/med-rec
```

It will stop at `gate-answers` waiting for a person. The answers are already there, so that gate
only needs closing.

---

## 5. The four open gates, and what each means

```bash
cd ~/cities/ptl-rig && gc bd gate list
```

| gate | run | what it is waiting for |
|---|---|---|
| `wk-bph9` | chase | **acceptance.** The design is done and audited |
| `wk-4z87` | med-rec | acceptance, on a run that died. Will be superseded |
| `wk-tyio` · `wk-avl` | older med-rec runs | residue. Harmless, and safe to leave |

To close one yourself:

```bash
cd ~/cities/ptl-rig && gc bd close <gate-id> --reason "..."
```

I cannot close these — the harness refuses an agent closing a human-approval gate as
`[Self-Approval]`, which is correct. The one exception is `tooling/rehearse-gate.sh`, which marks
the run a rehearsal and makes `compile` refuse to build from it. **Call it by its absolute path**
or the permission rule will not match:

```bash
/Users/thechrisoneil/software/process-to-loop/tooling/rehearse-gate.sh <gate-id> \
  --by "Name, Role" --why "..."
```

---

## 6. If you want to sign the chase design

It is the one that reached acceptance cleanly: 43 rules pass, both skills named, four audit
findings that all need a person.

```bash
~/software/process-to-loop/tooling/accept.sh \
  ~/cities/ptl-rig/processes/chase/chase.design --by "Buzz, process owner"
```

It shows the design's meta and content hash and waits for you to type `I accept`. The register row
will record that 21 of 21 interview answers were synthetic, permanently.

**Read `FINDINGS.md` first.** One of the four is a contradiction in the answers I gave on your
behalf: I said a recent hospital stay is never drafted as a chase note, and separately that the
form service cannot say which item raised a flag. The design cannot do both. The audit found it,
and it is a defect in the answers rather than in the design.

---

## 7. Nothing to restore

- the repo is committed and pushed — `github.com/TheChrisOneil/process-to-loop`, 309 assertions, 0 failed
- the bead store is Dolt-backed and survives the restart
- every artifact is on disk under `~/cities/ptl-rig/processes/`
- two untracked PNGs under `Claude outputs/` in the eb workspace are unrelated to this work

---

## The short version

1. `claude /login`, then confirm with a one-line prompt
2. `launchctl list | grep gascity`, then `gc status`
3. re-sling med-rec with the command in §4
4. close its `gate-answers` when it parks
5. decide whether to sign chase

Everything else is already where it should be.
