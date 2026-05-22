# Velero

Cluster-level backup tool that snapshots both PersistentVolumeClaims and Kubernetes resource state (Deployments, Services, Secrets, etc.). Works alongside Longhorn's own snapshot/backup capability.

## Velero vs Longhorn Backups

| | Velero | Longhorn |
|---|--------|---------|
| **What it backs up** | k8s resources + PVC data | PVC data only |
| **Restore granularity** | Entire namespace or app | Individual volume |
| **Disaster recovery** | Rebuild full cluster from scratch | Restore data to existing cluster |
| **Best for** | Full cluster DR | Volume-level data recovery |

Use both: Longhorn for fast per-volume restores, Velero for full cluster reconstruction.

## Prerequisites

- An S3-compatible storage target. Options:
  - **TrueNAS MinIO** — run MinIO on your TrueNAS (S3-compatible, free)
  - **Backblaze B2** — cheap offsite S3 storage (~$0.006/GB/month)
  - **AWS S3** — standard if you have an account
- Longhorn v1.3+ with the CSI snapshot support enabled

## Install (Helm)

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Create credentials file
cat > /tmp/credentials-velero <<EOF
[default]
aws_access_key_id=<your-access-key>
aws_secret_access_key=<your-secret-key>
EOF

helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set-file credentials.secretContents.cloud=/tmp/credentials-velero \
  --set configuration.backupStorageLocation[0].name=default \
  --set configuration.backupStorageLocation[0].provider=aws \
  --set configuration.backupStorageLocation[0].bucket=homelab-velero \
  --set configuration.backupStorageLocation[0].config.region=us-east-1 \
  --set configuration.backupStorageLocation[0].config.s3Url=http://truenas-ip:9000 \
  --set configuration.backupStorageLocation[0].config.s3ForcePathStyle=true \
  --set configuration.volumeSnapshotLocation[0].name=default \
  --set configuration.volumeSnapshotLocation[0].provider=csi \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.9.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins \
  --set initContainers[1].name=velero-plugin-for-csi \
  --set initContainers[1].image=velero/velero-plugin-for-csi:v0.7.0 \
  --set initContainers[1].volumeMounts[0].mountPath=/target \
  --set initContainers[1].volumeMounts[0].name=plugins

rm /tmp/credentials-velero
```

Replace `truenas-ip:9000` with your MinIO/S3 endpoint and `homelab-velero` with your bucket name.

## Longhorn CSI Snapshot Setup

Velero uses the CSI snapshot driver to snapshot Longhorn volumes. Enable it:

```bash
# Install CSI snapshot CRDs (if not present from Longhorn)
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

# Create a VolumeSnapshotClass for Longhorn
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: longhorn-snapshot
  labels:
    velero.io/csi-volumesnapshot-class: "true"
driver: driver.longhorn.io
deletionPolicy: Delete
EOF
```

## Scheduled Backups

```bash
# Back up everything nightly at 2AM, keep 14 days
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --ttl 336h

# Back up a specific namespace
velero schedule create immich-backup \
  --schedule="0 3 * * *" \
  --include-namespaces immich \
  --ttl 336h
```

## Restore

```bash
# List backups
velero backup get

# Restore a full backup
velero restore create --from-backup daily-backup-<timestamp>

# Restore a single namespace
velero restore create --from-backup daily-backup-<timestamp> --include-namespaces immich
```

## Verify Backups Are Working

```bash
velero backup get
velero backup describe daily-backup-<timestamp> --details
velero backup logs daily-backup-<timestamp>
```

## MinIO on TrueNAS (Recommended Setup)

If you don't have an S3 target yet, run MinIO as a TrueNAS app:
1. TrueNAS → Apps → Available → MinIO
2. Create a dedicated bucket `homelab-velero`
3. Create an access key with read/write on that bucket
4. Use `http://<truenas-ip>:9000` as the S3 URL with `s3ForcePathStyle=true`

This keeps backups on-premise on your ZFS pool with its own redundancy.
