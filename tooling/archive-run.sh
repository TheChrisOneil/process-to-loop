#!/usr/bin/env bash
# Put the previous run's artifacts beyond reach before this one overwrites them.
#
#   archive-run.sh <artifact_root> [label]
#
# Every run writes the design, the brief, the diagrams, the verdict and the
# findings into the same directory, so run N+1 destroys run N. Worse, it does not
# destroy all of it: a verdict and a findings file left behind are READ by later
# steps, which is how a run reached a person with yesterday's audit in front of
# them.
#
# So this copies everything into prior/<label>/, and then REMOVES the two
# artifacts that must never survive into a new run — the audit verdict and the
# findings. Both describe one specific design. Inputs are left alone.
#
# Exit 0  there was nothing to archive, or it is archived
# Exit 1  something could not be copied, so nothing was deleted
# Exit 64 wrong arguments
set -uo pipefail
R=${1:?artifact_root}
[ -d "$R" ] || { echo "no artifact_root at $R" >&2; exit 64; }
LABEL=${2:-}
[ -n "$LABEL" ] || LABEL=$(date -u +%Y%m%dT%H%M%SZ)

# Only ever reused by a later step, so only ever dangerous to leave behind.
DERIVED="design-audit-verdict.json FINDINGS.md"
# Worth keeping a copy of, but harmless if left.
KEEP="BRIEF.md diagrams"

HAVE=""
for f in $DERIVED $KEEP; do [ -e "$R/$f" ] && HAVE="$HAVE $f"; done
for d in "$R"/*.design; do [ -e "$d" ] && HAVE="$HAVE $(basename "$d")"; done

if [ -z "${HAVE// /}" ]; then
  echo "nothing to archive in $R — this is the first run."
  exit 0
fi

DEST="$R/prior/$LABEL"
mkdir -p "$DEST" || { echo "could not create $DEST" >&2; exit 1; }

for f in $HAVE; do
  cp -pR "$R/$f" "$DEST/" || { echo "could not copy $f; nothing was deleted." >&2; exit 1; }
done

# Record what this is, so an archive is readable without the bead store.
{
  echo "archived_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "label: $LABEL"
  echo "from: $R"
  for d in "$DEST"/*.design; do
    [ -e "$d" ] && echo "design_sha256: $(shasum -a 256 "$d" | awk '{print $1}')"
  done
  echo "files:"
  for f in $HAVE; do echo "  - $f"; done
} > "$DEST/MANIFEST.txt"

# Only now, with copies confirmed on disk, remove what must not be reused.
REMOVED=""
for f in $DERIVED; do
  if [ -e "$R/$f" ] && [ -e "$DEST/$f" ]; then
    rm -rf "$R/$f" && REMOVED="$REMOVED $f"
  fi
done

echo "archived to $DEST:$HAVE"
[ -n "$REMOVED" ] && echo "removed from the working directory, so no step can reuse them:$REMOVED"
exit 0
