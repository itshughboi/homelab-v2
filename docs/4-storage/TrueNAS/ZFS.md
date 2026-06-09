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

## Current pool

| Disks | VDEV | Purpose |
| --- | --- | --- |
| 2× Samsung 870 EVO 4TB SSD | mirror (1-disk fault tolerance) | TrueNAS VM/app data, NFS exports |

Passed through to the TrueNAS VM from pve-srv-1 — device IDs + the passthrough steps are in
[README.md](README.md). (The 2× 8TB HDDs on the host are **not** TrueNAS — they're passed to
the PBS VM for its local datastore; see [../PBS/README.md](../PBS/README.md).)

---

## Maintenance

```sh
# Monthly scrub — catches silent bit rot before it becomes data loss
zpool scrub <pool>
zpool status                # scrub progress / results

smartctl -a /dev/sdX        # per-drive SMART health, periodically
zpool iostat -v 1           # live per-VDEV I/O

# Cap ARC so ZFS doesn't starve VM memory — /etc/modprobe.d/zfs.conf:
options zfs zfs_arc_max=17179869184   # 16 GB; tune to ~50% of RAM
```

Networking (always use a `br0` bridge) is documented once in
[Networking.md](Networking.md).
