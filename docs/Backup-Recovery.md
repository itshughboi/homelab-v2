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
| Docker `.env` files | **PBS** (inside the dock-prod VM image) + Vaultwarden | every service credential on dock-prod | per-VM restore / per-entry | ⚠️ see below |
| Secrets | **Vaultwarden** + age key (paper/cloud) | the keys to rebuild everything | — | paper + cloud ✓ |

The **3-2-1 view**: Longhorn replicas (on-host) → PBS/Velero (second copy) → Synology/B2 (offsite,
in progress). See [storage 3-2-1](4-storage/index.md#backup-strategy-3-2-1).

> [!WARNING] Known gap — Docker `.env` files are NOT in the repo (yet)
> The repo ships `.env.example` for ~25 Docker services, but the **real `.env` files exist only
> on dock-prod's disk**. They are *not* committed (by design — plaintext) and the SOPS migration
> that would commit them **encrypted** (`.env.sops`) has not run yet (`.sops.yaml` is still the
> placeholder). Until that lands, a **repo-only rebuild of dock-prod cannot recover service
> credentials**. Recovery paths today, in order:
> 1. **PBS restore** of the dock-prod VM (the `.env` files come back with the disk), or
> 2. **Vaultwarden** entries (`homelab/<service>/…`) re-typed into fresh `.env` files, or
> 3. The paper/cloud age key is irrelevant here *until* `.env.sops` files exist.
>
> **Closing the gap** = run `./scripts/age-setup.sh` on Athena, then `./scripts/sops-migrate.sh
> <service>` per service ([scripts/README](../scripts/README.md)). The Gitea CI `sops-coverage`
> job fails until every `.env.example` has a matching `.env.sops` — that's intentional.
> Note the circularity: Vaultwarden itself runs **on dock-prod** — export an encrypted
> Vaultwarden backup offsite so the credential store survives the host it protects.

---

## Ad-hoc: back up a Docker named volume before a risky change

Not part of the automated layers above — this is the manual safety net to run **before**
cutting a Docker Compose service over to a new deploy path/host, when the service holds real
data in a named volume (not a bind mount to `apps/docker/<service>/`, which is already visible
on disk). Used during the SOPS migration whenever a service's data mattered (e.g. `hoarder`'s
bookmarks/search index in `hoarder_data`/`hoarder_meilisearch`).

```sh
# 1. Find the real volume name(s) — docker compose config | grep -A2 '^volumes:'
#    or docker inspect <container> --format '{{json .Mounts}}'
docker volume ls | grep <service>

# 2. Tar the volume's contents to a host path (read-only mount, container never modifies it)
mkdir -p /home/hughboi/backups
docker run --rm -v <volume_name>:/data -v /home/hughboi/backups:/backup alpine \
  tar czf /backup/<volume_name>_$(date +%Y%m%d_%H%M%S).tar.gz -C /data .

# 3. Confirm it's non-trivial in size before proceeding with anything destructive
ls -la /home/hughboi/backups/
```

**To restore** (into a fresh or existing empty volume):
```sh
docker run --rm -v <volume_name>:/data -v /home/hughboi/backups:/backup alpine \
  tar xzf /backup/<the-backup-file>.tar.gz -C /data
```

Before trusting a cutover to a new compose file (different directory/project name), verify the
**volume name Docker will actually use** matches the existing one — Compose derives it from the
project name (the compose directory's basename by default) plus the volume's short name in
`volumes:`. A mismatch silently creates a new empty volume instead of attaching to existing data,
with no error. Check first, non-destructively:
```sh
cd apps/docker/<service> && docker compose config | tail -5     # shows resolved volume names
```
If the resolved name matches what `docker volume ls` already shows, the deploy is safe to
attach to existing data.

These tarballs are **not** covered by any automated backup layer above — they're a manual,
point-in-time safety net for a single risky operation. Delete them once the cutover is confirmed
working, or move them into the Restic path above if you want them retained longer-term.

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
