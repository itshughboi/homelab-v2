# Node Install — Ventoy USB (Primary Method)

> **This is the canonical way nodes are installed.** Netboot/PXE was tried and abandoned
> — see the [post-mortem](../../1-networking/Alternative%20Methods/Netboot/README.md) for why. Ventoy boots the
> ISO as real install media, which sidesteps the entire class of failures that sank the
> PXE approach.

Two flavors — pick per situation:

| Flavor | What happens | When |
| --- | --- | --- |
| **Automated** (recommended) | Per-node ISO with the answer file baked in → boot, walk away, comes back installed | Normal node provisioning |
| **Manual** | Stock ISO → click through the Proxmox installer by hand | No tooling handy, or a one-off |

Both keep the same end state. The automated flavor keeps your per-node config in git
(`bootstrap/netbootxyz/assets/proxmox/pve-srv-X.toml`) — those TOMLs drop straight in.

> [!TIP] No provisioning VLAN, no cable move
> Because the answer files use `source = "from-answer"` with a **static** management IP,
> you plug the node straight into its **permanent trunk port** (VLAN 10) and it installs
> directly onto `10.10.10.X`. There is no VLAN 99 step and no "move the cable afterward"
> dance anymore — that was a netboot-era constraint.

---

## BIOS Prerequisites (per node)

- [ ] **USB boot: Enabled**, USB first in boot order (Network/PXE no longer needed)
- [ ] Secure Boot: **OFF**

---

## Flavor A — Automated (baked answer file)

`proxmox-auto-install-assistant` is an **amd64 Proxmox tool**. Your Mac and the Libre
Potato are ARM and can't run it — but **pve-srv-1 already has it** (ships with PVE 8.2+).
Prepare the ISOs there.

### 1. On pve-srv-1: prepare a per-node ISO

```sh
# Confirm the tool + exact flags (do this once)
proxmox-auto-install-assistant prepare-iso --help

# Download the stock ISO
wget https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso

# Validate the answer file before baking it in
proxmox-auto-install-assistant validate-answer pve-srv-4.toml

# Bake the answer file into a new ISO (--fetch-from iso = no network needed at install)
proxmox-auto-install-assistant prepare-iso \
  proxmox-ve_9.1-1.iso \
  --fetch-from iso \
  --answer-file pve-srv-4.toml \
  --output pve-srv-4-auto.iso
```

Repeat for each node (`pve-srv-2`, `pve-srv-3`, …) with its own TOML. The TOMLs live in
the repo at `bootstrap/netbootxyz/assets/proxmox/` — pull them with `git clone` so you
don't recreate them.

### 2. Copy the prepared ISO(s) onto the Ventoy USB

Drop `pve-srv-4-auto.iso` (and the others) into the Ventoy partition. One stick can hold
all of them.

### 3. Boot the node

1. Plug node into its **permanent trunk port** (USW Flex Mini, VLAN 10)
2. Boot from the Ventoy USB → pick that node's `pve-srv-X-auto.iso`
3. Select **Automated Installation** at the Proxmox boot menu (or it proceeds on its own)
4. Walk away — installs unattended, reboots onto `10.10.10.X`
5. Verify: `https://10.10.10.X:8006` and `ssh root@10.10.10.X`

---

## Flavor B — Manual (stock ISO, click through)

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
