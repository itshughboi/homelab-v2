# 1. Prep

Everything before the first node powers on: hardware inventory, prerequisites, SSH keys, and the PXE netboot setup that automates bare-metal Proxmox installation.

---

## Hardware Inventory

| Node | CPU | RAM | Role |
| --- | --- | --- | --- |
| pve-srv-1 | Ryzen 5 5600x | 96 GB | Primary node, PBS, future NAS host |
| pve-srv-2 | Ryzen 7 5800U | 32 GB | k3s master-1 + worker-1 |
| pve-srv-3 | — | — | k3s master-2 + worker-2 |
| pve-srv-4 | — | — | k3s master-3 + worker-3 |
| Libre Potato | ARM | — | Permanent PXE netboot server — lives on VLAN 99 |

→ Full per-node NIC layout and bridge configs: [`Inventory/`](Inventory/)

### Planned NAS Build (pve-srv-1 upgrade)

- Case: Jonsbo N6
- CPU: i5-13500
- RAM: 96–128 GB DDR4
- SATA Controller: Broadcom/LSI 9400-8i (8× SATA)
- **4× 4TB Samsung 870 QVO SSD** → 2+2 mirror VDEVs (fast pool)
- **4× 8TB WD Red Plus HDD** → 2+2 mirror VDEVs (bulk pool)

---

## Prerequisites Checklist

### Credentials (gather before touching hardware)

| Credential | Where to get it | Used by |
| --- | --- | --- |
| Cloudflare API Token | Cloudflare → My Profile → API Tokens → Zone:DNS:Edit | cert-manager, Traefik TLS |
| Cloudflare Zone ID | Cloudflare → domain overview | cert-manager |
| Discord webhook URL | Channel → Edit → Integrations → Webhooks | Alertmanager, Semaphore, n8n |
| SSH public key | `cat ~/.ssh/id_ed25519.pub` | Packer, Terraform, Ansible |
| IGDB Client ID + Secret | dev.twitch.tv → create app | RomM |
| SteamGridDB API key | steamgriddb.com → preferences → API | RomM |
| RetroAchievements API key | retroachievements.org → settings | RomM |

### Tooling on Your Laptop

```sh
brew install terraform ansible packer git age sops helm
brew install --cask docker
```

### SSH Key — Dedicated Datacenter Keypair

Create a separate keypair for the homelab. This gets injected into every node at build time — don't reuse your personal key.

```sh
ssh-keygen -t ed25519 -C "homelab-datacenter" -f ~/.ssh/homelab_id_ed25519
```

Store the private key locally for now, in Vaultwarden once it's running.

### Clone the Repo

```sh
git clone https://gitea.hughboi.cc/hughboi/homelab.git
cd homelab
```

---

## Architecture Overview

```
Physical hardware (4× Proxmox nodes)
         │
         ▼
PXE network boot (Libre Potato, VLAN 99)
  → Automated Proxmox install via per-node TOML answer file
         │
         ▼
Proxmox 4-node cluster
  → Terraform provisions all VMs from Template 9999
         │
         ├── Athena (10.10.10.8) — Management plane
         │     Docker: Traefik, Gitea, Semaphore, Bind9
         │     Semaphore runs all Ansible from here (laptop retires)
         │
         ├── dock-prod (10.10.10.10) — Production Docker host
         │     Vaultwarden, AdGuard, Jellyfin, n8n, etc.
         │
         └── k3s cluster (9 nodes, VLAN 30)
               ArgoCD watches Gitea → applies everything declaratively
               Longhorn distributed storage across workers
               Traefik + cert-manager for TLS ingress
```

### Guiding Principles

**Everything is code.** Network config, VM provisioning, k8s manifests, DNS records — all live in Git. Rebuilding from bare metal is a known, repeatable process.

**Separation of planes.** Management never mixes with storage or workload traffic. VLANs enforce this at the switch, not just the firewall.

**GitOps over manual.** Push to Git → automation applies it. No SSH-and-edit habits that create undocumented state.

**Secrets never touch Git unencrypted.** SOPS + Age is the rule. Once a plaintext secret hits Git history, rotation is mandatory regardless of deletion.

**Blast radius by design.** A compromised workload container cannot pivot to management or storage — the VLAN firewall rules make it structurally impossible.

---

## PXE Netboot

The Libre Potato (10.10.99.99) serves automated Proxmox installs to all nodes via iPXE over VLAN 99. It pulls updates from Gitea every 5 minutes via a systemd timer.

### Boot Chain

```
Node powers on
    → DHCP (VLAN 99) returns Option 66: 10.10.99.99, Option 67: ipxe.efi
    → Libre Potato serves ipxe.efi over HTTP port 8080
    → iPXE loads, runs autoexec.ipxe → local.ipxe
    → local.ipxe reads node MAC → maps to hostname
    → node pulls its TOML: http://10.10.99.99:8080/proxmox/pve-srv-X.toml
    → Proxmox installs automatically, node receives permanent IP (VLAN 10)
    → Move cable from provisioning port to permanent trunk port
```

### Why netboot.xyz over USB

| Method | Pros | Cons |
| --- | --- | --- |
| netboot.xyz ✅ | No USB juggling, config in Git, fast | Infra must stay healthy |
| Ventoy USB | Works without network | Manual, slow at scale |
| BMC/IPMI | Enterprise break-glass | Requires enterprise hardware |

### BIOS Prerequisites (every node)

- [ ] PXE boot: **Enabled** (may need to enable "Network Stack" first before this option appears)
- [ ] Boot order: **Network/PXE first**, then NVMe
- [ ] Secure Boot: **OFF**

### Register a Node Before Booting

Three files must be committed and pushed before powering a node on:

**1. Per-node TOML** at `bootstrap/netbootxyz/config/proxmox/pve-srv-X.toml`:

```toml
[global]
keyboard = "us"
timezone = "America/Denver"
# Generate hashed password: printf "yourpassword" | openssl passwd -6 -stdin
root_password = "$6$..."
reboot_on_error = false   # shows errors instead of rebooting in a loop — use this

[network]
source = "from-dhcp"
hostname = "pve-srv-1"   # must match MAC mapping in local.ipxe exactly

[disk]
selection = ["nvme0n1", "sda"]   # tries each in order, installs to first found
filesystem = "zfs"
zfs.raid = "single"              # change to "mirror" if you have 2 disks
```

> [!NOTE]
> `reboot_on_error = false` is critical during initial setup. The installer pauses and shows the error instead of rebooting in a loop, which makes it actually debuggable.

**2. MAC → hostname mapping** in `bootstrap/netbootxyz/config/local.ipxe`:

```
:mac-aabbccddeeff
  set hostname pve-srv-1
  chain http://10.10.99.99:8080/proxmox/pve-srv-1.toml
```

**3. MAC reservation** in UniFi (VLAN 10) so the node gets its permanent IP after install.

Push to Gitea → Libre Potato picks up changes within 5 minutes.

### Verify Netboot is Serving

Always run this before powering on a node:

```sh
curl -I http://10.10.99.99:8080/ipxe.efi
curl -I http://10.10.99.99:8080/proxmox/pve-srv-1.toml
```

- `200 OK` → good
- `404 Not Found` → file missing from `assets/proxmox/` or path mismatch in `local.ipxe`
- `Connection refused` → container not running — check Docker on Libre Potato

### Boot Procedure

1. Plug node into UXG Max Port 3 (VLAN 99 access port)
2. Power on — watch it PXE boot, pull TOML, install Proxmox (fully automated)
3. Wait for Proxmox login prompt at `https://10.10.10.X:8006`
4. Verify SSH: `ssh root@10.10.10.X`
5. Move cable to permanent trunk port on USW Flex Mini

### Auto-Refresh Timer (Libre Potato)

The git pull timer keeps the Libre Potato current without any SSH access:

```sh
# /etc/systemd/system/netboot-update.service
[Unit]
Description=Update netboot from Git
[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-netboot.sh

# /etc/systemd/system/netboot-update.timer
[Unit]
Description=Check for netboot updates every 5 min
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
```

```bash
# /usr/local/bin/update-netboot.sh
#!/bin/bash
set -e
sudo -u hughboi git fetch origin main
if sudo -u hughboi git diff --quiet HEAD origin/main -- bootstrap/netbootxyz; then
    echo "No changes in bootstrap/netbootxyz — skipping"
else
    sudo -u hughboi git pull origin main
    cd /opt/iac/bootstrap/netbootxyz
    docker compose up -d
fi
```

Enable: `systemctl enable --now netboot-update.timer`

---

## Ventoy USB Fallback {#ventoy-fallback}

Use when Libre Potato is unavailable or you're rebuilding from zero:

1. Format USB with Ventoy
2. Rename main partition to `PROXMOX_AIC` — **required** for the installer to find the answer file
3. Copy Proxmox VE ISO to USB
4. Place `pve-srv-X.toml` renamed to `answer.toml` adjacent to the ISO
5. Boot from USB → select **Automated Installation** from the Proxmox boot menu

---

## Adding a New Node Later

Under 5 minutes of manual work:

1. Copy existing TOML, update: `hostname`, disk selection
2. Add MAC → hostname entry to `local.ipxe`
3. Add MAC reservation in UniFi (VLAN 10)
4. Push to Gitea — Libre Potato picks up within 5 minutes
5. Plug into UXG Max Port 3, power on
6. After install: move cable to trunk port
7. From Semaphore: run `proxmox/join-cluster` playbook
8. Verify: `pvecm status` shows new node with full votes
