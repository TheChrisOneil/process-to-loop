# Catch a self-dependency in the loader, not at graph-apply

## Summary

A step whose `needs` names itself is refused — but only after the graph has started materialising
beads. Moving the check into formula validation, beside the existing `needs references unknown
step` check, refuses it before anything is created.

## Reproduce

```toml
formula = "selfdep"
description = "probe"
[requires]
formula_compiler = ">=2.0.0"
[catalog]
name = "selfdep"
description = "probe"
[[steps]]
id = "a"
title = "a step that needs itself"
description = "Close with gc.outcome=pass."
needs = ["a"]
```

```
$ gc formula cook selfdep --rig work
native graph apply: adding edge wk-2sjj->wk-2sjj: cannot add self-dependency:
wk-2sjj cannot depend on itself
```

The bead id in the message is the tell: by the time this fires, beads exist.

## Compare with the sibling case

A `needs` pointing at a step that does not exist is caught cleanly, in the loader, before anything
is created:

```
formula validation failed:
  - steps[0] (a): needs references unknown step "nosuchstep"
```

Both are statements about the step graph that are decidable from the file alone. One is checked
there and one is not.

## Suggested change

In the same validation pass that produces `needs references unknown step`, also reject a `needs`
entry equal to the step's own id:

```
  - steps[0] (a): needs references itself
```

## Why it is worth the few lines

A failed cook that has already created beads leaves a partial graph behind, and the error names a
bead id rather than the line in the formula that caused it. The loader has the step id and the
`needs` list in hand; the information is strictly better there.
