#!/usr/bin/env bash
# The compiler's own rules over an emitted formula.
#   validate-formula.sh <formula.toml> [--checkroot <dir>]
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
F=${1:-}; shift || true
ROOT=""
while [ $# -gt 0 ]; do case "$1" in --checkroot) ROOT=${2:-}; shift 2 ;; *) shift ;; esac; done
[ -n "$F" ] || { echo "validate-formula.sh <formula.toml> [--checkroot <dir>]" >&2; exit 64; }
[ -f "$F" ] || { echo "REFUSED: no formula at $F." >&2; exit 1; }
awk -v FILE="$F" -v CHECKROOT="$ROOT" -f "$HERE/lib/validate-formula.awk" "$F"
