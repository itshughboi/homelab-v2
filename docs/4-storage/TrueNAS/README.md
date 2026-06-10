# TrueNAS

Primary bulk storage. **Manual appliance — intentionally NOT in Terraform** (set-once; this doc is
the source of truth — see [index.md](../index.md) for the rationale). Runs as a Proxmox VM on
**pve-srv-1** with the storage SSDs passed through.

| | |
|---|---|
| **VM** | ID 105 on pve-srv-1 — created by hand in Proxmox (appliance, not IaC) |
| **OS / admin** | TrueNAS SCALE · admin user `truenas_admin` |
| **Pool** | **`The Archive`** — single **mirror** vdev (2× Samsung 870 EVO 4TB SSD) |
| **Mgmt / UI** | `10.10.10.5` (VLAN 10) — web UI + SSH |
| **Data** | `10.10.40.5` (VLAN 40, **MTU 9000** jumbo) — east-west NFS/SMB, no gateway |
| **Disks here** | 2× Samsung 870 EVO 4TB SSD. *(The 2× Seagate 8TB HDD go to **PBS**, not here — [../PBS](../PBS/README.md).)* |

> [!CAUTION] The pool name contains a space (`The Archive`)
> ZFS can't rename a pool, so we live with it. The space **must** be escaped as `\040` in
> `/etc/fstab` (never use quotes there) and **quoted** in other configs (k8s NFS `path:`, etc.).
> Server-side, datasets live at `/mnt/The Archive/<Dataset>`.

**Rebuild order:** provision VM → passthrough SSDs → create pool → datasets → NFS/SMB shares →
networking + jumbo → mount on clients. Do this **after** the network (VLANs 10 + 40) exists and
**before** anything that consumes storage (PBS offsite, Docker apps, k3s NFS PVs).

---

## 1. Provision the VM

Create VM **105** by hand in the Proxmox UI on pve-srv-1 (appliance — no Terraform), boot the
**TrueNAS SCALE** ISO, install to a small boot disk, set the `truenas_admin` password. Then pass
through the data SSDs ↓.

## 2. Disk passthrough — 2× Samsung 870 EVO 4TB SSD → VM 105

> Only the **Samsung SSDs** go to TrueNAS. The 2× Seagate ST8000DM004 8TB HDD are passed to
> **PBS** ([../PBS](../PBS/README.md)) — do **not** add them here.

```sh
# On the pve-srv-1 shell:
apt install -y lshw
lshw -class disk -class storage          # note the serials of the two Samsung SSDs

# Map each serial → its stable /dev/disk/by-id name:
ls -l /dev/disk/by-id/ | grep -i samsung
#   ata-Samsung_SSD_870_EVO_4TB_S6PJNJ0W401496L
#   ata-Samsung_SSD_870_EVO_4TB_S6PJNJ0W401500P

# Attach each as a passthrough disk (increment --scsiN per disk):
qm set 105 --scsi1 /dev/disk/by-id/ata-Samsung_SSD_870_EVO_4TB_S6PJNJ0W401496L
qm set 105 --scsi2 /dev/disk/by-id/ata-Samsung_SSD_870_EVO_4TB_S6PJNJ0W401500P
```

Optional (make the serial visible to TrueNAS for SMART): edit `/etc/pve/qemu-server/105.conf` and
append `,serial=<serial>` to each `scsiN:` line.

**Verify:** the two SSDs appear under TrueNAS → **Storage → Disks**.

## 3. Create the pool `The Archive` (mirror)

TrueNAS UI → **Storage → Create Pool** → name **`The Archive`** → add the two Samsung SSDs as a
**mirror** vdev → Create. ZFS concepts/maintenance: [ZFS.md](ZFS.md).

**Verify:** pool mounts at `/mnt/The Archive`; `zpool status` shows the mirror `ONLINE`.

## 4. Datasets

One dataset per app / content area under `The Archive`. Current layout:

| Dataset (`/mnt/The Archive/…`) | Kind | Consumer |
|---|---|---|
| `Epoch-1`, `Epoch-2` | personal | photo/media archive (also feeds Immich, see below) |
| `Gaming`, `ios`, `Homelab`, `Obsidian` | personal | misc personal data / notes |
| `Eros`, `Liyah` | personal/media | shares |
| `Jellyfin`, `Music`, `YT-Audios` | app/media | Jellyfin, tube-archivist |
| `ISOs` | app | ISO library (NFS-only) |
| `Restic` | app | Restic backup target |
| `swarm` | app | legacy swarm data |

Immich pulls from nested paths under the Epoch datasets, e.g. `Epoch-2/Pictures` and
`Epoch-1/Legacy/Pictures`; Paperless from `Epoch-1/Legacy/Documents/Financial`.

> [!NOTE] Planned: split personal vs app data across two mirrors (once 4× SSD)
> The pool is near capacity (~3.3 TiB used). When the second pair of SSDs is added, the plan is:
> **mirror A (personal):** `Epoch-1`, `Epoch-2`, `Gaming`, `ios`; **mirror B (app data):** the rest.
> Until then everything lives on the single `The Archive` mirror.

## 5. NFS (and SMB) shares

TrueNAS UI → **Shares → NFS → Add** for each dataset to export (most also have an SMB share;
`ISOs` and `Obsidian` are NFS-only).

> [!IMPORTANT] `mapall` — required on some datasets
> Set **Mapall User: `root`** (share → Advanced) on datasets where the consumer writes as root or
> needs UID mapping — **without it some shares won't mount/load correctly**. Apply it to the
> datasets that need it (the app/write datasets); read-only media shares generally don't.

NFS listens on all interfaces, so clients reach exports on **`10.10.40.5`** (jumbo — preferred) or
`10.10.10.5` (mgmt).

**Verify:** `showmount -e 10.10.40.5` lists the exports.

## 6. Networking — two NICs + jumbo frames

Two bridges (bridge/cabling steps: [Networking.md](Networking.md)):

- **`br0` mgmt** → `10.10.10.5` (VLAN 10) — UI/SSH.
- **storage NIC** → `10.10.40.5` (VLAN 40, **MTU 9000**, **no gateway**) — east-west NFS/SMB.

**MTU 9000 must match end-to-end** or you get silent NFS stalls: the TrueNAS storage NIC, the
Proxmox bridge `vmbr1.40` (and parent `vmbr1`), the **UniFi VLAN-40 switch ports**, *and* each
client's VLAN-40 NIC.

**Verify (no fragmentation):** `ping -M do -s 8972 10.10.40.5` from a VLAN-40 client.

## 7. Mounting on clients

Convention: mount the **parent** `/mnt/The Archive` → **`/mnt/truenas`** on the client (drops the
space client-side); the final path segment is the per-app dataset. So server
`/mnt/The Archive/Jellyfin` → client `/mnt/truenas/jellyfin`.

`/etc/fstab` — escape the space as `\040`, **no quotes**:
```fstab
# <server>:<server export path>            <client mount>          <type> <options>             0 0
10.10.40.5:/mnt/The\040Archive/Jellyfin    /mnt/truenas/jellyfin   nfs    vers=3,defaults        0 0
10.10.40.5:/mnt/The\040Archive/Restic      /mnt/truenas/restic     nfs    defaults               0 0
10.10.40.5:/mnt/The\040Archive/Eros        /mnt/truenas/eros       nfs    defaults,soft,intr,bg  0 0
```

> [!IMPORTANT] Which IP — `.40.5` (jumbo) vs `.10.5` (mgmt)
> Use **`10.10.40.5`** only from clients that are **on VLAN 40**. VLAN 40 has **no gateway**
> (east-west only), so a VLAN-10-only host can't reach it. The **k3s** worker/longhorn nodes are
> dual-homed (30+40) so they use `.40.5` directly; **dock-prod** is now dual-homed too
> (`10.10.40.10`, see `terraform/proxmox/dock-prod.tf`) — after `terraform apply` gives it the
> `eth1` NIC, switch its fstab from `10.10.10.5` → `10.10.40.5`. Anything still on VLAN 10 only
> must keep using `10.10.10.5`.

**Verify:** `sudo mount -a && df -h | grep truenas`; a large sequential read should run at link rate.

---

## Related
- [Networking.md](Networking.md) — bridge + VLAN/MTU setup on the TrueNAS VM
- [ZFS.md](ZFS.md) — pool/vdev concepts, scrub & snapshot maintenance
- [../PBS/README.md](../PBS/README.md) — Proxmox Backup Server (the Seagate HDDs) + offsite sync
- [Network inventory](../../1-networking/Unifi/Assignments/MAC%20Reservations.md) — authoritative IPs (`.5`/`.40.5`)
