# Contributing

Investigative project. Opinions are welcome, especially ones that disagree with the design.

## One house rule, and it is not negotiable

**This repository is public. Everything in it is public.**

A use-case file describes how somebody's business actually works — volumes, thresholds, who
approves what, and which failure already happened and embarrassed someone. Do not put a real
internal process in one. Change the numbers, change the names, or write about a process nobody
will recognize.

The same goes for a design, a formula, or an example. If you would not send it to a competitor,
it does not belong here.

## Working on it

```bash
make test          # four designs compiled, four refusals proven, gc asked
```

`make test` must pass before anything is merged. It is quick and it needs no city.

If you have `gc` installed, `make probe` re-derives what Gas City itself enforces against
whatever version you have. Diff its output when you upgrade — the rules in `REFERENCE.md` are
a digest of a moving spec, and the probe is how you find out it moved.

## What a good change looks like

**Rules earn their place by catching something.** A new design rule or formula rule should come
with the case that fails it. `test.sh` has the pattern: build the broken thing, assert the
tooling refuses it.

**Refusals name the next human action.** Every refusal in this codebase says what to do about
it. A message that only says something is wrong is not finished.

**Nothing reports success it did not verify.** The compiler counts the gates it wrote against
the gates the design declared and deletes its own output when they differ. That posture is the
point of the project; changes that weaken it will be asked to justify themselves.

**Deterministic beats probabilistic.** The emitters produce identical bytes from identical
input. Keep it that way.

## The spec

Gas City's formula surface is documented at
<https://docs.gascity.com/reference/specs/formula-spec-v2>. `REFERENCE.md` here is a working
digest organized as a compile target — it is not a replacement, and where the two disagree the
spec wins.
