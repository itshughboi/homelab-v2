#!/usr/bin/env bash
# Render the Jinja2 Packer template and run a build.
#
# Usage:
#   ./build.sh                        # uses proxmox.pkrvars.sh for values
#   ./build.sh --dry-run              # render template only, don't run packer
#   PROXMOX_NODE=pve-srv-2 ./build.sh # override the target Proxmox node

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/proxmox-iso-ubuntu.pkr.hcl.j2"
RENDERED="$SCRIPT_DIR/proxmox-iso-ubuntu.pkr.hcl"
VARS_FILE="$SCRIPT_DIR/proxmox.pkrvars.sh"
DRY_RUN=false

# ── Args ───────────────────────────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ── Load vars ─────────────────────────────────────────────────────────────────

if [[ ! -f "$VARS_FILE" ]]; then
  echo "Error: $VARS_FILE not found."
  echo ""
  echo "Copy the example and fill in your values:"
  echo "  cp $SCRIPT_DIR/proxmox.pkrvars.sh.example $VARS_FILE"
  echo "  \$EDITOR $VARS_FILE"
  exit 1
fi

# shellcheck source=/dev/null
source "$VARS_FILE"

# ── Dependency checks ─────────────────────────────────────────────────────────

check_dep() {
  if ! command -v "$1" &>/dev/null; then
    echo "Error: '$1' not found. Install with: $2"
    exit 1
  fi
}

check_dep packer   "https://developer.hashicorp.com/packer/install"
check_dep python3  "brew install python3  OR  apt install python3"

python3 -c "import jinja2" 2>/dev/null || {
  echo "Error: Python jinja2 not installed."
  echo "Install with: pip3 install jinja2 PyYAML"
  exit 1
}

# ── Render template ───────────────────────────────────────────────────────────

echo "→ Rendering Packer template..."

python3 - <<PYEOF
import jinja2, os, sys

template_path = "$TEMPLATE"
output_path   = "$RENDERED"

# Values from sourced vars file (passed via environment)
context = {
    "image_name":        os.environ.get("IMAGE_NAME",        "ubuntu-server-noble"),
    "vm_id":             os.environ.get("VM_ID",             "9999"),
    "vm_description":    os.environ.get("VM_DESCRIPTION",    "Ubuntu Server Noble (24.04) — k3s base image"),
    "proxmox_node":      os.environ.get("PROXMOX_NODE",      "pve-srv-1"),
    "disk_storage":      os.environ.get("DISK_STORAGE",      "local-lvm"),
    "disk_size":         os.environ.get("DISK_SIZE",         "25G"),
    "cpu_cores":         os.environ.get("CPU_CORES",         "2"),
    "memory_mb":         os.environ.get("MEMORY_MB",         "2048"),
    "network_bridge":    os.environ.get("NETWORK_BRIDGE",    "vmbr0"),
    "cloudinit_storage": os.environ.get("CLOUDINIT_STORAGE", "local-lvm"),
    "iso_source":        os.environ.get("ISO_SOURCE",        "local"),
    "iso_file":          os.environ.get("ISO_FILE",          "local:iso/ubuntu-24.04-live-server-amd64.iso"),
    "iso_url":           os.environ.get("ISO_URL",           ""),
    "iso_storage":       os.environ.get("ISO_STORAGE",       "local"),
    "iso_checksum":      os.environ.get("ISO_CHECKSUM",      ""),
    "skip_tls_verify":   os.environ.get("SKIP_TLS_VERIFY",  "true").lower() in ("true", "1", "yes"),
    "ssh_username":      os.environ.get("SSH_USERNAME",      "hughboi"),
    "ssh_auth_method":   os.environ.get("SSH_AUTH_METHOD",   "password"),
    "ssh_password":      os.environ.get("SSH_PASSWORD",      ""),
    "ssh_private_key_file": os.environ.get("SSH_PRIVATE_KEY_FILE", "~/.ssh/id_ed25519"),
    "ssh_public_key":    os.environ.get("SSH_PUBLIC_KEY",    ""),
    "ssh_timeout":       os.environ.get("SSH_TIMEOUT",       "30m"),
    "boot_wait":         os.environ.get("BOOT_WAIT",         "5s"),
    "http_bind_address": os.environ.get("HTTP_BIND_ADDRESS", "0.0.0.0"),
    "http_port_min":     int(os.environ.get("HTTP_PORT_MIN", "8802")),
    "http_port_max":     int(os.environ.get("HTTP_PORT_MAX", "8802")),
    "locale":            os.environ.get("LOCALE",            "en_US"),
    "keyboard_layout":   os.environ.get("KEYBOARD_LAYOUT",  "us"),
    "timezone":          os.environ.get("TIMEZONE",          "America/Denver"),
}

with open(template_path) as f:
    template = jinja2.Template(f.read())

rendered = template.render(**context)

with open(output_path, "w") as f:
    f.write(rendered)

print(f"  Written: {output_path}")
PYEOF

echo "✓ Template rendered."
echo ""

if $DRY_RUN; then
  echo "Dry run — not running packer. Rendered file: $RENDERED"
  exit 0
fi

# ── Run Packer ────────────────────────────────────────────────────────────────

echo "→ Initialising Packer plugins..."
packer init "$RENDERED"

echo ""
echo "→ Building template (VM ID: ${VM_ID:-9000} on ${PROXMOX_NODE:-pve-srv-1})..."
echo "   This takes ~10-15 minutes."
echo ""

packer build \
  -var "proxmox_api_url=${PROXMOX_API_URL}" \
  -var "proxmox_api_token_id=${PROXMOX_API_TOKEN_ID}" \
  -var "proxmox_api_token_secret=${PROXMOX_API_TOKEN_SECRET}" \
  "$RENDERED"

echo ""
echo "✓ Template build complete."
echo "  Template VM ID: ${VM_ID:-9000}"
echo "  Node: ${PROXMOX_NODE:-pve-srv-1}"
echo ""
echo "Next step: Terraform clone this template:"
echo "  cd ../../terraform/proxmox"
echo "  terraform apply"
