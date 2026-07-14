# TrueNAS → Synology Dataset Migration via rsync over SSH

## Context

One-time migration of dataset contents from TrueNAS SCALE to Synology NAS over LAN using rsync over SSH. Used to move the Jellyfin dataset (~517G) off TrueNAS due to storage pressure from Immich machine learning assets filling the pool.

---

## Prerequisites

### On Synology

- SSH enabled on port 22 (Control Panel → Terminal & SNMP)
- rsync service enabled (Control Panel → File Services → rsync)
- A local user exists that will receive the data (e.g. `rsync`) with read/write access to the destination shared folder
- User home service enabled (Control Panel → Users & Groups → Advanced)

### On TrueNAS

- SSH keypair created via **Credentials → Backup Credentials → SSH Keypairs → Add**
- Private key written to `/root/.ssh/id_rsa` (see setup below)

---

## One-Time Setup

### 1. Extract the private key from TrueNAS to disk

TrueNAS SCALE stores keypairs in its internal database, not on disk. Write it out manually:

```bash
midclt call keychaincredential.query | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data:
    if item['type'] == 'SSH_KEY_PAIR':
        print(item['attributes']['private_key'])
" > /tmp/id_rsa

sudo cp /tmp/id_rsa /root/.ssh/id_rsa
sudo chmod 600 /root/.ssh/id_rsa
```

### 2. Add the public key to the Synology user

SSH into the Synology and run:

```bash
sudo mkdir -p /var/services/homes/rsync/.ssh
sudo nano /var/services/homes/rsync/.ssh/authorized_keys
# paste the public key from TrueNAS UI (Credentials → SSH Keypairs)
sudo chmod 700 /var/services/homes/rsync/.ssh
sudo chmod 600 /var/services/homes/rsync/.ssh/authorized_keys
sudo chown -R rsync:users /var/services/homes/rsync/.ssh
sudo chown rsync:users /var/services/homes/rsync
```

> **Gotcha:** Synology's `/etc/passwd` shows the rsync user home as `/var/services/homes/rsync` (with an **s**). Earlier DSM docs and some guides reference `/var/services/home` (no **s**) — the wrong path will silently fail key auth.

### 3. Verify key auth works

From TrueNAS shell:

```bash
ssh -i /root/.ssh/id_rsa rsync@<synology-ip> echo "success"
```

Should connect and print `success` without prompting for a password.

---

## Run the Transfer

```bash
sudo rsync -avz --progress \
  -e "ssh -i /root/.ssh/id_rsa -o StrictHostKeyChecking=no" \
  "/mnt/The Archive/Jellyfin/" \
  rsync@10.10.10.147:/volume1/jellyfin/
```

Flags:

- `-a` — archive mode (preserves permissions, timestamps, symlinks)
- `-v` — verbose
- `-z` — compress in transit
- `--progress` — show per-file progress

> **Note:** The trailing slash on the source path (`Jellyfin/`) is intentional — it means "copy the contents of this folder" rather than the folder itself.

---

## Freeing Space on TrueNAS After Migration

Once data is verified on the Synology:

```bash
# Remove contents (keep dataset)
rm -rf "/mnt/The Archive/Jellyfin/"*

# Check for snapshots holding space
zfs list -t snapshot | grep -i jellyfin

# Destroy snapshots if present
zfs destroy "The Archive/Jellyfin@<snapshot-name>"
```

> Snapshots must be deleted via the TrueNAS UI (**Datasets → Manage Snapshots**) if the shell returns permission denied on `zfs destroy`.

---

## Troubleshooting Notes

- TrueNAS SCALE's built-in rsync task UI (Data Protection → Rsync Tasks) with SSH mode does **not** reliably pick up `/root/.ssh/id_rsa` — error code 5 (STARTCLIENT) with no useful log output. Manual rsync from shell is more reliable for one-off migrations.
- The web shell in TrueNAS SCALE drops you into a restricted environment — `sudo` works for most things but `/root` is not directly writable. Use `/tmp` as a staging area then `sudo cp`.
- The `rsync` service account on TrueNAS has `/var/empty` as its home dir and cannot store SSH keys. Use `root` for manual rsync commands.
- ZFS won't reclaim space from deleted files until all snapshots referencing those blocks are also deleted.