# ntfy

Self-hosted push notification service. Used by Gatus, Mailrise, and Ansible playbooks to deliver alerts.

## Overview

| | |
|---|---|
| **Image** | `binwiederhier/ntfy:latest` |
| **Domain** | `ntfy.hughboi.cc` |
| **Port** | 80 |
| **Storage** | 2Gi Longhorn PVC (`/var/cache/ntfy` — SQLite message cache + user DB) |

## Deploy

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f configmap.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## Configuration

Edit [configmap.yaml](configmap.yaml) to change server settings. Key options:

| Setting | Default | Notes |
|---------|---------|-------|
| `auth-default-access` | `deny-all` | Require auth for all topics |
| `cache-duration` | `12h` | How long to retain messages |
| `behind-proxy` | `true` | Required for Traefik to forward correct IPs |

After changing config:
```bash
kubectl apply -f configmap.yaml
kubectl rollout restart deployment/ntfy -n ntfy
```

## Creating Users and Topics

```bash
kubectl exec -it deployment/ntfy -n ntfy -- ntfy user add admin
kubectl exec -it deployment/ntfy -n ntfy -- ntfy access admin '*' rw
```

## Migrating from Docker

Copy the existing cache DB to preserve message history and users:
```bash
kubectl run copy --image=alpine -n ntfy --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/ntfy/cache.db ntfy/copy:/var/cache/ntfy/cache.db
kubectl cp /home/hughboi/data/ntfy/user.db ntfy/copy:/var/cache/ntfy/user.db
kubectl delete pod copy -n ntfy
```

## Notes

- `strategy: Recreate` required for ReadWriteOnce PVC.
- Update `base-url` in [configmap.yaml](configmap.yaml) if you change the domain.
- Add `ntfy` to the Reflector annotation on the TLS certificate.
- Internal cluster address for other services: `http://ntfy.ntfy.svc.cluster.local`
