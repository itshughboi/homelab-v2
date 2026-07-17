#!/usr/bin/env bash
# Show which Docker services have a .env.example but no .env.sops yet.
# Run this to see your migration progress at a glance.
#
# Usage: ./scripts/sops-check.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_ROOT="$REPO_ROOT/apps/docker"

MIGRATED=()
NOT_MIGRATED=()
SOPS_ONLY=()   # has .env.sops but no .env.example (fine, just noting it)

# Walk all .env.example files (including nested like immich/home)
while IFS= read -r example_file; do
  service_dir=$(dirname "$example_file")
  service_name="${service_dir#$DOCKER_ROOT/}"
  sops_file="$service_dir/.env.sops"

  if [[ -f "$sops_file" ]]; then
    # Also check key coverage
    EXAMPLE_KEYS=$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$example_file" | cut -d= -f1 | sort)
    SOPS_KEYS=$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*' "$sops_file" 2>/dev/null | sort || true)
    MISSING=$(comm -23 <(echo "$EXAMPLE_KEYS") <(echo "$SOPS_KEYS") 2>/dev/null | tr '\n' ',' | sed 's/,$//' || true)

    if [[ -n "$MISSING" ]]; then
      MIGRATED+=("⚠  $service_name  (missing keys: $MISSING)")
    else
      MIGRATED+=("✓  $service_name")
    fi
  else
    NOT_MIGRATED+=("✗  $service_name")
  fi
done < <(find "$DOCKER_ROOT" -name ".env.example" | sort)

# Check for .env.sops with no corresponding .env.example
while IFS= read -r sops_file; do
  service_dir=$(dirname "$sops_file")
  service_name="${service_dir#$DOCKER_ROOT/}"
  if [[ ! -f "$service_dir/.env.example" ]]; then
    SOPS_ONLY+=("·  $service_name  (no .env.example to compare against)")
  fi
done < <(find "$DOCKER_ROOT" -name ".env.sops" | sort)

# Config-as-secret services (e.g. mailrise) commit <filename>.<ext>.sops
# instead of .env.sops, and are invisible to the .env.example scan above —
# surface them separately so they don't look unmigrated.
while IFS= read -r sops_file; do
  service_dir=$(dirname "$sops_file")
  service_name="${service_dir#$DOCKER_ROOT/}"
  SOPS_ONLY+=("·  $service_name  ($(basename "$sops_file") — config-as-secret, not .env-based)")
done < <(find "$DOCKER_ROOT" -name "*.sops" ! -name ".env.sops" | sort)

# ── Output ─────────────────────────────────────────────────────────────────────

TOTAL=$(( ${#MIGRATED[@]} + ${#NOT_MIGRATED[@]} ))
DONE=${#MIGRATED[@]}

echo "SOPS Migration Status  ($DONE / $TOTAL migrated)"
echo "═══════════════════════════════════════════════"
echo ""

if [[ ${#MIGRATED[@]} -gt 0 ]]; then
  echo "Encrypted (.env.sops exists):"
  for s in "${MIGRATED[@]}"; do echo "  $s"; done
  echo ""
fi

if [[ ${#NOT_MIGRATED[@]} -gt 0 ]]; then
  echo "Not yet migrated (.env.sops missing):"
  for s in "${NOT_MIGRATED[@]}"; do echo "  $s"; done
  echo ""
  echo "  To migrate:  ./scripts/sops-migrate.sh <service>"
  echo "  To migrate all at once (reads from live .env files on this host):"
  printf "    for svc in"
  for s in "${NOT_MIGRATED[@]}"; do
    name=$(echo "$s" | awk '{print $2}')
    printf " %s" "$name"
  done
  echo "; do ./scripts/sops-migrate.sh \"\$svc\"; done"
  echo ""
fi

if [[ ${#SOPS_ONLY[@]} -gt 0 ]]; then
  echo "Has .env.sops (no .env.example to compare):"
  for s in "${SOPS_ONLY[@]}"; do echo "  $s"; done
  echo ""
fi

if [[ ${#NOT_MIGRATED[@]} -eq 0 ]]; then
  echo "All services with .env.example have been migrated to SOPS. ✓"
  echo ""
  echo "Remember: the old .env files on disk still exist — they're just"
  echo "no longer needed for deployments. You can delete them if you want:"
  echo "  find apps/docker -name '.env' -not -name '*.example' -not -name '*.sops' -delete"
fi
