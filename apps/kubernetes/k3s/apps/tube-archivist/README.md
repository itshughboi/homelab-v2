# Tube-Archivist

Self-hosted YouTube media manager and archiver.

## Overview

| | |
|---|---|
| **Domain** | `yt.hughboi.cc` |
| **Port** | 8000 |
| **Containers** | tubearchivist + elasticsearch + redis |

## Storage

| PVC | Type | Mount | Purpose |
|-----|------|-------|---------|
| `tube-archivist-media` | NFS (TrueNAS) | `/youtube` | Video files |
| `tube-archivist-cache` | Longhorn 10Gi | `/cache` | Thumbnails, temp files |
| `redis-data` | Longhorn 2Gi | `/data` | Task queue |
| `elasticsearch-data` | Longhorn 20Gi | `/usr/share/elasticsearch/data` | Search index |

## Before You Apply

1. **Confirm TrueNAS NFS details** in [storage.yaml](storage.yaml):
   - Server IP is set to `10.10.40.5` (storage VLAN). Confirm the dataset export path (`/mnt/truenas/tube-archivist`).
   - Confirm the NFS export has `no_root_squash` or maps `uid=1000` correctly

2. **Fill in secrets** in [secret.yaml](secret.yaml):
   ```bash
   kubectl create secret generic tube-archivist-env -n tube-archivist \
     --from-literal=TA_HOST=https://yt.hughboi.cc \
     --from-literal=TA_USERNAME=admin \
     --from-literal=TA_PASSWORD=<password> \
     --from-literal=ELASTIC_PASSWORD=<password>
   ```

## Deploy Order

Elasticsearch must be healthy before tube-archivist starts — apply them in order and wait.

```bash
kubectl apply -f namespace.yaml
kubectl apply -f secret.yaml
kubectl apply -f storage.yaml
kubectl apply -f elasticsearch.yaml
kubectl rollout status deployment/elasticsearch -n tube-archivist
kubectl apply -f redis.yaml
kubectl apply -f tubearchivist.yaml
kubectl apply -f ingressroute.yaml
```

## Elasticsearch Notes

The [elasticsearch.yaml](elasticsearch.yaml) includes an init container that sets `vm.max_map_count=262144` at pod startup using a privileged `sysctl` call. This is required by Elasticsearch and avoids having to set it permanently on every node.

The init container runs as `privileged: true` — this is allowed by default in k3s.

## Notes

- Tube-archivist has a long startup time on first run while it sets up the Elasticsearch index. The readiness probe allows up to 10 failures (150s) before marking the pod as failed.
- The `ELASTIC_PASSWORD` in the secret must match across both the `tube-archivist-env` secret and the Elasticsearch env.
