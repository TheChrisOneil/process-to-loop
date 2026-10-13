# Upstream proposal: refuse unknown keys in a check block

Draft for Gas City. Written 2026-10-13. **Not yet submitted, and no longer the primary ask.**

> **Superseded as a motivation by `pr-three-check-outcomes.md`.** This draft proposed a
> configurable `blocked_exit_codes` key, and then spent most of its length keeping an extension
> registry from becoming a coordination problem — a problem it had invented. The real ask needs no
> key at all: a check returns pass, fail, or could-not-run, and exit 75 already means the third
> thing in `sysexits.h`.
>
> Kept because the defect is real and independent: an unrecognised key in a check block is
> accepted, dropped and never mentioned. The extensibility analysis below stands on its own, and
> applies whenever gc does add a key worth misspelling.

---

## The defect

A key gc does not recognise inside `[steps.check.check]` is accepted at cook time, dropped, and
never mentioned.

```toml
[steps.check.check]
mode = "exec"
path = "checks/thing.sh"
timeout = "2m"
blocked_exit_codes = [75]      # invented
on_could_not_run  = "blocked"  # invented
```

That formula cooks without a word of complaint, and neither key reaches the bead. Only
`gc.check_mode`, `gc.check_path` and `gc.check_timeout` arrive.

The same happens to a **misspelled optional key**: `timeou = "2m"` cooks, the key is dropped, and
the step silently takes the default timeout.

## Why it matters more here than it looks

gc already validates the keys it knows. Misspell `max_attempts` and cooking fails:

```
steps[0] (probe).check: max_attempts must be >= 1
```

So the author of a formula gets a clear signal for a constrained key and **silence** for an
unknown one. Silence is the worse of the two, because a formula is supposed to be the executable
form of a method. A line that reads as a control and is inert makes the formula partly a
document, and nothing downstream can catch it — by the time anything downstream exists, the key
is gone.

## Evidence

| probe | result |
|---|---|
| cook with `blocked_exit_codes` and `on_could_not_run` | cooks clean; neither key on the bead |
| cook with `timeou` instead of `timeout` | cooks clean; default timeout used |
| cook with `max_attempt` instead of `max_attempts` | **refused**: *max_attempts must be >= 1* |

Reproducible against a one-step formula; the probes are in `docs/upstream-parking-lot.md`
PARKED-5.

## The change

In the formula loader, where `[steps.check.check]` is decoded: collect keys that are not
recognised, and fail validation naming each one — the same shape as the existing
`max_attempts must be >= 1` error.

```
steps[0] (probe).check.check: unknown key "blocked_exit_codes"
steps[0] (probe).check.check: unknown key "timeou" (did you mean "timeout"?)
```

The "did you mean" is worth the few lines: the misspelling case is the common one, and a
Levenshtein distance of 1 or 2 against the known set catches it.

**It only works for keys gc owns.** gc knows `mode`, `path` and `timeout`, so it can tell that
`timeou` was meant to be one of them. It has no vocabulary for anything else, and cannot acquire
one by inspection.

---

## The objection that has to be answered first: do you need a registry?

**Yes, and that is the real design work.** A strict allowlist is the easy half; what it breaks is
everyone who had a reason to put something there.

A refusal that cannot be opted out of means:

- an **older formula** that set a key a newer gc removed now fails to cook, where before it was
  harmlessly ignored
- a **tool built on gc** that stores its own metadata in a check block stops working
- a **forward-compatible formula** written for gc 1.4 cannot be cooked on 1.3

Four ways to resolve it, with what each costs:

### 1. A reserved namespace — recommended

Any key matching a prefix is accepted and carried through verbatim onto the bead:

```toml
[steps.check.check]
mode = "exec"
path = "checks/thing.sh"
x-process-to-loop-expects = "75"
```

Everything else is refused. The prefix is the registry: no central list, no coordination, and the
key **reaches the bead**, so whoever set it can read it back. This is what HTTP did with `X-`,
what TOML-adjacent formats do with `x-`, and what OpenAPI does with `x-` extensions.

Cost: one regex and a decision about the prefix. Benefit: unknown-key typos are caught, and
extension is explicit rather than accidental. **A key that is a typo and a key that is an
extension stop looking identical, which is the whole point.**

#### But then how does gc know the correct spelling inside the namespace?

It does not, and it cannot. `x-process-to-loop-expcts` is indistinguishable from
`x-process-to-loop-expects` to a parser with no vocabulary for either.

That is the trade, and it is acceptable for one reason: **the key reaches the bead.** Whoever owns
the prefix can read their own keys back and validate them, because they do know the spelling.
Today the key vanishes at cook time, so nobody can — not gc, and not the tool that set it.

So the boundary is responsibility, not capability:

| | who spell-checks | how |
|---|---|---|
| `mode`, `path`, `timeout` | **gc** | it owns the vocabulary; refuse unknown, suggest the near miss |
| `x-anything` | **whoever owns the prefix** | read it off the bead and validate; gc carries it verbatim |

This is strictly better than today in both halves. gc's own keys go from silently dropped to
refused with a suggestion. Extension keys go from silently dropped to **carried**, which is the
first time an extension could check its own spelling at all.

It is worth being plain that this leaves a gap: a typo inside the namespace is caught by the
extension or not at all. Option (2) closes it — a declared registry lets gc validate extension
keys too — at the cost of every extension having to be known to gc. That is the real axis:

> **the namespace trades typo-detection inside the prefix for zero coordination.
> The registry buys it back, and charges coordination for it.**

For a formula compiler with a small number of extension authors, the namespace is the right
starting point and the registry is the upgrade if it is ever needed.

### 2. A declared registry in the formula

```toml
[requires]
formula_compiler = ">=2.0.0"
extensions = ["process-to-loop/v1"]
```

More ceremony, and it needs gc to know what each extension permits — which is a coordination
problem the namespace avoids.

### 3. Warn, do not fail

Honest and weak. A warning in a cook that prints five lines is a warning nobody reads, and the
defect this fixes is precisely that nobody was told loudly enough.

### 4. Strict, with a version gate

Refuse unknown keys only when `[requires] formula_compiler >= 2.1.0`. Existing formulas keep
cooking; new ones opt into strictness. Combines well with (1) and is probably how it should ship.

### What I would propose

**(1) plus (4):** reserved `x-` prefix carried onto the bead, strict refusal of everything else,
gated behind the compiler version so nothing in the field breaks on upgrade.

---

## What this does not fix

The larger gap, which is PARKED-5: there is still no step outcome for *could not run*. An exec
check exiting 75 consumes its attempts and closes `fail`, identically to exit 1. This PR only
stops a formula from **appearing** to configure that.

The two are related and should be read together — if `blocked_exit_codes` ever becomes real, this
PR is what stops a typo in it being silent.

## Standing offer

We maintain a formula validator with eighteen rules over emitted formulas, and measured which of
them gc already enforces. Two findings worth sending regardless of this PR:

- **gc's message is better than ours** for duplicate step ids (it names both definitions) and for
  the missing `[requires]` key (it names the deprecated alternative too).
- **ours catches one thing earlier**: a step that `needs` itself is refused by gc at graph-apply,
  *after* beads have been created. Catching it in the loader would avoid materialising a graph
  that cannot run.

That last one is a smaller PR than this and might be the better first contribution.
