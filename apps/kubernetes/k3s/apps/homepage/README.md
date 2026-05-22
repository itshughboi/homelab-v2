# Homepage

Self-hosted start page with service integrations, API widgets, and Kubernetes-aware service discovery.

## Overview

| | |
|---|---|
| **Image** | `ghcr.io/gethomepage/homepage:latest` |
| **Domain** | `home.hughboi.vip` |
| **Port** | 3000 |
| **Storage** | 1Gi Longhorn PVC (`/app/config` — YAML config files) |

## Files

| File | Purpose |
|------|---------|
| [secret.yaml](secret.yaml) | All API keys as env vars (`HOMEPAGE_VAR_*`) |
| [deployment.yaml](deployment.yaml) | Deployment + ServiceAccount + RBAC |
| [service.yaml](service.yaml) | ClusterIP Service |
| [ingressroute.yaml](ingressroute.yaml) | Traefik IngressRoute |

## Before You Apply

Fill in all `CHANGE_ME` values in [secret.yaml](secret.yaml) with real API keys. The `HOMEPAGE_VAR_*` env vars are referenced in the homepage config YAML files as `{{HOMEPAGE_VAR_TRUENAS_KEY}}` etc.

```bash
kubectl create secret generic homepage-env -n homepage \
  --from-literal=HOMEPAGE_ALLOWED_HOSTS=home.hughboi.vip \
  --from-literal=HOMEPAGE_VAR_PROXMOX_USERNAME=admin@pam \
  --from-literal=HOMEPAGE_VAR_PROXMOX_PASSWORD=<password> \
  # ... all other keys
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

## Migrating Config from Docker

The homepage config files (`services.yaml`, `bookmarks.yaml`, `settings.yaml`, `widgets.yaml`) live in `/app/config`. Copy from the Docker host:

```bash
kubectl scale deployment homepage -n homepage --replicas=0
kubectl run copy --image=alpine -n homepage --restart=Never -- sleep 3600
kubectl cp /home/hughboi/code/homepage/config/. homepage/copy:/app/config/
kubectl delete pod copy -n homepage
kubectl scale deployment homepage -n homepage --replicas=1
```

After migration, update service URLs in the config from `*.hughboi.cc` to `*.hughboi.vip`.

## Kubernetes Integration

The Deployment includes a ServiceAccount with read access to:
- Namespaces, Pods, Nodes, Services
- Deployments, ReplicaSets, StatefulSets
- Ingresses + Traefik IngressRoutes

This enables the Kubernetes widget and per-service pod status badges. Configure in `widgets.yaml`:
```yaml
- kubernetes:
    cluster:
      show: true
    nodes:
      show: true
```

## Notes

- `strategy: Recreate` required for ReadWriteOnce PVC.
- `HOMEPAGE_ALLOWED_HOSTS` is required since Homepage 3.x — set it to the domain name.
- Add `homepage` to the Reflector annotation on the TLS certificate.
- The Docker compose had `apparmor:unconfined` — not needed in k3s.
