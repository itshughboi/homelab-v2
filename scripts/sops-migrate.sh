#!/usr/bin/env bash
# Encrypt a live .env file into a .env.sops file for one Docker service.
# The .env file must exist on this machine (it's never committed to Git).
# The resulting .env.sops is safe to commit.
#
# Usage:
#   ./scripts/sops-migrate.sh <service>
#   ./scripts/sops-migrate.sh vaultwarden
#   ./scripts/sops-migrate.sh immich/home    # for nested paths
#
# Pre-requisites:
#   - Run ./scripts/age-setup.sh first
#   - Your .env file must be populated with real values (not the .example)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SOPS_CONFIG="$REPO_ROOT/.sops.yaml"

SERVICE="${1:?Usage: sops-migrate.sh <service>  (e.g. vaultwarden, immich/home)}"

ENV_DIR="$REPO_ROOT/apps/docker/$SERVICE"
ENV_FILE="$ENV_DIR/.env"
SOPS_FILE="$ENV_DIR/.env.sops"
EXAMPLE_FILE="$ENV_DIR/.env.example"

# ── Preflight ──────────────────────────────────────────────────────────────────

if ! command -v sops &>/dev/null; then
  echo "Error: sops not installed. Run: brew install sops"
  exit 1
fi

if grep -q "AGE_PUBLIC_KEY_PLACEHOLDER" "$SOPS_CONFIG"; then
  echo "Error: .sops.yaml still has a placeholder key."
  echo "Run ./scripts/age-setup.sh first."
  exit 1
fi

if [[ ! -d "$ENV_DIR" ]]; then
  echo "Error: service directory not found: $ENV_DIR"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE not found."
  echo ""
  echo "The .env file must exist on this machine with real values."
  if [[ -f "$EXAMPLE_FILE" ]]; then
    echo "To create it from the example:"
    echo "  cp $EXAMPLE_FILE $ENV_FILE"
    echo "  \$EDITOR $ENV_FILE    # fill in the blanks"
  fi
  exit 1
fi

# Warn if .env file looks like it still has blanks (VALUE= with nothing after =)
BLANK_KEYS=$(grep -E '^[A-Z_]+=\s*$' "$ENV_FILE" 2>/dev/null | cut -d= -f1 || true)
if [[ -n "$BLANK_KEYS" ]]; then
  echo "⚠ Warning: the following keys have empty values in $ENV_FILE:"
  echo "$BLANK_KEYS" | sed 's/^/    /'
  echo ""
  echo "You may want to fill these in before encrypting."
  read -rp "Continue anyway? [y/N] " confirm
  [[ "${confirm,,}" != "y" ]] && { echo "Aborted."; exit 0; }
  echo ""
fi

# Confirm overwrite if .env.sops already exists
if [[ -f "$SOPS_FILE" ]]; then
  echo "⚠ $SOPS_FILE already exists."
  read -rp "Overwrite with current .env values? [y/N] " confirm
  [[ "${confirm,,}" != "y" ]] && { echo "Aborted."; exit 0; }
fi

# ── Encrypt ────────────────────────────────────────────────────────────────────

echo "→ Encrypting $SERVICE/.env → $SERVICE/.env.sops ..."

# Strip inline comments (# ...) from values to avoid encrypting them as part of the value.
# e.g.  TOKEN=abc123  # copy from dashboard  →  TOKEN=abc123
# Blank lines and full-line comments are preserved as-is (SOPS keeps them readable).
CLEANED_ENV=$(mktemp)
trap 'rm -f "$CLEANED_ENV"' EXIT

while IFS= read -r line; do
  # Full-line comment or blank: pass through
  if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// /}" ]]; then
    echo "$line"
  # KEY=VALUE  # inline comment: strip the comment
  elif [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)[[:space:]]+#.*$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    # Trim trailing whitespace from value
    val="${val%"${val##*[![:space:]]}"}"
    echo "$key=$val"
  else
    echo "$line"
  fi
done < "$ENV_FILE" > "$CLEANED_ENV"

sops --encrypt \
  --config "$SOPS_CONFIG" \
  --input-type dotenv \
  --output-type dotenv \
  --filename-override "$SOPS_FILE" \
  "$CLEANED_ENV" > "$SOPS_FILE"

# ── Verify ─────────────────────────────────────────────────────────────────────

echo "✓ Created: $SOPS_FILE"
echo ""

# Quick sanity check: decrypt and count vars
VAR_COUNT=$(sops --decrypt --input-type dotenv --output-type dotenv "$SOPS_FILE" 2>/dev/null \
  | grep -cE '^[A-Za-z_][A-Za-z0-9_]*=' || true)
echo "  Verified: $VAR_COUNT variable(s) decrypt successfully."
echo ""

# Compare keys against .env.example if it exists
if [[ -f "$EXAMPLE_FILE" ]]; then
  EXAMPLE_KEYS=$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$EXAMPLE_FILE" | cut -d= -f1 | sort)
  SOPS_KEYS=$(sops --decrypt --input-type dotenv --output-type dotenv "$SOPS_FILE" 2>/dev/null \
    | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' | cut -d= -f1 | sort || true)

  MISSING=$(comm -23 <(echo "$EXAMPLE_KEYS") <(echo "$SOPS_KEYS") || true)
  if [[ -n "$MISSING" ]]; then
    echo "⚠ These keys are in .env.example but not in the encrypted file:"
    echo "$MISSING" | sed 's/^/    /'
    echo ""
  else
    echo "  Key coverage: all .env.example keys are present ✓"
    echo ""
  fi
fi

echo "Next steps:"
echo "  1. Test it:    ./scripts/sops-run.sh $SERVICE config"
echo "  2. Commit it:  git add apps/docker/$SERVICE/.env.sops"
echo ""
echo "When deploying fresh:"
echo "  ./scripts/sops-run.sh $SERVICE up -d"
