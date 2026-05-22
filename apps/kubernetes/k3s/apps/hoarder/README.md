# Hoarder (Karakeep)

Self-hosted bookmark manager with AI tagging and full-text search.

## Overview

| | |
|---|---|
| **Image** | `ghcr.io/hoarder-app/hoarder:latest` |
| **Domain** | `hoarder.hughboi.vip` |
| **Port** | 3000 |
| **Containers** | hoarder + chrome (sidecar) + meilisearch (separate Deployment) |
| **Storage** | 10Gi PVC (hoarder data) + 5Gi PVC (meilisearch index) |

## Design

- **hoarder + chrome** run in the same pod (sidecar) — Chrome is accessed via `localhost:9222`
- **meilisearch** runs as a separate Deployment with its own PVC

## Before You Apply

```bash
kubectl create secret generic hoarder-env -n hoarder \
  --from-literal=NEXTAUTH_SECRET=$(openssl rand -hex 36) \
  --from-literal=MEILI_MASTER_KEY=$(openssl rand -hex 32) \
  --from-literal=OPENAI_API_KEY=""
```

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml
kubectl apply -f meilisearch.yaml
kubectl rollout status deployment/hoarder-meilisearch -n hoarder
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Migrating from Docker

```bash
kubectl scale deployment hoarder -n hoarder --replicas=0
kubectl run copy --image=alpine -n hoarder --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/hoarder/. hoarder/copy:/data/
kubectl delete pod copy -n hoarder
kubectl scale deployment hoarder -n hoarder --replicas=1
```

## Notes

- `NEXTAUTH_URL` must match the public URL exactly — wrong value causes auth failures.
- Meilisearch version is pinned to `v1.15.2` matching your Docker setup. Check Hoarder compatibility before upgrading.
- `strategy: Recreate` required for ReadWriteOnce PVCs.
- Add `hoarder` to the Reflector annotation on the TLS certificate.
