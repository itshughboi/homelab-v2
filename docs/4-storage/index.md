# 4. Storage

TrueNAS for primary NAS + NFS, Proxmox Backup Server (PBS) for VM backups. Both run on
pve-srv-1 — TrueNAS as a VM with disk passthrough, **PBS as a VM that owns its own disks**.

> ▸ **Build order:** [BUILD.md](../BUILD.md) **Phase 2 (Storage)** — after the Proxmox cluster, *before* Athena. (Folder number ≠ build order.)

| Doc | Contents |
| --- | --- |
| [TrueNAS/README.md](TrueNAS/README.md) | TrueNAS setup, disk passthrough, NFS exports |
| [TrueNAS/ZFS.md](TrueNAS/ZFS.md) | ZFS concepts, VDEV types, pool layout, maintenance |
| [TrueNAS/Networking.md](TrueNAS/Networking.md) | Bridge interface (`br0`) — the swap-friendly NIC setup |
| [PBS/README.md](PBS/README.md) | PBS VM: passthrough → local ZFS datastore → offsite to Synology |

---

## Architecture

```
pve-srv-1 (physical)
    │
    ├── TrueNAS VM (disk passthrough — direct disk access)
    │       ZFS pool on 2× Samsung 870 EVO 4TB SSD
    │       NFS exports → VMs, Docker services, k3s PVs
    │
    └── PBS VM (ID 106, Ubuntu)
            2× 8TB HDD passed through → LOCAL ZFS datastore (PBS owns its disks)
            Backup target for all VMs
            Replicates offsite → Synology (Tailscale)
```

> [!IMPORTANT] PBS is a VM, not an LXC, and does not use TrueNAS NFS
> PBS owns its disks directly (passthrough → local ZFS) for integrity. Offsite resilience comes
> from replicating finished backups to the Synology — not from a network datastore. Full
> runbook: [PBS/README.md](PBS/README.md).

---

## TrueNAS

### Why disk passthrough?

If Proxmox manages the disks, TrueNAS can't see raw SMART data or run its own end-to-end ZFS
checksums — you lose the integrity guarantees. Passing the disks (or HBA) straight through gives
TrueNAS bare-metal access, exactly as if it were on physical hardware. Setup +
device IDs: [TrueNAS/README.md](TrueNAS/README.md).

### Networking

Always assign IPs to a **bridge (`br0`)**, never the raw NIC — so you can swap the underlying
interface later without reconfiguring every share. Steps: [TrueNAS/Networking.md](TrueNAS/Networking.md).

### Current pool

| Pool | Disks | VDEV | Purpose |
| --- | --- | --- | --- |
| (TrueNAS) | 2× Samsung 870 EVO 4TB SSD | mirror | VM/app data, NFS exports |

ZFS concepts, VDEV trade-offs (mirror vs RAIDZ), and maintenance: [TrueNAS/ZFS.md](TrueNAS/ZFS.md).
The 2× 8TB HDDs are **not** TrueNAS — they're passed through to PBS (see PBS doc).

### NFS datasets & exports

| Dataset | Used by | Permissions |
| --- | --- | --- |
| `YT-Audios` | Tube Archivist | mapall user: root |
| `Restic` | Restic backup | owner: `hughboi:hughboi` |
| `k3s-backups` | k3s etcd backup playbook | owner: `hughboi:hughboi` |
| `docker-volume-backups` | Docker volume backup playbook | — |

### Storage VLAN (VLAN 40)

> [!DANGER]
> MTU 9000 must match **end-to-end**: UniFi switch ports, Proxmox bridges, the TrueNAS bridge,
> and any VM on VLAN 40. One device at default 1500 = silent packet loss (NFS hangs, slow
> transfers). Test: `ping -M do -s 8972 10.10.40.X` (must not fragment).

---

## Proxmox Backup Server (PBS)

VM 106 with passed-through disks and a **local ZFS** datastore; backups replicate **offsite to
the Synology**. Full setup (passthrough, ZFS datastore, user, schedule, jobs, Synology, homepage):
**[PBS/README.md](PBS/README.md)**.

### Why PBS over plain NFS backups?

PBS uses a deduplicating chunk store — 10 VMs sharing one Ubuntu base image store that base once.
Smaller backups, faster incrementals, automatic retention.

### Backup schedule

Proxmox `Datacenter → Backup`: all VMs daily, **snapshot** mode (no downtime).
**Retention is set on PBS, not in Proxmox VE.**

### Testing restores (monthly)

> A backup you've never restored from is not a backup — it's a hope.

Restore a non-critical VM to a temporary VM ID, confirm it boots, delete it.

---

## Backup Strategy (3-2-1)

| Copy | Location | Tool |
| --- | --- | --- |
| 1st | Longhorn replicas (3× across k3s workers) | Longhorn auto-replication |
| 2nd | PBS **local ZFS** datastore (2× 8TB HDD on pve-srv-1) | PBS + Proxmox schedule |
| 3rd | Offsite — **Synology** via Tailscale | PBS sync job |
