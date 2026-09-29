# The first live run

2026-09-29. `tooling/run-authoring.sh examples/invoices.design 1` — both model lanes against
the real CLI, the deterministic gates in between.

Gate 1 of the invoice design: *exposure over 2000 USD, or supplier on the supervised list, or
no purchase order exists*.

## What happened

| Stage | Result |
|---|---|
| fixtures | 5 rows, 3 undeclared |
| author — `claude-opus-5` | 155 lines |
| **selftest** | 2 passed, 0 failed, **3 still undeclared → refused** |
| audit — `claude-sonnet-5` | verdict `defective`, 1 critical |
| **audit-verdict** | **refused** |

Cost: **$0.619** to author, **$0.440** to audit. About **$1.06 per gate**.

## The defect a different model found

> The `no purchase order exists` clause only runs when `GATE01_PO` is present in the
> environment. If the call site never sets `GATE01_PO`, the whole clause is skipped and the
> gate falls through to PROCEED.

Confirmed by running it, and it is worse than the finding says. With `GATE01_PO` unset:

```
$ ./gate-01.sh 500
PROCEED: exposure 500 USD is at or below 2000, supplier is not supervised,
         purchase order is on file
exit=0
```

**The control asserts "purchase order is on file" having never looked.** A misconfigured call
site — one missing environment variable — turns a three-clause gate into a one-clause gate,
silently, while printing a sentence that says otherwise.

No fixture would have caught it. The fixture table drives the script through its value
argument; this defect lives in what the script does when a *different* input is absent
entirely. That is the boundary between the two halves of the workflow, and it is why the
second model is worth $0.44.

## What the deterministic half caught first

The selftest refused before a token was spent on the audit, for a different reason: the author
decided the boundary inside the script — *"over 2000 USD is strict, so 2000 is not over 2000"*,
which is correct — but never wrote that decision back into the fixture table it was told to
update. Three rows still said `declare`.

So both gates refused, for two unrelated and both legitimate reasons, on the first run.

## What it also found about this tooling

The selftest's check on refusal text looked for `REFUSED` and the script printed `REFUSE:`, so
it warned that a perfectly good refusal said nothing actionable. Narrow heuristic, fixed.

## What this does not prove

The run stops where a person would be asked. No bead was cooked, no retry was driven by the
orchestrator, no gate bead was closed by a human. Those need a city with a controller.
