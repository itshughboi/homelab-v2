# n8n

Workflow automation platform.

## Overview

| | |
|---|---|
| **Image** | `n8nio/n8n:latest` |
| **Domain** | `n8n.hughboi.cc` |
| **Port** | 5678 |
| **Containers** | n8n + PostgreSQL |
| **Storage** | 5Gi PVC (n8n data) + 5Gi PVC (postgres) |

## Before You Apply

Fill in [secret.yaml](secret.yaml):
- `POSTGRES_PASSWORD` / `DB_POSTGRESDB_PASSWORD` — must match
- `N8N_ENCRYPTION_KEY` — generate with `openssl rand -hex 32` and keep stable

```bash
kubectl create secret generic n8n-env -n n8n \
  --from-literal=POSTGRES_DB=n8n \
  --from-literal=POSTGRES_USER=n8n \
  --from-literal=POSTGRES_PASSWORD=<password> \
  --from-literal=DB_TYPE=postgresdb \
  --from-literal=DB_POSTGRESDB_HOST=n8n-postgres \
  --from-literal=DB_POSTGRESDB_PORT=5432 \
  --from-literal=DB_POSTGRESDB_DATABASE=n8n \
  --from-literal=DB_POSTGRESDB_USER=n8n \
  --from-literal=DB_POSTGRESDB_PASSWORD=<password> \
  --from-literal=N8N_HOST=n8n.hughboi.cc \
  --from-literal=N8N_PORT=5678 \
  --from-literal=N8N_PROTOCOL=https \
  --from-literal=WEBHOOK_URL=https://n8n.hughboi.cc/ \
  --from-literal=N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
```

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml
kubectl apply -f postgres.yaml
kubectl rollout status deployment/n8n-postgres -n n8n
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Migrating from Docker

```bash
kubectl scale deployment n8n -n n8n --replicas=0
kubectl run copy --image=alpine -n n8n --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/n8n/data/. n8n/copy:/home/node/.n8n/
kubectl delete pod copy -n n8n
kubectl scale deployment n8n -n n8n --replicas=1
```

The Docker compose stored the DB on the host at `/home/hughboi/data/n8n/db`. If migrating an existing n8n with SQLite data, use the n8n export/import flow instead of copying files directly when switching to PostgreSQL.

## Notes

- `strategy: Recreate` required for ReadWriteOnce PVCs.
- `N8N_ENCRYPTION_KEY` encrypts stored credentials — **never rotate this** after setup or all credentials become unreadable.
- `WEBHOOK_URL` must be set to the public URL for webhook nodes to generate correct callback URLs.
- Add `n8n` to the Reflector annotation on the TLS certificate.
