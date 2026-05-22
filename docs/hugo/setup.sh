#!/usr/bin/env bash
# Sets up and runs the Hugo docs site locally.
# Run once from this directory: ./setup.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

# ── Check dependencies ────────────────────────────────────────────────────────

check_dep() {
  if ! command -v "$1" &>/dev/null; then
    echo "Error: '$1' not found."
    echo "Install: $2"
    exit 1
  fi
}

check_dep hugo  "brew install hugo"
check_dep go    "brew install go"

echo "→ Hugo version: $(hugo version)"
echo ""

# ── Fetch theme ───────────────────────────────────────────────────────────────

echo "→ Fetching hugo-book theme..."
hugo mod tidy
echo "✓ Theme ready."
echo ""

# ── Serve ─────────────────────────────────────────────────────────────────────

echo "→ Starting local server at http://localhost:1313"
echo "  Press Ctrl+C to stop."
echo ""

hugo server \
  --buildDrafts \
  --disableFastRender \
  --navigateToChanged
