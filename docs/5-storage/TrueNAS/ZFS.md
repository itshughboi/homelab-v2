# ZFS

Reference: https://www.youtube.com/watch?v=Xt436NAjpZA

---

## Core Concepts

ZFS isn't just a filesystem — it controls the drives as well.

Two storage types:
- **Dataset** — file storage. Network shares (NFS/SMB) access datasets.
- **ZVOL** — block storage. Used for iSCSI or NVMe-oF. Common for virtualization.

---

## VDEV / RAID Types

| Type | Drive Failures Tolerated per VDEV | Notes |
| --- | --- | --- |
| RAIDZ1 | 1 | 3–6 drives |
| RAIDZ2 | 2 | 6–10 drives |
| RAIDZ3 | 3 | 8–14 drives |
| Mirror VDEV | 1 per VDEV | Highest performance, lowest storage efficiency |

---

## VDEV Design Rules

**Don't make the pool too wide.** Wide VDEVs cause:
- Extremely long resilver times on failure
- Higher random IO latency

**More smaller VDEVs > fewer large VDEVs.** Comparing 10×20TB vs 20×10TB drives:
grouping data across multiple datasets and multiple VDEVs gives better performance.

**Mirror VDEVs:**
- Lose 50% capacity
- Lowest latency, best random IOPS
- Not ideal for large sequential media files (movies) where you'd prefer storage efficiency

---

## NAS Build (pve-srv-1 Current)

Planned ZFS pool layout:

- **4× 4TB Samsung 870 QVO SSD** → mirrored VDEVs (2+2 mirror)
- **4× 8TB WD Red Plus 5400** → mirrored VDEVs (2+2 mirror)

Hardware:
- Case: Jonsbo N6
- CPU: i5-13500
- RAM: 96 GB → 128 GB DDR4
- MB: MSI PRO B760-P
- SATA Controller: Broadcom/LSI 9400-8i (8× SATA)

> This hardware is replacing pve-srv-1. See [`01_Hardware/01_Inventory.md`](../01_Hardware/01_Inventory.md)
> for current pve-srv-1 specs.

---

## TrueNAS Bridge Interface

When setting up TrueNAS networking, use a bridge interface (br0) rather than assigning
an IP directly to the physical NIC. This makes it easy to swap out the underlying interface
without reconfiguring everything attached to it.

**System → Network → Interfaces:**
1. Note the current interface name
2. Click 3 dots → Edit → **Remove the IP** → hit **Save**
   > Do NOT hit "Test Changes" — just Save
3. Click **Add Interface**
   - Type: **Bridge**
   - Name: `br0`
   - IP: same IP as before
   - Bridge Members: original interface name

All containers and network shares attached to the bridge don't need to change when
you swap the underlying physical interface later.
