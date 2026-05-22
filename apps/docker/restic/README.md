# Restic

**Docs:** https://restic.readthedocs.io/

File-level backup to TrueNAS NFS. Restic creates deduplicated, encrypted snapshots of `/home/hughboi` and sends them to the restic repository on TrueNAS. No web UI — managed via CLI or by checking container logs.

## Three-Container Design

| Container | Role | Schedule |
|---|---|---|
| `restic` (backup) | Creates new snapshots | Every 12 hours + on startup |
| `restic-prune` | Removes old snapshots per retention policy | Daily at 04:00 |
| `restic-check` | Verifies repository integrity (10% data read) | Daily at 05:15 |

All three containers use the same `mazzolino/restic` image. The role is determined by which env vars are set (`BACKUP_CRON`, `PRUNE_CRON`, or `CHECK_CRON`).

## Repository

The restic repository lives at `/mnt/truenas/restic` on the host (NFS mount). All three containers mount this as `/restic`.

## Backup Source

`/home/hughboi` is backed up recursively. The backup is tagged `restic-proxmox` for identification.

## Retention Policy (`RESTIC_FORGET_ARGS`)

| Policy | Value |
|---|---|
| Keep last N | 20 snapshots |
| Keep weekly | 1 per week |
| Keep monthly | 2 per month |

## Key Environment Variables (`.env`)

| Variable | Purpose |
|---|---|
| `RESTIC_PASSWORD` | Encryption password for the repository — **never lose this** |
| `TZ` | Timezone for cron scheduling (`America/Denver`) |

## Checking Backup Status

```sh
# List snapshots
docker exec -it restic restic snapshots

# See what's in the latest snapshot
docker exec -it restic restic ls latest

# Check repo integrity manually
docker exec -it restic-check restic check --read-data-subset=10%
```

## Restoring Files

```sh
# List snapshots to find the one to restore from
docker exec -it restic restic snapshots

# Restore a specific file from a snapshot
docker exec -it restic restic restore SNAPSHOT_ID \
  --target /tmp-for-restore \
  --include /mnt/volumes/data/specific/file.txt

# Restore everything from a snapshot
docker exec -it restic restic restore latest --target /tmp-for-restore
```

The `/tmp-for-restore` path inside the container maps to `/mnt/truenas/restic/tmp-for-restore` on the host (from the backup container's volume mount).

## Compression

`RESTIC_COMPRESSION=auto` — Restic auto-selects the best compression level. This was added in Restic 0.14+.

## Upgrade Notes

- The restic repository format is versioned. After upgrading the restic binary, run:
```sh
docker exec -it restic restic migrate
```
- The repository password (`RESTIC_PASSWORD`) must be stored separately from the repository. If lost, the repository is permanently inaccessible.

---

## TrueNAS NFS Mount
1. On Ubuntu host, add the mount (make sure /mnt/truenas/restic exists prior)
```sh
sudo mount "truenas:/mnt/The Archive/Restic" /mnt/truenas/restic
```
2. Mount upon reboot ``` nano /etc/fstab ```
```sh
"truenas:/mnt/The Archive/Restic" /mnt/truenas/restic nfs defaults 0 0
```

## TrueNAS Permissions
1. Click on the Dataset -> Edit Permissions <br>
User: hughboi (Apply user CHECKED) <br>
Group: hughboi (Apply Group CHECKED) <br>

***
**Advanced**: <br>
Apply permissions recursively (CHECKED) <br>
Apply permissions to child datasets (CHECKED) <br>

***
**Access**:
- User: RWX
- Group: RX
- Other: RX
