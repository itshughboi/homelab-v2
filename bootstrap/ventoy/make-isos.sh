#!/usr/bin/env bash
# Build per-node Proxmox auto-install ISOs (Ventoy "rung A" — answer baked into the ISO).
#
# Run on a Proxmox host (amd64) — proxmox-auto-install-assistant is amd64-only.
# Produces one pve-srv-X-auto.iso per TOML; copy them onto the Ventoy USB.
#
# Usage: make-isos.sh <proxmox-ve.iso> [answers-dir] [out-dir]
set -euo pipefail

ISO="${1:?usage: make-isos.sh <proxmox-ve.iso> [answers-dir] [out-dir]}"
ANSWERS="${2:-$(dirname "${BASH_SOURCE[0]}")/answers}"
OUT="${3:-./out}"

command -v proxmox-auto-install-assistant >/dev/null || {
  echo "proxmox-auto-install-assistant not found — run this on a Proxmox node." >&2
  exit 1
}

mkdir -p "$OUT"
shopt -s nullglob
for toml in "$ANSWERS"/pve-srv-*.toml; do
  node="$(basename "$toml" .toml)"
  echo ">> $node"
  proxmox-auto-install-assistant validate-answer "$toml"
  proxmox-auto-install-assistant prepare-iso "$ISO" \
    --fetch-from iso \
    --answer-file "$toml" \
    --output "$OUT/${node}-auto.iso"
done
echo "Done. Copy $OUT/*.iso onto the Ventoy USB."
