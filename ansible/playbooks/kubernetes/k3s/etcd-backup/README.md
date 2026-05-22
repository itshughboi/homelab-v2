# k3s etcd backup

Backs up k3s cluster state to TrueNAS NFS daily. Supports both k3s deployment modes automatically.

## What it does

1. Detects whether k3s is running with **embedded etcd** (HA, 3 servers) or **SQLite** (single server)
2. Takes a snapshot via `k3s etcd-snapshot save` (etcd mode) or SQLite `.backup` (SQLite mode)
3. Copies the snapshot to TrueNAS NFS at `/mnt/truenas/k3s-backups/`
4. Also copies `/var/lib/rancher/k3s/server/token` and `config.yaml` — needed for node re-join on full restore
5. Prunes backups older than the last 14 snapshots
6. Sends ntfy notification (success: low priority, failure: urgent)

This is your entire cluster state. Lose it without a backup and you re-provision from scratch.

## Run

```sh
cd ansible/playbooks/kubernetes/k3s/etcd-backup
ansible-playbook -i inventory.yaml main.yaml
```

## Schedule

Run daily via Semaphore. The inventory targets `k3s_primary` — one control plane node is sufficient, k3s replicates etcd state across all servers.

## Restore (etcd mode)

```sh
# On a fresh k3s server node, copy snapshot back, then:
k3s server \
  --cluster-reset \
  --cluster-reset-restore-path=/var/lib/rancher/k3s/server/db/snapshots/<snapshot-name>

# Restore token
cp /mnt/truenas/k3s-backups/k3s-token-<date> /var/lib/rancher/k3s/server/token

# Start k3s normally
systemctl start k3s
```

## Backup location

```
/mnt/truenas/k3s-backups/
├── k3s-2026-05-20-0300.snap      # etcd snapshot
├── k3s-token-2026-05-20          # node join token
├── k3s-config-2026-05-20.yaml    # server config
└── ...                           # 14 total kept
```

## Notes

- TrueNAS NFS must be mounted on the target node at `/mnt/truenas/k3s-backups/` before running
- The playbook uses `become: true` — SSH user must have sudo
- Retention (`retention_count: 14`) keeps the last 14 snapshots across all file patterns
