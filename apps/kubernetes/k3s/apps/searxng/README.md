# SearXNG

Privacy-respecting metasearch engine.

## Overview

| | |
|---|---|
| **Image** | `searxng/searxng:latest` |
| **Domain** | `search.hughboi.cc` |
| **Port** | 8080 |
| **Storage** | 1Gi Longhorn PVC (`/etc/searxng` — settings and runtime config) |

## Deploy

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

## After First Deploy

SearXNG writes to `/etc/searxng` at runtime (limiter state, session data). On first start the PVC will be empty — SearXNG will generate default config. If you want to migrate your existing settings from Docker:

```bash
# Get the pod name
kubectl get pods -n searxng

# Copy your existing config in
kubectl cp /home/hughboi/data/searxng/. searxng/<pod-name>:/etc/searxng/
kubectl rollout restart deployment/searxng -n searxng
```

## Notes

- The container runs with `CHOWN`, `SETGID`, `SETUID`, `FOWNER` capabilities — these are required by the SearXNG image for file permission management.
- UWSGI workers/threads default to 4/4 — adjust in [deployment.yaml](deployment.yaml) if your cluster nodes are resource-constrained.
