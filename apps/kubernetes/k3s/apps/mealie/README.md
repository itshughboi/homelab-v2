# Mealie

Self-hosted recipe manager and meal planner.

## Overview

| | |
|---|---|
| **Image** | `ghcr.io/mealie-recipes/mealie:latest` |
| **Domain** | `mealie.hughboi.cc` |
| **Port** | 9000 |
| **Storage** | 5Gi Longhorn PVC (`/app/data` — SQLite db, recipes, images) |

## Before You Apply

Edit [secret.yaml](secret.yaml) with real values:
- `DEFAULT_EMAIL` / `DEFAULT_PASSWORD` — initial admin credentials (change after first login)
- SMTP settings point at Mailrise by default — adjust if needed

```bash
kubectl create secret generic mealie-env -n mealie \
  --from-literal=DEFAULT_EMAIL=admin@example.com \
  --from-literal=DEFAULT_PASSWORD=changeme \
  --from-literal=SMTP_HOST=mailrise.mailrise.svc.cluster.local \
  --from-literal=SMTP_PORT=8025 \
  --from-literal=SMTP_FROM_EMAIL=mealie@hughboi.cc \
  --from-literal=SMTP_FROM_NAME=Mealie \
  --from-literal=SMTP_AUTH_STRATEGY=NONE
```

## Deploy

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Migrating from Docker

```bash
kubectl scale deployment mealie -n mealie --replicas=0
kubectl run copy --image=alpine -n mealie --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/mealie/. mealie/copy:/app/data/
kubectl delete pod copy -n mealie
kubectl scale deployment mealie -n mealie --replicas=1
```

## Notes

- `strategy: Recreate` required for ReadWriteOnce PVC.
- Mealie uses SQLite by default — no separate database pod needed.
- Add `mealie` to the Reflector annotation on the TLS certificate.
