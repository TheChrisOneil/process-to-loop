Check a city against seven properties the pack specification leaves undefined.

Usage:
  gc <binding> preflight [--accept] [--offline]

The spec states it "contains no normative drift or staleness detection
semantics" and does not define how an operator discovers that a resolved pack
no longer matches upstream. `requires_gc` exists and is not enforced. These are
those semantics:

  PINNED      every import declares a version; a blank one floats
  COHERENT    declared, locked and resolved agree
  UNIFIED     one pack family resolves to one version
  CURRENT     the declared sha is upstream main, or knowingly behind
  CAPABLE     gc hook --claim answers and gc.run-operator resolves
  CONSISTENT  the claim command the role prompt mandates exists here
  COMPATIBLE  the capability surface has not moved since you accepted it

--accept records the current surface to .gc/capability.lock. packs.lock records
which version resolved; nothing else records what that version committed to.

Exits non-zero when a property fails, because formulas developed against a city
that fails one may be written for a capability surface it does not have.
