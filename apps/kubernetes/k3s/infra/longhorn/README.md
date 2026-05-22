# Longhorn

Distributed block storage for k3s. Provides the default `StorageClass` used by every PVC in this cluster that isn't explicitly backed by NFS.

## Overview

| | |
|---|---|
| **Version** | `v1.6.1` |
| **StorageClass** | `longhorn` (default) |
| **UI** | `10.10.30.50` (longhorn-vip) |
| **Replicas** | 3 (one per Longhorn node) |
| **Storage nodes** | longhorn-1 (10.10.30.51), longhorn-2 (10.10.30.52), longhorn-3 (10.10.30.53) |

## How It Works

Longhorn runs a manager DaemonSet on every node and provisions replicated block volumes on local disks. When a PVC is created with `storageClassName: longhorn`, Longhorn creates a volume, replicates it across the configured number of nodes, and exposes it as a block device to the pod. If a node goes offline, the volume remains accessible from the surviving replicas.

## Deploy

The `longhorn.yaml` in this directory is a full rendered manifest (output of `helm template`). Apply it directly:

```bash
kubectl apply -f longhorn.yaml
kubectl rollout status daemonset/longhorn-manager -n longhorn-system
```

To install via Helm instead (gets you upgrade tooling):

```bash
helm repo add longhorn https://charts.longhorn.io
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --version 1.6.1
```

## Prerequisites

Each storage node needs these packages installed:

```bash
apt install -y open-iscsi nfs-common
systemctl enable --now iscsid
```

The Ansible role at `ansible/playbooks/k3s/` handles this. If provisioning manually, run the checks:

```bash
curl -sSfL https://raw.githubusercontent.com/longhorn/longhorn/v1.6.1/scripts/environment_check.sh | bash
```

## Accessing the UI

Longhorn UI is exposed at `http://10.10.30.50` (LoadBalancer service, MetalLB). No Traefik IngressRoute is configured — access it directly from inside the LAN.

## Using Longhorn PVCs

Every app in this repo that needs persistent storage uses Longhorn by default:

```yaml
storageClassName: longhorn
accessModes: [ReadWriteOnce]
```

Apps with media on TrueNAS use NFS PersistentVolumes instead — see those apps' `storage.yaml` files for the pattern.

## Notes

- Default replica count is 3. If you have fewer than 3 Longhorn nodes, lower `numberOfReplicas` in the StorageClass or set it per-PVC.
- `ReadWriteOnce` is the only supported access mode for block volumes. Apps that need multi-pod access to the same volume must use NFS.
- Longhorn performs recurring snapshot and backup jobs — configure the backup target (S3 or NFS) in the Longhorn UI if you want off-node backups.
- Do not delete the `longhorn-system` namespace while volumes are in use — it will hang waiting for finalizers.
