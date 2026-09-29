#!/usr/bin/env bash
# Ask the installed gc whether an emitted formula actually compiles.
# Builds a throwaway city, never registers it, so no controller or patrol runs.
set -uo pipefail
OUT=${1:?out dir}; NAME=${2:?formula name}
F="$OUT/formulas/$NAME.toml"
[ -f "$F" ] || { echo "REFUSED: no formula at $F. Next human action: make compile first." >&2; exit 1; }
command -v gc >/dev/null || { echo "REFUSED: gc is not installed." >&2; exit 1; }

CITY=$(mktemp -d); trap 'rm -rf "$CITY"' EXIT
mkdir -p "$CITY/formulas"
cat > "$CITY/city.toml" <<'EOF'
[workspace]
provider = "claude"
[providers]
[providers.claude]
base = "builtin:claude"
EOF
cp "$F" "$CITY/formulas/$NAME.toml"

echo "  asking gc to compile $NAME …"
OUTPUT=$(gc formula show "$NAME" --city "$CITY" 2>&1 | grep -v '^warning: this city does not import')
STATUS=$?
echo "$OUTPUT" | sed 's/^/    /'
if echo "$OUTPUT" | grep -qi "validation failed\|cycle\|error"; then
  echo "  REFUSED: gc will not compile it." >&2
  exit 1
fi
STEPS=$(echo "$OUTPUT" | grep -c '├──\|└──')
echo
echo "  gc compiled it: $STEPS step(s), including the workflow-finalize it appends."
