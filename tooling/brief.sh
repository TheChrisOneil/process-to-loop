#!/usr/bin/env bash
# Turn a validated design into something a person can read and evaluate: the brief, and both
# diagrams archived as files. Deterministic — nothing here is written by a model.
#
#   ./brief.sh <design file>        writes BRIEF.md and diagrams/ beside the design
#
# generate.sh calls this, and so does anyone who wrote a design by hand.
# Students reach this through:  make brief DESIGN=<design>
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DESIGN="${1:?usage: brief.sh <design file>}"
[ -f "$DESIGN" ] || { echo "no such design file: $DESIGN" >&2; exit 2; }

if ! "$HERE/validate.sh" "$DESIGN" >/dev/null 2>&1; then
  echo "REFUSED: this design does not pass the validator, so no brief is written." >&2
  echo "         Run:  make check DESIGN=$DESIGN" >&2
  exit 1
fi

DIR="$(cd "$(dirname "$DESIGN")" && pwd)"
DIA="$DIR/diagrams"; mkdir -p "$DIA"
"$HERE/render.sh"        "$DESIGN" > "$DIA/sequence.mmd"
"$HERE/render.sh" --flow "$DESIGN" > "$DIA/flow.mmd"
# Rendering to SVG is the part that can fail, and failing quietly is how somebody ends up with
# two .mmd files and no idea why. Say what happened, every time.
SVG=""; SVG_NOTE=""
# mmdc installs under the active node version, which some shells put on PATH and some do not
# — nvm adds it interactively, conda can reorder it away. Look where it lives before giving up.
MMDC="$(command -v mmdc 2>/dev/null || true)"
if [ -z "$MMDC" ]; then
  for c in "$HOME"/.nvm/versions/node/*/bin/mmdc /usr/local/bin/mmdc /opt/homebrew/bin/mmdc; do
    # mmdc is a node script, so node has to be reachable too — it sits in the same folder.
    [ -x "$c" ] && { MMDC="$c"; PATH="$(dirname "$c"):$PATH"; export PATH
                     echo "  note: mmdc is not on PATH; using $MMDC" >&2; break; }
  done
fi
if [ -z "$MMDC" ]; then
  SVG_NOTE="mmdc is not installed, so no SVG was drawn."
  # Any SVG already here is from an older design. Leaving it is worse than having none:
  # it is a picture of something this brief no longer describes.
  rm -f "$DIA/sequence.svg" "$DIA/flow.svg"
  echo "  note: mmdc is not installed — the .mmd files are still valid Mermaid." >&2
  echo "        any earlier .svg has been removed, because it drew a different design." >&2
else
  ERR="$DIA/.mmdc.log"
  if "$MMDC" -i "$DIA/sequence.mmd" -o "$DIA/sequence.svg" >"$ERR" 2>&1 \
     && "$MMDC" -i "$DIA/flow.mmd" -o "$DIA/flow.svg" >>"$ERR" 2>&1 \
     && [ -s "$DIA/sequence.svg" ] && [ -s "$DIA/flow.svg" ]; then
    SVG=yes; rm -f "$ERR"
  else
    SVG_NOTE="mmdc is installed but could not draw these diagrams. Its output is in diagrams/.mmdc.log."
    rm -f "$DIA/sequence.svg" "$DIA/flow.svg"
    echo "  note: mmdc failed — see $DIA/.mmdc.log. The .mmd files are still valid Mermaid." >&2
    tail -3 "$ERR" 2>/dev/null | sed 's/^/        /' >&2
  fi
fi

{
  awk -f "$HERE/lib/parse.awk" -f "$HERE/lib/brief.awk" "$DESIGN"
  echo
  echo "## The flow it proposes"
  echo
  if [ -n "$SVG" ]; then
    echo "Pictures, for reading: [\`diagrams/sequence.svg\`](diagrams/sequence.svg) and"
    echo "[\`diagrams/flow.svg\`](diagrams/flow.svg). Open either one — no tooling needed."
  else
    echo "**No pictures were drawn.** $SVG_NOTE"
    echo
    echo "To see either diagram, paste the block below into <https://mermaid.live>, or install"
    echo "the renderer with \`npm install -g @mermaid-js/mermaid-cli\` and run"
    echo "\`make brief DESIGN=<this design>\` again."
  fi
  echo
  echo "### Step by step, with every gate"
  echo
  echo '```mermaid'; cat "$DIA/sequence.mmd"; echo '```'
  echo
  echo "### The same design as a flowchart, coloured by the kind of step"
  echo
  echo "Green is a rule. Pink is the judgment. Amber is a gate. Blue is a check."
  echo
  echo '```mermaid'; cat "$DIA/flow.mmd"; echo '```'
} > "$DIR/BRIEF.md"

echo "  $DIR/BRIEF.md"
echo "  $DIA/  $(ls "$DIA" | tr '\n' ' ')"
