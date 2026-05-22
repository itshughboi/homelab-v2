# Restic Backup

> **Approach changes significantly in k8s.** The Docker setup runs restic as a long-lived container on the host, backing up `/home/hughboi` to a TrueNAS NFS mount. In k8s, the right pattern is a `CronJob` — not a Deployment.

## Current Docker Approach

The Docker container:
- Runs on `dock-prod` (Docker host)
- Backs up `/home/hughboi` (bind-mounted read-only)
- Writes to `/mnt/truenas/restic` (NFS-mounted on Docker host)
- Schedule: every 12 hours (`0 */12 * * *`)
- Retention: last 20, weekly 1, monthly 2

## k8s CronJob Approach

In k8s, restic backup jobs are best run as a `CronJob` that spins up a pod on schedule, runs the backup, and terminates. This is more cloud-native than a permanent Deployment.

**However:** The Docker setup backs up the Docker host's filesystem (`/home/hughboi`). Once services move to k8s, what needs backing up changes:

| What to back up | How in k8s |
|-----------------|-----------|
| Application data (Vaultwarden, etc.) | Longhorn built-in snapshots + Longhorn backup target (S3/NFS) |
| Gitea repos | `git bundle` via CronJob |
| NFS data (TrueNAS) | TrueNAS built-in snapshots (ZFS) |
| Host `/home/hughboi` | Keep the Docker restic job until Docker stack is fully decommissioned |

## Recommended k8s Backup Strategy

1. **Longhorn snapshots** — automatic, recurring, configured in the Longhorn UI. Set a backup target (TrueNAS NFS or S3) for off-cluster copies.
2. **Velero** — cluster-level backup tool that snapshots PVCs + k8s resource state. Integrates with Longhorn and S3.
3. **Per-app database dumps** — CronJob that runs `pg_dump` / `mysqldump` and stores the output on NFS.

## When to Migrate

Once the Docker stack is decommissioned and all apps are running in k8s, the restic Docker container becomes unnecessary. Set up Longhorn backup targets and optionally Velero before that cutover.

## If You Still Want a restic CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: restic-backup
  namespace: restic
spec:
  schedule: "0 */12 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: restic
              image: mazzolino/restic:latest
              env:
                - name: RESTIC_REPOSITORY
                  value: /restic
                - name: RESTIC_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: restic-env
                      key: RESTIC_PASSWORD
              # Mount Longhorn PVCs read-only + NFS target
          restartPolicy: OnFailure
```

This would back up specific PVCs by mounting them read-only and writing snapshots to the NFS target.
