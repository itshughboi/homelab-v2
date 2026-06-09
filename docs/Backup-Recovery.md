# Backup & Recovery — Validation Runbook

> A backup you've never restored from is not a backup — it's a hope. This is the drill that
> turns hope into a known-good recovery path. Pairs with the [Dependency-Map](Dependency-Map.md)
> (rebuild order) and the dead-man's switch ([Monitoring](7-k3s/Monitoring.md#dead-mans-switch)).

## What protects what

| Layer | Tool | Covers | Restore granularity | Offsite? |
| --- | --- | --- | --- | --- |
| Proxmox VMs | **PBS** (local ZFS) | Whole VMs (athena, dock-prod, k3s nodes, …) | per-VM | → Synology (planned) |
| k8s cluster state | **Velero** | Namespaces: resources **+** PVC data → S3 | per-namespace / full-cluster | S3 target (MinIO/B2) |
| k8s volumes | **Longhorn** | PVC data, replicated 3× | per-volume | Longhorn backup target |
| k3s control plane | **etcd snapshot** (`kubernetes/k3s/etcd-backup`) | cluster API state | full control-plane | — |
| App/host data | **Restic** | file-level → TrueNAS/offsite | per-path | offsite |
| Secrets | **Vaultwarden** + age key (paper/cloud) | the keys to rebuild everything | — | paper + cloud ✓ |

The **3-2-1 view**: Longhorn replicas (on-host) → PBS/Velero (second copy) → Synology/B2 (offsite,
in progress). See [storage 3-2-1](4-storage/index.md#backup-strategy-3-2-1).

---

## The drill (run quarterly; automate the health-check daily)

For each system: **(1) confirm a recent successful backup, (2) restore it somewhere throwaway,
(3) verify it works, (4) tear down.** Never restore over the live thing.

### PBS — restore a VM
1. Confirm: PBS UI → Datastore → recent snapshot per VM; **Verify** job green (not just "present").
2. Restore: Proxmox → restore the snapshot to a **new temporary VM ID** (not the original).
3. Verify: boot it, confirm it reaches a login / its service responds.
4. Tear down the temp VM.

### Velero — restore a namespace
```sh
velero backup get                                   # confirm a recent Completed backup
velero restore create test-<ns> --from-backup <backup> \
  --namespace-mappings <ns>:<ns>-restoretest        # restore into a scratch namespace
kubectl get all -n <ns>-restoretest                 # verify objects + pods come up
velero restore get
kubectl delete ns <ns>-restoretest                  # tear down
```
Pick a **stateful** app (e.g. `mealie`, `paperless`) so PVC-data restore is exercised, not just manifests.

### etcd — verify the snapshot
```sh
ls -lt /var/lib/rancher/k3s/server/db/snapshots/    # or your etcd-backup target — recent + non-zero
# Full restore is destructive — practice on a SCRATCH single-node k3s, never the live cluster:
#   k3s server --cluster-reset --cluster-reset-restore-path=<snapshot>
```

### Longhorn — restore a volume
Longhorn UI → Backup → pick a volume backup → **Restore** into a new PVC → mount it in a throwaway
pod → confirm data. Delete the test PVC.

> [!IMPORTANT] Velero needs its S3 target to exist
> Velero is the full-cluster-rebuild backup, but it writes to S3 (MinIO on TrueNAS, or B2). Stand
> that up first, or Velero silently has nowhere to go. Include "can I reach the S3 bucket" in the
> check.

---

## Automated health-check (Semaphore)

The drill above is manual + quarterly. The **`backup-verify` playbook**
(`ansible/playbooks/backup-verify/`) runs **daily** from Semaphore and alerts via ntfy if any
backup is **stale or failed** — catching a silently-broken job long before the quarterly drill:

- PBS: newest snapshot age + last Verify result per datastore
- Velero: last backup `Completed` + age
- etcd: newest snapshot age + size
- Longhorn: volumes with a recent successful backup

A stale/failed result → ntfy alert. This is detection; the quarterly restore drill is proof.
