Compute the capability surface of two pack versions and classify the difference.

Usage:
  gc <binding> pack-diff <pack-dir-a> <pack-dir-b>

Public-API diffing applied to a pack. cargo public-api, japicmp and go apidiff
exist because semver is a human promise about a surface and humans get it
wrong. Here the promise is worse than wrong: every version of a pack may
declare the same 0.1.0, and 0.x.y formally permits breaking changes in any
release. So the surface is computed rather than consumed.

Six properties. PROVIDES, MANDATES, DEMANDS and USES are what a pack commits
to. NORMS and OPAQUE are judgment, split into the half that can be computed —
every must, never, only and do-not in the role prompts — and the half that can
only be detected.

Verdicts: BREAKING (exit 2), ADDITIVE (0), UNCLASSIFIED (1), NONE (0).

UNCLASSIFIED is not NONE. A prompt rewritten to give different judgment with
the same surface lands there, and nothing computable can tell you which it was.
