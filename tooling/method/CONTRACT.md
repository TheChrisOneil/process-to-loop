# What the tooling requires of a design

`GENERATE.md` says what a good design *is*. This says what the programs downstream of it will
**do with the bytes you write**, so you do not have to read them to find out.

Everything here is a property of `tooling/lib/*.awk`. If something below is wrong, the awk is
right and this file is stale — but read the awk only then, not as a matter of course. A run on
2026-10-02 opened eight of those libraries to work this out and spent 26 minutes doing it.

## How your file is parsed — `parse.awk`

One shared parser serves the validator, both renderers and every emitter, so none of them can
disagree about what your design says.

- A line starting with `#` is a comment. A blank line is ignored. Both are dropped **before**
  anything else looks at the line, so a commented-out call is not a call.
- `@name` on its own line opens a section. Leading and trailing whitespace is stripped from
  every line.
- **Keyed sections** — `@meta`, `@unit`, `@evidence`, `@record` — are `key: value`, split on the
  **first** colon. A value may contain colons; a key may not. A line with no colon is skipped
  silently, so a typo'd key does not error, it disappears.
- **`@assumptions`** is a list: a line must begin `- ` or it is dropped.
- **Table sections** — `@steps`, `@gates`, `@kpis` — are split on ` | ` (spaces around the bar
  are tolerated). Field counts are recorded, and the validator checks them.

Field order, which nothing will tell you at runtime:

| section | fields |
|---|---|
| `@steps` | `id │ name │ type │ actor │ description │ scope` |
| `@gates` | `after_step_id │ condition │ refusal` |
| `@kpis` | `name │ kind │ baseline` |

`scope` is optional and defaults to `unit`.

A section name the parser does not know is remembered, not rejected. An invented section is
therefore silent: it will not appear in any diagram, check or bundle.

## Gates must attach to a real step — `check-gates.awk`

Every gate's first field must equal the `id` of a step that exists. The **render refuses before
printing anything** if one does not. This is deliberate: a diagram that quietly drops a control
is the failure the whole method exists to prevent, so the drawing will not be produced at all
rather than produced incomplete.

## Your refusal text becomes a shell string — `emit-check.awk`

One gate row compiles to one check script, and your refusal is placed inside a double-quoted
bash string:

```bash
echo "REFUSED: <your refusal text>" >&2
```

So: **a double quote in a refusal breaks the generated script.** Write refusals in plain prose
with no `"` and no backticks. The condition and the refusal are also copied verbatim into the
script's header comment, where they are the only record of what the check was supposed to do.

Every emitted check exits 1 and says it is not implemented. That is correct and expected — the
emitter writes the gate's *shape* and a person writes its logic. A check that cannot run exits
**75**, which does not consume an attempt and must never be used for a business failure.

## A condition describes what REFUSES — `fixtures.awk`

This is the one that is most often backwards, and the fixture generator is built entirely on it:

> The condition holding means the gate **fires** and the work is **refused**.

From each condition the generator derives a boundary table: `name │ value │ expect │ why`, where
`expect` is `refuse`, `proceed`, or `declare`. `declare` means the tool could not settle the case
and you must rewrite the condition until it can.

It recognises strictly-greater forms — `over N`, `above N`, `more than N`, `greater than N`,
`exceeds N`, `> N` — and steps one unit at the literal's own precision, so `2000` steps by `1`
and `0.01` steps by `0.01`. Write the number the way you mean it to be compared.

Rule V15 exists to serve this: every condition must carry a number, a comparison, or the word
`never`, so there is always a boundary to generate.

## Sources and tools

`@sources` is `id | from | provides | constraint`; `@tools` is `id | used_by | purpose`. Both are
parsed exactly like `@steps` — split on ` | `, one record per line.

`from` and `id` must name catalog entries. The emitter resolves each tool to an absolute path at
build time and writes it into the step, so the bundle calls the real thing and needs no catalog at
run time. Each read appends a ledger line naming the source, the tool and the data class; the
records gate runs a tick and refuses if a declared source left no such line.

## Check your work without reading the implementations

Run these against your draft in a scratchpad. This is what the tooling does to you downstream,
and it is the whole of it:

```bash
tooling/validate.sh <design>              # the 26 rules
tooling/validate.sh --rules               # what they are, in one line each
tooling/brief.sh <design>                 # both diagrams and BRIEF.md
tooling/compile.sh <design> --name <n>     # the formula and its check scripts
```

If those four pass, the libraries you have not read will not surprise you.
