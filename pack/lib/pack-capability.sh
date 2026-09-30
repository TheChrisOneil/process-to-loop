#!/usr/bin/env bash
# A pack directory -> its capability manifest.
#
#   pack-capability.sh <pack-dir>
#
# Deterministic: same directory in, same bytes out.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
P=${1:-}
[ -n "$P" ] || { echo "pack-capability.sh <pack-dir>" >&2; exit 64; }
[ -d "$P" ] || { echo "REFUSED: no pack directory at $P." >&2; exit 1; }
P=$(cd "$P" && pwd)

{
  # PROVIDES — what the pack ships, by name
  [ -d "$P/commands" ] && for c in "$P/commands"/*; do
      [ -e "$c" ] && echo -e "PROVIDES\tcommand:$(basename "$c")"; done
  for r in "$P/roles/agents" "$P/agents"; do
    [ -d "$r" ] && for a in "$r"/*; do [ -d "$a" ] && echo -e "PROVIDES\tagent:$(basename "$a")"; done
  done
  [ -d "$P/formulas" ] && for f in "$P/formulas"/*.toml; do
      [ -e "$f" ] && echo -e "PROVIDES\tformula:$(basename "$f" .toml)"; done

  # the rest, from the prose and the toml
  find "$P" -type f \( -name "*.md" -o -name "*.toml" \) 2>/dev/null | sort | while read -r f; do
    rel=${f#"$P"/}
    awk -v REL="$rel" -f "$HERE/lib/capability.awk" "$f" 2>/dev/null
  done

  # OPAQUE — a digest per prose file. This is the half that cannot be computed.
  find "$P" -type f -name "*.md" 2>/dev/null | sort | while read -r f; do
    rel=${f#"$P"/}
    h=$(shasum -a 256 "$f" 2>/dev/null | cut -c1-12)
    echo -e "OPAQUE\t$rel $h"
  done
} | sort -u
