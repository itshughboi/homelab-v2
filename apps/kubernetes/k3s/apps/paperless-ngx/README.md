# Paperless-ngx

Document management system with OCR, full-text search, and auto-classification.

## Overview

| | |
|---|---|
| **Image** | `ghcr.io/paperless-ngx/paperless-ngx:latest` |
| **Domain** | `paperless.hughboi.vip` |
| **Port** | 8000 |
| **Containers** | webserver + PostgreSQL + Redis + Gotenberg + Tika |
| **Storage** | 10Gi (data) + 50Gi (media) + 10Gi (export) + 10Gi (postgres) + 2Gi (redis) + NFS (consume) |

## Architecture

| Container | Purpose |
|-----------|---------|
| `paperless-webserver` | Main application (UI + API + OCR worker) |
| `paperless-postgres` | Document metadata storage |
| `paperless-redis` | Task queue for background jobs |
| `paperless-gotenberg` | PDF conversion via Chrome (JS disabled) |
| `paperless-tika` | Document parsing (Word, Excel, etc.) |

The **consume** path is an NFS mount from TrueNAS — drop a file there and Paperless picks it up automatically.

## Before You Apply

1. Fill in `TRUENAS_IP` and NFS path in [storage.yaml](storage.yaml).

2. Create the secret:
```bash
kubectl create secret generic paperless-env -n paperless-ngx \
  --from-literal=POSTGRES_DB=paperless \
  --from-literal=POSTGRES_USER=paperless \
  --from-literal=PAPERLESS_DBPASS=<db-password> \
  --from-literal=PAPERLESS_ADMIN_USER=admin \
  --from-literal=PAPERLESS_ADMIN_PASSWORD=<admin-password>
```

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f storage.yaml
kubectl apply -f secret.yaml
kubectl apply -f postgres.yaml
kubectl apply -f redis.yaml
kubectl apply -f support.yaml      # gotenberg + tika
kubectl rollout status deployment/paperless-postgres -n paperless-ngx
kubectl rollout status deployment/paperless-redis -n paperless-ngx
kubectl apply -f webserver.yaml
kubectl apply -f ingressroute.yaml
```

## Migrating from Docker

```bash
kubectl scale deployment paperless-webserver -n paperless-ngx --replicas=0

# Copy data and media
kubectl run copy --image=alpine -n paperless-ngx --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/paperless/data/. paperless-ngx/copy:/tmp/data/
kubectl cp /home/hughboi/data/paperless/media/. paperless-ngx/copy:/tmp/media/
# Then exec into copy pod and cp the files into the PVC-backed dirs
kubectl delete pod copy -n paperless-ngx
kubectl scale deployment paperless-webserver -n paperless-ngx --replicas=1
```

For Postgres migration: `pg_dump` on Docker host → `pg_restore` into k8s Postgres.

## Notes

- All 5 services must be healthy for documents to process correctly. Check status with `kubectl get pods -n paperless-ngx`.
- `strategy: Recreate` required for ReadWriteOnce PVCs.
- Add `paperless-ngx` to the Reflector annotation on the TLS certificate.
- The consume NFS path supports `ReadWriteMany` so you can write to it from multiple devices simultaneously.
