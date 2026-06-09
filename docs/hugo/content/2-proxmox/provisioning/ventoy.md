---
title: "Node Install — Ventoy USB (Primary Method)"
---

# Node Install — Ventoy USB (Primary Method)

> **This is the canonical way nodes are installed.** Netboot/PXE was tried and abandoned
> — see the [post-mortem](../../1-networking/Alternative%20Methods/Netboot/README.md) for why. Ventoy boots the
> ISO as real install media, which sidesteps the entire class of failures that sank the
> PXE approach.

All three modes USB-boot the Proxmox installer; they differ only in how the *answer file*
reaches it. Per-node config lives in git as `bootstrap/netbootxyz/assets/proxmox/pve-srv-X.toml`.

| Rung | How the answer is delivered | Touch per install | Infra | Best for |
| --- | --- | --- | --- | --- |
| **B — Answer server** ✅ *(in use)* | One generic ISO; installer fetches its answer by MAC over HTTP | Boot, pick the one ISO | A small service (during installs) | Frequent reimaging / testing — edit a TOML in git, no ISO rebuild. [Runbook](../../../bootstrap/proxmox-answer-server/README.md) |
| **A — Per-node baked ISO** | Answer baked into a per-node ISO | Boot, pick the node's ISO | None | Few static nodes; zero infra. [Runbook](../../../bootstrap/ventoy/README.md) |
| **Manual** | None — type it in | Click through the installer | None | No tooling handy, or a one-off (below) |

B and A end in the same place; B just avoids rebuilding ISOs when a node's config changes.

> [!TIP] No provisioning VLAN, no cable move
> The answer files use `source = "from-answer"` with a **static** management IP, so you plug the
> node straight into its **permanent trunk port** (VLAN 10) and it installs directly onto
> `10.10.10.X`. No VLAN 99 step, no cable move — those were netboot-era constraints. (Rung B's
> installer DHCPs a temp IP on VLAN 10 just long enough to fetch its answer, then applies the
> static IP.)

---

## BIOS Prerequisites (per node)

- [ ] **USB boot: Enabled**, USB first in boot order (Network/PXE no longer needed)
- [ ] Secure Boot: **OFF**

---

## Rung B — Answer server (current)

One generic ISO for every node; the installer POSTs its MACs to an HTTP service that returns
the matching `pve-srv-X.toml` straight from git. Change a node = edit its TOML, no ISO rebuild.

Full setup (build the one ISO, run the service, verify the payload schema, test, security,
first-boot hook): **[bootstrap/proxmox-answer-server/README.md](../../../bootstrap/proxmox-answer-server/README.md)**.

## Rung A — Per-node baked ISO (no infra)

`make-isos.sh` loops your TOMLs through `proxmox-auto-install-assistant prepare-iso
--fetch-from iso`, producing one `pve-srv-X-auto.iso` per node to drop on the Ventoy USB. Boot,
pick the node's ISO, walk away. Rebuild a node's ISO when its TOML changes.

Full setup + the `ventoy.json` auto-boot option:
**[bootstrap/ventoy/README.md](../../../bootstrap/ventoy/README.md)**.

> Both rungs use `proxmox-auto-install-assistant`, which is **amd64-only** — run it on
> **pve-srv-1** (ships with PVE 8.2+), not your ARM Mac/Libre Potato.

---

## Manual (stock ISO, click through)

No prep tooling needed. Use when you just want a node up.

1. Download the stock Proxmox VE ISO and drop it on the Ventoy USB
2. Boot node from Ventoy → pick the ISO → **Install Proxmox VE** (graphical)
3. Click through: disk, country/keyboard, password, and **set the management IP/hostname
   by hand** (`10.10.10.X/24`, gw `10.10.10.254`, dns `10.10.10.8`, hostname `pve-srv-X`)
4. Reboot → `https://10.10.10.X:8006`

---

## After Install (either flavor)

Everything past the install is already automated and lives in git:

- **Network bridges/VLANs** — `ansible/playbooks/proxmox/network-setup/`
- **Repos + updates** — `ansible/playbooks/proxmox/cluster-update/`
- **Cluster join** — see [README.md](README.md#proxmox-cluster)

The installer's only job is "bootable Proxmox on the disk with the right IP." Ansible/
Semaphore does the rest — which is where the real GitOps automation already works.
