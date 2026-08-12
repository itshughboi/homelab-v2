#!/usr/bin/env bash
# Install the repo's git hooks by pointing core.hooksPath at .githooks/.
#
# Hooks live in .githooks/ (committed, versioned) rather than .git/hooks/ (per-clone,
# untracked) so everyone gets the same checks. Run this once per clone:
#
#   ./scripts/install-hooks.sh
#
# What you get:
#   - pre-commit: gitleaks scan of staged changes (blocks committing a secret)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

git config core.hooksPath .githooks
chmod +x .githooks/* 2>/dev/null || true

echo "✅ Git hooks installed (core.hooksPath = .githooks)."

if command -v gitleaks >/dev/null 2>&1; then
  echo "   gitleaks: $(gitleaks version)  — pre-commit secret scanning is active."
else
  echo "⚠️  gitleaks is NOT installed — the pre-commit hook will skip scanning until it is."
  echo "   Install:  https://github.com/gitleaks/gitleaks/releases  (or: brew install gitleaks)"
fi
