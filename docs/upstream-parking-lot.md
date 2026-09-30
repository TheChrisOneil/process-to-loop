# Upstream parking lot

Ideas that may belong to the Gas City community rather than to this repo — held here until
the evidence says so, and reviewed on a schedule so they are neither forgotten nor filed early.

**The rule:** nothing goes upstream on a hunch. A proposal leaves this file when it has run
against more than one city, over more than a few weeks, and its own numbers have stopped moving.
This repo has already drafted one issue that was wrong twice over and was never posted, because
a ten-second control test settled it. That is the standard.

---

## PARKED-1 · Capability-surface diffing for packs

**The idea.** A pack's declared version cannot carry compatibility. Every version of the gascity
pack on one machine declares `0.1.0`, and `0.x.y` formally permits breaking changes in any
release, so the field is unusable rather than stale. Compute the surface instead — the way
`cargo public-api`, `japicmp`, `go apidiff` and API Extractor compute a public API because semver
is a human promise about a surface and humans get it wrong.

**What we built.** `pack-capability.sh` emits six properties: PROVIDES, MANDATES, DEMANDS, USES
(what a pack commits to), then NORMS and OPAQUE (judgment, split into the computable half and
the detectable half). `pack-diff.sh` classifies BREAKING / ADDITIVE / UNCLASSIFIED / NONE.
UNCLASSIFIED is never NONE.

**Evidence so far.** On `sha:3b3b89f2` → current main it reports BREAKING and names the cause:
`gc hook --claim` no longer stated, `gc gc claim` newly stated. That is the change that cost this
project a day.

**What the community already says.** Issue **#4071** (open, kind/bug, p2) —
*"Bundled core-pack pin isn't refreshed before release, so `gc init` seeds fresh cities with a
stale pack SHA."* It calls this "a latent release-hygiene risk," documents a three-week lag
between the embedded pin and `main`, and proposes a release-gate check. **The sha it names,
`f895c0f`, is the one our preflight flags as the builtin pin in a city created this week.**

So staleness of the *bundled* pin is known and owned. What #4071 does not cover, and what we
might contribute:

- drift on **user-declared** imports, not just bundled ones
- **capability** comparison rather than commit comparison — knowing you are behind is not knowing
  what you are missing
- the **judgment** half: a prompt rewritten to change an agent's behaviour with no structural
  change, which no commit comparison can see

**Before proposing anything.** Comment on #4071 first rather than opening a new issue. Ask
whether capability diffing is wanted, or whether the release-gate check is considered sufficient.
A comment costs nothing and does not ask maintainers to triage an opinion.

**Status:** parked. Not raised with anyone.

---

## PARKED-2 · `city-preflight` as a contributed check

**The idea.** `gc doctor` runs 77 checks and none of them is "your imports are behind" or "the
command your role prompt mandates does not exist here." Our seven properties could be doctor
checks.

**Why it is parked.** They encode opinions Gas City has not adopted. `CURRENT` treats being
behind `main` as a failure, which a stable deployment would reasonably reject. `PINNED` refuses a
floating import, which `gc rig add` itself produces by default. Proposing these as universal
checks would be telling other people how to run their cities on the strength of one repo's
fortnight.

**What would change that.** Run it against every city we own, weekly, for a month. If CONSISTENT
and COMPATIBLE keep catching real problems and the others mostly do not, propose the two that
earn it rather than all seven.

**Status:** parked. `gc ptl preflight` is importable by anyone who wants it, which is a milder
way to offer an opinion than a pull request.

---

## Where the conversation happens

| | |
|---|---|
| Issues | `gastownhall/gascity` — active, high traffic, well-triaged with kind/ and priority/ labels |
| Discussions | enabled on the repo |
| Discord | `discord.gg/xHpUGUzZp2` — linked from the README |
| Contributing | `CONTRIBUTING.md`, `SUPPORT.md` in the repo root |

**Read before writing.** The issue tracker has a strong house style: reproduction steps, impact
stated honestly including "latent" when it is latent, and corrections appended when an earlier
attribution turns out wrong (#4071 does exactly that in its own body). Match it.

---

## The review

Look at this file when any of these happens, and at least monthly:

- `gc ptl preflight` fails a property on a city that was passing
- `pack-diff` returns BREAKING on an upgrade we were about to make
- a parked item's numbers stop moving — the check stops finding new things, which means it has
  either matured or gone blind, and both are worth knowing
- an upstream issue touches one of these topics

For each parked item ask three questions. **Is it still true?** **Has upstream solved it?** **Do
we have more than one city's worth of evidence?** Two yeses and a no is still parked.
