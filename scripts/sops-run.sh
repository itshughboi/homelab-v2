#!/usr/bin/env bash
# Run docker compose for a service with secrets injected from its .env.sops file.
# Secrets are decrypted in memory and passed as environment variables —
# no plaintext .env file is ever written to disk.
#
# Usage:
#   ./scripts/sops-run.sh <service> [docker compose args...]
#
# Examples:
#   ./scripts/sops-run.sh vaultwarden up -d
#   ./scripts/sops-run.sh vaultwarden down
#   ./scripts/sops-run.sh vaultwarden ps
#   ./scripts/sops-run.sh vaultwarden pull
#   ./scripts/sops-run.sh vaultwarden config       # dry-run: print resolved compose file
#   ./scripts/sops-run.sh immich/home up -d
#
# Note: If a service has no .env.sops (e.g. it has no secrets), this script
# falls back to plain docker compose so you can use it uniformly for all services.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SOPS_CONFIG="$REPO_ROOT/.sops.yaml"

SERVICE="${1:?Usage: sops-run.sh <service> [compose args...]}"
shift   # remaining args are passed to docker compose

COMPOSE_DIR="$REPO_ROOT/apps/docker/$SERVICE"
SOPS_FILE="$COMPOSE_DIR/.env.sops"
AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

# ── Locate compose file ────────────────────────────────────────────────────────

COMPOSE_FILE=""
for candidate in compose.yaml docker-compose.yml docker-compose.yaml; do
  if [[ -f "$COMPOSE_DIR/$candidate" ]]; then
    COMPOSE_FILE="$COMPOSE_DIR/$candidate"
    break
  fi
done

if [[ -z "$COMPOSE_FILE" ]]; then
  echo "Error: no compose file found in $COMPOSE_DIR"
  echo "Looked for: compose.yaml, docker-compose.yml, docker-compose.yaml"
  exit 1
fi

# ── Dependency checks ──────────────────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
  echo "Error: docker not found"
  exit 1
fi

# ── Run with or without SOPS ───────────────────────────────────────────────────

if [[ -f "$SOPS_FILE" ]]; then
  # Verify age key is present
  if [[ ! -f "$AGE_KEY_FILE" ]]; then
    echo "Error: age key not found at $AGE_KEY_FILE"
    echo ""
    echo "This machine hasn't been set up for SOPS yet."
    echo "Run: ./scripts/age-setup.sh"
    echo ""
    echo "Then restore your private key from Vaultwarden into:"
    echo "  $AGE_KEY_FILE"
    exit 1
  fi

  if ! command -v sops &>/dev/null; then
    echo "Error: sops not installed. Run: brew install sops"
    exit 1
  fi

  echo "→ [$SERVICE] sops exec-env + docker compose $*"
  # exec-env decrypts .env.sops and injects vars directly into the child process env.
  # Docker Compose reads ${VAR} substitutions from the shell environment when no .env
  # file is present — so this works without writing anything to disk.
  exec sops exec-env \
    --config "$SOPS_CONFIG" \
    --input-type dotenv \
    "$SOPS_FILE" \
    -- docker compose -f "$COMPOSE_FILE" "$@"

else
  # No .env.sops — service either has no secrets or hasn't been migrated yet
  if [[ -f "$COMPOSE_DIR/.env" ]]; then
    echo "⚠ [$SERVICE] No .env.sops found — falling back to .env file on disk."
    echo "  Migrate with: ./scripts/sops-migrate.sh $SERVICE"
    echo ""
  fi

  echo "→ [$SERVICE] docker compose $*"
  exec docker compose -f "$COMPOSE_FILE" "$@"
fi
