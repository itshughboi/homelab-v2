# Pocket ID

Simple OIDC identity provider. Handles SSO for apps that support OIDC.

## Overview

| | |
|---|---|
| **Image** | `ghcr.io/pocket-id/pocket-id:latest` |
| **Domain** | `pocket-id.hughboi.cc` |
| **Port** | 1411 |
| **Storage** | 2Gi Longhorn PVC (`/app/data` — SQLite db, passkeys) |

## Before You Apply

Fill [secret.yaml](secret.yaml) with real values:

```bash
kubectl create secret generic pocket-id-env -n pocket-id \
  --from-literal=JWT_SECRET=$(openssl rand -hex 32) \
  --from-literal=PUBLIC_APP_URL=https://pocket-id.hughboi.cc \
  --from-literal=SMTP_HOST=mailrise.mailrise.svc.cluster.local \
  --from-literal=SMTP_PORT=8025 \
  --from-literal=SMTP_FROM=pocket-id@hughboi.cc \
  --from-literal=SMTP_SENDER_NAME="Pocket ID"
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
kubectl scale deployment pocket-id -n pocket-id --replicas=0
kubectl run copy --image=alpine -n pocket-id --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/pocket-id/. pocket-id/copy:/app/data/
kubectl delete pod copy -n pocket-id
kubectl scale deployment pocket-id -n pocket-id --replicas=1
```

## Registering OIDC Clients

After deploy, go to `https://pocket-id.hughboi.cc` and add OIDC clients for each app that needs SSO. The OIDC discovery endpoint is:
```
https://pocket-id.hughboi.cc/.well-known/openid-configuration
```

## Notes

- `strategy: Recreate` required for ReadWriteOnce PVC.
- Add `pocket-id` to the Reflector annotation on the TLS certificate.
- `JWT_SECRET` must be a stable value — rotating it invalidates all existing sessions.
