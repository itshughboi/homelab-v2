# Immich

Self-hosted photo and video management. Google Photos alternative with mobile backup, face recognition, and smart search.

## Overview

| | |
|---|---|
| **Image** | `ghcr.io/immich-app/immich-server:release` |
| **Domain** | `immich.hughboi.cc` |
| **Port** | 2283 |
| **Containers** | server + machine-learning + PostgreSQL (pgvecto-rs) + Redis |
| **Storage** | 100Gi PVC (uploads) + NFS (external media RO) + 10Gi (ML cache) + 20Gi (postgres) + 1Gi (redis) |

## Architecture

| Component | Role |
|-----------|------|
| `immich-server` | Main API + web UI + microservices |
| `immich-machine-learning` | Face detection, CLIP embeddings, smart search |
| `immich-postgres` | Uses `tensorchord/pgvecto-rs` (not standard postgres — vector extension required) |
| `immich-redis` | Job queue |

## GPU Acceleration

Your Docker setup uses:
- **VAAPI** (immich-server) — Intel GPU video transcoding
- **OpenVINO** (immich-machine-learning) — Intel GPU ML inference

Both are **commented out** in the k8s manifests. The Intel GPU device plugin must be installed cluster-wide before enabling them.

### To enable GPU (requires Intel GPU device plugin):

```bash
# Install Intel GPU device plugin
kubectl apply -f https://raw.githubusercontent.com/intel/intel-device-plugins-for-kubernetes/main/deployments/gpu_plugin/gpu_plugin.yaml
```

Then uncomment the `securityContext` blocks in [server.yaml](server.yaml) and [machine-learning.yaml](machine-learning.yaml) and add:
```yaml
resources:
  limits:
    gpu.intel.com/i915: 1
```

You'll also need to pin these Deployments to the node with the GPU via `nodeSelector`.

## Before You Apply

1. Fill in `TRUENAS_IP` in [storage.yaml](storage.yaml).

2. Create the secret:
```bash
kubectl create secret generic immich-env -n immich \
  --from-literal=DB_DATABASE_NAME=immich \
  --from-literal=DB_USERNAME=immich \
  --from-literal=DB_PASSWORD=<password> \
  --from-literal=REDIS_HOSTNAME=immich-redis \
  --from-literal=IMMICH_VERSION=release \
  --from-literal=UPLOAD_LOCATION=/usr/src/app/upload \
  --from-literal=DB_HOSTNAME=immich-postgres
```

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f storage.yaml
kubectl apply -f secret.yaml
kubectl apply -f postgres.yaml
kubectl apply -f redis.yaml
kubectl rollout status deployment/immich-postgres -n immich
kubectl rollout status deployment/immich-redis -n immich
kubectl apply -f machine-learning.yaml
kubectl apply -f server.yaml
kubectl apply -f ingressroute.yaml
```

## Migrating from Docker

The critical data is in `/home/hughboi/data/immich/upload/` (your phone uploads) and the TrueNAS external media mount.

```bash
kubectl scale deployment immich-server -n immich --replicas=0
kubectl run copy --image=alpine -n immich --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/immich/upload/. immich/copy:/usr/src/app/upload/
kubectl delete pod copy -n immich
kubectl scale deployment immich-server -n immich --replicas=1
```

Postgres migration: `pg_dump` from Docker host + `pg_restore` into immich-postgres pod.

## Notes

- **pgvecto-rs** is mandatory — standard `postgres:16` will not work. Immich requires the vector extension.
- ML model cache (`immich-ml-cache`) persists downloaded CLIP/recognition models — avoids re-downloading on every restart.
- `strategy: Recreate` required for ReadWriteOnce PVCs.
- Add `immich` to the Reflector annotation on the TLS certificate.
- Immich releases frequently — use `release` tag to follow stable releases, or pin to a specific version.
