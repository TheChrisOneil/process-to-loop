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

# A revision run is HANDED the previous findings and design by path. If either
# names something in this directory, archiving would delete the input before the
# author reads it. Refuse: the run is already wrong, and deleting makes it
# unrecoverable. Point those vars at prior/latest/ instead.
for v in PRIOR_FINDINGS_PATH PRIOR_DESIGN_PATH; do
  t=$(eval "printf '%s' \"\${$v-}\"")
  [ -n "$t" ] || continue
  case "$t" in
    "$R"/prior/latest/*|"$R"/prior/latest)
      # latest is a moving pointer: this very run is about to repoint it, so the
      # path would mean one archive at sling time and a different one afterwards.
      echo "REFUSED: $v points through $R/prior/latest, which this run moves." >&2
      echo "         That path names one archive now and another once this step runs," >&2
      echo "         so the design being revised would change underneath the author." >&2
      echo "         Next human action: resolve it first and pass the fixed path —" >&2
      echo "             readlink \"$R/prior/latest\"" >&2
      exit 1 ;;
    "$R"/prior/*) continue ;;            # a specific archive — fixed, so safe
    "$R"/*)
      echo "REFUSED: $v points at $t, inside the directory being archived." >&2
      echo "         Archiving would delete this run's own input before it is read." >&2
      echo "         Next human action: point $v at $R/prior/latest/ instead." >&2
      exit 1 ;;
  esac
done

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

# Without a stable name, a revision run cannot name the archive it is revising:
# the label is a timestamp nobody knows in advance.
ln -sfn "$LABEL" "$R/prior/latest" 2>/dev/null || true

echo "archived to $DEST:$HAVE"
[ -L "$R/prior/latest" ] && echo "prior/latest now points at $LABEL"
[ -n "$REMOVED" ] && echo "removed from the working directory, so no step can reuse them:$REMOVED"
exit 0
