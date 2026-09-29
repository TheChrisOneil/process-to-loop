# process-to-loop

Turn a described business process into a running loop on the [Gas City](https://docs.gascity.com)
runtime — and refuse to emit anything the tooling cannot defend.

```bash
make demo          # compile the worked example and ask gc to confirm it
make test          # everything, end to end
```

## The idea

A business process optimization is usually a document. Someone interviews the people doing the
work, maps it, argues about where the judgment really is, and writes it up. Then the write-up
sits in a drive and an engineer builds something that resembles it.

This closes that gap. The optimization is captured in a **design** — a plain-text file a
business person can read and an engineer can compile. The design is checked by rules, signed by
a named person, and compiled into a **Gas City formula**: a method the orchestrator runs, with
gates that are executable scripts rather than instructions an agent might ignore.

```
a described process            prose, in the process owner's own words
  → a design                   25 rules judge it; a named person signs it
  → a formula + check scripts  17 rules judge those
  → gc                         compiles, cooks, and runs it
```

**The design is the source. The formula is a build artifact.** Never hand-edit a formula, the
same way you never hand-edit generated code. Edit the design and compile again.

## Why the gates matter

A gate written into a prompt is a request. The model may honor it, and the day it does not,
nothing reports that anything was skipped.

A gate compiled to `[steps.check] mode = "exec"` is a script the orchestrator runs. Everything
downstream blocks on it. Exit 0 passes, any other non-zero is "not yet" and consumes an attempt,
and exit 75 means the check could not run at all. That is a control, not a hope.

Every generated check refuses until somebody implements it, and says so on its own output. The
compiler will not emit a stub that passes, because a gate that cannot run is not a gate.

## Checks are authored, then attacked

A generated check script is frequently wrong in the same few ways: the polarity
is inverted, the boundary is off by one, a value is read from the model's own
output instead of the source record, or a business failure exits 75 and so never
consumes an attempt.

`formulas/check-authoring.toml` puts three things in front of a person, cheapest
first:

| | | |
|---|---|---|
| **selftest** | deterministic | runs the script against fixtures generated from the gate condition itself. Costs nothing, and catches polarity and boundary without anyone's opinion |
| **audit** | a *different* model | reviews what the first one wrote, against five named dimensions. Two lanes on one model produce correlated blind spots, and the review then looks like agreement when it is one opinion twice |
| **audit-verdict** | deterministic | decides whether the audit passed. The auditor does not grade itself, and it **refuses when the same model authored and audited** |

Then `[steps.gate]` holds the workflow until a person closes it.

The fixture table is the interesting part. From `exposure over 2000 USD` it
generates `1999 proceed`, `2001 refuse`, and `2000 declare` — the boundary is
left undecided on purpose, and the self-test refuses until somebody says which
side it falls on. An undecided threshold is the off-by-one you otherwise find
with the first real unit.

```bash
make compile DESIGN=examples/invoices.design NAME=my-method
make selftest NAME=my-method     # every check against its fixtures, no model
```

## The two rule sets

`gc` validates that the compiled graph is well formed. It does not validate that the method is
any good, and it silently accepts several things that look like controls and are not — a check
script that does not exist, an undeclared `{{var}}`, a formula with no gates at all.

| | |
|---|---|
| **25 design rules** | is the method sound? One judgment per unit, every gate with a number in it, every refusal naming a next human action, proof written by something that did not make the claim |
| **17 formula rules** | is the emitted formula defensible? Every check script exists and is executable, nothing inert is emitted, no step both reasons and writes its own evidence |

`make rules` prints both. `make probe` derives what `gc` itself enforces, by building a
throwaway city and feeding it malformed formulas one at a time.

## Getting started

```bash
make design DESIGN=examples/invoices.design            # read the rules working
make compile DESIGN=examples/invoices.design NAME=my-method
make conformance NAME=my-method                        # needs gc installed
```

`examples/` holds four worked designs and five described processes in a process owner's voice —
KYC onboarding, clinical prior authorization, expense audit, grant eligibility, RFP
qualification — for anyone who wants to start from a description rather than a design.

`schema/DESIGN-FORMAT.md` is the design format. `REFERENCE.md` is the Gas City formula surface,
organized as a compile target, with the spec cited and every claim's provenance marked.

## Requirements

Bash, awk and make — present on macOS and Linux. `gc` only for `make conformance` and
`make probe`; everything else runs without it. No city is needed: the conformance check builds
one in a temp directory, never registers it, and deletes it.

## Status

Investigative. The shape is settled and the tests pass; the edges are not finished.

- One formula per design. `scope: batch` and `scope: unit` should become a parent and a
  `[steps.drain]` item formula.
- No `extends`, so shared method skeletons are not factored out.
- No scopes, so setup and teardown have nowhere correct to live.
- The front door is two commands. Producing a design from a description is not yet part of this
  repo.
- The audit workflow is written and it compiles, but it has not been run against live
  providers. The deterministic halves are tested; the two model lanes are not.

Contributions welcome — see `CONTRIBUTING.md`.
