# The tool contract

A tool is a command this system may invoke on a design's behalf. It is named in the catalog,
referenced by `@sources.via` or `@tools`, and called by an emitted step.

Three subcommands, all deterministic, none interactive.

```
<tool> health          exit 0 if reachable, 75 if it cannot answer
<tool> schema          the fields it provides: one `name<TAB>type` per line
<tool> fetch [unit]    TSV on stdout: a header row, then rows
```

## Why `schema` is not optional

It is what makes a design's `@sources.provides` **derivable** rather than typed from memory. A
person asked to describe a record gets it subtly wrong; a tool asked for its schema does not.
Anything in `provides` that the tool does not report is a design naming a field that will not
exist at run time.

## Why `health` is not optional

Preflight asks every named tool whether it answers, before a run starts. A catalog entry nothing
verifies is a comment, and a run that discovers an unreachable source on attempt one has spent an
attempt learning something checkable in a second.

## Exit codes

The same three this system uses everywhere, so a tool failure is never mistaken for a business
outcome.

```
0   it worked
1   it refused — a real answer about the data
75  it could not run — unreachable, unreadable, not configured
```

A tool that cannot reach its backend exits **75**, never 1. The difference is whether a person
should look at the process or at the plumbing.
