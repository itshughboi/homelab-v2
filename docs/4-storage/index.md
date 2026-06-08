# 5. Storage

TrueNAS for primary NAS + NFS, Proxmox Backup Server (PBS) for VM backups. Both run on pve-srv-1 — TrueNAS as a VM with HBA passthrough, PBS as a lightweight Debian LXC.

---

## Architecture

```
pve-srv-1 (physical)
    │
    ├── TrueNAS VM (HBA passthrough — direct disk access)
    │       ZFS pools: ssd-pool (4TB SSDs) + rust-pool (8TB HDDs)
    │       NFS exports → all VMs and Docker services
    │       iSCSI (future) → k3s block storage
    │
    └── PBS LXC (Debian, lightweight)
            Datastore on TrueNAS NFS
            Proxmox backup target for all VMs
            Retention: 7 daily / 4 weekly / 3 monthly
```

---

## TrueNAS

### Why HBA Passthrough?

If Proxmox manages the disks, TrueNAS can't see raw SMART data, can't run its own ZFS checksums end-to-end, and you lose data integrity guarantees. PCIe passthrough of the HBA controller gives TrueNAS bare-metal access to the drives — exactly the same as if it were installed on physical hardware.

### Networking — Always Use a Bridge

Inside TrueNAS: **System → Network → Interfaces → Add Bridge (`br0`)**, not a raw interface IP.

Assigning IPs to `br0` instead of the physical NIC means you can replace the underlying NIC later (hardware failure, upgrade) without reconfiguring every NFS share, iSCSI target, and container attached to it.

### ZFS Pool Layout

| Pool | Disks | VDEV Type | Purpose |
| --- | --- | --- | --- |
| ssd-pool | 4× 4TB Samsung 870 QVO SSD | 2+2 Mirror VDEVs | VM disks, databases, fast storage |
| rust-pool | 4× 8TB WD Red Plus HDD | 2+2 Mirror VDEVs | Media, bulk storage, backups |

**Why mirror VDEVs over RAIDZ?**
- Mirror: best read performance (reads from either disk), fastest resilver on failure, simplest expansion
- RAIDZ: more raw capacity, but: slower resilver (data risk window), no expansion after creation, worse random IOPS
- For a homelab with valuable data, mirror's faster resilver is worth the capacity trade-off

| VDEV Type | Failures Tolerated | Ideal For |
| --- | --- | --- |
| Mirror | 1 per VDEV | VM disks, databases, low latency |
| RAIDZ1 | 1 total | General NAS, 3–6 drives |
| RAIDZ2 | 2 total | Media, 6–10 drives |
| RAIDZ3 | 3 total | Critical archive, 8–14 drives |

### NFS Datasets and Exports

| Dataset | NFS Path | Used by | Permissions |
| --- | --- | --- | --- |
| `YT-Audios` | `/mnt/The Archive/YT-Audios` | Tube Archivist | mapall user: root |
| `Restic` | `/mnt/The Archive/Restic` | Restic backup | owner: `hughboi:hughboi` |
| `k3s-backups` | `/mnt/.../k3s-backups` | k3s etcd backup playbook | owner: `hughboi:hughboi` |
| `pbs-storage/datastore1` | Internal NFS | PBS backup datastore | UID 2147000035 |
| `docker-volume-backups` | Local or NFS | Docker volume backup playbook | — |

### Storage VLAN (VLAN 40)

> [!DANGER]
> MTU 9000 must match **end-to-end**: UniFi switch ports, Proxmox bridge interfaces, TrueNAS bridge, PBS LXC NIC, and any VM on VLAN 40.
> **One device at default MTU 1500 causes silent packet loss.**
> Symptoms: NFS mounts hang, backup jobs timeout, mysteriously slow transfer speeds.

Test after configuring everything:
```sh
ping -M do -s 8972 10.10.40.X   # 8972 + 28 byte header = 9000 — must not fragment
```

### ZFS Maintenance

```sh
# Monthly scrub (catches silent bit rot before it becomes data loss)
zpool scrub <pool>
zpool status   # check scrub progress/results

# SMART health on drives
smartctl -a /dev/sdX   # check each drive periodically

# Live I/O view
zpool iostat -v 1   # per-VDEV I/O in real time

# Cap ARC size (ZFS is greedy — prevent VM memory starvation)
# Add to /etc/modprobe.d/zfs.conf:
options zfs zfs_arc_max=17179869184   # 16 GB example — tune to ~50% of RAM
```

---

## Proxmox Backup Server (PBS)

Full setup walkthrough: [`Proxmox Backup Server.md`](Proxmox%20Backup%20Server.md)

### Why PBS over Plain NFS Backups?

PBS uses a deduplicating chunk store. 10 VMs that all share the same Ubuntu base image → PBS stores that base data once. Backup sizes are dramatically smaller, incremental backups are faster, and the retention policy runs automatically.

### Quick Setup Summary

1. Create TrueNAS dataset `pbs-storage/datastore1` (type: Generic)
2. Set ACLs:
   ```sh
   chown -R 2147000035:2147000035 /mnt/tank/pbs-storage/datastore1
   setfacl -m u:2147000035:rwx,d:u:2147000035:rwx datastore1
   ```
3. Create Debian 13 LXC on pve-srv-1
4. Inside LXC: install PBS from `http://download.proxmox.com/debian/pbs`
5. Access Web UI: `https://<lxc-ip>:8007` → root / Linux PAM
6. Add PBS as a backup target in Proxmox: Datacenter → Storage → Add → Proxmox Backup Server

Test ACL setup before configuring anything:
```sh
sudo -u backup touch /mnt/pbs/datastore1/testfile && rm /mnt/pbs/datastore1/testfile
```

### Backup Schedule

Configure in Proxmox Datacenter → Backup:
- All VMs: daily at 02:00
- Mode: snapshot (no VM downtime)
- Retention: 7 daily, 4 weekly, 3 monthly

### Testing Restores (Do This Monthly)

> A backup you've never restored from is not a backup — it's a hope.

1. Pick any non-critical VM
2. Restore it to a new temporary VM from PBS
3. Verify it boots and functions correctly
4. Delete the test VM

---

## Backup Strategy (3-2-1)

| Copy | Location | Tool |
| --- | --- | --- |
| 1st | Longhorn replicas (3× across k3s workers) | Longhorn auto-replication |
| 2nd | PBS datastore on TrueNAS NFS | PBS + Proxmox schedule |
| 3rd | Offsite — TBD (Backblaze B2 or remote VPS rsync) | To be configured |
