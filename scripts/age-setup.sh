#!/usr/bin/env bash
# One-time setup: generate an age keypair and wire it into .sops.yaml.
# Run this once on each machine that needs to encrypt or decrypt secrets.
#
# Usage: ./scripts/age-setup.sh
#
# What it does:
#   1. Generates an age keypair at ~/.config/sops/age/keys.txt (if not already present)
#   2. Replaces the AGE_PUBLIC_KEY_PLACEHOLDER in .sops.yaml with your public key
#   3. Reminds you to back up the private key to Vaultwarden

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SOPS_CONFIG="$REPO_ROOT/.sops.yaml"
AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

# ── Dependency checks ──────────────────────────────────────────────────────────

check_dep() {
  if ! command -v "$1" &>/dev/null; then
    echo "Error: '$1' not found."
    echo "Install with:"
    echo "  macOS:  brew install $2"
    echo "  Ubuntu: $3"
    echo ""
    exit 1
  fi
}

check_dep age-keygen age "download the static binary from https://github.com/FiloSottile/age/releases — NOT 'apt install age': apt's build is dynamically linked against glibc and silently fails to exec inside musl-based containers (e.g. Semaphore's own Alpine image)"
check_dep sops sops "snap install sops  OR  download from https://github.com/getsops/sops/releases"

# ── Key generation ─────────────────────────────────────────────────────────────

if [[ -f "$AGE_KEY_FILE" ]]; then
  echo "Age key already exists at: $AGE_KEY_FILE"
  PUBLIC_KEY=$(grep "# public key:" "$AGE_KEY_FILE" | awk '{print $NF}')
  echo "Public key: $PUBLIC_KEY"
  echo ""
else
  echo "→ Generating new age keypair..."
  mkdir -p "$(dirname "$AGE_KEY_FILE")"
  age-keygen -o "$AGE_KEY_FILE" 2>/dev/null
  chmod 600 "$AGE_KEY_FILE"
  PUBLIC_KEY=$(grep "# public key:" "$AGE_KEY_FILE" | awk '{print $NF}')
  echo "✓ Keypair generated at: $AGE_KEY_FILE"
  echo "  Public key:  $PUBLIC_KEY"
  echo ""
fi

# ── Wire into .sops.yaml ───────────────────────────────────────────────────────

if grep -q "AGE_PUBLIC_KEY_PLACEHOLDER" "$SOPS_CONFIG"; then
  echo "→ Patching .sops.yaml with your public key..."
  # Use temp file for portability (sed -i differs between macOS and Linux)
  sed "s|AGE_PUBLIC_KEY_PLACEHOLDER|$PUBLIC_KEY|g" "$SOPS_CONFIG" > "$SOPS_CONFIG.tmp"
  mv "$SOPS_CONFIG.tmp" "$SOPS_CONFIG"
  echo "✓ .sops.yaml updated"
  echo ""
  echo "  Commit .sops.yaml — the public key is safe to store in Git:"
  echo "    git add .sops.yaml"
  echo "    git commit -m 'chore: configure sops age public key'"
  echo ""
else
  CURRENT_KEY=$(grep "age:" "$SOPS_CONFIG" | awk '{print $2}')
  if [[ "$CURRENT_KEY" == "$PUBLIC_KEY" ]]; then
    echo "✓ .sops.yaml already configured with your key — nothing to change."
  else
    echo "⚠ .sops.yaml has a different age key than the one on this machine."
    echo "  In .sops.yaml: $CURRENT_KEY"
    echo "  This machine:  $PUBLIC_KEY"
    echo ""
    echo "  This is expected if multiple machines share the repo."
    echo "  To allow this machine to decrypt, add your key to .sops.yaml:"
    echo "    age: <existing-key>,<this-machine-key>"
    echo ""
  fi
fi

# ── Backup reminder ────────────────────────────────────────────────────────────

echo "════════════════════════════════════════════════════════════════"
echo "  IMPORTANT: Back up your private key to Vaultwarden NOW"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  If you lose this key, every .env.sops file becomes permanently"
echo "  unreadable. There is no recovery path."
echo ""
echo "  Private key file: $AGE_KEY_FILE"
echo ""
echo "  Copy the contents to a Vaultwarden secure note:"
echo "    cat $AGE_KEY_FILE"
echo ""
echo "  Store it under something like:"
echo "    'homelab / sops-age-private-key / docker-host'"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Next step: migrate your first service:"
echo "  ./scripts/sops-migrate.sh vaultwarden"
echo ""
echo "Or check what's left to migrate:"
echo "  ./scripts/sops-check.sh"
echo ""
echo "If this is Athena: Semaphore's container also needs a copy of this key at"
echo "/etc/sops/age/keys.txt (a separate, world-traversable path — \$HOME is chmod"
echo "750, which blocks the container's UID from reaching ~/.config at all). See"
echo "'Deploying from Semaphore' in docs/8-gitops/sops-secrets.md for the full copy"
echo "command — the two copies are NOT kept in sync automatically."
